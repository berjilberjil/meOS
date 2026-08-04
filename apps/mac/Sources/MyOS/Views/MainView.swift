import SwiftUI

enum NavTab: String, CaseIterable, Identifiable {
    case today, finance, fitness, journal, notes, profile, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .today: return "Today"
        case .finance: return "Finance"
        case .fitness: return "Fitness"
        case .journal: return "Journal"
        case .notes: return "Notes"
        case .profile: return "Profile"
        case .settings: return "Settings"
        }
    }
    var icon: String {
        switch self {
        case .today: return "sun.max.fill"
        case .finance: return "indianrupeesign.circle.fill"
        case .fitness: return "figure.run"
        case .journal: return "book.closed.fill"
        case .notes: return "note.text"
        case .profile: return "person.crop.circle.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

struct MainView: View {
    @EnvironmentObject var state: AppState
    @State private var tab: NavTab = .today

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 204, ideal: 216, max: 240)
                .toolbarBackground(.hidden, for: .windowToolbar)
        } detail: {
            VStack(spacing: 0) {
                QuickLogBar()
                    // Clear the hidden title bar / traffic-light zone so the quick-log
                    // bar never collides with the window controls at the top.
                    .padding(.horizontal, 28).padding(.top, 30).padding(.bottom, 12)
                    .frame(maxWidth: 1120)
                    .frame(maxWidth: .infinity)

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
                            case .finance: FinanceView()
                            case .fitness: FitnessView()
                            case .journal: JournalView()
                            case .notes:   EmptyView()
                            case .profile: ProfileView()
                            case .settings: SettingsView()
                            }
                        }
                        .padding(.horizontal, 28).padding(.top, 6).padding(.bottom, 28)
                        .frame(maxWidth: 1120)
                        .frame(maxWidth: .infinity)
                    }
                    // Re-key on tab so each screen's cards replay the rise-in entrance.
                    .id(tab)
                    .transition(.opacity)
                }
            }
            .background(Palette.bg)
            .toolbarBackground(.hidden, for: .windowToolbar)
            .overlay(alignment: .bottomTrailing) {
                ChatWidget().padding(20)
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    private func switchTo(_ t: NavTab) {
        withAnimation(.knPop) { tab = t }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 9) {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(LinearGradient(colors: [Palette.brand, Palette.brandDeep],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 30, height: 30)
                    .overlay(
                        Text("M")
                            .font(.system(size: 18, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                    )
                    .knShadow()
                Text("MyOS")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(Palette.brand)
            }
            .padding(.horizontal, 14).padding(.top, 30).padding(.bottom, 16)

            ForEach(NavTab.allCases) { t in
                NavItem(tab: t, active: tab == t) { switchTo(t) }
                    .padding(.horizontal, 8)
            }

            Spacer()

            if let err = state.lastSyncError ?? state.lastHydrateError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10))
                    Text(err).lineLimit(2)
                }
                .font(.system(size: 11))
                .foregroundStyle(Palette.amber)
                .padding(.horizontal, 14).padding(.bottom, 10)
            }

            Button { Task { await state.logout() } } label: {
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                    Text(state.username.isEmpty ? "Log out" : "@\(state.username)")
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(KGhostButtonStyle(color: Palette.faint))
            .padding(.horizontal, 8).padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Palette.sidebar)
        .overlay(alignment: .trailing) {
            Rectangle().fill(Palette.border).frame(width: 2)
        }
    }
}

/// A sidebar navigation row: cartoon glyph + uppercase label. Active shows the
/// Duolingo blue-outlined pill; icons stay full-color in every state.
private struct NavItem: View {
    let tab: NavTab
    let active: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                NavGlyph(tab: tab, size: 26)
                Text(tab.title.uppercased())
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .tracking(0.6)
                    .foregroundStyle(active ? Palette.blue : (hover ? Palette.text : Palette.muted))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(background, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(active ? Palette.blue : .clear, lineWidth: 2)
            )
            .contentShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(KPressStyle())
        .onHover { h in hover = h; cursor(h) }
        .animation(.knFast, value: hover)
        .animation(.knFast, value: active)
    }

    private var background: Color {
        if active { return Palette.blue.opacity(0.13) }
        if hover { return Palette.surface2.opacity(0.5) }
        return .clear
    }
}
