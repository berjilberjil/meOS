import SwiftUI

struct RootView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var themeStore = ThemeStore.shared
    /// Observed so the app tint follows a colour change without waiting for
    /// something else to invalidate this view.
    @ObservedObject private var appearance = AppearanceStore.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var unlocked = false
    /// When MyOS itself came to the front on the phone. iOS lets an app time
    /// exactly one app — itself — and this is that measurement.
    @State private var foregroundSince: Date?

    var body: some View {
        ZStack {
            Palette.background
            Group {
                switch state.phase {
                case .loading:
                    // The only status line in the app that is allowed to exist,
                    // and only because bootstrap is real work — hydrate, then pull.
                    SplashView(status: "Getting your day ready…")
                case .loggedOut:
                    LoginView()
                case .setup:
                    VaultSetupView()
                case .locked:
                    VaultUnlockView()
                case .loggedIn:
                    loggedIn
                }
            }
            .transition(.opacity)
            // A palette swap has to reach every view, and SwiftUI has no way to
            // know that a global changed underneath it: `Palette.green` is not
            // an input to anything, so a view whose inputs did not change keeps
            // the colour it last drew. Bumping `themeVersion` re-renders
            // everything that observes `AppState`, which is most screens but not
            // all of them — which is exactly why the theme used to be "mostly"
            // applied until the app was relaunched. Re-keying the tree is the
            // only thing that reaches the rest. It is a rare, deliberate action,
            // so a rebuild is a fair price for it landing everywhere at once.
            .id(appearance.revision)

            // One-time recovery code — shown above any phase, after setup or a
            // regeneration from Settings.
            if let code = state.recoveryCodeToShow {
                RecoveryCodeOverlay(code: code)
                    .transition(.opacity)
            }
        }
        // Splash and app are one continuous moment, not two screens: the phase
        // change cross-fades instead of cutting.
        .animation(.easeInOut(duration: 0.28), value: state.phase)
        .preferredColorScheme(themeStore.theme.colorScheme)
        // One lever for the whole app's scale: it moves the type and every SF
        // Symbol sized by a text style together, which is why the Mac's icons
        // grew with its text rather than being left behind at the old size.
        .dynamicTypeSize(appearance.settings.textSize.dynamicTypeSize)
        .tint(Palette.accent)
        .animation(.knTheme, value: themeStore.theme.id)
        .task {
            #if os(iOS)
            SoundPlayer.open()   // cold launch — scenePhase is already .active by now
            #endif
            // The sensor starts BEFORE the vault is unlocked, and deliberately.
            // The Mac asks for the passphrase every launch, so a sensor that
            // waited for `.loggedIn` recorded nothing on any day the app sat at
            // the lock screen. Sessions go to `ActivityJournal` on disk until
            // there is a document to fold them into.
            ActivityCoordinator.shared.begin()
            await state.bootstrap()
            if state.phase == .loggedIn {
                DietBridge.shared.start(state: state)
                // Sensors last: they need a hydrated state to write into.
                ActivityCoordinator.shared.configure(state: state)
                foregroundSince = Date()
                await state.generateWeeklyReportIfDue()
            }
        }
        // The sensor needs a hydrated `AppState` to write into, and on the Mac
        // that does NOT happen during `.task`. The Mac is ad-hoc signed, so the
        // data-protection Keychain always refuses — `unlockFromKeychain` can
        // never succeed and bootstrap therefore always lands on `.locked`. The
        // one-shot `if phase == .loggedIn` above was consequently never true on
        // this machine, `configure(state:)` was never called, and the Mac
        // recorded nothing: "Not tracking on this device" on Today and an empty
        // Productivity tab. Wiring it to the transition covers every route in —
        // cached hydrate, fresh hydrate, first-run setup, and unlock.
        .onChange(of: state.phase) { _, phase in
            guard phase == .loggedIn else { return }
            ActivityCoordinator.shared.configure(state: state)
        }
        .onChange(of: scenePhase) { old, newPhase in
            if newPhase == .background { unlocked = false }

            // Which of the two poll speeds live sync runs at. Fast only while
            // the app is the thing you are looking at — that is the only time a
            // sync delay is something you can see, and the only time it is
            // worth spending requests on.
            state.isForeground = (newPhase == .active)

            // Activity: bank this device's own foreground stretch, take whatever
            // the iPhone's automations queued, and get it synced before the app
            // is suspended.
            if newPhase == .active {
                foregroundSince = Date()
                ActivityCoordinator.shared.drainInbox()
            }
            if newPhase == .background {
                if let since = foregroundSince {
                    ActivityCoordinator.shared.recordOwnForeground(from: since, to: Date())
                    foregroundSince = nil
                }
                ActivityCoordinator.shared.flush()
            }

            if newPhase == .active {
                Task {
                    // Everything, now — state and media both — rather than
                    // waiting out a tick for something that changed while this
                    // device was away.
                    await state.syncNow()
                    // Friday 6pm: the first time the app is open and unlocked
                    // after it, the week gets read back.
                    await state.generateWeeklyReportIfDue()
                }
            }
            #if os(iOS)
            // The app has a voice for coming and going. Only a real re-open counts —
            // gating on `.background` keeps Control Center and the Face ID prompt
            // (both of which only go `.inactive`) from setting it off.
            if newPhase == .active, old == .background { SoundPlayer.open() }
            if newPhase == .background { SoundPlayer.close() }
            #endif
        }
    }

    @ViewBuilder private var loggedIn: some View {
        Group {
            if BiometricLock.isEnabled && !unlocked {
                LockView { await tryUnlock() }
            } else if state.taskMode.on {
                // The whole takeover, in one line and on both platforms: no
                // sidebar, no dock, no chat widget — just the task.
                TaskModeView()
            } else {
                MainView()
            }
        }
        .onAppear { DietBridge.shared.start(state: state) }
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
