import SwiftUI

/// Today, one day per page.
///
/// Three attempts got here, so the reasoning is worth keeping.
///
/// **Not a gesture.** The day was originally turned by a
/// `simultaneousGesture(DragGesture)` layered over the vertical scroll view.
/// "Simultaneous" is literal, so one angled flick both scrolled the page and
/// flipped the day.
///
/// **Not a `TabView` either.** Paging by `TabView` fixed the gesture conflict —
/// UIKit's directional lock decides the axis and the loser never fires — but a
/// `UIPageViewController` asks for the neighbouring page *at the moment the
/// drag begins*. So the incoming day was built with a finger already moving,
/// and a whole `TodayView` is nine cards of work. That is the stutter: the page
/// follows, hesitates while it builds, then catches up.
///
/// **A lazy paging `ScrollView`.** A `LazyHStack` materialises a little beyond
/// what is visible, so the next day already exists — laid out, drawn — before
/// you touch the screen. Nothing is built during the drag. Paging feel is
/// native (`scrollTargetBehavior(.paging)`), the axis lock is UIScrollView's
/// own, and there are no placeholder pages to swap in and out.
///
/// **Pages stay lined up.** Each day scrolls independently, so an unvisited day
/// used to sit at the top while the day you were leaving was scrolled down —
/// mid-swipe you saw two pages at different heights. Every page now tracks the
/// same *section*: the page you are on publishes which section is at the top,
/// and the others follow. Swipe from Meals and you arrive at Meals.
struct TodayPager: View {
    // No `AppState` here on purpose: every materialized page (~3 `TodayView`s)
    // used to rebuild mid-swipe on any store tick. The window is anchored to
    // the calendar day, observed via the system day-change note.
    var go: (NavTab) -> Void

    /// Swiping is for nearby days. Jumping somewhere far away is what the
    /// calendar in Settings is for, which is why this window is small enough
    /// to stay cheap.
    private static let backDays = 30

    @ObservedObject private var signals = UISignals.shared

    @State private var day: String? = AppState.dateKey(Date())
    /// Section id every page is aligned on — see the note above.
    @State private var anchor: String? = TodayView.headerAnchor
    @State private var days: [String] = []

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(days, id: \.self) { date in
                    page(date).containerRelativeFrame(.horizontal)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $day)
        .scrollIndicators(.hidden)
        // Turning the page is not arriving on a screen. Without this every card
        // on the incoming day fades up from zero as it slides in.
        .environment(\.knEntrances, false)
        .background(Palette.background)
        .onAppear { rebuildWindow(); consumeAnchor() }
        // The window is anchored to "today", so it has to move when midnight does.
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in rebuildWindow() }
        .onChange(of: signals.todayAnchor) { _, _ in consumeAnchor() }
    }

    /// A notification asked for a particular card. Reminders are always about
    /// today, so this turns the page back to today before scrolling — tapping
    /// "log your weight" while parked on last Tuesday must not log it there.
    private func consumeAnchor() {
        guard let target = signals.todayAnchor else { return }
        signals.todayAnchor = nil
        day = AppState.dateKey(Date())
        withAnimation(.knNormal) { anchor = target }
    }

    private func page(_ date: String) -> some View {
        ScrollView {
            TodayView(go: go,
                      externalDate: Binding(get: { date }, set: { day = $0 }),
                      sectionAnchors: true)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 128)   // clears the dock + chat widget
        }
        .scrollIndicators(.hidden)
        .scrollPosition(id: anchorBinding(for: date), anchor: .top)
    }

    /// Every page reads the shared anchor; only the page you are actually on
    /// writes to it, or two pages would argue about where the top is.
    private func anchorBinding(for date: String) -> Binding<String?> {
        Binding(
            get: { anchor },
            set: { new in if date == day { anchor = new } }
        )
    }

    /// today − backDays … today + DayPaging.maxForwardDays.
    private func rebuildWindow() {
        let today = AppState.dateKey(Date())
        let window = (-Self.backDays...DayPaging.maxForwardDays).map { AppState.addDays($0, to: today) }
        guard window != days else { return }
        // What "today" was before this rebuild — the page the user is on if they
        // have not navigated. Moving only when the current day falls *out* of
        // the window left the pager parked on yesterday at every rollover, since
        // yesterday is still comfortably inside today−30…today+7: open the app
        // at 08:00 after using it at 23:55 and every meal, step and workout tap
        // wrote to the previous day.
        let wasToday = days.count > Self.backDays ? days[Self.backDays] : nil
        days = window
        if day == nil || !window.contains(day!) || day == wasToday { day = today }
    }
}
