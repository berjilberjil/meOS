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
    /// Drives the programmatic push to Journal/Events from a notification.
    @State private var showJournal = false
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
                        .chrome(NavTab.today)
                }
            }

            Tab(NavTab.productivity.title, systemImage: NavTab.productivity.icon, value: NavTab.productivity) {
                NavigationStack {
                    // Not wrapped in `screen`: it brings its own ScrollView so it
                    // can pin the "log a video" bar to the bottom.
                    ProductivityView()
                        .chrome(NavTab.productivity)
                        .toolbar {
                            // Gallery sits beside Stuff, where Berjil asked for
                            // it — the two things this tab can push to.
                            ToolbarItem(placement: .topBarTrailing) {
                                NavigationLink {
                                    screen { GalleryView() }
                                        .navigationTitle(NavTab.gallery.title)
                                        .pushedChrome(NavTab.gallery)
                                } label: {
                                    Label(NavTab.gallery.title, systemImage: NavTab.gallery.icon)
                                }
                            }
                            ToolbarItem(placement: .topBarTrailing) {
                                NavigationLink {
                                    screen { BelongingsView() }
                                        .navigationTitle(NavTab.stuff.title)
                                        .pushedChrome(NavTab.stuff)
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
                        .chrome(NavTab.scan)
                }
            }

            Tab(NavTab.fitness.title, systemImage: NavTab.fitness.icon, value: NavTab.fitness) {
                NavigationStack {
                    screen { FitnessView() }
                        .chrome(NavTab.fitness)
                }
            }

            Tab(NavTab.notes.title, systemImage: NavTab.notes.icon, value: NavTab.notes) {
                NavigationStack {
                    NotesView()
                        .chrome(NavTab.notes)
                        // The same destination the toolbar link pushes, reachable
                        // without a tap — a tapped event reminder has to be able
                        // to open the screen it is about.
                        .navigationDestination(isPresented: $showJournal) {
                            screen { JournalView() }
                                .pushedChrome(NavTab.journal)
                        }
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                NavigationLink {
                                    // JournalView owns that title — it swaps with
                                    // the Events/Journal segment.
                                    screen { JournalView() }
                                        .pushedChrome(NavTab.journal)
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
        // A tapped notification. Consumed on appear as well as on change, and
        // that is the whole bug fix: from a killed app the route is delivered
        // before this view exists, so `.onChange` never fires and the tap did
        // nothing at all.
        .onAppear { consumeRoute() }
        .onChange(of: signals.pendingRoute) { _, _ in consumeRoute() }
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

    /// Take a tapped notification to the thing it is about.
    ///
    /// The tab is only the first half — a lunch reminder that lands on Today
    /// and leaves you to find Meals has not really taken you anywhere — so the
    /// second half is handed on to the page itself.
    private func consumeRoute() {
        guard let route = signals.pendingRoute else { return }
        signals.pendingRoute = nil
        switch route {
        case .today:
            select(.today)
        case .weight:
            select(.today)
            signals.todayAnchor = TodaySection.weight.rawValue
        case .steps:
            select(.today)
            signals.todayAnchor = TodaySection.activity.rawValue
        case .breakfast, .lunch, .dinner:
            select(.today)
            signals.pendingMeal = route.meal
        case .workout:
            select(.fitness)
        case .weekly:
            signals.openWeeklyReport = true
            showSettings = true
        case .events:
            // Events is not a tab of its own here — it is the first segment of
            // the Journal screen, which is pushed from Notes. Landing on Notes
            // and leaving you to find it is exactly the half-journey the comment
            // above warns about, so the push is programmatic.
            select(.notes)
            showJournal = true
        }
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
    func chrome(_ tab: NavTab) -> some View {
        self
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .pageBackground()
            // The bars take the canvas too. Left to itself the default bar
            // material renders a grey slab over a black page, so the top and
            // bottom of every screen read as a different colour from the middle.
            .toolbarBackground(Palette.background, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
            .toolbarBackground(Palette.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text(tab.title).font(.headline).foregroundStyle(Palette.text)
                }
            }
    }

    /// A pushed screen. Same colour treatment, but the navigation bar draws its
    /// own title so this must not plant a second one.
    func pushedChrome(_ tab: NavTab) -> some View {
        self
            .navigationBarTitleDisplayMode(.inline)
            .pageBackground()
            .toolbarBackground(Palette.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Palette.background, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
    }
}
