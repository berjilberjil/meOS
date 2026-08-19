import Foundation
import CryptoKit

/// The plaintext, non-secret crypto metadata stored on the server under the
/// `myos.crypto` key. Nothing here reveals the data without the passphrase:
///   - salts are public by design,
///   - `wrappedByPass` / `wrappedByRecovery` are the DEK sealed under keys derived
///     from the passphrase and the recovery code respectively,
///   - `check` is a fixed token sealed under the DEK, used to confirm an unlock.
struct CryptoMeta: Codable, Equatable {
    var v: Int
    var kdf: String
    var iterations: Int
    var passSalt: String          // base64
    var recoverySalt: String      // base64
    var wrappedByPass: String     // base64 sealed-box
    var wrappedByRecovery: String // base64 sealed-box
    var check: String             // base64 sealed-box of CHECK_TOKEN under the DEK
}

/// The envelope written in place of each encrypted `app_state` value:
/// `{ "v": 1, "ct": "base64(nonce‖ciphertext‖tag)" }`.
struct SealedEnvelope: Codable {
    var v: Int
    var ct: String
}

enum VaultError: LocalizedError {
    case locked
    case noMeta
    case alreadyUnlocked
    var errorDescription: String? {
        switch self {
        case .locked:          return "Vault is locked."
        case .noMeta:          return "No vault has been set up yet."
        case .alreadyUnlocked: return "Vault is already unlocked."
        }
    }
}

/// Owns the device's view of the encryption key. Not an ObservableObject — the
/// UI reacts through `AppState.phase`; this stays a plain, testable engine.
final class Vault {
    /// Keys whose values are stored in plaintext (never sensitive, and the server
    /// still needs to read `myos.ai.routes` to pick a model). Everything else is
    /// encrypted at rest.
    static let plaintextKeys: Set<String> = ["myos.crypto", "myos.ai.routes"]
    static let metaKey = "myos.crypto"
    private static let checkToken = Data("myos.vault.check.v1".utf8)

    private(set) var dek: SymmetricKey?
    private(set) var meta: CryptoMeta?

    var isUnlocked: Bool { dek != nil }
    var hasMeta: Bool { meta != nil }

    func shouldEncrypt(_ key: String) -> Bool { !Self.plaintextKeys.contains(key) }

    // MARK: - Meta lifecycle

    /// Record the meta pulled from the server (or nil if the account has none yet).
    func adoptMeta(_ meta: CryptoMeta?) { self.meta = meta }

    /// Try to unlock silently with a DEK cached in this device's Keychain.
    /// Returns true if it worked (and validates against `check`).
    @discardableResult
    func unlockFromKeychain(username: String) -> Bool {
        guard let meta, let key = KeychainStore.loadDEK(username: username) else { return false }
        guard (try? MyOSCrypto.open(meta.check, key: key, aad: Data("check".utf8))) == Self.checkToken else {
            return false
        }
        dek = key
        return true
    }

    /// First-time setup: mint a DEK + recovery code, wrap the DEK under both the
    /// passphrase and the recovery code, and return the meta to upload plus the
    /// recovery code to show the user ONCE. The DEK is held in memory on success.
    func setup(passphrase: String) throws -> (meta: CryptoMeta, recoveryCode: String) {
        let dek = MyOSCrypto.newDEK()
        let recoveryCode = MyOSCrypto.newRecoveryCode()
        let passSalt = MyOSCrypto.newSalt()
        let recoverySalt = MyOSCrypto.newSalt()
        let iterations = MyOSCrypto.pbkdf2Iterations

        let kekPass = try MyOSCrypto.deriveKey(from: passphrase, salt: passSalt, iterations: iterations)
        let kekRec  = try MyOSCrypto.deriveKey(from: MyOSCrypto.normalizeRecoveryCode(recoveryCode),
                                               salt: recoverySalt, iterations: iterations)
        let dekData = dek.withUnsafeBytes { Data($0) }
        let meta = CryptoMeta(
            v: MyOSCrypto.formatVersion,
            kdf: MyOSCrypto.kdfName,
            iterations: iterations,
            passSalt: passSalt.base64EncodedString(),
            recoverySalt: recoverySalt.base64EncodedString(),
            wrappedByPass: try MyOSCrypto.seal(dekData, key: kekPass, aad: Data("wrap:pass".utf8)),
            wrappedByRecovery: try MyOSCrypto.seal(dekData, key: kekRec, aad: Data("wrap:recovery".utf8)),
            check: try MyOSCrypto.seal(Self.checkToken, key: dek, aad: Data("check".utf8)))
        self.dek = dek
        self.meta = meta
        return (meta, recoveryCode)
    }

    /// Unlock with the passphrase. Throws `.decryptFailed` if it's wrong.
    func unlock(passphrase: String) throws {
        guard let meta else { throw VaultError.noMeta }
        let kek = try MyOSCrypto.deriveKey(from: passphrase,
                                           salt: Self.b64(meta.passSalt),
                                           iterations: meta.iterations)
        let dekData = try MyOSCrypto.open(meta.wrappedByPass, key: kek, aad: Data("wrap:pass".utf8))
        try adoptUnwrapped(dekData, meta: meta)
    }

    /// Unlock with the one-time recovery code (for a lost device / forgotten pass).
    func unlock(recoveryCode: String) throws {
        guard let meta else { throw VaultError.noMeta }
        let kek = try MyOSCrypto.deriveKey(from: MyOSCrypto.normalizeRecoveryCode(recoveryCode),
                                           salt: Self.b64(meta.recoverySalt),
                                           iterations: meta.iterations)
        let dekData = try MyOSCrypto.open(meta.wrappedByRecovery, key: kek, aad: Data("wrap:recovery".utf8))
        try adoptUnwrapped(dekData, meta: meta)
    }

    /// Is this the owner's passphrase? Derives and unwraps exactly like `unlock`
    /// but keeps every result local — used to re-authenticate before a wipe, where
    /// re-unlocking (and re-hydrating) would be wrong.
    func verify(passphrase: String) -> Bool {
        guard let meta else { return false }
        guard let kek = try? MyOSCrypto.deriveKey(from: passphrase,
                                                  salt: Self.b64(meta.passSalt),
                                                  iterations: meta.iterations),
              let dekData = try? MyOSCrypto.open(meta.wrappedByPass, key: kek,
                                                 aad: Data("wrap:pass".utf8))
        else { return false }
        let key = SymmetricKey(data: dekData)
        return (try? MyOSCrypto.open(meta.check, key: key, aad: Data("check".utf8))) == Self.checkToken
    }

    private func adoptUnwrapped(_ dekData: Data, meta: CryptoMeta) throws {
        let key = SymmetricKey(data: dekData)
        // Confirm this really is the right DEK before trusting it.
        guard (try? MyOSCrypto.open(meta.check, key: key, aad: Data("check".utf8))) == Self.checkToken else {
            throw MyOSCryptoError.decryptFailed
        }
        self.dek = key
    }

    /// Persist the current DEK to this device's Keychain for silent relaunch.
    func cacheToKeychain(username: String) {
        guard let dek else { return }
        KeychainStore.saveDEK(dek, username: username)
    }

    func lock() { dek = nil }

    /// Forget the DEK on this device (used at logout).
    func forget(username: String) {
        dek = nil
        meta = nil
        KeychainStore.deleteDEK(username: username)
    }

    // MARK: - Re-wrapping (change passphrase / regenerate recovery)

    /// Re-wrap the existing DEK under a new passphrase. Requires an unlocked vault.
    /// Returns the updated meta to upload.
    func rewrap(newPassphrase: String) throws -> CryptoMeta {
        guard let dek, var meta else { throw VaultError.locked }
        let passSalt = MyOSCrypto.newSalt()
        let kek = try MyOSCrypto.deriveKey(from: newPassphrase, salt: passSalt, iterations: meta.iterations)
        let dekData = dek.withUnsafeBytes { Data($0) }
        meta.passSalt = passSalt.base64EncodedString()
        meta.wrappedByPass = try MyOSCrypto.seal(dekData, key: kek, aad: Data("wrap:pass".utf8))
        self.meta = meta
        return meta
    }

    /// Mint a fresh recovery code and re-wrap the DEK under it. Requires unlock.
    /// Returns the new meta to upload plus the code to show ONCE.
    func regenerateRecovery() throws -> (meta: CryptoMeta, recoveryCode: String) {
        guard let dek, var meta else { throw VaultError.locked }
        let code = MyOSCrypto.newRecoveryCode()
        let salt = MyOSCrypto.newSalt()
        let kek = try MyOSCrypto.deriveKey(from: MyOSCrypto.normalizeRecoveryCode(code),
                                           salt: salt, iterations: meta.iterations)
        let dekData = dek.withUnsafeBytes { Data($0) }
        meta.recoverySalt = salt.base64EncodedString()
        meta.wrappedByRecovery = try MyOSCrypto.seal(dekData, key: kek, aad: Data("wrap:recovery".utf8))
        self.meta = meta
        return (meta, code)
    }

    // MARK: - Value transform (used by APIClient)

    /// Is this decoded JSON value an encrypted envelope?
    func isEnvelope(_ value: Any) -> Bool {
        guard let dict = value as? [String: Any] else { return false }
        return dict["ct"] is String && dict["v"] != nil
    }

    /// Encode plaintext JSON bytes as an encrypted envelope `{v,ct}` (JSON Data).
    func sealValue(_ plaintextJSON: Data, key: String) throws -> Data {
        guard let dek else { throw VaultError.locked }
        let ct = try MyOSCrypto.seal(plaintextJSON, key: dek, aad: Data(key.utf8))
        let env = SealedEnvelope(v: MyOSCrypto.formatVersion, ct: ct)
        return try JSONEncoder().encode(env)
    }

    /// Given a decoded envelope dict, return the decrypted plaintext JSON bytes.
    func openValue(_ envelope: [String: Any], key: String) throws -> Data {
        guard let dek else { throw VaultError.locked }
        guard let ct = envelope["ct"] as? String else { throw MyOSCryptoError.badBase64 }
        return try MyOSCrypto.open(ct, key: dek, aad: Data(key.utf8))
    }

    private static func b64(_ s: String) -> Data { Data(base64Encoded: s) ?? Data() }
}
