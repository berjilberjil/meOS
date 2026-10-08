import SwiftUI

/// The rebuilt Mac shell.
///
/// The old Mac shell was a hand-rolled sidebar with its own chrome, a splash
/// screen and a collapsed-rail state machine. This one is the system's
/// `NavigationSplitView` on the white canvas: the sidebar is a plain `List`,
/// the detail is a `NavigationStack` per tab, and nothing is hand-drawn that
/// the platform draws better.
///
/// The wiring is the iOS shell's, adapted to sidebar navigation: same routes,
/// same sync hooks, same chat widget, same settings sheet. No `AppState` here
/// on purpose — a sync or chat tick must never rebuild the shell, so feed and
/// sync work lives in `SyncHooks`, an invisible view.
struct MainView: View {
    @State private var tab: NavTab = PrefsStore.shared.resolveOpeningTab(allowed: WhiteTheme.tabs)
    @State private var showSettings = false
    /// Drives the programmatic push to the Journal screen from a notification.
    @State private var showJournal = false
    @ObservedObject private var signals = UISignals.shared

    private var selection: Binding<NavTab> {
        Binding(get: { tab }, set: { select($0) })
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 216, max: 260)
        } detail: {
            detail
        }
        .tint(Palette.accent)
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .overlay(alignment: .bottomTrailing) {
            ChatWidget()
                .padding(.trailing, ChatWidget.edgeInset)
                .padding(.bottom, ChatWidget.edgeInset)
        }
        // A tapped notification. Consumed on appear as well as on change:
        // from a cold launch the route is delivered before this view exists,
        // so `.onChange` alone misses it.
        .onAppear { consumeRoute() }
        .onChange(of: signals.pendingRoute) { _, _ in consumeRoute() }
        .onChange(of: signals.openSettings) { _, on in
            if on { signals.openSettings = false; showSettings = true }
        }
        // Tapped the Friday report notification. SettingsView clears the flag
        // once it is up, and opens on the report.
        .onChange(of: signals.openWeeklyReport) { _, on in if on { showSettings = true } }
        .background(SyncHooks())
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: selection) {
            Section {
                ForEach(WhiteTheme.tabs) { t in
                    Label(t.title, systemImage: t.icon)
                        .tag(t)
                }
            }
            Section {
                Button { showSettings = true } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Palette.background)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        switch tab {
        case .today:
            // Owns its own scrolling: a horizontal pager of day pages, each
            // with its own vertical ScrollView.
            TodayPager(go: select)

        case .productivity:
            // Not wrapped in `screen`: it brings its own ScrollView so it can
            // pin the "log a video" bar to the bottom.
            NavigationStack {
                ProductivityView()
                    .toolbar {
                        ToolbarItemGroup(placement: .primaryAction) {
                            NavigationLink {
                                screen { GalleryView() }
                            } label: {
                                Label(NavTab.gallery.title, systemImage: NavTab.gallery.icon)
                            }
                            NavigationLink {
                                screen { BelongingsView() }
                            } label: {
                                Label(NavTab.stuff.title, systemImage: NavTab.stuff.icon)
                            }
                        }
                    }
            }

        case .scan:
            NavigationStack { screen { ScanView() } }

        case .fitness:
            NavigationStack { screen { FitnessView() } }

        case .notes:
            NavigationStack {
                NotesView()
                    // The same destination the toolbar link pushes, reachable
                    // without a tap — a tapped event reminder has to be able
                    // to open the screen it is about.
                    .navigationDestination(isPresented: $showJournal) {
                        screen { JournalView() }
                    }
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            NavigationLink {
                                screen { JournalView() }
                            } label: {
                                Label(NavTab.journal.title, systemImage: NavTab.journal.icon)
                            }
                        }
                    }
            }

        case .events:
            NavigationStack { screen { EventsView() } }

        default:
            NavigationStack { screen { TodayPager(go: select) } }
        }
    }

    /// Screens other than Today and Productivity carry no `ScrollView` of
    /// their own — the shell supplies it, the way the iOS shell does.
    @ViewBuilder
    private func screen<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            content()
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(Palette.background)
    }

    // MARK: - Routes

    /// Take a tapped notification to the thing it is about. The tab is only
    /// the first half — a lunch reminder that lands on Today and leaves you
    /// to find Meals has not really taken you anywhere — so the second half
    /// is handed on to the page itself.
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
            // Its own sidebar item on the Mac — one `select` away.
            select(.events)
        }
    }

    private func select(_ newValue: NavTab) {
        if newValue != tab { Haptics.selection() }
        tab = newValue
        PrefsStore.shared.lastTab = newValue   // so reopening resumes here
    }
}

/// Feed + sync work for the shell, isolated in one invisible view.
///
/// The only thing here that observes `AppState`. A sync/chat/activity tick
/// invalidates this empty view — never the sidebar or its content.
///
/// The iOS shell's hooks also pull HealthKit steps and the Favorites body
/// importer; both are iOS-only sources, and a Mac has neither, so they are
/// simply absent here. Photos sync and the share inbox are the same calls the
/// phone makes.
private struct SyncHooks: View {
    @EnvironmentObject var state: AppState
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .task { await Self.refreshFeeds(into: state) }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task {
                        await state.pullRemote()
                        await Self.refreshFeeds(into: state)
                    }
                }
            }
    }

    /// Anything shared in from outside. `drainShareInbox` runs last so
    /// something shared while the app was away is appended to fresh state.
    static func refreshFeeds(into state: AppState) async {
        await ProgressPhotoSync.syncAll()
        await state.drainShareInbox()
    }
}
