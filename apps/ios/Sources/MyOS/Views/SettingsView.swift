import SwiftUI

/// A lightweight iOS Settings tab — account, AI providers/agent routing (the
/// exact same cards as mac), Face ID lock, and sign out. The mac app's
/// SettingsView carries extra AppKit-only bits (file import, Groww CSV export,
/// vault passphrase change UI) that aren't ported yet — those stay mac-only for
/// now; everything that actually changes your data works here.
struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @AppStorage(BiometricLock.key) private var faceIDEnabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Settings").font(.system(size: 24, weight: .semibold)).foregroundStyle(Palette.text)
                .knRise(0)
            accountCard.knRise(1)
            if BiometricLock.isAvailable { securityCard.knRise(2) }
            AppearanceCard().knRise(3)
            GeneralSettingsCard().knRise(3)
            AgentSettingsCard().knRise(4)
            AIProvidersCard().knRise(5)
            signOutButton.knRise(6)
        }
    }

    private var accountCard: some View {
        Card {
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 30)).foregroundStyle(Palette.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.username.isEmpty ? "Signed in" : "@\(state.username)")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
                    Text("Your data syncs to your MyOS account.")
                        .font(.system(size: 12)).foregroundStyle(Palette.faint)
                }
                Spacer()
            }
        }
    }

    private var securityCard: some View {
        Card {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Lock with \(BiometricLock.biometryName)").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.text)
                    Text("Require it every time MyOS opens or comes back from the background.")
                        .font(.system(size: 11)).foregroundStyle(Palette.faint)
                }
                Spacer()
                Toggle("", isOn: $faceIDEnabled).labelsHidden()
            }
        }
    }

    private var signOutButton: some View {
        Button(role: .destructive) { Task { await state.logout() } } label: {
            Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(KSecondaryButtonStyle(fullWidth: true))
    }
}
