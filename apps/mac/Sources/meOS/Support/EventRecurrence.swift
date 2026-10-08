import Foundation

/// When a repeating event actually happens.
///
/// Occurrences are *projected*, never stored. A birthday is one row in
/// `events` with a yearly rule on it, not thirty-one rows — which means editing
/// it edits all of them, deleting it deletes all of them, and the sync blob does
/// not grow by a row a year for the rest of your life.
///
/// Pure and POSIX/gregorian throughout, for the same reason `EventVoice` is: day
/// keys are strings, and doing string-day arithmetic through the user's current
/// calendar is how an event lands a day out for half the year.
enum EventRecurrence {

    // MARK: - Calendar plumbing

    private static func calendar() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "en_US_POSIX")
        c.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return c
    }

    /// `yyyy-MM-dd` → (year, month, day), or nil if it is not a real date.
    static func parts(_ key: String) -> (y: Int, m: Int, d: Int)? {
        let f = key.split(separator: "-")
        guard f.count == 3, f[0].count == 4,
              let y = Int(f[0]), let m = Int(f[1]), let d = Int(f[2]),
              (1...12).contains(m), (1...31).contains(d),
              d <= daysIn(year: y, month: m)
        else { return nil }
        return (y, m, d)
    }

    static func key(_ y: Int, _ m: Int, _ d: Int) -> String {
        String(format: "%04d-%02d-%02d", y, m, d)
    }

    static func daysIn(year: Int, month: Int) -> Int {
        var c = DateComponents(); c.year = year; c.month = month; c.day = 1
        let cal = calendar()
        guard let date = cal.date(from: c),
              let range = cal.range(of: .day, in: .month, for: date) else { return 31 }
        return range.count
    }

    // MARK: - The next occurrence

    /// The first occurrence of `event` on or after `dayKey`.
    ///
    /// `nil` when there is none: a one-off whose day has passed, or a rule that
    /// has run past its `until`.
    static func next(_ event: EventItem, onOrAfter dayKey: String) -> String? {
        guard let anchor = parts(event.date) else { return nil }
        let rule = event.recurrence

        guard rule.repeats else {
            return event.date >= dayKey ? event.date : nil
        }
        guard parts(dayKey) != nil else { return nil }

        let candidate: String?
        switch rule.unit {
        case .none:
            candidate = nil
        case .daily:
            candidate = nextByDays(anchor: event.date, step: rule.interval, onOrAfter: dayKey)
        case .weekly:
            candidate = nextByDays(anchor: event.date, step: rule.interval * 7, onOrAfter: dayKey)
        case .monthly:
            candidate = nextByMonths(anchor: anchor, step: rule.interval, onOrAfter: dayKey)
        case .yearly:
            candidate = nextByMonths(anchor: anchor, step: rule.interval * 12, onOrAfter: dayKey)
        }

        guard let day = candidate else { return nil }
        if let until = rule.until, !until.isEmpty, day > until { return nil }
        return day
    }

    /// The occurrence strictly after `dayKey` — for walking a series forward.
    static func next(_ event: EventItem, after dayKey: String) -> String? {
        next(event, onOrAfter: EventVoice.key(addingDays: 1, to: dayKey))
    }

    /// Whole-day steps: daily and weekly. Straight arithmetic, no clamping to do.
    private static func nextByDays(anchor: String, step: Int, onOrAfter dayKey: String) -> String? {
        guard step > 0, let delta = EventVoice.dayDelta(from: anchor, to: dayKey) else { return nil }
        guard delta > 0 else { return anchor }              // the anchor is still ahead
        // Round up to the next whole step.
        let steps = (delta + step - 1) / step
        return EventVoice.key(addingDays: steps * step, to: anchor)
    }

    /// Month-stepping, which is where the two real edge cases live.
    ///
    /// The day of month is always taken from the **anchor**, then clamped to the
    /// target month's length — never carried forward from a previous clamp. So a
    /// monthly event anchored on the 31st runs 31 Jan, 28 Feb, 31 Mar, and a
    /// birthday on 29 Feb falls on the 28th in common years and back on the 29th
    /// when the next leap year comes round. Clamping the clamp instead would
    /// walk the whole series onto the 28th for good.
    private static func nextByMonths(anchor: (y: Int, m: Int, d: Int),
                                     step: Int,
                                     onOrAfter dayKey: String) -> String? {
        guard step > 0, let target = parts(dayKey) else { return nil }

        let anchorMonths = anchor.y * 12 + (anchor.m - 1)
        let targetMonths = target.y * 12 + (target.m - 1)

        var steps = max(0, Int(ceil(Double(targetMonths - anchorMonths) / Double(step))))

        // Clamping can pull a candidate to a day earlier in the month than the
        // target, so the rounded-up guess is not always far enough. At most a
        // couple of corrections — bounded anyway, so a surprise cannot hang.
        for _ in 0...4 {
            let total = anchorMonths + steps * step
            let y = total / 12
            let m = total % 12 + 1
            let day = min(anchor.d, daysIn(year: y, month: m))
            let candidate = key(y, m, day)
            if candidate >= dayKey { return candidate }
            steps += 1
        }
        return nil
    }

    // MARK: - A window of them

    /// Every occurrence between two day keys, inclusive — what the calendar
    /// paints its dots from.
    ///
    /// `cap` is a guard, not a feature: a daily event over a year window is 365
    /// entries and a Year view asks for twelve months at a time, so the ceiling
    /// keeps a rule nobody meant from turning into a hang.
    static func occurrences(_ event: EventItem,
                            from start: String,
                            to end: String,
                            cap: Int = 400) -> [String] {
        guard start <= end else { return [] }
        var out: [String] = []
        var cursor = start
        while out.count < cap, let day = next(event, onOrAfter: cursor), day <= end {
            out.append(day)
            guard event.recurrence.repeats else { break }
            cursor = EventVoice.key(addingDays: 1, to: day)
        }
        return out
    }

    // MARK: - Saying it out loud

    /// How the rule reads on a row: "Every year", "Every 2 weeks".
    static func describe(_ rule: Recurrence) -> String {
        guard rule.repeats else { return "Does not repeat" }
        let n = max(1, rule.interval)
        let base: String
        if n == 1 {
            switch rule.unit {
            case .daily:   base = "Every day"
            case .weekly:  base = "Every week"
            case .monthly: base = "Every month"
            case .yearly:  base = "Every year"
            case .none:    base = "Does not repeat"
            }
        } else {
            base = "Every \(n) \(rule.unit.plural)"
        }
        guard let until = rule.until, !until.isEmpty else { return base }
        return "\(base), until \(until)"
    }

    /// The short chip on an event row: "Yearly", "Every 3 weeks".
    static func shortDescribe(_ rule: Recurrence) -> String {
        guard rule.repeats else { return "" }
        let n = max(1, rule.interval)
        return n == 1 ? rule.unit.label : "Every \(n) \(rule.unit.plural)"
    }

    // MARK: - Anniversaries

    /// Which occurrence this is, counting the anchor as the first.
    ///
    /// What turns "Amma's birthday" into "Amma's birthday — 61st". Only
    /// meaningful for yearly rules; anything else has no ordinal worth reading.
    static func ordinal(_ event: EventItem, on dayKey: String) -> Int? {
        guard event.recurrence.unit == .yearly,
              let anchor = parts(event.date), let day = parts(dayKey) else { return nil }
        let years = day.y - anchor.y
        guard years > 0, years % max(1, event.recurrence.interval) == 0 else { return nil }
        return years
    }

    /// "61st", "2nd", "13th".
    static func ordinalLabel(_ n: Int) -> String {
        let tens = n % 100
        if (11...13).contains(tens) { return "\(n)th" }
        switch n % 10 {
        case 1:  return "\(n)st"
        case 2:  return "\(n)nd"
        case 3:  return "\(n)rd"
        default: return "\(n)th"
        }
    }
}
