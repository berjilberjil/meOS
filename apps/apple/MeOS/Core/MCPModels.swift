import Foundation
import CryptoKit

enum MCPStamp {
    static func now() -> String {
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(identifier: "Asia/Kolkata")
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: Date())
    }
}

/// The synced MCP connector registry.
///
/// The app is the only place a raw token is ever shown. What syncs is a SHA-256
/// hash plus a short prefix, so another device — or the server — cannot recover
/// the credential. The MCP gateway reads this document, unlocks it with the
/// vault, and accepts only active, unexpired hashes.
struct MCPClientRecord: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString.lowercased()
    var name: String
    var tokenHash: String
    var tokenPrefix: String
    var scopes: [String]
    var createdAt: String = MCPStamp.now()
    var expiresAt: String? = nil
    var revoked: Bool = false
}

struct MCPConfig: Codable, Hashable {
    var schemaVersion: Int = 1
    var updatedAt: String = MCPStamp.now()
    /// Local Streamable HTTP endpoint. `/mcp` is the path the gateway serves.
    var gatewayURL: String = "http://127.0.0.1:8788/mcp"
    /// Optional public HTTPS URL (Cloudflare Tunnel, reverse proxy, etc.).
    var publicURL: String = ""
    var clients: [MCPClientRecord] = []
}

enum MCPToken {
    static let scopeOptions: [(id: String, label: String, detail: String)] = [
        ("read", "Read", "Read finance, health, notes, events and other granted modules."),
        ("write", "Write", "Create accounts, transactions, transfers and other records."),
        ("health", "Health", "Read fitness, nutrition, diet and body-photo metadata."),
        ("secret", "Secret", "Read locked notes and private profile details."),
        ("destructive", "Destructive", "Delete or purge records. Requires explicit confirmation."),
    ]

    static func generate() -> (token: String, hash: String, prefix: String) {
        var bytes = [UInt8](repeating: 0, count: 32)
        for i in bytes.indices { bytes[i] = UInt8.random(in: 0...255) }
        let body = Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let token = "meos_mcp_" + body
        return (token, hash(token), "meos_mcp_" + body.prefix(8))
    }

    static func hash(_ token: String) -> String {
        SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func expiry(days: Int?) -> String? {
        guard let days else { return nil }
        let date = Calendar(identifier: .gregorian).date(byAdding: .day, value: days, to: Date()) ?? Date()
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(identifier: "Asia/Kolkata")
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }
}
