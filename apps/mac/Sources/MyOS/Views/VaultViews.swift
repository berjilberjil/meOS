import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - Setup (first-time: create the encryption passphrase)

struct VaultSetupView: View {
    @EnvironmentObject var state: AppState
    @State private var pass = ""
    @State private var confirm = ""
    @FocusState private var focus: Field?
    private enum Field { case pass, confirm }

    var body: some View {
        VaultShell(icon: "lock.shield.fill",
                   title: "Lock your data",
                   subtitle: "Everything you store gets encrypted on this Mac with a key only you hold. Even if the server and database are hacked, your data stays unreadable.") {
            VStack(spacing: 12) {
                secure("Create an encryption passphrase", text: $pass, field: .pass)
                secure("Confirm passphrase", text: $confirm, field: .confirm)

                Text("This is separate from your login password, and it can’t be reset. If you forget it, your recovery code is the only way back in — we’ll show it next.")
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let err = state.vaultError {
                    Text(err).font(.footnote).foregroundStyle(Palette.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                PrimaryButton(title: "Encrypt my data", loading: state.vaultBusy) {
                    Task { await submit() }
                }
                .padding(.top, 2)
            }
        }
        .onSubmit { Task { await submit() } }
    }

    private func submit() async {
        state.vaultError = nil
        guard pass.count >= 8 else { state.vaultError = "Use at least 8 characters."; return }
        guard pass == confirm else { state.vaultError = "The two passphrases don’t match."; return }
        await state.completeVaultSetup(passphrase: pass)
    }

    private func secure(_ placeholder: String, text: Binding<String>, field: Field) -> some View {
        SecureField("", text: text, prompt: Text(placeholder).foregroundColor(Palette.faint))
            .textFieldStyle(.plain).foregroundStyle(Palette.text)
            .focused($focus, equals: field)
            .knField(focused: focus == field)
    }
}

// MARK: - Unlock (existing vault, this device needs the key)

struct VaultUnlockView: View {
    @EnvironmentObject var state: AppState
    @State private var secret = ""
    @State private var useRecovery = false
    @FocusState private var focused: Bool

    var body: some View {
        VaultShell(icon: "lock.fill",
                   title: "Unlock MyOS",
                   subtitle: useRecovery
                        ? "Enter your one-time recovery code."
                        : "Enter your encryption passphrase to decrypt your data on this device.") {
            VStack(spacing: 12) {
                if useRecovery {
                    TextField("", text: $secret, prompt: Text("XXXX-XXXX-XXXX-XXXX-XXXX-XXXX").foregroundColor(Palette.faint))
                        .textFieldStyle(.plain).foregroundStyle(Palette.text)
                        .autocorrectionDisabled()
                        .focused($focused)
                        .knField(focused: focused)
                } else {
                    SecureField("", text: $secret, prompt: Text("Encryption passphrase").foregroundColor(Palette.faint))
                        .textFieldStyle(.plain).foregroundStyle(Palette.text)
                        .focused($focused)
                        .knField(focused: focused)
                }

                if let err = state.vaultError {
                    Text(err).font(.footnote).foregroundStyle(Palette.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                PrimaryButton(title: "Unlock", loading: state.vaultBusy) {
                    Task { await submit() }
                }
                .padding(.top, 2)

                HStack {
                    Button {
                        withAnimation(.knFast) { useRecovery.toggle(); secret = ""; state.vaultError = nil }
                    } label: {
                        Text(useRecovery ? "Use passphrase instead" : "Forgot it? Use recovery code")
                            .font(.footnote.weight(.medium)).foregroundStyle(Palette.muted)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Button { Task { await state.logout() } } label: {
                        Text("Log out").font(.footnote.weight(.medium)).foregroundStyle(Palette.muted)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .onSubmit { Task { await submit() } }
        .onAppear { focused = true }
    }

    private func submit() async {
        let s = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return }
        if useRecovery { await state.unlockWithRecovery(s) }
        else { await state.unlockWithPassphrase(s) }
    }
}

// MARK: - One-time recovery code

struct RecoveryCodeOverlay: View {
    @EnvironmentObject var state: AppState
    let code: String
    @State private var saved = false
    @State private var copied = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "key.fill").font(.largeTitle).foregroundStyle(Palette.brand)
                Text("Your recovery code")
                    .font(.title3.weight(.bold)).foregroundStyle(Palette.text)
                Text("This is the only way back in if you forget your passphrase or lose this Mac. Save it in your password manager now — we can’t show it again.")
                    .font(.footnote).foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text(code)
                    .font(.body.weight(.semibold).monospaced())
                    .foregroundStyle(Palette.text)
                    .textSelection(.enabled)
                    .padding(.vertical, 14).padding(.horizontal, 18)
                    .frame(maxWidth: .infinity)
                    .background(Palette.bg, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(Palette.ring, lineWidth: 1))

                Button {
                    #if os(macOS)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    #else
                    UIPasteboard.general.string = code
                    #endif
                    withAnimation(.knFast) { copied = true }
                } label: {
                    Label(copied ? "Copied" : "Copy code", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.footnote.weight(.medium)).foregroundStyle(Palette.muted)
                }
                .buttonStyle(.plain)

                Toggle(isOn: $saved) {
                    Text("I’ve saved this somewhere safe").font(.footnote).foregroundStyle(Palette.text)
                }
                #if os(macOS)
                .toggleStyle(.checkbox)
                #endif
                .padding(.top, 2)

                PrimaryButton(title: "Done", loading: false) {
                    state.recoveryCodeToShow = nil
                }
                .disabled(!saved)
                .opacity(saved ? 1 : 0.5)
            }
            .padding(26)
            .frame(width: 400)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(Palette.ring, lineWidth: 1))
            .knShadow(true)
        }
    }
}

// MARK: - Shared shell

private struct VaultShell<Content: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: icon).font(.largeTitle).foregroundStyle(Palette.brand)
                VStack(spacing: 6) {
                    Text(title).font(.title.weight(.bold)).foregroundStyle(Palette.text)
                    Text(subtitle)
                        .font(.footnote).foregroundStyle(Palette.muted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.bottom, 24)
            .frame(width: 360)

            VStack(spacing: 12) { content() }
                .padding(24)
                .frame(width: 360)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(Palette.ring, lineWidth: 1))
                .knShadow(true)
            Spacer(); Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.bg.ignoresSafeArea())
    }
}
