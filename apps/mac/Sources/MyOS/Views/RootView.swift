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
                SplashView()
            case .loggedOut:
                LoginView()
            case .setup:
                VaultSetupView()
            case .locked:
                VaultUnlockView()
            case .loggedIn:
                Group {
                    if BiometricLock.isEnabled && !unlocked {
                        LockView { await tryUnlock() }
                    } else if state.taskMode.on {
                        // The whole takeover, in one line and on both platforms:
                        // no sidebar, no dock, no chat widget — just the task.
                        TaskModeView()
                    } else {
                        MainView()
                    }
                }
                .onAppear { DietBridge.shared.start(state: state) }
            }

            // One-time recovery code — shown above any phase, after setup or a
            // regeneration from Settings.
            if let code = state.recoveryCodeToShow {
                RecoveryCodeOverlay(code: code)
                    .transition(.opacity)
            }
        }
        .fontDesign(.rounded)   // Feather-substitute: rounds all text app-wide
        .preferredColorScheme(themeStore.theme.colorScheme)
        .tint(themeStore.theme.brand)
        .animation(.knTheme, value: themeStore.theme.id)
        .task {
            #if os(iOS)
            SoundPlayer.open()   // cold launch — scenePhase is already .active by now
            #endif
            await state.bootstrap()
            if state.phase == .loggedIn { DietBridge.shared.start(state: state) }
        }
        .onChange(of: scenePhase) { old, newPhase in
            if newPhase == .background { unlocked = false }
            if newPhase == .active { Task { await state.pullRemote() } }
            #if os(iOS)
            // The app has a voice for coming and going. Only a real re-open counts —
            // gating on `.background` keeps Control Center and the Face ID prompt
            // (both of which only go `.inactive`) from setting it off.
            if newPhase == .active, old == .background { SoundPlayer.open() }
            if newPhase == .background { SoundPlayer.close() }
            #endif
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
        SplashView(
            failed: failed,
            retryTitle: "Try again with \(BiometricLock.biometryName)",
            onRetry: { Task { await attempt() } }
        )
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
