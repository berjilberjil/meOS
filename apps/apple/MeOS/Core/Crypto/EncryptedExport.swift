import Foundation
import CryptoKit

/// A passphrase-encrypted backup file.
///
/// The old Settings action wrote a plaintext JSON dump to the temporary
/// directory and offered it in the share sheet. That is exactly the file that
/// ends up in Mail, Downloads or a cloud drive. This envelope is sealed with
/// AES-256-GCM under a key derived from a passphrase the user chooses for the
/// backup (PBKDF2-HMAC-SHA256, 600k rounds). Losing that passphrase makes the
/// backup unreadable; that is the point, and the UI says so.
///
/// This is separate from the vault passphrase. Reusing the vault passphrase is
/// allowed but not required — the export is a portable sealed box.
enum EncryptedExportError: LocalizedError {
    case weakPassphrase
    case wrongPassphrase
    case malformed

    var errorDescription: String? {
        switch self {
        case .weakPassphrase:  return "Use at least 10 characters for the backup passphrase."
        case .wrongPassphrase: return "Wrong passphrase, or the backup is corrupt."
        case .malformed:       return "That file is not a MeOS encrypted backup."
        }
    }
}

enum EncryptedExport {
    static let iterations = 600_000
    private static let aad = Data("meos.export.v1".utf8)

    struct Envelope: Codable {
        var format: String
        var version: Int
        var kdf: String
        var iterations: Int
        var salt: String
        var ct: String
        var createdAt: String
    }

    static func seal(_ data: Data, passphrase: String) throws -> Data {
        guard passphrase.count >= 10 else { throw EncryptedExportError.weakPassphrase }
        let salt = MyOSCrypto.newSalt()
        let key = try MyOSCrypto.deriveKey(from: passphrase, salt: salt, iterations: iterations)
        let ct = try MyOSCrypto.seal(data, key: key, aad: aad)
        let env = Envelope(
            format: "meos-encrypted-export",
            version: 1,
            kdf: "pbkdf2-sha256",
            iterations: iterations,
            salt: salt.base64EncodedString(),
            ct: ct,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
        return try JSONEncoder().encode(env)
    }

    static func open(_ data: Data, passphrase: String) throws -> Data {
        guard let env = try? JSONDecoder().decode(Envelope.self, from: data),
              env.format == "meos-encrypted-export",
              env.kdf == "pbkdf2-sha256",
              env.iterations >= 100_000,
              let salt = Data(base64Encoded: env.salt) else {
            throw EncryptedExportError.malformed
        }
        let key = try MyOSCrypto.deriveKey(from: passphrase, salt: salt, iterations: env.iterations)
        do {
            return try MyOSCrypto.open(env.ct, key: key, aad: aad)
        } catch {
            throw EncryptedExportError.wrongPassphrase
        }
    }
}
