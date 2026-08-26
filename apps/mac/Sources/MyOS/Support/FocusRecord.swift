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

    /// Which day's plan holds a given to-do.
    ///
    /// The focus timer used to bank its minutes into `days[todayKey]` with
    /// `todayKey` re-read from the clock at the moment it finished. A block
    /// begun at 23:50 and ended at 00:15 therefore looked for its to-do in a day
    /// that had just turned over and did not contain it, so the write silently
    /// did nothing — and since the timer had already drained its counter, the
    /// twenty-five minutes were gone rather than merely unrecorded. Completing
    /// that block failed the same way and left the task unticked.
    ///
    /// Today is checked first so the common case costs one lookup, and the rest
    /// are walked newest-first so a duplicated id can only resolve forwards.
    static func dayOwning(todo id: String, in days: [String: DayPlan], today: String) -> String? {
        if days[today]?.todos.contains(where: { $0.id == id }) == true { return today }
        return days.keys.sorted(by: >).first { key in
            days[key]?.todos.contains { $0.id == id } == true
        }
    }
}
