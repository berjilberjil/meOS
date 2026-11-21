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
    /// Same module vocabulary as OAuth. A new connector gets profile read only;
    /// every other module is an explicit choice.
    static let moduleOptions: [(id: String, label: String, detail: String)] = [
        ("profile", "Profile", "Name, city, role, links and achievements"),
        ("finance", "Finance", "Accounts, balances, spending and the finance ledger"),
        ("fitness", "Fitness", "Workouts, training and body metrics"),
        ("health", "Health", "Weight, calories, water and steps"),
        ("notes", "Notes", "Notes and search; locked notes also need Secret"),
        ("tasks", "Tasks", "Daily to-dos and habits"),
        ("calendar", "Calendar", "Events, tags and reminders"),
        ("goals", "Goals", "Life goals and achievements"),
        ("memory", "Memory", "Curated facts MeOS remembers"),
        ("diet", "Diet", "Meal plans and food log"),
        ("knowledge", "Knowledge", "Learning videos and takeaways"),
        ("files", "Files", "Media metadata, storage and recycle bin"),
        ("analytics", "Analytics", "Daily, weekly and monthly summaries"),
    ]

    static let specialOptions: [(id: String, label: String, detail: String)] = [
        ("secret", "Secret", "Read locked notes and private profile fields"),
        ("destructive", "Destructive", "Delete or purge records; still requires confirmation"),
    ]

    static var allowedScopes: Set<String> {
        var out = Set<String>()
        for module in moduleOptions {
            out.insert("meos.\(module.id).read")
            out.insert("meos.\(module.id).write")
        }
        out.formUnion(specialOptions.map(\.id))
        return out
    }

    static func label(for scope: String) -> String {
        if let module = moduleOptions.first(where: {
            scope == "meos.\($0.id).read" || scope == "meos.\($0.id).write"
        }) {
            return "\(module.label) · \(scope.hasSuffix(".write") ? "Write" : "Read")"
        }
        if let special = specialOptions.first(where: { $0.id == scope }) {
            return special.label
        }
        // Legacy tokens created before the module vocabulary are still shown.
        switch scope {
        case "read": return "Legacy · Read all modules"
        case "write": return "Legacy · Write all modules"
        case "health": return "Legacy · Health"
        default: return scope
        }
    }

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
