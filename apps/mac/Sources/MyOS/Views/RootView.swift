import SwiftUI

struct RootView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var themeStore = ThemeStore.shared
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

    @discardableResult
    private func tryUnlock() async -> Bool {
        unlocked = await BiometricLock.authenticate()
        return unlocked
    }
}

/// The gate shown when the app-lock preference is on.
///
/// It prompts on its own — a button is a fallback, never the way in. The prompt is
/// tied to the scene being `.active` rather than to the view appearing, because
/// LocalAuthentication cancels instantly if it's raised while the app is still
/// transitioning (app launch, or returning from background, both of which land
/// here mid-transition). Firing on appear looked automatic but failed every time,
/// leaving the button as the only route.
struct LockView: View {
    let unlock: () async -> Bool

    @Environment(\.scenePhase) private var scenePhase
    @State private var failed = false
    @State private var busy = false

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.fill").font(.system(size: 40)).foregroundStyle(Palette.brand)
            Text("MyOS is locked").font(.system(size: 20, weight: .semibold)).foregroundStyle(Palette.text)

            // Only surfaces once an attempt has actually been made and refused —
            // cancelled, or a face/finger it didn't recognise.
            if failed {
                Button { Task { await attempt() } } label: {
                    Text("Try again with \(BiometricLock.biometryName)")
                }
                .buttonStyle(KPrimaryButtonStyle())
            } else {
                ProgressView().tint(Palette.brand)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.bg.ignoresSafeArea())
        // Runs on appear and again on every scene-phase change, so returning to an
        // already-open app re-prompts without a tap.
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await attempt()
        }
    }

    private func attempt() async {
        guard !busy else { return }        // never stack two prompts
        busy = true
        defer { busy = false }
        failed = !(await unlock())
    }
}
