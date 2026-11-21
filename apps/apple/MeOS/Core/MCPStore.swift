import Foundation

// MARK: - MCP connector mutations
//
// The raw bearer token is generated here, shown once by the UI, hashed with
// SHA-256, and then discarded. The synced document contains only the hash and
// a short prefix. The gateway reads the same document through the vault.

@MainActor
extension AppState {

    private func mcpCommit(_ mutate: (inout MCPConfig) -> Void) {
        var next = mcp
        mutate(&next)
        next.updatedAt = MCPStamp.now()
        mcp = next
        push(StateKey.mcp, next)
    }

    /// Creates a token and returns the raw value exactly once. Callers must
    /// display it immediately and must never persist it.
    func mcpCreateClient(name: String,
                         scopes: [String],
                         expiresInDays: Int?) -> String? {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return nil }
        let cleanScopes = Array(Set(scopes.filter { MCPToken.allowedScopes.contains($0) })).sorted()
        // A token with no scope is a broken credential, not a read-all token.
        guard !cleanScopes.isEmpty else { return nil }
        let generated = MCPToken.generate()
        let client = MCPClientRecord(name: cleanName,
                                     tokenHash: generated.hash,
                                     tokenPrefix: generated.prefix,
                                     scopes: cleanScopes,
                                     expiresAt: MCPToken.expiry(days: expiresInDays))
        mcpCommit { $0.clients.append(client) }
        Haptics.success()
        return generated.token
    }

    func mcpRevokeClient(_ id: String) {
        mcpCommit { config in
            guard let i = config.clients.firstIndex(where: { $0.id == id }) else { return }
            config.clients[i].revoked = true
        }
        Haptics.success()
    }

    func mcpDeleteClient(_ id: String) {
        mcpCommit { $0.clients.removeAll { $0.id == id } }
        Haptics.success()
    }

    func mcpSetURLs(gateway: String, publicURL: String) {
        mcpCommit {
            $0.gatewayURL = gateway.trimmingCharacters(in: .whitespacesAndNewlines)
            $0.publicURL = publicURL.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    func mcpActiveClients() -> [MCPClientRecord] {
        mcp.clients.filter { !$0.revoked }
    }

    /// A copy-ready JSON block for one client. `token` is only available in the
    /// just-created sheet; existing clients show a placeholder.
    func mcpJSONConfig(client: MCPClientRecord, token: String, kind: MCPClientKind) -> String {
        let url = mcp.publicURL.isEmpty ? mcp.gatewayURL : mcp.publicURL
        if kind == .openCode {
            return """
            {
              "mcp": {
                "meos": {
                  "type": "remote",
                  "url": "\(url)",
                  "headers": {
                    "Authorization": "Bearer \(token)"
                  }
                }
              }
            }
            """
        }
        return """
        {
          "mcpServers": {
            "meos": {
              "type": "http",
              "url": "\(url)",
              "headers": {
                "Authorization": "Bearer \(token)"
              }
            }
          }
        }
        """
    }
}

enum MCPClientKind: String, CaseIterable, Identifiable {
    case claudeDesktop = "Claude Desktop"
    case openCode = "OpenCode"
    case chatGPT = "ChatGPT / other"

    var id: String { rawValue }
}
