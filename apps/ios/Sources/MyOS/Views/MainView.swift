import SwiftUI

/// The iOS shell — a bottom tab bar (the natural mobile pattern), replacing the
/// mac app's persistent sidebar. Every tab reuses the exact same content views
/// and the exact same AppState/APIClient as the mac app; only the container
/// around them is iOS-native.
///
/// Each content view (FinanceView, FitnessView, JournalView…) already draws its
/// own big title as its first element — so the nav bar stays hidden here rather
/// than showing the screen name a second time.
struct MainView: View {
    @EnvironmentObject var state: AppState
    @State private var tab: NavTab = .today

    var body: some View {
        ZStack {
            TabView(selection: $tab) {
                page(.today) {
                    VStack(alignment: .leading, spacing: 14) {
                        QuickLogBar()
                        TodayView(go: { tab = $0 })
                    }
                }
                page(.finance) { FinanceView() }
                page(.fitness) { FitnessView() }
                page(.journal) { JournalView() }
                page(.settings) { SettingsView() }
            }
            .tint(Palette.brand)

            // The floating mentor — same widget as mac, pinned above the tab bar.
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    ChatWidget().padding(.trailing, 16).padding(.bottom, 78)
                }
            }
        }
        .background(Palette.bg.ignoresSafeArea())
    }

    /// One tab: scrollable content, re-keyed so cards replay their entrance
    /// animation each time you switch in. No nav bar — content owns its title.
    private func page<Content: View>(_ t: NavTab, @ViewBuilder content: @escaping () -> Content) -> some View {
        NavigationStack {
            ScrollView {
                content()
                    .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 32)
            }
            .background(Palette.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .id(t)
        .tabItem { Label(t.title, systemImage: t.icon) }
        .tag(t)
    }
}
