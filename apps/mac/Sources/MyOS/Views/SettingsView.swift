import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// One place to edit everything and manage the data. Every editor here writes the
/// same state the feature tabs do, so a change in Settings shows up there and vice
/// versa. Destructive actions are guarded by a three-step confirm (see DangerConfirm).
struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var themeStore = ThemeStore.shared

    // Change-passphrase form
    @State private var newPass = ""
    @State private var newPassConfirm = ""
    @State private var passMsg: String?
    @State private var passOK = false
    @State private var exportMsg: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Settings").font(.system(size: 28, weight: .semibold)).foregroundStyle(Palette.text)
                .knRise(0)

            accountCard.knRise(1)
            AppearanceCard().knRise(2)
            GeneralSettingsCard().knRise(2)
            NotificationsCard().knRise(3)
            AgentSettingsCard().knRise(3)
            AIProvidersCard().knRise(3)
            securityCard.knRise(4)
            DataManagementCard().knRise(5)
        }
        .animation(.knTheme, value: themeStore.theme.id)
    }

    // MARK: - Account

    private var accountCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(text: "Account")
                HStack(spacing: 10) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 22)).foregroundStyle(Palette.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(state.username.isEmpty ? "Signed in" : "@\(state.username)")
                            .font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.text)
                        Text("Signed in. Changes sync to iPhone.")
                            .font(.system(size: 13)).foregroundStyle(Palette.faint)
                    }
                    Spacer()
                    Button { Task { await state.refresh() } } label: { Text("Refresh") }
                        .buttonStyle(KSecondaryButtonStyle())
                    Button { Task { await state.logout() } } label: { Text("Log out") }
                        .buttonStyle(KGhostButtonStyle(color: Palette.faint))
                }
                if let err = state.lastSyncError ?? state.lastHydrateError {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12)).foregroundStyle(Palette.amber)
                }
            }
        }
    }

    // MARK: - Security & encryption

    private var securityCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(text: "Security & encryption")
                Text("Encrypted on this Mac. The server only stores ciphertext.")
                    .font(.system(size: 14)).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)

                // Export (plaintext backup / escape hatch)
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Export my data").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
                        Text("A decrypted JSON backup. Keep it somewhere safe.")
                            .font(.system(size: 13)).foregroundStyle(Palette.faint)
                    }
                    Spacer()
                    Button { exportData() } label: { Text("Export…") }
                        .buttonStyle(KSecondaryButtonStyle())
                }
                if let m = exportMsg {
                    Text(m).font(.system(size: 11)).foregroundStyle(Palette.green)
                }

                Divider().overlay(Palette.ring)

                // New recovery code
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Recovery code").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
                        Text("A new code replaces the old one.")
                            .font(.system(size: 13)).foregroundStyle(Palette.faint)
                    }
                    Spacer()
                    Button { Task { await state.regenerateRecoveryCode() } } label: { Text("New code") }
                        .buttonStyle(KSecondaryButtonStyle())
                }

                Divider().overlay(Palette.ring)

                // Change passphrase
                Text("Change passphrase").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
                SecureField("", text: $newPass, prompt: Text("New passphrase").foregroundColor(Palette.faint))
                    .textFieldStyle(.plain).foregroundStyle(Palette.text).knField()
                SecureField("", text: $newPassConfirm, prompt: Text("Confirm new passphrase").foregroundColor(Palette.faint))
                    .textFieldStyle(.plain).foregroundStyle(Palette.text).knField()
                if let m = passMsg {
                    Text(m).font(.system(size: 12)).foregroundStyle(passOK ? Palette.green : Palette.red)
                }
                Button { Task { await changePass() } } label: { Text("Update passphrase") }
                    .buttonStyle(KSecondaryButtonStyle())
            }
        }
    }

    private func changePass() async {
        passMsg = nil; passOK = false
        guard newPass.count >= 8 else { passMsg = "Use at least 8 characters."; return }
        guard newPass == newPassConfirm else { passMsg = "The two passphrases don’t match."; return }
        if await state.changePassphrase(to: newPass) {
            passOK = true; passMsg = "Passphrase updated."
            newPass = ""; newPassConfirm = ""
        } else {
            passMsg = state.vaultError ?? "Couldn’t update the passphrase."
        }
    }

    private func exportData() {
        exportMsg = nil
        guard let data = state.exportJSON() else { exportMsg = nil; return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "myos-export.json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            do { try data.write(to: url); exportMsg = "Saved to \(url.lastPathComponent)." }
            catch { exportMsg = "Couldn’t save the file." }
        }
    }

}
