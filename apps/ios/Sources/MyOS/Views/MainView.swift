import SwiftUI

/// The iOS shell — custom dock with Scan raised in the center.
struct MainView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var themeStore = ThemeStore.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: NavTab = PrefsStore.shared.resolveOpeningTab(allowed: NavTab.iosTabs)
    @State private var notesTaps = 0
    @State private var lastNotesTap = Date.distantPast
    @State private var foldTaps = 0
    @State private var lastFoldTap = Date.distantPast
    @State private var showSettings = false
    @ObservedObject private var signals = UISignals.shared

    var body: some View {
        ZStack {
            Palette.bg.ignoresSafeArea()

            // No NavigationStack: nothing here pushes, and a stack whose bar is
            // hidden re-negotiates the scroll view's safe-area inset after the
            // first layout — which shows up as the page quietly re-seating
            // itself while you are already scrolling.
            Group {
                if tab == .today {
                    // Owns its own scrolling: one scroll view per day page.
                    TodayPager(go: { select($0) })
                } else {
                    ScrollView {
                        content
                            .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 128)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .id(tab)

            VStack(spacing: 0) {
                Spacer()
                HStack {
                    Spacer()
                    ChatWidget()
                        .padding(.trailing, ChatWidget.edgeInset)
                        .padding(.bottom, ChatWidget.edgeInset)
                }
                .padding(.bottom, 72)
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
        // Tapped the Friday report notification. SettingsView clears the flag
        // once it is up, and opens on the report.
        .onChange(of: signals.openWeeklyReport) { _, on in if on { showSettings = true } }
        // Every heavy import lives here, not in the cards. Today is paged by
        // day, so a card-level `.task` runs once per live page — i.e. three
        // times, and again on every swipe.
        .task { await refreshFeeds() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task {
                    await state.pullRemote()
                    await refreshFeeds()
                }
            }
        }
    }

    /// Photos, steps and anything shared in from outside. `drainShareInbox`
    /// runs last so a video shared while the app was away is appended to fresh
    /// state rather than a stale copy.
    private func refreshFeeds() async {
        await FavoritesBodyImporter.sync()
        await ProgressPhotoSync.syncAll()
        await HealthSteps.syncRecent(into: state)
        await state.drainShareInbox()
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
        PrefsStore.shared.lastTab = newValue   // so reopening resumes here
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

    /// 1 tap → Stuff. 2 taps → Fold (money).
    private func tapFold() {
        let now = Date()
        if now.timeIntervalSince(lastFoldTap) < 0.45 { foldTaps += 1 } else { foldTaps = 1 }
        lastFoldTap = now
        if foldTaps >= 2 {
            foldTaps = 0
            Haptics.success()
            select(.fold)
            return
        }
        select(.stuff)
    }
}
