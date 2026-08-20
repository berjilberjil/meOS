import Foundation
import CryptoKit

/// Event photos and videos used to ride inside the `myos.events` blob as base64
/// — 2 MB of a 2.27 MB payload, re-synced on every poll. They now live in R2,
/// sealed on-device with the vault DEK, so the server stores opaque bytes.
///
/// Views ask for bytes synchronously. A hit returns immediately; a miss returns
/// nil and starts a fetch, then bumps `version` so SwiftUI re-renders.
@MainActor
final class EventMediaStore: ObservableObject {
    static let shared = EventMediaStore()

    /// Bumped whenever new bytes land in the cache, so views observing this
    /// object re-render and pick them up.
    @Published private(set) var version = 0

    private var memory: [String: Data] = [:]
    private var inFlight: Set<String> = []
    private var failed: Set<String> = []

    /// Set once by AppState. Held here so the synchronous read path — and every
    /// existing call site of `EventMediaIO` — keeps its old signature.
    private weak var api: APIClient?
    private weak var vault: Vault?

    func configure(api: APIClient, vault: Vault) {
        self.api = api
        self.vault = vault
    }

    private static let dir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let d = base.appendingPathComponent("MyOS/event-media", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    private static func aad(_ id: String) -> Data { Data("event-media:\(id)".utf8) }
    private static func cacheURL(_ id: String) -> URL { dir.appendingPathComponent(id) }

    // MARK: - Reading

    /// Plaintext bytes for a media item's main asset, or nil while it loads.
    func data(for m: EventMedia) -> Data? {
        if !m.data.isEmpty { return Data(base64Encoded: m.data) }   // legacy inline
        guard let key = m.r2Key else { return nil }
        return bytes(id: key)
    }

    /// A video's thumbnail, or an image's own bytes.
    func poster(for m: EventMedia) -> Data? {
        if m.kind == .image { return data(for: m) }
        if let p = m.poster, !p.isEmpty { return Data(base64Encoded: p) }   // legacy inline
        guard let key = m.posterKey else { return nil }
        return bytes(id: key)
    }

    private func bytes(id: String) -> Data? {
        if let d = memory[id] { return d }
        if let d = try? Data(contentsOf: Self.cacheURL(id)) {
            memory[id] = d
            return d
        }
        guard !inFlight.contains(id), !failed.contains(id),
              let api, let vault else { return nil }
        inFlight.insert(id)
        Task { await load(id: id, api: api, vault: vault) }
        return nil
    }

    private func load(id: String, api: APIClient, vault: Vault) async {
        defer { inFlight.remove(id) }
        guard let dek = vault.dek else { return }   // locked — retry when unlocked
        do {
            let urls = try await api.signEventMedia(ids: [id])
            guard let s = urls[id], let url = URL(string: s) else { failed.insert(id); return }
            let (sealed, _) = try await URLSession.shared.data(from: url)
            let plain = try MyOSCrypto.open(sealed.base64EncodedString(), key: dek, aad: Self.aad(id))
            try? plain.write(to: Self.cacheURL(id), options: .atomic)
            memory[id] = plain
            version &+= 1
        } catch {
            failed.insert(id)
        }
    }

    /// Let a locked-then-unlocked session retry everything it gave up on.
    func retryFailures() {
        guard !failed.isEmpty else { return }
        failed.removeAll()
        version &+= 1
    }

    // MARK: - Writing

    /// Seal one asset and upload it. Returns the R2 key to store on the media.
    static func upload(_ plain: Data, api: APIClient, dek: SymmetricKey) async throws -> String {
        let id = UUID().uuidString.lowercased()
        let sealedB64 = try MyOSCrypto.seal(plain, key: dek, aad: aad(id))
        guard let sealed = Data(base64Encoded: sealedB64) else { throw MyOSCryptoError.badBase64 }
        try await api.uploadEventMedia(id: id, sealed: sealed)
        try? plain.write(to: cacheURL(id), options: .atomic)   // we already have the bytes
        return id
    }

    /// Move one media item's inline base64 into R2. Returns nil if there is
    /// nothing to move, so the caller can tell a real migration from a no-op.
    static func migrate(_ m: EventMedia, api: APIClient, dek: SymmetricKey) async throws -> EventMedia? {
        var out = m
        var changed = false

        if out.r2Key == nil, !out.data.isEmpty, let bytes = Data(base64Encoded: out.data) {
            out.r2Key = try await upload(bytes, api: api, dek: dek)
            out.data = ""
            changed = true
        }
        if out.posterKey == nil, let p = out.poster, !p.isEmpty, let bytes = Data(base64Encoded: p) {
            out.posterKey = try await upload(bytes, api: api, dek: dek)
            out.poster = nil
            changed = true
        }
        return changed ? out : nil
    }
}
