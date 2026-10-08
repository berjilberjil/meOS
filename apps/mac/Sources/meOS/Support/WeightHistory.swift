import Foundation

/// The maths behind the weight chart: which weigh-ins fall in a range,
/// and what the range says.
///
/// Separate from the view because it is the part that can be wrong in a
/// way you would not notice by looking. A chart draws something
/// plausible from bad input — a trend line through a window that quietly
/// dropped its first point still looks like a trend.
///
/// Main-actor, because the day math it leans on is. `AppState`'s
/// `dayCalendar` keeps a mutable static cache of the calendar and the
/// current time zone — worth it, since a Today render derives well over
/// a hundred day keys — and that cache is only safe because everything
/// touching it is on one actor. Reaching it from a nonisolated context
/// would be a data race, not a convenience.
@MainActor
enum WeightHistory {

    /// How far back the chart looks.
    enum Range: String, CaseIterable, Identifiable, Hashable {
        case month, quarter, year, all

        var id: String { rawValue }

        var label: String {
            switch self {
            case .month:   return "30D"
            case .quarter: return "90D"
            case .year:    return "1Y"
            case .all:     return "All"
            }
        }

        /// Days back from today, or nil for everything on record.
        var days: Int? {
            switch self {
            case .month:   return 30
            case .quarter: return 90
            case .year:    return 365
            case .all:     return nil
            }
        }
    }

    /// One weigh-in: the day key it was logged against, and the kilos.
    ///
    /// `date` is stored rather than computed. Nested types do not
    /// inherit the enclosing `@MainActor`, so a computed one could not
    /// reach the day math at all — and resolving it once here beats
    /// resolving it again for every mark the chart draws.
    struct Point: Equatable, Identifiable {
        let day: String        // yyyy-MM-dd
        let kg: Double
        /// The day as a `Date`, for the chart's x-axis.
        let date: Date
        var id: String { day }
    }

    /// Every weigh-in in `range`, oldest first.
    ///
    /// Zero and negative weights are dropped rather than plotted. The
    /// field is an optional `Double` that several older paths wrote `0`
    /// into to mean "cleared", and a zero on this chart is not a light
    /// day — it rescales the whole y-axis and flattens every real
    /// reading into a line along the top.
    static func series(_ fitness: [String: FitnessDay],
                       range: Range,
                       today: String) -> [Point] {
        let cutoff = range.days.map { AppState.addDays(-$0, to: today) }
        return fitness.compactMap { key, day -> Point? in
            guard let kg = day.weightKg, kg > 0 else { return nil }
            if let cutoff, key < cutoff { return nil }   // yyyy-MM-dd sorts as it dates
            // A key that will not parse is not a day. Dropped rather
            // than given a fallback of `Date()`, which would plot every
            // malformed entry on top of today.
            guard let date = AppState.date(fromKey: key) else { return nil }
            return Point(day: key, kg: kg, date: date)
        }
        .sorted { $0.day < $1.day }
    }

    /// What the range is worth saying out loud.
    struct Summary: Equatable {
        /// Newest minus oldest across the range. Negative is a loss.
        let change: Double
        let lightest: Double
        let heaviest: Double
        let latest: Double
        /// Weigh-ins in the range.
        let count: Int
    }

    /// nil when there is nothing to summarise. One weigh-in is enough
    /// for a reading — its change is simply zero — but zero is not.
    static func summary(_ points: [Point]) -> Summary? {
        guard let first = points.first, let last = points.last else { return nil }
        let values = points.map(\.kg)
        return Summary(change: last.kg - first.kg,
                       lightest: values.min() ?? last.kg,
                       heaviest: values.max() ?? last.kg,
                       latest: last.kg,
                       count: points.count)
    }

    /// The y-axis window: the data's own span with a little air, never
    /// anchored to zero.
    ///
    /// A weight chart zeroed at the origin is a flat line — the
    /// interesting range is three kilos out of eighty. Padding is a
    /// tenth of the span, floored at half a kilo so a week of nearly
    /// identical readings does not render as a jagged mountain with a
    /// 0.05kg axis either. Both failure modes are the same mistake:
    /// letting the data decide the scale without a floor or a ceiling.
    static func domain(_ points: [Point], target: Double?) -> ClosedRange<Double> {
        var values = points.map(\.kg)
        // The goal line has to be inside the window or it is drawn
        // clipped to an edge, which reads as "you are exactly on target".
        if let target, target > 0 { values.append(target) }
        guard let lo = values.min(), let hi = values.max() else { return 0...1 }
        let pad = max(0.5, (hi - lo) * 0.1)
        return (lo - pad)...(hi + pad)
    }
}
