import SwiftUI

/// The iOS shell — the system's `TabView`.
///
/// Replaced a hand-built dock (`IOSTabBar`). Scan is an ordinary tab now, and
/// the destinations that dock hid behind multi-taps are toolbar items.
///
/// Titles sit **leading**, not centred: the bar stays compact (`.inline`) and the
/// name is a `topBarLeading` toolbar item, so a screen gets its name without the
/// large-title block eating the top of the page. Screens must therefore NOT draw
/// their own title — theirs are `#if os(macOS)`.
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
                    // Owns its own scrolling: a horizontal pager of day pages,
                    // each with its own vertical ScrollView.
                    TodayPager(go: { select($0) })
                        .chrome(NavTab.today.title)
                }
            }

            Tab(NavTab.productivity.title, systemImage: NavTab.productivity.icon, value: NavTab.productivity) {
                NavigationStack {
                    // Not wrapped in `screen`: it brings its own ScrollView so it
                    // can pin the "log a video" bar to the bottom.
                    ProductivityView()
                        .chrome(NavTab.productivity.title)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                NavigationLink {
                                    screen { BelongingsView() }
                                        .navigationTitle(NavTab.stuff.title)
                                        .navigationBarTitleDisplayMode(.inline)
                                        .toolbarBackground(.visible, for: .tabBar)
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
                        .chrome(NavTab.scan.title)
                }
            }

            Tab(NavTab.fitness.title, systemImage: NavTab.fitness.icon, value: NavTab.fitness) {
                NavigationStack {
                    screen { FitnessView() }
                        .chrome(NavTab.fitness.title)
                }
            }

            Tab(NavTab.notes.title, systemImage: NavTab.notes.icon, value: NavTab.notes) {
                NavigationStack {
                    NotesView()
                        .chrome(NavTab.notes.title)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                NavigationLink {
                                    // JournalView owns that title — it swaps with
                                    // the Events/Journal segment.
                                    screen { JournalView() }
                                        .navigationBarTitleDisplayMode(.inline)
                                        .toolbarBackground(.visible, for: .tabBar)
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
            // This overlay covers the whole TabView, tab bar included, so it has
            // to clear the bar itself.
            ChatWidget()
                .padding(.trailing, ChatWidget.edgeInset)
                .padding(.bottom, ChatWidget.edgeInset + 52)
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        // Settings is the last row of the Today page now, not a toolbar gear.
        .onChange(of: signals.openSettings) { _, on in
            if on { signals.openSettings = false; showSettings = true }
        }
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

    /// Screens other than Today and Productivity carry no `ScrollView` of their
    /// own — the shell has always supplied it.
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

private extension View {
    /// One screen's bar: compact, name on the left, and a tab bar that actually
    /// draws its material. Applied per tab — `.toolbarBackground` set on the
    /// TabView itself does not reach the bars inside each tab, which is why
    /// content was showing through the tab labels.
    func chrome(_ title: String) -> some View {
        self
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .tabBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text(title).font(.headline)
                }
            }
    }
}
