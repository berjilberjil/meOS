import SwiftUI

/// The iOS shell — custom dock with Scan raised in the center.
struct MainView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var themeStore = ThemeStore.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: NavTab = NavTab.resolveLaunch(PrefsStore.shared.launchTab.rawValue, allowed: NavTab.iosTabs)
    @State private var notesTaps = 0
    @State private var lastNotesTap = Date.distantPast
    @State private var foldTaps = 0
    @State private var lastFoldTap = Date.distantPast
    @State private var showSettings = false

    var body: some View {
        ZStack {
            Palette.bg.ignoresSafeArea()

            NavigationStack {
                ScrollView {
                    content
                        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 108)
                }
                .background(Palette.bg.ignoresSafeArea())
                .toolbar(.hidden, for: .navigationBar)
            }
            .id(tab)

            VStack(spacing: 0) {
                Spacer()
                HStack {
                    Spacer()
                    ChatWidget().padding(.trailing, 16).padding(.bottom, 8)
                }
                IOSTabBar(
                    tab: Binding(get: { tab }, set: { select($0) }),
                    onScan: {
                        UISignals.shared.openScanCamera = true
                        select(.scan)
                    },
                    onSettings: { showSettings = true },
                    onNotesTap: { tapNotes() },
                    onFoldTap: { tapFold() }
                )
            }
        }
        .animation(.knTheme, value: themeStore.theme.id)
        .preferredColorScheme(themeStore.theme.colorScheme)
        .sheet(isPresented: $showSettings) { SettingsView() }
        .task {
            await FavoritesBodyImporter.sync()
            await HealthSteps.syncToday(into: state)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task {
                    await state.pullRemote()
                    await FavoritesBodyImporter.sync()
                    await HealthSteps.syncToday(into: state)
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .today:   TodayView(go: { select($0) })
        case .fold:    FoldView()
        case .stuff:   BelongingsView()
        case .scan:    ScanView()
        case .fitness: FitnessView()
        case .notes:   NotesView()
        case .journal: JournalView()
        case .events:  EventsView()
        default:       TodayView(go: { select($0) })
        }
    }

    private func select(_ newValue: NavTab) {
        if newValue != tab { Haptics.selection() }
        tab = newValue
    }

    /// 1 tap → Notes. 2 → new note. 3 → Journal. 5 → hidden notes (Face ID).
    private func tapNotes() {
        let now = Date()
        if now.timeIntervalSince(lastNotesTap) < 0.55 { notesTaps += 1 } else { notesTaps = 1 }
        lastNotesTap = now
        select(.notes)
        Task { @MainActor in
            let count = notesTaps
            try? await Task.sleep(nanoseconds: 550_000_000)
            guard notesTaps == count else { return }
            notesTaps = 0
            if count >= 5 {
                Haptics.success()
                UISignals.shared.revealHiddenNotes = true
            } else if count >= 3 {
                Haptics.success()
                select(.journal)
            } else if count == 2 {
                state.requestNewNote()
            }
        }
    }

    /// 1 tap → Fold. 2 taps → Stuff (what you own + daily cost).
    private func tapFold() {
        let now = Date()
        if now.timeIntervalSince(lastFoldTap) < 0.45 { foldTaps += 1 } else { foldTaps = 1 }
        lastFoldTap = now
        if foldTaps >= 2 {
            foldTaps = 0
            Haptics.success()
            select(.stuff)
            return
        }
        select(.fold)
    }
}
