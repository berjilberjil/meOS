import SwiftUI

/// Today, one day per page.
///
/// Why a `TabView` and not a gesture: the day used to be turned by a
/// `simultaneousGesture(DragGesture)` layered on top of the vertical scroll
/// view. "Simultaneous" is literal — an angled flick scrolled the page *and*
/// flipped the day, and because the day change swapped every card inside the
/// same scroll view while keeping the same offset, you also landed somewhere
/// you had not scrolled to. That is the wobble.
///
/// A paged `TabView` hands the conflict to UIKit, which resolves it the way
/// every Apple app does: the first few points of the drag decide the axis and
/// the loser never fires. And because each day is its own page with its own
/// `ScrollView`, a day change cannot move your scroll position — each day
/// simply remembers where it was.
///
/// Pages are cheap: only the current page and its two neighbours build a real
/// `TodayView`, so swiping never waits on a build, and the ~100 pages you are
/// not looking at cost one `Color.clear` each.
struct TodayPager: View {
    @EnvironmentObject var state: AppState
    var go: (NavTab) -> Void

    /// How far back you can page. Forward is capped by `DayPaging` so you can't
    /// swipe into empty future forever.
    private static let backDays = 120

    @State private var day = AppState.dateKey(Date())

    var body: some View {
        let days = self.days
        let current = days.firstIndex(of: day) ?? Self.backDays

        TabView(selection: $day) {
            ForEach(Array(days.enumerated()), id: \.element) { index, date in
                page(date, live: abs(index - current) <= 1)
                    .tag(date)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        // Turning the page is not arriving on a screen. Without this every card
        // on the incoming day fades up from zero as it slides in, which reads as
        // the page failing to draw rather than as polish.
        .environment(\.knEntrances, false)
        .background(Palette.bg.ignoresSafeArea())
        // The day list is anchored to "today", so it has to move when midnight
        // does — otherwise the page you are on quietly becomes yesterday's.
        .onChange(of: state.todayKey) { _, today in
            // `self.days`, not the `days` captured above — that one is still
            // anchored to yesterday at the moment this fires.
            if !self.days.contains(day) { day = today }
        }
    }

    /// today − backDays … today + DayPaging.maxForwardDays.
    private var days: [String] {
        let today = state.todayKey
        return (-Self.backDays...DayPaging.maxForwardDays).map { AppState.addDays($0, to: today) }
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
