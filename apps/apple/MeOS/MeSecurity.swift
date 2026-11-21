import SwiftUI

/// Security center: second factor, signed-in sessions and the audit feed.
///
/// Everything here is metadata. The audit feed carries no note text, amounts,
/// tokens or raw IPs; session rows carry no token. Sensitive actions ask for the
/// login password again (and a TOTP code when MFA is on).
struct MeSecurity: View {
    @EnvironmentObject private var state: AppState

    @State private var mfa: APIClient.MFAStatus?
    @State private var setup: APIClient.MFASetup?
    @State private var sessions: [APIClient.SessionInfo] = []
    @State private var feed: APIClient.SecurityFeed?
    @State private var password = ""
    @State private var code = ""
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        Screen(title: "Security", sub: "Lock, sessions, audit") {
            mfaCard
            sessionsCard
            auditCard
            if let message {
                Text(message).font(.subheadline.weight(.semibold)).foregroundStyle(Color.dim)
            }
        }
        .task { await load() }
    }

    private var mfaCard: some View {
        MCard {
            HStack {
                Label("Two-factor authentication", systemImage: "lock.shield")
                    .font(.title3.weight(.semibold))
                Spacer()
                Text(mfa?.enabled == true ? "On" : "Off")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(mfa?.enabled == true ? Color.green : Color.dim)
            }
            if let mfa {
                Text(mfa.enabled
                     ? "\(mfa.recoveryCodesRemaining) recovery codes left. A stolen password alone cannot sign in."
                     : "Optional TOTP second factor. The vault passphrase stays separate.")
                    .font(.subheadline).foregroundStyle(Color.dim)
            }
            SecureField("Login password (to confirm)", text: $password)
            TextField("Authenticator code (6 digits)", text: $code)

            if let setup {
                Divider()
                Text("Add this secret to your authenticator app").font(.headline)
                Text(setup.secret).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                Text(setup.otpauthUrl).font(.caption).foregroundStyle(Color.dim).textSelection(.enabled)
                Text("Recovery codes — save them now, they are shown once")
                    .font(.headline)
                Text(setup.recoveryCodes.joined(separator: "  "))
                    .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                Button(busy ? "Enabling…" : "Enable two-factor") { Task { await enable() } }
                    .font(.headline).disabled(busy || code.isEmpty)
            } else if mfa?.enabled == true {
                Button("Disable two-factor") { Task { await disable() } }
                    .font(.headline).tint(.red)
                    .disabled(busy || password.isEmpty || code.isEmpty)
            } else {
                Button(busy ? "Preparing…" : "Set up two-factor") { Task { await beginSetup() } }
                    .font(.headline).disabled(busy || password.isEmpty)
            }
        }
    }

    private var sessionsCard: some View {
        MCard {
            Label("Signed-in sessions", systemImage: "laptopcomputer.and.iphone")
                .font(.title3.weight(.semibold))
            ForEach(sessions) { s in
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.current ? "This device" : (s.userAgent?.prefix(48).description ?? "Unknown device"))
                        .font(.subheadline.weight(.semibold))
                    Text("Last active \(s.lastSeenAt.prefix(16)) · expires \(s.expiresAt.prefix(10))")
                        .font(.caption).foregroundStyle(Color.dim)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button("Sign out every other device") { Task { await revokeOthers() } }
                .font(.headline)
                .disabled(busy || password.isEmpty || sessions.filter { !$0.current }.isEmpty)
        }
    }

    private var auditCard: some View {
        MCard {
            Label("Recent security activity", systemImage: "list.bullet.rectangle")
                .font(.title3.weight(.semibold))
            if let alerts = feed?.alerts, !alerts.isEmpty {
                ForEach(alerts, id: \.self) { a in
                    Text(a).font(.subheadline.weight(.semibold)).foregroundStyle(.orange)
                }
            }
            ForEach((feed?.events ?? []).prefix(12)) { e in
                HStack {
                    Text(e.event).font(.caption.monospaced())
                    Spacer()
                    Text(e.outcome).font(.caption).foregroundStyle(e.outcome == "success" ? Color.dim : .orange)
                    Text(e.at.prefix(16)).font(.caption2).foregroundStyle(Color.dim)
                }
            }
            if feed?.events.isEmpty == true {
                Text("No events yet.").font(.subheadline).foregroundStyle(Color.dim)
            }
        }
    }

    private func load() async {
        async let m = try? state.api.mfaStatus()
        async let s = try? state.api.sessions()
        async let f = try? state.api.securityEvents()
        mfa = await m
        sessions = (await s) ?? []
        feed = await f
    }

    private func beginSetup() async {
        busy = true; defer { busy = false }
        message = nil
        do {
            setup = try await state.api.mfaSetup(password: password, code: code)
        } catch let e as APIError where e.mfaRequired {
            message = "Enter your current authenticator code too."
        } catch {
            message = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    private func enable() async {
        busy = true; defer { busy = false }
        do {
            mfa = try await state.api.mfaEnable(code: code)
            setup = nil
            code = ""
            password = ""
            message = "Two-factor authentication is on."
        } catch {
            message = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    private func disable() async {
        busy = true; defer { busy = false }
        do {
            mfa = try await state.api.mfaDisable(password: password, code: code)
            password = ""; code = ""
            message = "Two-factor authentication is off."
            await load()
        } catch {
            message = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    private func revokeOthers() async {
        busy = true; defer { busy = false }
        do {
            try await state.api.revokeOtherSessions(password: password, code: code)
            password = ""; code = ""
            await load()
            message = "Every other session was signed out."
        } catch let e as APIError where e.reauthRequired {
            message = "Confirm your login password first."
        } catch {
            message = (error as? APIError)?.message ?? error.localizedDescription
        }
    }
}
