import SwiftUI

/// Today, one day per page.
///
/// The iOS pager, ported. The reasoning carries over verbatim: a lazy paging
/// `ScrollView` (`LazyHStack` + `.scrollTargetBehavior(.paging)`) so the next
/// day already exists, laid out and drawn, before the trackpad flick arrives —
/// nothing is built during the gesture. Pages stay aligned on the same
/// section, so paging to a neighbouring day arrives where you left the day
/// you were on.
///
/// Mac differences: the page-turn is a trackpad swipe (the same axis-lock
/// UIScrollView applies on the phone), the bottom clearance clears the chat
/// widget instead of the iOS tab bar, and turning a page never replays card
/// entrances.
struct TodayPager: View {
    var go: (NavTab) -> Void

    /// Swiping is for nearby days. Jumping somewhere far away is what the
    /// calendar in Settings is for, which is why this window is small enough
    /// to stay cheap.
    private static let backDays = 30

    @ObservedObject private var signals = UISignals.shared

    @State private var day: String? = AppState.dateKey(Date())
    /// Section id every page is aligned on.
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
        // Turning the page is not arriving on a screen. Without this every
        // card on the incoming day fades up from zero as it slides in.
        .environment(\.knEntrances, false)
        .background(Palette.background)
        .onAppear { rebuildWindow(); consumeAnchor() }
        // The window is anchored to "today", so it has to move when midnight does.
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in rebuildWindow() }
        .onChange(of: signals.todayAnchor) { _, _ in consumeAnchor() }
    }

    /// A notification asked for a particular card. Reminders are always about
    /// today, so this turns the page back to today before scrolling.
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
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 80)   // clears the chat widget
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
        // What "today" was before this rebuild — the page the user is on if
        // they have not navigated. Moving only when the current day falls out
        // of the window left the pager parked on yesterday at every rollover.
        let wasToday = days.count > Self.backDays ? days[Self.backDays] : nil
        days = window
        if day == nil || !window.contains(day!) || day == wasToday { day = today }
    }
}
