import SwiftUI

// NavTab now lives in Support/Navigation.swift, shared with iOS.

struct MainView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var themeStore = ThemeStore.shared
    @State private var tab: NavTab = PrefsStore.shared.launchTab
    private static let kCollapsed = "myos.sidebar.collapsed"
    @State private var collapsed = UserDefaults.standard.bool(forKey: MainView.kCollapsed)

    var body: some View {
        // A plain HStack, NOT NavigationSplitView. The split view auto-injects a
        // window toolbar (the sidebar-toggle button) whose grey glass material was
        // the "unwanted grey band" up top. The app draws its own always-visible
        // rail, so we don't need it — this removes the toolbar at the source.
        HStack(spacing: 0) {
            sidebar
                .frame(width: collapsed ? 68 : 216)
                .animation(.knNormal, value: collapsed)

            ZStack(alignment: .bottom) {
                // Notes manages its own scrolling (its editor hosts an NSScrollView);
                // every other tab shares the standard scrolling container.
                if tab == .notes {
                    NotesView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        Group {
                            switch tab {
                            case .today:   TodayView(go: { switchTo($0) })
                            case .scan:    ScanView()
                            case .events:  EventsView()
                            case .fold: FoldView()
                            case .stuff: BelongingsView()
                            case .fitness: FitnessView()
                            case .productivity: ProductivityView()
                            case .journal: JournalView()
                            case .notes:   EmptyView()
                            case .profile: ProfileView()
                            case .settings: SettingsView()
                            }
                        }
                        // Top padding clears the hidden title bar / traffic-light zone;
                        // the tall bottom padding keeps content clear of the floating log bar.
                        // Events gets the full window width (the calendar fills the screen).
                        .padding(.horizontal, 28).padding(.top, 30).padding(.bottom, 104)
                        .frame(maxWidth: tab == .events ? .infinity : 1120)
                        .frame(maxWidth: .infinity)
                    }
                    // Re-key on tab so each screen's cards replay the rise-in entrance.
                    .id(tab)
                    .transition(.opacity)
                }

                // The AI command bar now floats at the bottom center. Trailing inset
                // leaves room for the chat widget's corner.
                if tab != .today && tab != .scan {
                    QuickLogBar()
                        .padding(.horizontal, 28)
                        .frame(maxWidth: 1080)
                        .frame(maxWidth: .infinity)
                        .padding(.trailing, 64)
                        .padding(.bottom, 18)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.bg.ignoresSafeArea())
            .overlay(alignment: .bottomTrailing) {
                ChatWidget().padding(.trailing, 20).padding(.bottom, 18)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.bg.ignoresSafeArea())
        .animation(.knTheme, value: themeStore.theme.id)
        .onChange(of: tab) { _, _ in Haptics.selection() }
    }

    @State private var foldTaps = 0
    @State private var lastFoldTap = Date.distantPast

    private func switchTo(_ t: NavTab) {
        withAnimation(.knPop) { tab = t }
    }

    /// One click → Fold. Two quick clicks → Stuff.
    private func tapFold() {
        let now = Date()
        if now.timeIntervalSince(lastFoldTap) < 0.45 { foldTaps += 1 } else { foldTaps = 1 }
        lastFoldTap = now
        if foldTaps >= 2 {
            foldTaps = 0
            switchTo(.stuff)
        } else {
            switchTo(.fold)
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

            if let err = state.lastSyncError ?? state.lastHydrateError {
                Group {
                    if collapsed {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 13)).help(err)
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10))
                            Text(err).lineLimit(2)
                        }
                        .font(.system(size: 11))
                    }
                }
                .foregroundStyle(Palette.amber)
                .padding(.horizontal, 14).padding(.bottom, 10)
            }

            Button { Task { await state.logout() } } label: {
                if collapsed {
                    Image(systemName: "rectangle.portrait.and.arrow.right").font(.system(size: 15))
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
            .buttonStyle(KGhostButtonStyle(color: Palette.faint))
            .padding(.horizontal, 8).padding(.bottom, 12)
            .help(collapsed ? (state.username.isEmpty ? "Log out" : "@\(state.username)") : "")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Palette.sidebar.ignoresSafeArea())
        .overlay(alignment: .trailing) {
            Rectangle().fill(Palette.border).frame(width: 2)
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
            Image(systemName: "sidebar.left").font(.system(size: 14, weight: .semibold))
        }
        .buttonStyle(KIconButtonStyle(size: 28, color: Palette.faint))
        .help(collapsed ? "Expand sidebar" : "Collapse sidebar")

        return Group {
            if collapsed {
                VStack(spacing: 10) { logo; toggle }
                    .padding(.top, 30).padding(.bottom, 14)
            } else {
                HStack(spacing: 9) {
                    logo
                    Text("MyOS")
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(Palette.brand)
                    Spacer(minLength: 0)
                    toggle
                }
                .padding(.horizontal, 14).padding(.top, 34).padding(.bottom, 16)
            }
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
            HStack(spacing: 12) {
                NavGlyph(tab: tab, size: 26)
                if !collapsed {
                    Text(tab.title.uppercased())
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .tracking(0.6)
                        .foregroundStyle(active ? tab.tint : (hover ? Palette.text : Palette.muted))
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: collapsed ? .infinity : nil)
            .padding(.horizontal, collapsed ? 8 : 12).padding(.vertical, 9)
            .background(background, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(active ? tab.tint : .clear, lineWidth: 2)
            )
            .contentShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(KPressStyle())
        .onHover { h in hover = h; cursor(h) }
        .animation(.knFast, value: hover)
        .animation(.knFast, value: active)
        .help(collapsed ? tab.title : "")
    }

    private var background: Color {
        if active { return tab.tint.opacity(0.16) }
        if hover { return Palette.surface2.opacity(0.5) }
        return .clear
    }
}
