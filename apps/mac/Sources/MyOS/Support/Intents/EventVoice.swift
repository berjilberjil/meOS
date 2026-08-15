import Foundation

/// What Siri says about events — selection + phrasing, with no I/O and no
/// `AppState`. Kept pure so the whole spoken surface is unit-testable without an
/// unlocked vault or a device. `EventIntentStore` supplies the data; the intents
/// in `EventIntents.swift` only glue the two together.
enum EventVoice {
    /// Most events a single answer will read out — past that, speech stops being useful.
    static let maxSpoken = 10

    // MARK: - Day math (POSIX/gregorian, mirrors AppState's key helpers)

    private static func formatter() -> DateFormatter {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }

    /// Whole days between two `yyyy-MM-dd` keys — negative for the past, nil if
    /// either key isn't a real date.
    static func dayDelta(from todayKey: String, to dateKey: String) -> Int? {
        let f = formatter()
        guard let from = f.date(from: todayKey), let to = f.date(from: dateKey) else { return nil }
        return f.calendar.dateComponents([.day], from: from, to: to).day
    }

    /// A `yyyy-MM-dd` key `n` days from another key. Test/seed helper.
    static func key(addingDays n: Int, to dateKey: String) -> String {
        let f = formatter()
        guard let d = f.date(from: dateKey),
              let moved = f.calendar.date(byAdding: .day, value: n, to: d) else { return dateKey }
        return f.string(from: moved)
    }

    /// A `yyyy-MM-dd` key for a `Date` (what Siri hands us for a date parameter).
    static func key(from date: Date) -> String { formatter().string(from: date) }

    // MARK: - Phrasing

    /// How a date sounds relative to today: "today", "tomorrow", "in 4 days",
    /// "yesterday", "3 days ago".
    static func relativePhrase(from todayKey: String, to dateKey: String) -> String {
        guard let d = dayDelta(from: todayKey, to: dateKey) else { return "on an unknown date" }
        switch d {
        case 0:  return "today"
        case 1:  return "tomorrow"
        case -1: return "yesterday"
        case let n where n > 1:  return "in \(n) days"
        default: return "\(-d) days ago"
        }
    }

    /// Strip dictation noise off a spoken title. Siri often tacks on a full stop.
    static func cleanTitle(_ raw: String) -> String {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = t.last, ".!?,".contains(last) { t.removeLast() }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Selection

    private static func clamp(_ limit: Int) -> Int { min(max(limit, 1), maxSpoken) }

    /// Events from today onward, soonest first. Matches the Today spine's rule
    /// (`date >= today`) so voice and screen never disagree.
    static func upcoming(_ events: [EventItem], today: String, limit: Int) -> [EventItem] {
        Array(events.filter { !$0.date.isEmpty && $0.date >= today }
                    .sorted { $0.date < $1.date }
                    .prefix(clamp(limit)))
    }

    /// Events strictly before today, most recent first.
    static func past(_ events: [EventItem], today: String, limit: Int) -> [EventItem] {
        Array(events.filter { !$0.date.isEmpty && $0.date < today }
                    .sorted { $0.date > $1.date }
                    .prefix(clamp(limit)))
    }

    // MARK: - Sentences

    /// "A today, B tomorrow, and C in 4 days." — Oxford comma reads better aloud.
    private static func join(_ parts: [String]) -> String {
        switch parts.count {
        case 0:  return ""
        case 1:  return parts[0]
        case 2:  return "\(parts[0]), and \(parts[1])"
        default: return parts.dropLast().joined(separator: ", ") + ", and " + parts[parts.count - 1]
        }
    }

    private static func clause(_ e: EventItem, today: String) -> String {
        "\(e.title) \(relativePhrase(from: today, to: e.date))"
    }

    /// Speak an already-selected list of upcoming events.
    static func spokenUpcoming(_ events: [EventItem], today: String) -> String {
        guard !events.isEmpty else { return "Nothing coming up." }
        return join(events.map { clause($0, today: today) }) + "."
    }

    /// Speak an already-selected list of past events.
    static func spokenPast(_ events: [EventItem], today: String) -> String {
        guard !events.isEmpty else { return "No past events logged." }
        return join(events.map { clause($0, today: today) }) + "."
    }

    /// Confirmation after creating one.
    static func spokenCreated(title: String, date: String, today: String) -> String {
        "Added \(title) \(relativePhrase(from: today, to: date))."
    }
}
