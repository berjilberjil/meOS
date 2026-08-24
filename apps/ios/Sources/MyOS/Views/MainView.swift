import SwiftUI

/// The iOS shell — the system's `TabView`.
///
/// This replaced a hand-built dock (`IOSTabBar`) that drew its own slots, raised
/// Scan in the centre on a coloured circle, and hung hidden multi-tap gestures
/// off each slot. None of that survives a real tab bar, and none of it should:
/// Scan is an ordinary tab, and the secondary destinations it used to hide
/// (Stuff, Journal) are toolbar items, which is where Apple's own apps put them.
///
/// Every tab owns a `NavigationStack`, so screens get a real large title, a real
/// toolbar, and somewhere for `.searchable` and pushes to go. Non-Today tabs
/// keep their `ScrollView` here, because the screens themselves have never
/// supplied one — see `screen(_:)`.
struct MainView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var themeStore = ThemeStore.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: NavTab = PrefsStore.shared.resolveOpeningTab(allowed: NavTab.iosTabs)
    @State private var showSettings = false
    @ObservedObject private var signals = UISignals.shared

    private var selection: Binding<NavTab> {
        Binding(get: { tab }, set: { select($0) })
    }

    var body: some View {
        TabView(selection: selection) {
            Tab(NavTab.today.title, systemImage: NavTab.today.icon, value: NavTab.today) {
                NavigationStack {
                    // Owns its own scrolling: one scroll view per day page.
                    TodayPager(go: { select($0) })
                        .navigationTitle(NavTab.today.title)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button {
                                    showSettings = true
                                } label: {
                                    Label("Settings", systemImage: "gearshape")
                                }
                            }
                        }
                }
            }

            Tab(NavTab.fold.title, systemImage: NavTab.fold.icon, value: NavTab.fold) {
                NavigationStack {
                    screen { FoldView() }
                        .navigationTitle(NavTab.fold.title)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                NavigationLink {
                                    screen { BelongingsView() }
                                        .navigationTitle(NavTab.stuff.title)
                                } label: {
                                    Label(NavTab.stuff.title, systemImage: NavTab.stuff.icon)
                                }
                            }
                        }
                }
            }

            Tab(NavTab.scan.title, systemImage: NavTab.scan.icon, value: NavTab.scan) {
                NavigationStack {
                    screen { ScanView() }
                        .navigationTitle(NavTab.scan.title)
                }
            }

            Tab(NavTab.fitness.title, systemImage: NavTab.fitness.icon, value: NavTab.fitness) {
                NavigationStack {
                    screen { FitnessView() }
                        .navigationTitle(NavTab.fitness.title)
                }
            }

            Tab(NavTab.notes.title, systemImage: NavTab.notes.icon, value: NavTab.notes) {
                NavigationStack {
                    NotesView()
                        .navigationTitle(NavTab.notes.title)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                NavigationLink {
                                    screen { JournalView() }
                                        .navigationTitle(NavTab.journal.title)
                                } label: {
                                    Label(NavTab.journal.title, systemImage: NavTab.journal.icon)
                                }
                            }
                        }
                }
            }
        }
        .preferredColorScheme(themeStore.theme.colorScheme)
        .overlay(alignment: .bottomTrailing) {
            ChatWidget()
                .padding(.trailing, ChatWidget.edgeInset)
                .padding(.bottom, ChatWidget.edgeInset)
        }
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

    /// Screens other than Today have never carried their own `ScrollView` — the
    /// shell has always supplied it. Keep doing that, inside the stack.
    @ViewBuilder
    private func screen<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            content()
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
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

    private func select(_ newValue: NavTab) {
        if newValue != tab { Haptics.selection() }
        tab = newValue
        PrefsStore.shared.lastTab = newValue   // so reopening resumes here
    }
}
