import Foundation

/// Everything the weight dial knows that isn't drawing.
///
/// Weight is the one number in meOS you change by feel rather than by typing:
/// thumb on the glass, eyes on the readout, one tick of haptics per 50 g. That
/// only works if the arithmetic underneath is exact — a dial that drifts to
/// 72.99999 or banks a hundred phantom detents against its own floor is a dial
/// you stop trusting after a week. So the maths lives here, in front of a test,
/// and the view is left with nothing to get wrong but pixels.
enum WeightDial {

    // MARK: - What a movement is worth

    /// One detent of the dial. Fifty grams — the resolution a day's drift
    /// actually has.
    static let fineStep: Double = 0.05

    /// One tap of a cap button. Half a kilo, for when the number is simply in
    /// the wrong place and you don't want to turn thirty times to say so.
    static let coarseStep: Double = 0.5

    /// Rotation per detent. Fifteen degrees puts 24 ticks in a revolution —
    /// 1.2 kg a turn, which is a full sweep of the thumb for a change you'd
    /// actually make in a week.
    static let degreesPerDetent: Double = 15

    // MARK: - What a weight is

    static let minKg: Double = 20
    static let maxKg: Double = 300
    /// Only reached when the app holds no number about your body at all.
    static let fallbackKg: Double = 70

    /// Into the human range. NaN is not a small number or a large one — it is
    /// the absence of one, so it lands on the fallback rather than an edge.
    static func clamp(_ kg: Double) -> Double {
        guard !kg.isNaN else { return fallbackKg }
        return min(max(kg, minKg), maxKg)
    }

    /// To the nearest 50 g, and to two decimal places exactly.
    ///
    /// Binary floating point cannot hold 0.05, so twenty honest additions of it
    /// land on 72.99999999999999 and the readout says 72.99 for what the user
    /// just counted out as 73. Snapping after every movement — not only before
    /// display — keeps the stored number and the shown number the same thing.
    static func snap(_ kg: Double) -> Double {
        guard kg.isFinite else { return kg }
        return ((kg / fineStep).rounded() * fineStep * 100).rounded() / 100
    }

    /// Turn the dial by `detents`, signed. Clockwise is heavier.
    static func stepped(_ kg: Double, detents: Int) -> Double {
        snap(clamp(kg + Double(detents) * fineStep))
    }

    /// Tap a cap, by `delta` kg.
    static func nudged(_ kg: Double, by delta: Double) -> Double {
        snap(clamp(kg + delta))
    }

    // MARK: - Where the first number comes from

    /// The weight the dial opens on.
    ///
    /// `Profile` holds a height but no weight — in meOS your weight *is* the
    /// fitness history, so "from the profile" means the last day you logged
    /// one. Precedence: what today already says, then the most recent day that
    /// said anything, then the goal you're aiming at (the only other number the
    /// app holds about your body), then a number that is admittedly a guess.
    static func seed(logged: Double?, latest: Double?, target: Double?) -> Double {
        for candidate in [logged, latest, target] {
            guard let c = candidate, c.isFinite, c > 0 else { continue }
            return clamp(snap(c))
        }
        return fallbackKg
    }

    // MARK: - Reading it back

    /// The number as you would say it: `73`, `72.5`, `72.35`. Never `73.00`.
    ///
    /// Bounded by *magnitude* before the `Int` conversion, not by `clamp` — this
    /// formats deltas as well as weights, and a clamp into the human range turns
    /// a 350 g change into 20 kg. What it still has to prevent is the trap:
    /// `Int(_: Double)` crashes rather than saturating, and this runs against
    /// whatever is on the dial right now, including a number that arrived from
    /// sync.
    static func format(_ kg: Double) -> String {
        guard kg.isFinite else { return format(fallbackKg) }
        let v = snap(min(max(kg, -maxKg), maxKg))
        if v == v.rounded() { return String(Int(v)) }
        let oneDecimal = (v * 10).rounded() / 10
        if abs(v - oneDecimal) < 1e-9 { return String(format: "%.1f", v) }
        return String(format: "%.2f", v)
    }

    /// How far today has moved from a reference weight — `+0.35`, `−0.5`, or
    /// nil when there is nothing to compare against or nothing has moved.
    /// A true minus sign, not a hyphen: it sits beside the readout.
    static func deltaLabel(_ kg: Double, from previous: Double?) -> String? {
        guard let previous, previous.isFinite, kg.isFinite else { return nil }
        let d = snap(kg) - snap(previous)
        guard abs(d) >= fineStep / 2 else { return nil }
        return (d > 0 ? "+" : "\u{2212}") + format(abs(d))
    }
}

/// Accumulated rotation of a thumb around the dial.
///
/// Its whole reason to exist is the seam. `atan2` runs +π…−π, so a thumb
/// crossing nine o'clock produces a difference of nearly a full circle for a
/// movement of a millimetre — and the weight jumps 1.2 kg backwards in the
/// middle of a spin. Unwrapping the delta into the short way round fixes that;
/// keeping a running total rather than rounding each sample means the small
/// movements a real finger makes add up instead of each rounding to nothing.
struct DialRotation {
    private var lastAngle: Double?
    /// Signed degrees since the touch began.
    private var accumulated: Double = 0
    /// Detents already handed to the caller, so each is reported exactly once.
    private var emitted: Int = 0

    /// Thumb lifted. The next touch starts a fresh turn from wherever it lands
    /// — without this, putting a finger down on the other side of the dial
    /// reads as having swept there.
    mutating func reset() {
        lastAngle = nil
        accumulated = 0
        emitted = 0
    }

    /// Feed the current thumb angle in radians (`atan2(dy, dx)` about the dial
    /// centre). Returns the detents crossed since the last call — signed, and
    /// normally 0 or ±1. Positive is clockwise, which is heavier.
    mutating func update(radians: Double) -> Int {
        guard radians.isFinite else { return 0 }
        defer { lastAngle = radians }
        guard let last = lastAngle else { return 0 }

        var delta = radians - last
        if delta > .pi { delta -= 2 * .pi }
        if delta < -.pi { delta += 2 * .pi }

        accumulated += delta * 180 / .pi
        let total = Int((accumulated / WeightDial.degreesPerDetent).rounded(.towardZero))
        let crossed = total - emitted
        emitted = total
        return crossed
    }
}
