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
/// The two platforms need different plumbing: on iOS a horizontal swipe is a
/// `DragGesture`, gated on horizontal dominance so it never steals the vertical
/// scroll. On macOS a two-finger trackpad swipe is NOT a drag — it arrives as
/// `scrollWheel`, which SwiftUI does not surface, so an AppKit view bridges it.
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
            // Anything more vertical than horizontal belongs to the scroll view.
            guard abs(dx) > abs(dy) else { super.scrollWheel(with: event); return }

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

private struct DayPagerModifier: ViewModifier {
    @Binding var date: String
    let today: String

    func body(content: Content) -> some View {
        #if os(macOS)
        content.background(HorizontalScrollCatcher { delta in
            withAnimation(.easeOut(duration: 0.18)) {
                date = DayPaging.step(date, by: delta, today: today)
            }
        })
        #else
        content.simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    // Horizontal dominance gate: without this the page would
                    // fight the vertical scroll on every slightly-angled flick.
                    guard abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
                    let delta = value.translation.width < 0 ? 1 : -1
                    withAnimation(.easeOut(duration: 0.18)) {
                        date = DayPaging.step(date, by: delta, today: today)
                    }
                }
        )
        #endif
    }
}

extension View {
    /// Page `date` by day on horizontal swipe / two-finger trackpad swipe.
    func dayPager(date: Binding<String>, today: String) -> some View {
        modifier(DayPagerModifier(date: date, today: today))
    }
}
