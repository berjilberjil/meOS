import SwiftUI

/// The iOS shell — the system's `TabView`.
///
/// This replaced a hand-built dock (`IOSTabBar`) that drew its own slots, raised
/// Scan in the centre on a coloured circle, and hung hidden multi-tap gestures
/// off each slot. Scan is an ordinary tab now, and the secondary destinations
/// that dock used to hide are toolbar items.
///
/// Every tab owns a `NavigationStack`, so screens get a real title, a real
/// toolbar, and somewhere for `.searchable` and pushes to go. The screens
/// themselves must NOT also draw a title — theirs are `#if os(macOS)` now, or
/// you get the heading twice.
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
                    // each with its own vertical ScrollView. That means there is
                    // no single scroll view for a large title to track, and a
                    // large title with nothing to collapse against just sits on
                    // top of the page — which is exactly what it did. Inline.
                    TodayPager(go: { select($0) })
                        // No title at all here — the tab bar already says
                        // Today, and the page leads with the day and date.
                        .navigationTitle("")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button { showSettings = true } label: {
                                    Label("Settings", systemImage: "gearshape")
                                }
                            }
                        }
                }
            }

            Tab(NavTab.productivity.title, systemImage: NavTab.productivity.icon, value: NavTab.productivity) {
                NavigationStack {
                    screen { ProductivityView() }
                        .navigationTitle(NavTab.productivity.title)
                        .navigationBarTitleDisplayMode(.inline)
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
                        .navigationBarTitleDisplayMode(.inline)
                }
            }

            Tab(NavTab.fitness.title, systemImage: NavTab.fitness.icon, value: NavTab.fitness) {
                NavigationStack {
                    screen { FitnessView() }
                        .navigationTitle(NavTab.fitness.title)
                        .navigationBarTitleDisplayMode(.inline)
                }
            }

            Tab(NavTab.notes.title, systemImage: NavTab.notes.icon, value: NavTab.notes) {
                NavigationStack {
                    NotesView()
                        .navigationTitle(NavTab.notes.title)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                NavigationLink {
                                    // JournalView owns this title — it swaps
                                    // with the Events/Journal segment.
                                    screen { JournalView() }
                                } label: {
                                    Label(NavTab.journal.title, systemImage: NavTab.journal.icon)
                                }
                            }
                        }
                }
            }
        }
        // Content scrolls under the bar, so the bar needs its material. Without
        // this the tab labels sat directly on top of the cards.
        .toolbarBackground(.visible, for: .tabBar)
        .preferredColorScheme(themeStore.theme.colorScheme)
        .overlay(alignment: .bottomTrailing) {
            // This overlay covers the whole TabView, tab bar included, so it has
            // to clear the bar itself — it was landing on the Notes tab button.
            ChatWidget()
                .padding(.trailing, ChatWidget.edgeInset)
                .padding(.bottom, ChatWidget.edgeInset + 52)
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
