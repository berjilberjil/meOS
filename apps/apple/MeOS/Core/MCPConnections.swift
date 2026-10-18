import Foundation
import CryptoKit

/// Tokens that let an AI app (Wajo, Claude, ChatGPT…) read notes through the
/// remote MCP endpoint at `<baseURL>/mcp`.
///
/// The server must never be able to open the vault on its own, so this device
/// does all the key work: mint a random token, derive a wrapping key from it
/// (HKDF — the token is 256 random bits, so no slow passphrase KDF is needed),
/// seal the DEK under that key, and upload only `sha256(token)` and the sealed
/// DEK. The token itself is shown once and never stored, here or there.
///
/// Byte-compatible with apps/api/src/lib/server/mcpVault.ts — change both or neither.
enum MCPToken {
    static let prefix = "meos_"
    private static let salt = Data("meos.mcp.v1".utf8)
    private static let info = Data("wrap:mcp".utf8)
    static let wrapAAD = Data("wrap:mcp".utf8)

    static func mint() -> String {
        prefix + base64url(MyOSCrypto.randomData(32))
    }

    /// Lookup id the server stores: hex SHA-256 of the token string.
    static func hash(_ token: String) -> String {
        SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// The DEK sealed under a key derived from `token`.
    static func wrap(dek: SymmetricKey, token: String) throws -> String {
        guard let raw = bytes(of: token) else { throw MyOSCryptoError.badKeySize }
        let kek = HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: raw),
                                         salt: salt, info: info, outputByteCount: 32)
        let dekData = dek.withUnsafeBytes { Data($0) }
        return try MyOSCrypto.seal(dekData, key: kek, aad: wrapAAD)
    }

    private static func base64url(_ d: Data) -> String {
        d.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func bytes(of token: String) -> Data? {
        guard token.hasPrefix(prefix) else { return nil }
        var b64 = String(token.dropFirst(prefix.count))
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let d = Data(base64Encoded: b64), d.count == 32 else { return nil }
        return d
    }
}

/// Settings → AI connections. A device-local view over server state, like
/// `AISettingsStore`.
@MainActor
final class MCPConnectionsStore: ObservableObject {
    static let shared = MCPConnectionsStore()
    private let api = APIClient()

    @Published var connections: [APIClient.MCPConnectionDTO] = []
    @Published var loaded = false
    @Published var busy = false
    @Published var error: String?
    /// The token just created. Shown once; cleared when the sheet is dismissed.
    @Published var fresh: (name: String, token: String)?

    var endpoint: String { APIClient.url(for: "mcp").absoluteString }

    /// Same reason as `AISettingsStore.reset`: a process-lifetime singleton must
    /// not show the previous account's connections to the next one.
    func reset() {
        connections = []; loaded = false; busy = false; error = nil; fresh = nil
    }

    func loadIfNeeded() async { if !loaded { await load() } }

    func load() async {
        do { connections = try await api.mcpConnections(); error = nil }
        catch { self.error = (error as? APIError)?.message ?? error.localizedDescription }
        loaded = true
    }

    func create(name: String, dek: SymmetricKey?) async {
        guard let dek else { error = "Unlock MeOS first."; return }
        busy = true; error = nil
        defer { busy = false }
        do {
            let token = MCPToken.mint()
            let wrapped = try MCPToken.wrap(dek: dek, token: token)
            let made = try await api.mcpCreateConnection(name: name, tokenHash: MCPToken.hash(token), wrappedDek: wrapped)
            connections.insert(made, at: 0)
            fresh = (made.name, token)
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    func revoke(_ c: APIClient.MCPConnectionDTO) async {
        error = nil
        do {
            try await api.mcpDeleteConnection(id: c.id)
            connections.removeAll { $0.id == c.id }
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }
}
