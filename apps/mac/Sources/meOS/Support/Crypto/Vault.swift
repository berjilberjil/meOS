import Foundation
import CryptoKit

/// The plaintext, non-secret crypto metadata stored on the server under the
/// `myos.crypto` key. Nothing here reveals the data without the passphrase:
///   - salts are public by design,
///   - `wrappedByPass` / `wrappedByRecovery` are the DEK sealed under keys derived
///     from the passphrase and the recovery code respectively,
///   - `check` is a fixed token sealed under the DEK, used to confirm an unlock.
struct CryptoMeta: Codable, Equatable, Sendable {
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
        guard (try? meOSCrypto.open(meta.check, key: key, aad: Data("check".utf8))) == Self.checkToken else {
            return false
        }
        dek = key
        return true
    }

    /// First-time setup: mint a DEK + recovery code, wrap the DEK under both the
    /// passphrase and the recovery code, and return the meta to upload plus the
    /// recovery code to show the user ONCE. The DEK is held in memory on success.
    func setup(passphrase: String) throws -> (meta: CryptoMeta, recoveryCode: String) {
        let m = try Self.deriveSetup(passphrase: passphrase)
        adoptSetup(m)
        return (m.meta, m.recoveryCode)
    }

    /// Everything `setup` computes, without touching `self`. Pure + CPU-heavy
    /// (two 600k-round PBKDF2 derivations, ~1.5s) — callers run this off the
    /// main thread (see `verifyPassphrase` for the pattern) and adopt the
    /// result back on the main actor.
    struct SetupMaterial: Sendable {
        var meta: CryptoMeta
        var recoveryCode: String
        var dekData: Data
    }

    static func deriveSetup(passphrase: String) throws -> SetupMaterial {
        let dek = meOSCrypto.newDEK()
        let recoveryCode = meOSCrypto.newRecoveryCode()
        let passSalt = meOSCrypto.newSalt()
        let recoverySalt = meOSCrypto.newSalt()
        let iterations = meOSCrypto.pbkdf2Iterations

        let kekPass = try meOSCrypto.deriveKey(from: passphrase, salt: passSalt, iterations: iterations)
        let kekRec  = try meOSCrypto.deriveKey(from: meOSCrypto.normalizeRecoveryCode(recoveryCode),
                                               salt: recoverySalt, iterations: iterations)
        let dekData = dek.withUnsafeBytes { Data($0) }
        let meta = CryptoMeta(
            v: meOSCrypto.formatVersion,
            kdf: meOSCrypto.kdfName,
            iterations: iterations,
            passSalt: passSalt.base64EncodedString(),
            recoverySalt: recoverySalt.base64EncodedString(),
            wrappedByPass: try meOSCrypto.seal(dekData, key: kekPass, aad: Data("wrap:pass".utf8)),
            wrappedByRecovery: try meOSCrypto.seal(dekData, key: kekRec, aad: Data("wrap:recovery".utf8)),
            check: try meOSCrypto.seal(Self.checkToken, key: dek, aad: Data("check".utf8)))
        return SetupMaterial(meta: meta, recoveryCode: recoveryCode, dekData: dekData)
    }

    /// Adopt a derived setup on the main actor. The double-setup guard lives
    /// with the caller (`AppState.completeVaultSetup`), not here.
    func adoptSetup(_ m: SetupMaterial) {
        dek = SymmetricKey(data: m.dekData)
        meta = m.meta
    }

    /// Unlock with the passphrase. Throws `.decryptFailed` if it's wrong.
    func unlock(passphrase: String) throws {
        guard let meta else { throw VaultError.noMeta }
        try adoptUnwrapped(Self.deriveUnlockDEK(passphrase: passphrase, meta: meta), meta: meta)
    }

    /// The KDF half of `unlock(passphrase:)`, without touching `self`. Run off
    /// the main thread; adopt the bytes back on the main actor.
    static func deriveUnlockDEK(passphrase: String, meta: CryptoMeta) throws -> Data {
        let kek = try meOSCrypto.deriveKey(from: passphrase,
                                           salt: Self.b64(meta.passSalt),
                                           iterations: meta.iterations)
        return try openAndCheck(wrapped: meta.wrappedByPass, key: kek,
                                aad: Data("wrap:pass".utf8), meta: meta)
    }

    /// Unlock with the one-time recovery code (for a lost device / forgotten pass).
    func unlock(recoveryCode: String) throws {
        guard let meta else { throw VaultError.noMeta }
        try adoptUnwrapped(Self.deriveUnlockDEK(recoveryCode: recoveryCode, meta: meta), meta: meta)
    }

    /// The KDF half of `unlock(recoveryCode:)`, without touching `self`. Run
    /// off the main thread; adopt the bytes back on the main actor.
    static func deriveUnlockDEK(recoveryCode: String, meta: CryptoMeta) throws -> Data {
        let kek = try meOSCrypto.deriveKey(from: meOSCrypto.normalizeRecoveryCode(recoveryCode),
                                           salt: Self.b64(meta.recoverySalt),
                                           iterations: meta.iterations)
        return try openAndCheck(wrapped: meta.wrappedByRecovery, key: kek,
                                aad: Data("wrap:recovery".utf8), meta: meta)
    }

    /// Unwrap a DEK and confirm it against the check token before trusting it.
    /// Pure: safe to run wherever the derivation ran.
    private static func openAndCheck(wrapped: String, key: SymmetricKey, aad: Data,
                                     meta: CryptoMeta) throws -> Data {
        let dekData = try meOSCrypto.open(wrapped, key: key, aad: aad)
        let candidate = SymmetricKey(data: dekData)
        guard (try? meOSCrypto.open(meta.check, key: candidate, aad: Data("check".utf8))) == Self.checkToken else {
            throw meOSCryptoError.decryptFailed
        }
        return dekData
    }

    /// Is this the owner's passphrase? Derives and unwraps exactly like `unlock`
    /// but keeps every result local — used to re-authenticate before a wipe, where
    /// re-unlocking (and re-hydrating) would be wrong.
    func verify(passphrase: String) -> Bool {
        guard let meta else { return false }
        guard let kek = try? meOSCrypto.deriveKey(from: passphrase,
                                                  salt: Self.b64(meta.passSalt),
                                                  iterations: meta.iterations),
              let dekData = try? meOSCrypto.open(meta.wrappedByPass, key: kek,
                                                 aad: Data("wrap:pass".utf8))
        else { return false }
        let key = SymmetricKey(data: dekData)
        return (try? meOSCrypto.open(meta.check, key: key, aad: Data("check".utf8))) == Self.checkToken
    }

    /// Adopt unwrapped DEK bytes on the main actor, after an off-main
    /// derivation. Called from `AppState` (different file), so internal.
    func adoptUnwrapped(_ dekData: Data, meta: CryptoMeta) throws {        let key = SymmetricKey(data: dekData)
        // Confirm this really is the right DEK before trusting it.
        guard (try? meOSCrypto.open(meta.check, key: key, aad: Data("check".utf8))) == Self.checkToken else {
            throw meOSCryptoError.decryptFailed
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
        let passSalt = meOSCrypto.newSalt()
        let kek = try meOSCrypto.deriveKey(from: newPassphrase, salt: passSalt, iterations: meta.iterations)
        let dekData = dek.withUnsafeBytes { Data($0) }
        meta.passSalt = passSalt.base64EncodedString()
        meta.wrappedByPass = try meOSCrypto.seal(dekData, key: kek, aad: Data("wrap:pass".utf8))
        // Deliberately NOT assigned to `self.meta` — see `regenerateRecovery`.
        return meta
    }

    /// Mint a fresh recovery code and re-wrap the DEK under it. Requires unlock.
    /// Returns the new meta to upload plus the code to show ONCE.
    func regenerateRecovery() throws -> (meta: CryptoMeta, recoveryCode: String) {
        guard let dek, var meta else { throw VaultError.locked }
        let code = meOSCrypto.newRecoveryCode()
        let salt = meOSCrypto.newSalt()
        let kek = try meOSCrypto.deriveKey(from: meOSCrypto.normalizeRecoveryCode(code),
                                           salt: salt, iterations: meta.iterations)
        let dekData = dek.withUnsafeBytes { Data($0) }
        meta.recoverySalt = salt.base64EncodedString()
        meta.wrappedByRecovery = try meOSCrypto.seal(dekData, key: kek, aad: Data("wrap:recovery".utf8))
        // Deliberately NOT assigned to `self.meta`. Both this and `rewrap` used
        // to commit locally before the upload, so a failed PUT left the device
        // holding credentials the server had never seen — and the next
        // successful upload shipped them. Tap "New code" offline (the code is
        // never even shown, because that only happens after the PUT), then
        // change your passphrase later: `rewrap` reads this mutated meta, keeps
        // the orphaned recovery wrap, and PUTs the lot. The recovery code
        // written on paper no longer opens the vault. The mirror case is worse —
        // a passphrase change that reported failure goes live on the next
        // successful upload, and the old passphrase stops working at the next
        // launch. The caller adopts, once the server has it.
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
        let ct = try meOSCrypto.seal(plaintextJSON, key: dek, aad: Data(key.utf8))
        let env = SealedEnvelope(v: meOSCrypto.formatVersion, ct: ct)
        return try JSONEncoder().encode(env)
    }

    /// Given a decoded envelope dict, return the decrypted plaintext JSON bytes.
    func openValue(_ envelope: [String: Any], key: String) throws -> Data {
        guard let dek else { throw VaultError.locked }
        guard let ct = envelope["ct"] as? String else { throw meOSCryptoError.badBase64 }
        return try meOSCrypto.open(ct, key: dek, aad: Data(key.utf8))
    }

    private static func b64(_ s: String) -> Data { Data(base64Encoded: s) ?? Data() }
}
