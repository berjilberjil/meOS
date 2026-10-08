import Foundation
import CryptoKit

/// Where Fold's tokens live between launches.
///
/// They used to go in the data-protection Keychain. The Mac app is ad-hoc signed
/// (no team, no keychain entitlement), so every write came back -34018 and was
/// silently dropped: sign-in "worked", `isLinked` was false a second later, and
/// Refresh never called Fold at all. Tokens now sit next to the state cache,
/// sealed with the same vault DEK as everything else — no entitlement needed, no
/// prompt on rebuild, and unreadable without the passphrase.
enum FoldSession {
    struct Tokens: Codable, Equatable {
        var access: String
        var refresh: String?
        var userID: String?
        /// From Fold's `expires_at`. The access token lives ~15 minutes, so this is
        /// what decides whether a pull needs to renew — renewing a token that is
        /// still good got a brand-new session 401'd.
        var expiresAt: Date?

        func needsRenewal(now: Date = Date(), margin: TimeInterval = 60) -> Bool {
            guard let expiresAt else { return true }        // no expiry known → try
            return expiresAt.timeIntervalSince(now) <= margin
        }
    }

    /// Set once by `AppState` so this always sees the live DEK — nil while locked.
    static var keyProvider: () -> SymmetricKey? = { nil }

    private static let aad = Data("fold.session".utf8)

    static var fileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("MeOS/fold.session")
    }

    /// Pre-rename location. `load()` falls back to it once and `save()` clears
    /// it, so an existing banking session survives the update.
    private static var legacyFileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("MyOS/fold.session")
    }

    // MARK: - Live session (default location, current DEK)

    static func load() -> Tokens? {
        guard let url = fileURL else { return nil }
        if let t = read(from: url, key: keyProvider()) { return t }
        // Pre-rename location — same sealed format, just a moved file.
        if let legacy = legacyFileURL, let t = read(from: legacy, key: keyProvider()) { return t }
        return nil
    }

    @discardableResult
    static func save(_ tokens: Tokens) -> Bool {
        guard let url = fileURL else { return false }
        guard write(tokens, to: url, key: keyProvider()) else { return false }
        if let legacy = legacyFileURL { remove(at: legacy) }
        return true
    }

    static func clear() {
        guard let url = fileURL else { return }
        remove(at: url)
        if let legacy = legacyFileURL { remove(at: legacy) }
    }

    static var accessToken: String? { load()?.access }
    static var refreshToken: String? { load()?.refresh }

    // MARK: - Pure file I/O (unit-tested)

    static func read(from url: URL, key: SymmetricKey?) -> Tokens? {
        guard let key,
              let data = try? Data(contentsOf: url),
              let envelope = try? JSONDecoder().decode(SealedEnvelope.self, from: data),
              let plain = try? MyOSCrypto.open(envelope.ct, key: key, aad: aad),
              let tokens = try? JSONDecoder().decode(Tokens.self, from: plain),
              !tokens.access.isEmpty
        else { return nil }
        return tokens
    }

    @discardableResult
    static func write(_ tokens: Tokens, to url: URL, key: SymmetricKey?) -> Bool {
        guard let key,
              let plain = try? JSONEncoder().encode(tokens),
              let ct = try? MyOSCrypto.seal(plain, key: key, aad: aad),
              let body = try? JSONEncoder().encode(SealedEnvelope(v: MyOSCrypto.formatVersion, ct: ct))
        else { return false }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        do {
            try body.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    static func remove(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
