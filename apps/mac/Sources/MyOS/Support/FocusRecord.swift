import Foundation

/// How the daily focus list went, day by day. Pure math over the day spine so the
/// calendar, the streak and the tests all read the same rules.
enum FocusRecord {
    enum Verdict {
        case empty      // nothing was on the list
        case missed     // things were listed, none got done
        case partial
        case done
    }

    static func verdict(_ todos: [FocusItem]) -> Verdict {
        guard !todos.isEmpty else { return .empty }
        let done = todos.filter(\.done).count
        if done == todos.count { return .done }
        return done > 0 ? .partial : .missed
    }

    /// Consecutive clean days counting back from `today`. Today itself is never a
    /// miss — the day isn't over — so an empty or half-finished today just doesn't
    /// add to the streak; the count carries on from yesterday.
    static func streak(days: [String: DayPlan], today: Date = Date(), limit: Int = 400) -> Int {
        var streak = 0
        var cursor = today
        for step in 0..<limit {
            let key = CalMath.dateKey(cursor)
            guard let back = CalMath.cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            defer { cursor = back }
            if verdict(days[key]?.todos ?? []) == .done {
                streak += 1
            } else if step > 0 {
                break
            }
        }
        return streak
    }

    /// Minutes actually spent in focus blocks on a day.
    static func focusedMinutes(_ todos: [FocusItem]) -> Int {
        todos.reduce(0) { $0 + $1.spent } / 60
    }
}
