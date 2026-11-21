import SwiftUI

// MARK: - MCP & AI connectors

struct MeMCPConnectors: View {
    @EnvironmentObject var state: AppState
    @State private var creating = false
    @State private var created: MCPCreated?
    @State private var gateway = "http://127.0.0.1:8788/mcp"
    @State private var publicURL = ""
    @State private var saved = false
    @State private var health: MCPHealth?
    @State private var testing = false
    @State private var revoking: MCPClientRecord?
    @State private var deleting: MCPClientRecord?

    private var clients: [MCPClientRecord] {
        state.mcp.clients.sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        Screen(title: "MCP & AI connectors",
               sub: "Give Claude, OpenCode, ChatGPT or any MCP client scoped access") {

            gatewayCard
            securityCard

            MLabel("Connectors")
            if clients.isEmpty {
                MCard {
                    Empty(icon: "network", text: "No AI client is connected yet.")
                    Text("Create a token, start the MCP gateway, then paste the URL and token into your AI client. The raw token is shown once.")
                        .font(.subheadline).foregroundStyle(Color.dim)
                }
            } else {
                ForEach(clients) { client in
                    clientCard(client)
                        .opacity(client.revoked ? 0.45 : 1)
                }
            }
            MButton(title: "Create MCP token", icon: "key.horizontal") { creating = true }

            setupCard

            MCard {
                Text("What each client gets").font(.title3.bold())
                Text("Tokens use the same module scopes as OAuth. A read-only token cannot create or edit anything. Write implies read for that module. Locked notes and private profile fields also need Secret, and deletes also need Destructive plus an explicit confirmation. Every other module stays invisible to that client.")
                    .font(.subheadline).foregroundStyle(Color.dim)
            }
        }
        .onAppear {
            gateway = state.mcp.gatewayURL
            publicURL = state.mcp.publicURL
        }
        .sheet(isPresented: $creating) {
            MCPCreateSheet { client, token in
                creating = false
                // Let the create sheet finish dismissing before presenting the
                // one-time secret sheet.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    created = MCPCreated(client: client, token: token)
                }
            }
            .environmentObject(state)
        }
        .sheet(item: $created) { item in
            MCPCreatedSheet(created: item)
                .environmentObject(state)
        }
        .confirmationDialog("Revoke this connector?", isPresented: Binding(
            get: { revoking != nil },
            set: { if !$0 { revoking = nil } }
        ), titleVisibility: .visible) {
            if let c = revoking {
                Button("Revoke token", role: .destructive) {
                    state.mcpRevokeClient(c.id)
                    revoking = nil
                }
            }
            Button("Cancel", role: .cancel) { revoking = nil }
        } message: {
            Text("The gateway refuses this token within 10 seconds. You can create a replacement at any time.")
        }
        .confirmationDialog("Delete this connector record?", isPresented: Binding(
            get: { deleting != nil },
            set: { if !$0 { deleting = nil } }
        ), titleVisibility: .visible) {
            if let c = deleting {
                Button("Delete record", role: .destructive) {
                    state.mcpDeleteClient(c.id)
                    deleting = nil
                }
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: {
            Text("Only the local record is removed. Any token value held by an AI client stops working within 10 seconds, when the gateway refreshes the registry.")
        }
    }

    private var gatewayCard: some View {
        MCard {
            HStack {
                Label("Gateway", systemImage: "network").font(.title3.bold())
                Spacer()
                if let health {
                    HStack(spacing: 5) {
                        Circle().fill(health.ok ? Color.green : Color.orange).frame(width: 7, height: 7)
                        Text(health.label).font(.caption.weight(.semibold)).foregroundStyle(Color.dim)
                    }
                }
            }
            Text("Local URL").font(.caption.weight(.semibold)).foregroundStyle(Color.dim)
            MField(icon: "link", placeholder: "http://127.0.0.1:8788/mcp", text: $gateway)
            Text("Public HTTPS URL").font(.caption.weight(.semibold)).foregroundStyle(Color.dim)
            MField(icon: "globe", placeholder: "https://your-tunnel.example.com/mcp", text: $publicURL)
            if let health, !health.detail.isEmpty {
                Text(health.detail).font(.caption).foregroundStyle(Color.dim)
            }
            HStack(spacing: 10) {
                Button {
                    state.mcpSetURLs(gateway: gateway, publicURL: publicURL)
                    saved = true
                    withAnimation(DS.spring) { saved = false }
                } label: {
                    Chip(text: saved ? "Saved" : "Save URLs", on: saved)
                }
                .buttonStyle(.press)
                Button {
                    Task { await testGateway() }
                } label: {
                    Chip(text: testing ? "Testing…" : "Test gateway")
                }
                .buttonStyle(.press)
                .disabled(testing)
                Spacer()
            }
            Text("The local URL works for clients on this Mac. ChatGPT and other cloud AIs need the public HTTPS URL, which requires a tunnel or reverse proxy.")
                .font(.caption).foregroundStyle(Color.dim)
        }
    }

    private var securityCard: some View {
        MCard {
            Label("Authenticate once, scope tightly", systemImage: "lock.shield").font(.title3.bold())
            Text("The app creates a random bearer token, stores only its SHA-256 hash in the encrypted meos.mcp document, and shows the raw token once. The MCP gateway decrypts that registry and refuses revoked or expired tokens.")
                .font(.subheadline).foregroundStyle(Color.dim)
            Text("Never paste a token into a public chat, screenshot or repository. Revoke it here if it leaks.")
                .font(.caption).foregroundStyle(Color.orange)
        }
    }

    private func clientCard(_ client: MCPClientRecord) -> some View {
        MCard {
            HStack(alignment: .top, spacing: 12) {
                BigIcon(name: client.revoked ? "xmark.octagon" : "key.horizontal", size: 18)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(client.name).font(.title3.bold())
                        if client.revoked { Chip(text: "Revoked") } else { Chip(text: "Active", on: true) }
                    }
                    Text(client.tokenPrefix + "…").font(.system(.caption, design: .monospaced)).foregroundStyle(Color.dim)
                    ScrollView(.horizontal) {
                        HStack(spacing: 5) {
                            ForEach(client.scopes, id: \.self) { scope in
                                Chip(text: MCPToken.label(for: scope))
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    HStack(spacing: 12) {
                        Text("Created \(Fmt.day(client.createdAt))")
                        if let expiry = client.expiresAt {
                            Text("Expires \(Fmt.day(expiry))")
                        } else {
                            Text("No expiry")
                        }
                    }
                    .font(.caption).foregroundStyle(Color.dim)
                }
                Spacer()
            }
            HStack(spacing: 8) {
                if !client.revoked {
                    Button { revoking = client } label: { Chip(text: "Revoke") }.buttonStyle(.press)
                }
                Button { deleting = client } label: { Chip(text: "Delete") }.buttonStyle(.press)
                Spacer()
                Button {
                    UIPasteboard.general.string = state.mcp.gatewayURL
                } label: { Chip(text: "Copy URL") }.buttonStyle(.press)
            }
        }
    }

    private var setupCard: some View {
        MCard {
            Text("Set up the gateway").font(.title3.bold())
            Text("1. Run the HTTP gateway on this Mac").font(.headline)
            Text("cd \(repoHint)/mcp/meos\nnpm run start:http")
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.card, in: .rect(cornerRadius: 12))
            Text("2. For cloud AIs, expose it over HTTPS").font(.headline)
            Text("brew install cloudflared\ncloudflared tunnel --url http://127.0.0.1:8788")
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.card, in: .rect(cornerRadius: 12))
            Text("3. Paste the tunnel URL above, save, and create a token. Paste the URL and bearer token into your AI client's MCP settings.")
                .font(.subheadline).foregroundStyle(Color.dim)
            Text("Claude Desktop / Claude Code, OpenCode and other clients that support remote MCP with an Authorization header can use this directly. ChatGPT connector support depends on whether its current connector UI accepts a custom bearer token; the gateway itself is standard Streamable HTTP.")
                .font(.caption).foregroundStyle(Color.dim)
            Text("Local stdio clients do not use a token: they launch \(repoHint)/mcp/meos with the credentials in its .env file.")
                .font(.caption).foregroundStyle(Color.dim)
        }
    }

    private var repoHint: String {
        #if os(macOS)
        return "/Users/berjliper/Downloads/meOS"
        #else
        return "/ABSOLUTE/PATH/TO/meOS"
        #endif
    }

    private func testGateway() async {
        testing = true
        defer { testing = false }
        let base = gateway.replacingOccurrences(of: "/mcp", with: "")
        guard let url = URL(string: base + "/healthz") else {
            health = MCPHealth(ok: false, label: "Invalid URL", detail: "Use a full http(s) URL ending in /mcp.")
            return
        }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 4
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                health = MCPHealth(ok: true, label: "Reachable", detail: "The gateway answered on this address.")
            } else {
                health = MCPHealth(ok: false, label: "Not reachable", detail: "The gateway returned an unexpected response.")
            }
        } catch {
            health = MCPHealth(ok: false, label: "Not running",
                               detail: "Start the gateway with npm run start:http. On iPhone, localhost is the phone, not your Mac.")
        }
    }
}

private struct MCPHealth {
    let ok: Bool
    let label: String
    let detail: String
}

struct MCPCreated: Identifiable {
    let id = UUID()
    let client: MCPClientRecord
    let token: String
}

// MARK: - Create token

struct MCPCreateSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let created: (MCPClientRecord, String) -> Void

    @State private var name = ""
    @State private var readModules: Set<String> = ["profile"]
    @State private var writeModules: Set<String> = []
    @State private var specials: Set<String> = []
    @State private var expiry = 0
    @State private var error: String?

    private let expiries: [(Int, String)] = [(0, "Never"), (30, "30 days"), (90, "90 days"), (365, "1 year")]

    private var selectedScopes: [String] {
        var out = Set<String>()
        for module in readModules {
            out.insert("meos.\(module).read")
        }
        for module in writeModules {
            out.insert("meos.\(module).read")
            out.insert("meos.\(module).write")
        }
        out.formUnion(specials)
        return Array(out).sorted()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.gap) {
                    Title(text: "New MCP token", sub: "Shown once")
                    MField(icon: "tag", placeholder: "Connector name", text: $name)
                    MCard {
                        Text("Modules").font(.title3.bold())
                        Text("Read is the default. Grant only the modules this client needs; Write also requires Read.")
                            .font(.caption).foregroundStyle(Color.dim)
                        ForEach(MCPToken.moduleOptions, id: \.id) { option in
                            moduleRow(option)
                            if option.id != MCPToken.moduleOptions.last?.id { Divider() }
                        }
                    }
                    MCard {
                        Text("Additional access").font(.title3.bold())
                        ForEach(MCPToken.specialOptions, id: \.id) { option in
                            HStack(alignment: .top, spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(option.label).font(.headline)
                                    Text(option.detail).font(.caption).foregroundStyle(Color.dim)
                                }
                                Spacer()
                                Button {
                                    if specials.contains(option.id) { specials.remove(option.id) }
                                    else { specials.insert(option.id) }
                                } label: {
                                    Chip(text: specials.contains(option.id) ? "Granted" : "Grant",
                                         on: specials.contains(option.id))
                                }
                                .buttonStyle(.press)
                            }
                        }
                    }
                    MCard {
                        Text("Expiry").font(.title3.bold())
                        Picker("Expiry", selection: $expiry) {
                            ForEach(expiries, id: \.0) { item in Text(item.1).tag(item.0) }
                        }
                        .pickerStyle(.segmented)
                    }
                    if let error { Text(error).font(.subheadline.weight(.semibold)).foregroundStyle(Color.orange) }
                    MButton(title: "Create token", icon: "key.horizontal") { create() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || selectedScopes.isEmpty)
                    Text("A token with no module is refused. Revoke it here the moment it is no longer needed.")
                        .font(.caption).foregroundStyle(Color.dim)
                }
                .padding(DS.pad)
            }
            .background(Color.paper)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func moduleRow(_ option: (id: String, label: String, detail: String)) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(option.label).font(.headline)
                Text(option.detail).font(.caption).foregroundStyle(Color.dim)
            }
            Spacer(minLength: 8)
            Button { toggleRead(option.id) } label: {
                Chip(text: "Read", on: readModules.contains(option.id) || writeModules.contains(option.id))
            }
            .buttonStyle(.press)
            Button { toggleWrite(option.id) } label: {
                Chip(text: "Write", on: writeModules.contains(option.id))
            }
            .buttonStyle(.press)
        }
    }

    private func toggleRead(_ module: String) {
        if readModules.contains(module) || writeModules.contains(module) {
            readModules.remove(module)
            writeModules.remove(module)
        } else {
            readModules.insert(module)
        }
    }

    private func toggleWrite(_ module: String) {
        if writeModules.contains(module) {
            writeModules.remove(module)
        } else {
            writeModules.insert(module)
            readModules.insert(module)
        }
    }

    private func create() {
        guard !selectedScopes.isEmpty else {
            error = "Pick at least one module before creating the token."
            return
        }
        guard let token = state.mcpCreateClient(name: name,
                                                scopes: selectedScopes,
                                                expiresInDays: expiry == 0 ? nil : expiry),
              let client = state.mcp.clients.last else {
            error = "Could not create the token. Check the name and module selection."
            return
        }
        created(client, token)
        dismiss()
    }
}

// MARK: - Token shown once

struct MCPCreatedSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let created: MCPCreated
    @State private var saved = false
    @State private var kind: MCPClientKind = .claudeDesktop

    private var url: String {
        state.mcp.publicURL.isEmpty ? state.mcp.gatewayURL : state.mcp.publicURL
    }

    private var config: String {
        state.mcpJSONConfig(client: created.client, token: created.token, kind: kind)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.gap) {
                    Title(text: "Token created", sub: "Copy it now")
                    MCard(inverted: true) {
                        Text(created.token)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button { UIPasteboard.general.string = created.token } label: { Chip(text: "Copy token") }
                            .buttonStyle(.press)
                    }
                    Text("This is the only time the token is shown. MeOS stores only its hash. If you lose it, revoke it and create another.")
                        .font(.caption).foregroundStyle(Color.orange)

                    MCard {
                        Text("Endpoint").font(.headline)
                        Text(url).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        Divider()
                        Text("Authorization").font(.headline)
                        Text("Bearer \(created.token)")
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }

                    MCard {
                        Picker("Client", selection: $kind) {
                            ForEach(MCPClientKind.allCases) { k in Text(k.rawValue).tag(k) }
                        }
                        .pickerStyle(.menu)
                        Text(config)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.card, in: .rect(cornerRadius: 12))
                        HStack {
                            Button { UIPasteboard.general.string = config } label: { Chip(text: "Copy config") }
                                .buttonStyle(.press)
                            Button { UIPasteboard.general.string = url } label: { Chip(text: "Copy URL") }
                                .buttonStyle(.press)
                        }
                    }

                    Toggle(isOn: $saved) {
                        Text("I saved the token somewhere safe").font(.headline)
                    }
                    .tint(.green)

                    MButton(title: "Done", icon: "checkmark") { dismiss() }
                        .disabled(!saved)
                        .opacity(saved ? 1 : 0.35)
                }
                .padding(DS.pad)
            }
            .background(Color.paper)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.disabled(!saved)
                }
            }
            .interactiveDismissDisabled(!saved)
        }
    }
}
