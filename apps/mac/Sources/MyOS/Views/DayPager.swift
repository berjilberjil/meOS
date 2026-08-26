import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Horizontal day paging for the whole Today page.
///
/// One date drives every card, so the screen always shows one coherent day
/// rather than cards disagreeing with each other. Swipe left for the next day,
/// right for the previous.
///
/// The two platforms need different plumbing. **iOS does not use this modifier
/// at all** — `TodayPager` puts each day in its own page of a paged `TabView`,
/// so UIKit's own directional lock decides between "you are scrolling" and "you
/// are turning the page" and the two can never both win. (It used to be a
/// `simultaneousGesture(DragGesture)` layered over the vertical scroll view;
/// "simultaneous" is exactly what it says, so one angled flick both scrolled the
/// page and flipped the day. That is the wobble.) On macOS a two-finger trackpad
/// swipe is NOT a drag — it arrives as `scrollWheel`, which SwiftUI does not
/// surface, so an AppKit view bridges it.
@MainActor
enum DayPaging {
    /// How far into the future paging is allowed. Past is unbounded (data only
    /// goes back so far anyway); the future would otherwise scroll into empty
    /// space forever.
    static let maxForwardDays = 7

    /// Step `date` by `delta` days, clamped to today + `maxForwardDays`.
    static func step(_ date: String, by delta: Int, today: String) -> String {
        let next = AppState.addDays(delta, to: date)
        let limit = AppState.addDays(maxForwardDays, to: today)
        return next > limit ? date : next
    }

    /// Human label for the paged date: "Today", "Yesterday", "Tomorrow", or a date.
    static func label(_ date: String, today: String) -> String {
        if date == today { return "Today" }
        if date == AppState.addDays(-1, to: today) { return "Yesterday" }
        if date == AppState.addDays(1, to: today) { return "Tomorrow" }
        guard let d = AppState.date(fromKey: date) else { return date }
        let f = DateFormatter()
        f.dateFormat = "EEE d MMM"
        return f.string(from: d)
    }
}

#if os(macOS)
/// Catches two-finger horizontal trackpad swipes and forwards everything else
/// up the responder chain so vertical scrolling still works.
private struct HorizontalScrollCatcher: NSViewRepresentable {
    var onSwipe: (Int) -> Void

    func makeNSView(context: Context) -> CatcherView {
        let v = CatcherView()
        v.onSwipe = onSwipe
        return v
    }

    func updateNSView(_ nsView: CatcherView, context: Context) { nsView.onSwipe = onSwipe }

    final class CatcherView: NSView {
        var onSwipe: ((Int) -> Void)?
        private var accumulated: CGFloat = 0
        private var firedThisGesture = false

        /// Points of horizontal travel before a page turn. High enough that a
        /// slightly-diagonal vertical scroll never trips it.
        private let threshold: CGFloat = 50

        override func scrollWheel(with event: NSEvent) {
            let dx = event.scrollingDeltaX, dy = event.scrollingDeltaY

            // Phase first, THEN the dominance test. A phase marker carries zero
            // deltas, so `abs(0) > abs(0)` is false and .ended/.cancelled were
            // handed to the scroll view before they could ever clear the latch.
            // On a machine where .began also arrives with no deltas, the first
            // swipe set `firedThisGesture` and nothing ever unset it — day
            // paging died for the rest of the process.
            switch event.phase {
            case .began:
                accumulated = 0
                firedThisGesture = false
            case .ended, .cancelled:
                accumulated = 0
                firedThisGesture = false
                return
            default:
                break
            }

            // Anything more vertical than horizontal belongs to the scroll view.
            guard abs(dx) > abs(dy) else { super.scrollWheel(with: event); return }

            guard !firedThisGesture else { return }
            accumulated += dx
            if abs(accumulated) >= threshold {
                firedThisGesture = true
                // Natural scrolling: pushing content left (negative dx) means
                // "go forward", matching the iOS swipe direction.
                onSwipe?(accumulated < 0 ? 1 : -1)
                accumulated = 0
            }
        }
    }
}
#endif

#if os(macOS)
private struct DayPagerModifier: ViewModifier {
    @Binding var date: String
    let today: String

    func body(content: Content) -> some View {
        content.background(HorizontalScrollCatcher { delta in
            withAnimation(.knFast) {
                date = DayPaging.step(date, by: delta, today: today)
            }
        })
    }
}
#endif

extension View {
    /// Page `date` by day on a two-finger trackpad swipe (macOS only).
    ///
    /// `enabled` is false when something outside owns the day — on iOS
    /// `TodayPager` does, and a second pager fighting it is how you get two
    /// different answers to "which day am I on".
    @ViewBuilder
    func dayPager(date: Binding<String>, today: String, enabled: Bool = true) -> some View {
        #if os(macOS)
        if enabled { modifier(DayPagerModifier(date: date, today: today)) } else { self }
        #else
        self
        #endif
    }
}
