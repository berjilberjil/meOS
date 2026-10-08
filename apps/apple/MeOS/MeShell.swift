import SwiftUI

/// MeOS root: bootstrap, live sync, trash sweep, reminders, weekly report,
/// Face ID gate.
struct MeRoot: View {
    @EnvironmentObject var state: AppState
    @Environment(\.scenePhase) private var scenePhase
    @State private var bioUnlocked = false

    var body: some View {
        ZStack {
            Color.paper.ignoresSafeArea()
            Group {
                switch state.phase {
                case .loading: MeSplash()
                case .loggedOut: MeLogin()
                case .setup: MeVaultSetup()
                case .locked: MeUnlock()
                case .loggedIn:
                    if BiometricLock.isEnabled && !bioUnlocked {
                        MeFaceLock { bioUnlocked = await BiometricLock.authenticate(reason: "Unlock MeOS") }
                    } else if state.taskMode.on {
                        MeTaskMode()
                    } else {
                        #if os(iOS)
                        MeTabs()
                        #else
                        MeMacShell()
                        #endif
                    }
                }
            }
            .transition(.opacity)
            #if os(macOS)
            // Sign-in screens are a phone-width column, not a full-window form.
            .frame(maxWidth: state.phase == .loggedIn ? .infinity : 460)
            #endif
            if let code = state.recoveryCodeToShow {
                MeRecoveryOverlay(code: code).transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(DS.spring, value: state.phase)
        .animation(DS.spring, value: state.taskMode.on)
        .animation(DS.spring, value: state.recoveryCodeToShow)
        .tint(.primary)
        .task {
            SoundPlayer.open()
            Haptics.prepare()
            ActivityCoordinator.shared.begin()
            await state.bootstrap()
            if state.phase == .loggedIn {
                DietBridge.shared.start(state: state)
                ActivityCoordinator.shared.configure(state: state)
                await state.generateWeeklyReportIfDue()
            }
        }
        .onChange(of: state.phase) { _, phase in
            guard phase == .loggedIn else { return }
            ActivityCoordinator.shared.configure(state: state)
            DietBridge.shared.start(state: state)
        }
        .onChange(of: scenePhase) { old, new in
            if new == .background { bioUnlocked = false; ActivityCoordinator.shared.flush(); SoundPlayer.close() }
            state.isForeground = (new != .background)
            if new == .active {
                if old == .background { SoundPlayer.open() }
                Task {
                    await state.syncNow()
                    state.sweepTrash()
                    state.rescheduleEventReminders()
                    await state.generateWeeklyReportIfDue()
                    await MeTabs.refreshFeeds(into: state)
                }
            }
        }
    }
}

struct MeTabs: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        TabView {
            Tab("Today", systemImage: "sun.max") { NavigationStack { MeToday() } }
            Tab("Journal", systemImage: "book.closed") { NavigationStack { MeJournal() } }
            Tab("Fitness", systemImage: "figure.run") { NavigationStack { MeFitness() } }
            Tab("Notes", systemImage: "note.text") { NavigationStack { MeNotes() } }
            Tab("More", systemImage: "square.grid.2x2") { NavigationStack { MeMore() } }
        }
        .task { await Self.refreshFeeds(into: state) }
    }

    /// Photos, steps and anything shared in from outside, in feed order.
    static func refreshFeeds(into state: AppState) async {
        #if os(iOS)
        await FavoritesBodyImporter.sync()
        #endif
        await ProgressPhotoSync.syncAll()
        #if os(iOS)
        await HealthSteps.syncRecent(into: state)
        #endif
        await state.drainShareInbox()
    }
}

// MARK: - Auth surfaces

struct MeSplash: View {
    @State private var pulse = false
    var body: some View {
        BigIcon(name: "circle.hexagongrid.fill", size: 40, inverted: true)
            .scaleEffect(pulse ? 1.06 : 0.96)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
            .onAppear { pulse = true }
    }
}

struct MeLogin: View {
    @EnvironmentObject var state: AppState
    @State private var register = false
    @State private var user = ""
    @State private var pass = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            BigIcon(name: "circle.hexagongrid.fill", size: 40, inverted: true)
            Text("MeOS").font(.system(size: 64, weight: .bold)).tracking(-2)
            Text(register ? "Create your account." : "Welcome back.").font(.title2.weight(.medium)).foregroundStyle(Color.dim)
                .contentTransition(.opacity)
            MField(icon: "person", placeholder: "Username", text: $user).padding(.top, 12)
            MField(icon: "key", placeholder: "Password", text: $pass, secure: true)
                .onSubmit { Task { await submit() } }
            if let err = state.authError {
                Text(err).font(.subheadline.weight(.semibold)).transition(.opacity)
            }
            MButton(title: state.isWorking ? "…" : (register ? "Create account" : "Log in"), icon: "arrow.right") { Task { await submit() } }
                .disabled(state.isWorking)
            Button { withAnimation(DS.spring) { register.toggle(); state.authError = nil } } label: {
                Text(register ? "Have an account? Log in" : "New here? Create account").font(.headline).frame(maxWidth: .infinity)
            }
            .buttonStyle(.press).padding(.top, 4)
            Spacer()
        }
        .padding(DS.pad)
        .sensoryFeedback(.error, trigger: state.authError)
    }

    private func submit() async {
        let u = user.trimmingCharacters(in: .whitespaces)
        guard u.count >= 3 else { state.authError = "Username must be at least 3 characters."; return }
        guard pass.count >= 8 else { state.authError = "Password must be at least 8 characters."; return }
        if register { await state.register(username: u, password: pass) } else { await state.login(username: u, password: pass) }
    }
}

struct MeVaultSetup: View {
    @EnvironmentObject var state: AppState
    @State private var pass = ""
    @State private var confirm = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer()
            Title(text: "Encryption passphrase", sub: "Only on your devices")
            Text("Separate from your password. The server never sees it.").foregroundStyle(Color.dim)
            MField(icon: "lock", placeholder: "At least 8 characters", text: $pass, secure: true)
            MField(icon: "lock.rotation", placeholder: "Confirm", text: $confirm, secure: true)
            Bar(progress: Double(pass.count) / 8)
            if let err = state.vaultError { Text(err).font(.subheadline.weight(.semibold)) }
            MButton(title: state.vaultBusy ? "Encrypting…" : "Encrypt my data", icon: "checkmark") {
                state.vaultError = nil
                guard pass.count >= 8 else { state.vaultError = "Use at least 8 characters."; return }
                guard pass == confirm else { state.vaultError = "The two passphrases don’t match."; return }
                Task { await state.completeVaultSetup(passphrase: pass) }
            }
            .disabled(state.vaultBusy)
            Spacer()
        }
        .padding(DS.pad)
    }
}

struct MeUnlock: View {
    @EnvironmentObject var state: AppState
    @State private var secret = ""
    @State private var recovery = false
    @State private var shake = 0
    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            BigIcon(name: "lock.fill", size: 40, inverted: true)
            Text("Unlock your data").font(.largeTitle.bold())
            Text(recovery ? "Enter your recovery code." : "Enter your encryption passphrase.").foregroundStyle(Color.dim)
            MField(icon: recovery ? "key.horizontal" : "key", placeholder: recovery ? "Recovery code" : "Passphrase", text: $secret, secure: !recovery)
                .phaseAnimator([0, -10, 10, 0], trigger: shake) { v, x in v.offset(x: x) } animation: { _ in .spring(response: 0.12, dampingFraction: 0.5) }
                .onSubmit { Task { await go() } }
            if let err = state.vaultError { Text(err).font(.subheadline.weight(.semibold)) }
            MButton(title: state.vaultBusy ? "Unlocking…" : "Unlock", icon: "lock.open") { Task { await go() } }
                .disabled(state.vaultBusy)
            Button { withAnimation(DS.spring) { recovery.toggle(); secret = ""; state.vaultError = nil } } label: {
                Text(recovery ? "Use passphrase" : "Use recovery code").font(.headline)
            }
            Button { Task { await state.logout() } } label: { Text("Log out").font(.subheadline).foregroundStyle(Color.dim) }
            Spacer()
        }
        .padding(DS.pad)
        .sensoryFeedback(.error, trigger: shake)
    }
    private func go() async {
        let s = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return }
        if recovery { await state.unlockWithRecovery(s) } else { await state.unlockWithPassphrase(s) }
        if state.vaultError != nil { shake += 1 }
    }
}

struct MeRecoveryOverlay: View {
    @EnvironmentObject var state: AppState
    let code: String
    @State private var saved = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            Title(text: "Recovery code", sub: "Shown once")
            Text("If you forget your passphrase, this is the only way back in. Save it somewhere safe.").foregroundStyle(Color.dim)
            MCard(inverted: true) {
                Text(code).font(.system(size: 22, weight: .bold, design: .monospaced)).frame(maxWidth: .infinity).textSelection(.enabled)
            }
            Button { UIPasteboard.general.string = code } label: { Chip(text: "Copy") }.buttonStyle(.press)
            Toggle("I saved my recovery code", isOn: $saved).font(.headline)
            MButton(title: "Done", icon: "checkmark") { state.recoveryCodeToShow = nil }
                .disabled(!saved).opacity(saved ? 1 : 0.3)
            Spacer()
        }
        .padding(DS.pad)
        .background(Color.paper.ignoresSafeArea())
    }
}

struct MeFaceLock: View {
    let unlock: () async -> Void
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            BigIcon(name: "faceid", size: 44, inverted: true)
            Text("MeOS is locked").font(.largeTitle.bold())
            MButton(title: "Unlock with \(BiometricLock.biometryName)", icon: "faceid") { Task { await unlock() } }
            Spacer()
        }
        .padding(DS.pad)
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await unlock()
        }
    }
}
