import SwiftUI

struct RootView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.scenePhase) private var scenePhase
    @State private var unlocked = false

    var body: some View {
        ZStack {
            Palette.bg.ignoresSafeArea()
            switch state.phase {
            case .loading:
                VStack(spacing: 16) {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(Palette.brand)
                        .frame(width: 52, height: 52)
                        .overlay(
                            Image(systemName: "command")
                                .font(.system(size: 24, weight: .bold)).foregroundStyle(.white)
                        )
                    ProgressView().tint(Palette.brand)
                }
            case .loggedOut:
                LoginView()
            case .setup:
                VaultSetupView()
            case .locked:
                VaultUnlockView()
            case .loggedIn:
                if BiometricLock.isEnabled && !unlocked {
                    LockView { await tryUnlock() }
                } else {
                    MainView()
                }
            }

            // One-time recovery code — shown above any phase, after setup or a
            // regeneration from Settings.
            if let code = state.recoveryCodeToShow {
                RecoveryCodeOverlay(code: code)
                    .transition(.opacity)
            }
        }
        .fontDesign(.rounded)   // Feather-substitute: rounds all text app-wide
        .task { await state.bootstrap() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background { unlocked = false }
        }
    }

    private func tryUnlock() async { unlocked = await BiometricLock.authenticate() }
}

struct LockView: View {
    let unlock: () async -> Void
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.fill").font(.system(size: 40)).foregroundStyle(Palette.brand)
            Text("MyOS is locked").font(.system(size: 20, weight: .semibold)).foregroundStyle(Palette.text)
            Button { Task { await unlock() } } label: {
                Text("Unlock with \(BiometricLock.biometryName)")
            }
            .buttonStyle(KPrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.bg.ignoresSafeArea())
        .task { await unlock() }
    }
}
