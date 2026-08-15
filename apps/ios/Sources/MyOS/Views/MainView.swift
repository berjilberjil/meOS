import SwiftUI

/// The iOS shell — a bottom tab bar (the natural mobile pattern), replacing the
/// mac app's persistent sidebar. Every tab reuses the exact same content views
/// and the exact same AppState/APIClient as the mac app; only the container
/// around them is iOS-native.
///
/// Each content view (FoldView, FitnessView, JournalView…) already draws its
/// own big title as its first element — so the nav bar stays hidden here rather
/// than showing the screen name a second time.
struct MainView: View {
    @EnvironmentObject var state: AppState
    @State private var tab: NavTab = NavTab.resolveLaunch(PrefsStore.shared.launchTab.rawValue, allowed: NavTab.iosTabs)
    @State private var showSettings = false

    var body: some View {
        ZStack {
            TabView(selection: $tab) {
                page(.today) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Spacer()
                            Button { showSettings = true } label: {
                                Image(systemName: "gearshape.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Palette.muted)
                                    .frame(width: 34, height: 34)
                                    .background(Palette.surface, in: Circle())
                            }
                        }
                        QuickLogBar()
                        TodayView(go: { tab = $0 })
                    }
                }
                page(.fold) { FoldView() }
                page(.fitness) { FitnessView() }
                page(.journal) { JournalView() }
                page(.notes) { NotesView() }
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
        .sheet(isPresented: $showSettings) { SettingsView() }
        .onChange(of: tab) { _, _ in Haptics.selection() }
    }

    /// One tab: scrollable content, re-keyed so cards replay their entrance
    /// animation each time you switch in. No nav bar — content owns its title.
    private func page<Content: View>(_ t: NavTab, @ViewBuilder content: @escaping () -> Content) -> some View {
        NavigationStack {
            ScrollView {
                content()
                    // Extra bottom clearance so the last row (e.g. the Fitness tab's
                    // "Weekly meal plan / Scan food photo / New food" row) isn't
                    // covered by the floating chat FAB + tab bar.
                    .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 96)
            }
            .background(Palette.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .id(t)
        .tabItem { Label(t.title, systemImage: t.icon) }
        .tag(t)
    }
}
