import Foundation

/// Turns what the user said (“next Wednesday”) and what Catherine emitted
/// (`date="2024-10-30"`) into a real `yyyy-MM-dd` on or after today.
///
/// Models routinely invent last year’s calendar. The spoken phrase always wins.
enum EventDate {
    /// Resolve an event day.
    /// - Parameters:
    ///   - raw: The `date=` field from an ACTION line (ISO or leftover English).
    ///   - phrase: The user’s last message — the source of “next Wednesday”.
    ///   - today: Device today, `yyyy-MM-dd`.
    static func resolve(raw: String?, phrase: String, today: String) -> String {
        if let fromPhrase = parseRelative(phrase, today: today) { return fromPhrase }
        if let fromRaw = parseRelative(raw ?? "", today: today) { return fromRaw }
        if let iso = normalizeISO(raw ?? "") {
            if iso >= today { return iso }
            return rollYearForward(iso, today: today)
        }
        return today
    }

    /// English relative dates. `next Wednesday` skips today; `this/on Wednesday`
    /// keeps today when it already is Wednesday.
    static func parseRelative(_ text: String, today: String) -> String? {
        let s = text.lowercased()
        guard !s.isEmpty else { return nil }

        if let n = firstInt(s, pattern: #"\bin\s+(\d+)\s+days?\b"#) {
            return EventVoice.key(addingDays: n, to: today)
        }
        if hasWord(s, "today") || hasWord(s, "tonight") { return today }
        if hasWord(s, "tomorrow") { return EventVoice.key(addingDays: 1, to: today) }
        if hasWord(s, "yesterday") { return EventVoice.key(addingDays: -1, to: today) }

        if let wd = lastWeekday(in: s, prefixes: ["next "]) {
            return nextWeekday(wd, today: today, skipToday: true)
        }
        if let wd = lastWeekday(in: s, prefixes: ["this ", "on "]) {
            return nextWeekday(wd, today: today, skipToday: false)
        }
        return nil
    }

    /// Longest weekday name after one of the prefixes, last match in the string.
    private static func lastWeekday(in s: String, prefixes: [String]) -> Int? {
        var best: (loc: Int, wd: Int)?
        for (wd, words) in weekdayNames {
            for word in words {
                for prefix in prefixes {
                    let pat = prefix + word
                    var search = s.startIndex
                    while let r = s.range(of: pat, range: search..<s.endIndex) {
                        let after = r.upperBound
                        let boundary = after == s.endIndex || !s[after].isLetter
                        if boundary {
                            let loc = s.distance(from: s.startIndex, to: r.lowerBound)
                            if best == nil || loc >= best!.loc { best = (loc, wd) }
                        }
                        search = r.upperBound
                    }
                }
            }
        }
        return best?.wd
    }

    /// Same month/day in the current year if that’s still ahead, otherwise next year.
    static func rollYearForward(_ iso: String, today: String) -> String {
        guard iso.count >= 10, today.count >= 4 else { return today }
        let md = String(iso.dropFirst(4))          // -MM-dd
        let thisYear = String(today.prefix(4)) + md
        if thisYear >= today, EventVoice.dayDelta(from: today, to: thisYear) != nil {
            return thisYear
        }
        if let y = Int(today.prefix(4)) {
            let next = String(y + 1) + md
            if EventVoice.dayDelta(from: today, to: next) != nil { return next }
        }
        return today
    }

    static func normalizeISO(_ raw: String) -> String? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= 10 else { return nil }
        let key = String(t.prefix(10))
        return EventVoice.dayDelta(from: key, to: key) == 0 ? key : nil
    }

    /// Gregorian weekday: 1 = Sunday … 7 = Saturday.
    static func nextWeekday(_ weekday: Int, today: String, skipToday: Bool) -> String {
        let f = isoFormatter()
        guard let d = f.date(from: today) else { return today }
        let current = f.calendar.component(.weekday, from: d)
        var delta = weekday - current
        if delta < 0 { delta += 7 }
        if delta == 0 && skipToday { delta = 7 }
        return EventVoice.key(addingDays: delta, to: today)
    }

    private static func isoFormatter() -> DateFormatter {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }

    private static let weekdayNames: [(Int, [String])] = [
        (1, ["sunday", "sun"]),
        (2, ["monday", "mon"]),
        (3, ["tuesday", "tues", "tue"]),
        (4, ["wednesday", "wed"]),
        (5, ["thursday", "thurs", "thu"]),
        (6, ["friday", "fri"]),
        (7, ["saturday", "sat"])
    ]

    private static func hasWord(_ s: String, _ w: String) -> Bool {
        s.range(of: "\\b\(w)\\b", options: .regularExpression) != nil
    }

    private static func firstInt(_ s: String, pattern: String) -> Int? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: s) else { return nil }
        return Int(s[r])
    }
}
