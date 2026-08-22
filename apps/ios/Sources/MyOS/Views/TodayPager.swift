import SwiftUI

/// Today, one day per page.
///
/// Why a `TabView` and not a gesture: the day used to be turned by a
/// `simultaneousGesture(DragGesture)` layered on top of the vertical scroll
/// view. "Simultaneous" is literal — an angled flick scrolled the page *and*
/// flipped the day, and because the day change swapped every card inside the
/// same scroll view while keeping the same offset, you also landed somewhere
/// you had not scrolled to.
///
/// A paged `TabView` hands the conflict to UIKit, which resolves it the way
/// every Apple app does: the first few points of the drag decide the axis and
/// the loser never fires. And because each day is its own page with its own
/// `ScrollView`, a day change cannot move your scroll position — each day
/// simply remembers where it was.
///
/// **Everything here is about not doing work mid-swipe.** UIKit asks for the
/// neighbouring page the instant a drag begins, so anything expensive in a
/// page's first render is felt as the page turn hesitating. Hence: the day list
/// is built once and kept (deriving it per render meant 128 date conversions a
/// pass), a page you have already visited is never torn back down, and pages
/// you have not been near cost one `Color.clear` each.
struct TodayPager: View {
    @EnvironmentObject var state: AppState
    var go: (NavTab) -> Void

    /// How far back you can page. Forward is capped by `DayPaging` so you can't
    /// swipe into empty future forever.
    private static let backDays = 120

    @State private var day = AppState.dateKey(Date())
    @State private var days: [String] = []
    /// Index of every day, so finding the current page is a lookup rather than
    /// a scan of the whole window on each render.
    @State private var index: [String: Int] = [:]
    /// Pages that have been built. Kept built: rebuilding a day you are swiping
    /// back to is the one hitch a pager can least afford.
    @State private var visited: Set<String> = []

    var body: some View {
        let current = index[day] ?? Self.backDays

        TabView(selection: $day) {
            ForEach(days, id: \.self) { date in
                page(date, live: abs((index[date] ?? 0) - current) <= 1 || visited.contains(date))
                    .tag(date)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        // Turning the page is not arriving on a screen. Without this every card
        // on the incoming day fades up from zero as it slides in, which reads as
        // the page failing to draw rather than as polish.
        .environment(\.knEntrances, false)
        .background(Palette.bg.ignoresSafeArea())
        .onAppear(perform: rebuildWindow)
        // The window is anchored to "today", so it has to move when midnight
        // does — otherwise the page you are on quietly becomes yesterday's.
        .onChange(of: state.todayKey) { _, _ in rebuildWindow() }
        .onChange(of: day) { _, now in
            visited.insert(now)
            trimVisited(around: now)
        }
    }

    /// today − backDays … today + DayPaging.maxForwardDays.
    private func rebuildWindow() {
        let today = state.todayKey
        let window = (-Self.backDays...DayPaging.maxForwardDays).map { AppState.addDays($0, to: today) }
        guard window != days else { return }
        days = window
        index = Dictionary(uniqueKeysWithValues: window.enumerated().map { ($0.element, $0.offset) })
        if index[day] == nil { day = today }
        visited.insert(day)
    }

    /// Keeping every page you ever opened would grow without bound over a long
    /// session; a fortnight either side covers any realistic back-and-forth.
    private func trimVisited(around date: String) {
        guard let here = index[date], visited.count > 32 else { return }
        visited = visited.filter { abs((index[$0] ?? 0) - here) <= 14 }
        visited.insert(date)
    }

    @ViewBuilder
    private func page(_ date: String, live: Bool) -> some View {
        if live {
            ScrollView {
                TodayView(go: go, externalDate: Binding(get: { date }, set: { day = $0 }))
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 128)   // clears the dock + chat widget
            }
            .scrollIndicators(.hidden)
        } else {
            Color.clear
        }
    }
}
