import Foundation

/// The Friday report: this week's body photos read against last week's, framed by
/// the goal and the numbers actually logged. One per week, kept in `myos.weekly`.
struct WeeklyReport: Codable, Identifiable, Hashable {
    enum Verdict: String, Codable, Hashable {
        case gaining, holding, slipping, unknown

        var label: String {
            switch self {
            case .gaining: return "Gaining ground"
            case .holding: return "Holding"
            case .slipping: return "Slipping"
            case .unknown: return "Not enough to go on"
            }
        }
    }

    /// The ISO week the report covers — "2026-W34". Also the identity, so a week
    /// can only ever have one report.
    var id: String
    var at: String              // generated at, yyyy-MM-dd'T'HH:mm:ss
    var weekStart: String       // Monday of the reported week
    var weekEnd: String         // the day it was generated (Friday, usually)
    var verdict: String
    /// Signed, approximate change against last week. 0 when there was nothing to
    /// compare — never a number the model made up.
    var percent: Double
    var headline: String
    var read: String
    var workouts: [String]
    var diet: [String]
    var cheer: String
    var needsPhotos: Bool
    var photosThisWeek: Int
    var photosLastWeek: Int
    /// Cleared when he opens it, so the Settings row can badge an unread one.
    var seen: Bool

    static let cap = 12

    init(id: String, at: String, weekStart: String, weekEnd: String,
         verdict: String = Verdict.unknown.rawValue, percent: Double = 0,
         headline: String = "", read: String = "", workouts: [String] = [],
         diet: [String] = [], cheer: String = "", needsPhotos: Bool = false,
         photosThisWeek: Int = 0, photosLastWeek: Int = 0, seen: Bool = false) {
        self.id = id; self.at = at; self.weekStart = weekStart; self.weekEnd = weekEnd
        self.verdict = verdict; self.percent = percent; self.headline = headline
        self.read = read; self.workouts = workouts; self.diet = diet; self.cheer = cheer
        self.needsPhotos = needsPhotos
        self.photosThisWeek = photosThisWeek; self.photosLastWeek = photosLastWeek
        self.seen = seen
    }

    enum CodingKeys: String, CodingKey {
        case id, at, weekStart, weekEnd, verdict, percent, headline, read
        case workouts, diet, cheer, needsPhotos, photosThisWeek, photosLastWeek, seen
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        at = try c.decodeIfPresent(String.self, forKey: .at) ?? ""
        weekStart = try c.decodeIfPresent(String.self, forKey: .weekStart) ?? ""
        weekEnd = try c.decodeIfPresent(String.self, forKey: .weekEnd) ?? ""
        verdict = try c.decodeIfPresent(String.self, forKey: .verdict) ?? Verdict.unknown.rawValue
        percent = try c.decodeIfPresent(Double.self, forKey: .percent) ?? 0
        headline = try c.decodeIfPresent(String.self, forKey: .headline) ?? ""
        read = try c.decodeIfPresent(String.self, forKey: .read) ?? ""
        workouts = try c.decodeIfPresent([String].self, forKey: .workouts) ?? []
        diet = try c.decodeIfPresent([String].self, forKey: .diet) ?? []
        cheer = try c.decodeIfPresent(String.self, forKey: .cheer) ?? ""
        needsPhotos = try c.decodeIfPresent(Bool.self, forKey: .needsPhotos) ?? false
        photosThisWeek = try c.decodeIfPresent(Int.self, forKey: .photosThisWeek) ?? 0
        photosLastWeek = try c.decodeIfPresent(Int.self, forKey: .photosLastWeek) ?? 0
        seen = try c.decodeIfPresent(Bool.self, forKey: .seen) ?? false
    }

    var kind: Verdict { Verdict(rawValue: verdict) ?? .unknown }

    /// "+1.8%" / "−1.8%" / "" when there was nothing to measure.
    var percentLabel: String {
        guard !needsPhotos, abs(percent) >= 0.05 else { return "" }
        let sign = percent > 0 ? "+" : "−"
        return String(format: "%@%.1f%%", sign, abs(percent))
    }
}

/// Week arithmetic and the decision to run — pure, so Friday-6pm behaviour can be
/// tested without waiting for Friday.
enum WeeklyReportMath {
    /// ISO-8601 week, Monday-first: "2026-W34".
    static func weekKey(_ date: Date) -> String {
        let c = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return String(format: "%04d-W%02d", c.yearForWeekOfYear ?? 0, c.weekOfYear ?? 0)
    }

    /// Monday 00:00 of the week containing `date`.
    static func weekStart(_ date: Date) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
    }

    static func dateKey(_ date: Date) -> String {
        let f = formatter
        return f.string(from: date)
    }

    /// The two windows a report compares: this week so far, and all of last week.
    static func windows(now: Date) -> (thisWeek: ClosedRange<String>, lastWeek: ClosedRange<String>) {
        let start = weekStart(now)
        let prevStart = calendar.date(byAdding: .day, value: -7, to: start) ?? start
        let prevEnd = calendar.date(byAdding: .day, value: -1, to: start) ?? start
        return (dateKey(start)...dateKey(now), dateKey(prevStart)...dateKey(prevEnd))
    }

    /// Friday 18:00, in the app's own words. Sunday is the *end* of a Monday-first
    /// week, so raw weekday numbers (where Sunday is 1) can't be compared — this
    /// shifts them to Monday = 0 first.
    static func isDue(now: Date, lastReportWeek: String?, day: Int = 4, hour: Int = 18) -> Bool {
        if let lastReportWeek, lastReportWeek == weekKey(now) { return false }
        let c = calendar.dateComponents([.weekday, .hour], from: now)
        let index = ((c.weekday ?? 1) + 5) % 7          // Mon 0 … Fri 4 … Sun 6
        if index > day { return true }
        return index == day && (c.hour ?? 0) >= hour
    }

    /// Photos for one window, oldest first, thinned to at most `limit` spread
    /// across the window — eight near-identical Tuesday shots teach the model
    /// nothing and cost eight images.
    static func pick(_ photos: [ProgressPhoto], in window: ClosedRange<String>, limit: Int = 4) -> [ProgressPhoto] {
        let inWindow = photos.filter { window.contains($0.date) }.sorted { $0.id < $1.id }
        guard inWindow.count > limit else { return inWindow }
        let step = Double(inWindow.count - 1) / Double(limit - 1)
        return (0..<limit).map { inWindow[Int((Double($0) * step).rounded())] }
    }

    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "en_US_POSIX")
        c.firstWeekday = 2              // Monday
        c.minimumDaysInFirstWeek = 4    // ISO-8601
        return c
    }()

    private static var formatter: DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = calendar
        f.dateFormat = "yyyy-MM-dd"
        return f
    }
}

/// The text block that rides along with the photos: the goal, the targets, and
/// what was actually logged in each of the two weeks. Pure, so the exact wording
/// the model is judged on can be tested.
enum WeeklyBrief {
    struct Week {
        var label: String
        var range: ClosedRange<String>
        var photos: Int
    }

    static func text(name: String, goal: FitnessGoal, targetWeightKg: Double?,
                     calorieTarget: Double?, proteinTarget: Double?,
                     fitness: [String: FitnessDay], training: TrainingState,
                     lastWeek: Week, thisWeek: Week) -> String {
        var lines = ["Name: \(name.isEmpty ? "unknown" : name)"]
        var goalLine = "Goal: \(goal.label.lowercased())"
        if let t = targetWeightKg, t > 0 { goalLine += " (target \(num(t)) kg)" }
        lines.append(goalLine)

        var targets: [String] = []
        if let c = calorieTarget, c > 0 { targets.append("\(Int(c.rounded())) kcal") }
        if let p = proteinTarget, p > 0 { targets.append("\(Int(p.rounded())) g protein") }
        lines.append(targets.isEmpty ? "Daily targets: not set" : "Daily targets: " + targets.joined(separator: ", "))

        for week in [lastWeek, thisWeek] {
            lines.append("")
            lines.append(contentsOf: block(week, fitness: fitness, training: training))
        }
        return lines.joined(separator: "\n")
    }

    private static func block(_ w: Week, fitness: [String: FitnessDay],
                              training: TrainingState) -> [String] {
        var out = ["\(w.label) (\(w.range.lowerBound) to \(w.range.upperBound)) — "
                   + "\(w.photos) photo\(w.photos == 1 ? "" : "s") attached"]
        let days = fitness.filter { w.range.contains($0.key) }

        let weights = days.compactMapValues(\.weightKg).sorted { $0.key < $1.key }
        if let first = weights.first, let last = weights.last {
            let avg = weights.map(\.value).reduce(0, +) / Double(weights.count)
            out.append(first.key == last.key
                       ? "  weight: \(num(first.value)) kg (one reading)"
                       : "  weight: \(num(first.value)) to \(num(last.value)) kg (avg \(num(avg)) over \(weights.count) readings)")
        } else {
            out.append("  weight: not logged")
        }

        out.append(average(days.compactMapValues(\.calories), label: "calories", unit: "kcal"))
        out.append(average(days.compactMapValues(\.proteinG), label: "protein", unit: "g"))
        out.append(average(days.compactMapValues { $0.steps.map(Double.init) }, label: "steps", unit: ""))

        let logs = training.dayLog.filter { w.range.contains($0.key) }
        let done = logs.values.filter(\.done).count
        let skipped = logs.values.filter { $0.skipped && !$0.done }.count
        out.append("  workouts: \(done) done, \(skipped) skipped")
        return out
    }

    private static func average(_ values: [String: Double], label: String, unit: String) -> String {
        guard !values.isEmpty else { return "  \(label): not logged" }
        let avg = values.values.reduce(0, +) / Double(values.count)
        let suffix = unit.isEmpty ? "" : " \(unit)"
        return "  \(label): avg \(Int(avg.rounded()))\(suffix) over \(values.count) day\(values.count == 1 ? "" : "s")"
    }

    private static func num(_ d: Double) -> String {
        String(format: d == d.rounded() ? "%.0f" : "%.1f", d)
    }
}
