import Foundation
import CryptoKit
import CommonCrypto

/// Zero-knowledge crypto primitives for meOS.
///
/// The whole design: your data is encrypted on this device with a key (the DEK)
/// that the server never sees. The DEK is wrapped by a key derived from your
/// passphrase (and, separately, from a one-time recovery code). The server only
/// ever stores ciphertext + wrapped keys + salts — none of which reveal anything
/// without the passphrase. So a full leak of the DB *and* the server env still
/// yields nothing readable.
///
/// Primitives:
///   - AES-256-GCM (CryptoKit) for all sealing. Combined box = nonce(12) ‖ ct ‖ tag(16).
///   - PBKDF2-HMAC-SHA256 (CommonCrypto) for passphrase/recovery-code → key.
///     Versioned via `CryptoMeta.kdf` so Argon2id can replace it later without
///     breaking existing vaults.
enum meOSCryptoError: LocalizedError {
    case kdfFailed
    case badBase64
    case decryptFailed
    case badKeySize

    var errorDescription: String? {
        switch self {
        case .kdfFailed:      return "Could not derive the key."
        case .badBase64:      return "Corrupt encrypted data."
        case .decryptFailed:  return "Wrong passphrase, or the data is corrupt."
        case .badKeySize:     return "Bad key size."
        }
    }
}

enum meOSCrypto {
    /// Current envelope + KDF format version.
    static let formatVersion = 1
    /// PBKDF2 iterations. 600k comfortably exceeds the OWASP-2023 floor for
    /// PBKDF2-HMAC-SHA256. Recorded in `CryptoMeta.iterations` so it can rise later.
    static let pbkdf2Iterations = 600_000
    static let kdfName = "pbkdf2-sha256"

    static let saltBytes = 16
    static let dekBytes  = 32

    // MARK: - Random

    /// Cryptographically secure random bytes (SecRandomCopyBytes).
    static func randomData(_ count: Int) -> Data {
        var d = Data(count: count)
        let ok = d.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!) }
        precondition(ok == errSecSuccess, "SecRandomCopyBytes failed")
        return d
    }

    static func newDEK() -> SymmetricKey { SymmetricKey(data: randomData(dekBytes)) }
    static func newSalt() -> Data { randomData(saltBytes) }

    // MARK: - Key derivation (PBKDF2-HMAC-SHA256)

    /// Derive a 32-byte key from a secret string + salt. Unicode-normalized so the
    /// same passphrase typed on any device/keyboard derives the same key.
    static func deriveKey(from secret: String, salt: Data, iterations: Int = pbkdf2Iterations) throws -> SymmetricKey {
        let pw = Data(secret.precomposedStringWithCanonicalMapping.utf8)
        var derived = Data(count: dekBytes)
        let status: Int32 = derived.withUnsafeMutableBytes { dOut in
            salt.withUnsafeBytes { sIn in
                pw.withUnsafeBytes { pIn in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        pIn.baseAddress!.assumingMemoryBound(to: Int8.self), pw.count,
                        sIn.baseAddress!.assumingMemoryBound(to: UInt8.self), salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterations),
                        dOut.baseAddress!.assumingMemoryBound(to: UInt8.self), dekBytes)
                }
            }
        }
        guard status == kCCSuccess else { throw meOSCryptoError.kdfFailed }
        return SymmetricKey(data: derived)
    }

    // MARK: - Seal / open (AES-256-GCM)

    /// Seal plaintext → base64(combined box). `aad` binds the ciphertext to a
    /// context (e.g. the state key name) so a blob can't be moved between slots.
    static func seal(_ plaintext: Data, key: SymmetricKey, aad: Data = Data()) throws -> String {
        let box = try AES.GCM.seal(plaintext, using: key, authenticating: aad)
        guard let combined = box.combined else { throw meOSCryptoError.decryptFailed }
        return combined.base64EncodedString()
    }

    /// Open base64(combined box) → plaintext. Throws `.decryptFailed` on a wrong
    /// key, wrong aad, or tampering (GCM auth failure).
    static func open(_ base64: String, key: SymmetricKey, aad: Data = Data()) throws -> Data {
        guard let combined = Data(base64Encoded: base64) else { throw meOSCryptoError.badBase64 }
        do {
            let box = try AES.GCM.SealedBox(combined: combined)
            return try AES.GCM.open(box, using: key, authenticating: aad)
        } catch {
            throw meOSCryptoError.decryptFailed
        }
    }

    // MARK: - Recovery code (Crockford base32)

    private static let base32Alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    /// A one-time recovery code: 15 random bytes → 24 Crockford-base32 chars,
    /// grouped `XXXX-XXXX-XXXX-XXXX-XXXX-XXXX` for readability. ~120 bits.
    static func newRecoveryCode() -> String {
        let bytes = [UInt8](randomData(15))
        var bits = 0, acc = 0
        var out = ""
        for b in bytes {
            acc = (acc << 8) | Int(b); bits += 8
            while bits >= 5 {
                bits -= 5
                out.append(base32Alphabet[(acc >> bits) & 0x1F])
            }
        }
        // Group into blocks of 4.
        var grouped = ""
        for (i, ch) in out.enumerated() {
            if i > 0 && i % 4 == 0 { grouped.append("-") }
            grouped.append(ch)
        }
        return grouped
    }

    /// Normalize a user-typed recovery code before KDF: uppercase, drop separators,
    /// map look-alikes (O→0, I/L→1) so honest typos still unlock.
    static func normalizeRecoveryCode(_ code: String) -> String {
        var s = code.uppercased()
        s = s.replacingOccurrences(of: "O", with: "0")
        s = s.replacingOccurrences(of: "I", with: "1")
        s = s.replacingOccurrences(of: "L", with: "1")
        return String(s.unicodeScalars.filter { base32Alphabet.contains(Character($0)) })
    }
}
