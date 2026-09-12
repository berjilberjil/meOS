import SwiftUI

// NavTab now lives in Support/Navigation.swift, shared with iOS.

struct MainView: View {
    // No `AppState` here on purpose: the shell must not rebuild when a module
    // ticks (live activity, chat, sync). Status that does need the store lives
    // in `SidebarStatusView` below and invalidates only itself.
    @ObservedObject private var themeStore = ThemeStore.shared
    @ObservedObject private var signals = UISignals.shared
    @State private var tab: NavTab = MainView.openingTab()

    /// Which tab a freshly-built `MainView` should show.
    ///
    /// On the first build of the process that is the launch-tab preference. On
    /// any later one it is wherever you actually are — the view is rebuilt when
    /// the appearance changes, and being thrown back to the launch tab because
    /// you picked a colour would be absurd.
    nonisolated(unsafe) private static var hasLaunched = false
    private static func openingTab() -> NavTab {
        defer { hasLaunched = true }
        return hasLaunched ? PrefsStore.shared.lastTab : PrefsStore.shared.resolveOpeningTab()
    }
    private static let kCollapsed = "myos.sidebar.collapsed"
    @State private var collapsed = UserDefaults.standard.bool(forKey: MainView.kCollapsed)
    /// Tabs already visited this launch. The content view keeps its identity
    /// across tab switches (no `.id(tab)` remount), so a branch's cards would
    /// otherwise replay their rise-in entrance on every return. Entrances run
    /// on first arrival only — the same rule `TodayPager` applies to day pages
    /// via `knEntrances = false`.
    @State private var seenTabs: Set<NavTab> = []

    var body: some View {
        // A plain HStack, NOT NavigationSplitView. The split view auto-injects a
        // window toolbar (the sidebar-toggle button) whose grey glass material was
        // the "unwanted grey band" up top. The app draws its own always-visible
        // rail, so we don't need it — this removes the toolbar at the source.
        HStack(spacing: 0) {
            sidebar
                .frame(width: collapsed ? 68 : 216)
                .animation(.knNormal, value: collapsed)

            // A ZStack of one: the background + chat-widget overlay below hang off
            // this container, and a Group would re-apply them per branch.
            ZStack {
                // Macro Intelligence is a screen, not a dialog: it takes the whole
                // content area the way a tab does, keeping the rail to get back.
                // `openMacro` overlays every tab, so it has to be cleared when a
                // tab is chosen — otherwise clicking the sidebar moved the
                // highlight and persisted `lastTab` while the content area sat
                // on Macro Intelligence, looking frozen.
                if signals.openMacro {
                    MacroPulseView(onClose: { signals.openMacro = false })
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.opacity)
                } else if tab == .notes {
                    NotesView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .environment(\.knEntrances, !seenTabs.contains(tab))
                } else {
                    ScrollView {
                        Group {
                            switch tab {
                            case .today:   TodayView(go: { switchTo($0) })
                            case .scan:    ScanView()
                            case .events:  EventsView()
                            case .fold: FoldView()
                            case .stuff: BelongingsView()
                            case .gallery: GalleryView()
                            case .fitness: FitnessView()
                            case .productivity: ProductivityView()
                            case .journal: JournalView()
                            case .notes:   EmptyView()
                            case .profile: ProfileView()
                            case .settings: SettingsView()
                            }
                        }
                        // Top padding clears the hidden title bar / traffic-light zone;
                        // the bottom padding keeps content clear of the chat widget's corner.
                        // Events gets the full window width (the calendar fills the screen).
                        .padding(.horizontal, 28).padding(.top, 30).padding(.bottom, 96)
                        .frame(maxWidth: tab == .events ? .infinity : 1120)
                        .frame(maxWidth: .infinity)
                    }
                    // The content view keeps its identity across tabs: no `.id(tab)`
                    // remount, no fade. Re-keying destroyed and rebuilt the whole
                    // screen on every sidebar click.
                    //
                    // A tab is marked seen when it is left, not when it is
                    // entered: the incoming branch reads the flag at insertion,
                    // and marking the new tab in the same transaction would flip
                    // its entrance off mid-flight.
                    .environment(\.knEntrances, !seenTabs.contains(tab))
                    .onChange(of: tab) { old, _ in seenTabs.insert(old) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .pageBackground()
            .overlay(alignment: .bottomTrailing) {
                ChatWidget()
                        .padding(.trailing, ChatWidget.edgeInset)
                        .padding(.bottom, ChatWidget.edgeInset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background)
        .animation(.knTheme, value: themeStore.theme.id)
        .tint(Palette.accent)
        .onChange(of: tab) { _, _ in Haptics.selection() }
        // A tapped notification parks its destination in `UISignals`; the Mac
        // had no one taking it, so every banner just brought the window forward
        // and left you where you were.
        .onAppear { consumeRoute() }
        .onChange(of: signals.pendingRoute) { _, _ in consumeRoute() }
        // Tapped the Friday report notification.
        .onAppear { consumeWeeklySignal() }
        .onChange(of: signals.openWeeklyReport) { _, on in if on { consumeWeeklySignal() } }
    }

    @State private var foldTaps = 0
    @State private var lastFoldTap = Date.distantPast

    private func consumeWeeklySignal() {
        guard signals.openWeeklyReport else { return }
        signals.openWeeklyReport = false
        switchTo(.settings)
    }

    /// Take a tapped notification's destination and go there.
    ///
    /// Only the tabs the Mac actually has. A meal reminder on the Mac opens
    /// Today, which is where its editor lives.
    private func consumeRoute() {
        guard let route = signals.pendingRoute else { return }
        signals.pendingRoute = nil
        switch route {
        case .events:                                   switchTo(.events)
        case .workout:                                  switchTo(.fitness)
        case .weekly:                                   switchTo(.settings)
        case .today, .weight, .steps,
             .breakfast, .lunch, .dinner:               switchTo(.today)
        }
    }

    private func switchTo(_ t: NavTab) {
        // Macro Intelligence overlays every tab, so choosing one has to close
        // it. Without this the sidebar highlight moved and `lastTab` was
        // persisted while the content area stayed on Macro — the app looked
        // stuck, and the next launch opened a tab that had never been shown.
        signals.openMacro = false
        withAnimation(.knPop) { tab = t }
        PrefsStore.shared.lastTab = t   // so reopening resumes here
    }

    /// One click → Stuff. Two quick clicks → Fold (money).
    private func tapFold() {
        let now = Date()
        if now.timeIntervalSince(lastFoldTap) < 0.45 { foldTaps += 1 } else { foldTaps = 1 }
        lastFoldTap = now
        if foldTaps >= 2 {
            foldTaps = 0
            switchTo(.fold)
        } else {
            switchTo(.stuff)
        }
    }

    private var sidebar: some View {
        VStack(alignment: collapsed ? .center : .leading, spacing: 4) {
            sidebarHeader

            ForEach(NavTab.allCases) { t in
                NavItem(tab: t, active: tab == t || (t == .fold && tab == .stuff), collapsed: collapsed) {
                    if t == .fold { tapFold() } else { switchTo(t) }
                }
                    .padding(.horizontal, collapsed ? 10 : 8)
            }

            Spacer()

            SidebarStatusView(collapsed: collapsed)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // The rail is the same near-black as a card, separated from the canvas
        // by a hairline. It does not change colour with the open tab — that was
        // the loudest part of the old palette. It stays opaque on purpose: no
        // content scrolls underneath a full-height desktop rail, so a
        // translucent material (§12) would buy nothing here.
        .background(Palette.sidebar.ignoresSafeArea())
        .overlay(alignment: .trailing) {
            Rectangle().fill(Palette.border).frame(width: 1)
        }
    }

    // Logo + wordmark + a collapse/expand toggle. Collapsed: logo over the toggle.
    private var sidebarHeader: some View {
        let logo = Image("LogoMark")
            .resizable().interpolation(.high)
            .frame(width: 32, height: 32)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .knShadow()
        let toggle = Button {
            collapsed.toggle()
            UserDefaults.standard.set(collapsed, forKey: Self.kCollapsed)
        } label: {
            Image(systemName: "sidebar.left").font(.footnote.weight(.semibold))
        }
        .buttonStyle(.borderless).tint(Palette.faint)
        .help(collapsed ? "Expand sidebar" : "Collapse sidebar")

        return Group {
            if collapsed {
                VStack(spacing: 10) { logo; toggle }
                    .padding(.top, 30).padding(.bottom, 14)
            } else {
                HStack(spacing: 9) {
                    logo
                    Text("MyOS")
                        .font(.title2.weight(.heavy))
                        .foregroundStyle(Palette.action)
                    Spacer(minLength: 0)
                    toggle
                }
                .padding(.horizontal, 14).padding(.top, 34).padding(.bottom, 16)
            }
        }
    }
}

/// The only part of the Mac shell that observes `AppState`: the sync-error
/// line, Task Mode, and logout. Everything else in the rail is static, so a
/// store tick invalidates this footer alone — never the sidebar or content.
private struct SidebarStatusView: View {
    @EnvironmentObject var state: AppState
    var collapsed: Bool

    var body: some View {
        VStack(spacing: 0) {
            if let err = state.lastSyncError ?? state.lastHydrateError {
                Group {
                    if collapsed {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.footnote).help(err)
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill").font(.caption2)
                            Text(err).lineLimit(2)
                        }
                        .font(.caption2)
                    }
                }
                .foregroundStyle(Palette.attention)
                .padding(.horizontal, 14).padding(.bottom, 10)
            }

            Button { state.setTaskMode(true) } label: {
                if collapsed {
                    Image(systemName: "target").font(.subheadline)
                        .frame(width: 44, height: 30)
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "target")
                        Text("TASK MODE")
                            .font(.caption.weight(.heavy)).tracking(0.6)
                        Spacer(minLength: 0)
                    }
                }
            }
            .buttonStyle(.borderless).tint(Palette.success)
            .padding(.horizontal, 8).padding(.bottom, 4)
            .help("Hide everything but today's task")

            Button { Task { await state.logout() } } label: {
                if collapsed {
                    Image(systemName: "rectangle.portrait.and.arrow.right").font(.subheadline)
                        .frame(width: 44, height: 30)
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                        Text(state.username.isEmpty ? "Log out" : "@\(state.username)")
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }
            }
            .buttonStyle(.borderless).tint(Palette.faint)
            .padding(.horizontal, 8).padding(.bottom, 12)
            .help(collapsed ? (state.username.isEmpty ? "Log out" : "@\(state.username)") : "")
        }
    }
}

/// A sidebar navigation row: cartoon glyph + uppercase label. Active shows the
/// Duolingo blue-outlined pill; icons stay full-color in every state.
private struct NavItem: View {
    let tab: NavTab
    let active: Bool
    var collapsed: Bool = false
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.md) {
                NavGlyph(tab: tab, size: 22)
                if !collapsed {
                    Text(tab.title.uppercased())
                        .font(.footnote.weight(.semibold))
                        .tracking(0.6)
                    Spacer(minLength: 0)
                }
            }
            // One colour decision for the whole row: green when this is where
            // you are, muted white when it is not.
            .foregroundStyle(active ? Palette.action : (hover ? Palette.text : Palette.muted))
            .frame(maxWidth: collapsed ? .infinity : nil)
            .padding(.horizontal, collapsed ? 8 : 12).padding(.vertical, 9)
            .background(background, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(active ? Palette.action.opacity(0.55) : .clear, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        // Press-down physics (§1): the row answers the instant the click lands,
        // not on release. Plain chrome — the tint already carries the meaning.
        .buttonStyle(FluidPressStyle(scale: 0.99))
        .onHover { h in hover = h; cursor(h) }
        .animation(.knFast, value: hover)
        .animation(.knFast, value: active)
        .help(collapsed ? tab.title : "")
    }

    private var background: Color {
        if active { return Palette.action.opacity(0.12) }
        if hover { return Palette.surfaceElevated }
        return .clear
    }
}
