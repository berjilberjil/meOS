import Foundation

// The intelligence layer. Activity data is the raw input; this is the product.
//
// Every line below is derived from numbers that were actually measured, and
// every line names them. There is no motivational text, no encouragement that
// would read the same on a good day and a bad one, and nothing is generated
// when there is nothing to say — an honest empty state beats an invented
// insight.
//
// Deliberately a pure, local rules engine rather than a model call: this runs on
// the Today card every time the page draws, it has to be instant and offline,
// and a sentence about your day that is *wrong* is worse than no sentence.

/// What is happening right now, and whether it is worth doing.
struct FocusNow: Hashable {
    var appName: String
    var category: ActivityCategory
    var productivity: ProductivityType
    var seconds: Int
    /// The priority this session lines up with, when it lines up with one.
    var alignedTask: String?
    /// The priority it is displacing, when it is displacing one.
    var displacedTask: String?
    var insight: String
}

enum ActivityVerdict: String, Hashable {
    case excellent, good, mixed, needsAttention, poor
    var label: String {
        switch self {
        case .excellent:     return "Excellent"
        case .good:          return "Good"
        case .mixed:         return "Mixed"
        case .needsAttention: return "Needs attention"
        case .poor:          return "Poor"
        }
    }
    var isPositive: Bool { self == .excellent || self == .good }
}

/// The single recommendation. One, never a list — ten things to improve is zero
/// things improved.
struct ActivityAction: Hashable {
    enum Kind: String, Hashable {
        case goodMove, nextMove, fixThisNow
        var heading: String {
            switch self {
            case .goodMove:   return "GOOD MOVE"
            case .nextMove:   return "NEXT MOVE"
            case .fixThisNow: return "FIX THIS NOW"
            }
        }
    }
    var kind: Kind
    var text: String
}

/// A named observation for the Productivity tab.
struct TimeInsight: Identifiable, Hashable {
    var title: String
    var detail: String
    var productivity: ProductivityType
    var id: String { title }
}

/// Everything the day surfaces need, computed once.
struct DayIntelligence: Hashable {
    var focusNow: FocusNow?
    var verdict: ActivityVerdict?
    var verdictLine: String = ""
    var action: ActivityAction?
    var insights: [TimeInsight] = []
}

/// The week's read, plus how it moved against the week before.
struct WeekIntelligence: Hashable {
    var narrative: String = ""
    var biggestLeak: TimeInsight?
    var bestWindow: TimeInsight?
    var biggestImprovement: TimeInsight?
    var verdict: ActivityVerdict?
    var verdictLine: String = ""
    var nextWeek: String = ""
}

enum ActivityInsights {

    // MARK: - Task alignment
    //
    // The difference between "you are on YouTube" and "you are on YouTube
    // instead of the DSA practice you said you'd do". Matching is deliberately
    // crude — a word in a to-do that belongs to the category of the app in
    // front of you — because a wrong confident claim about someone's priorities
    // is worse than a vague one.

    static let taskKeywords: [ActivityCategory: [String]] = [
        .contentCreation: ["edit", "video", "vlog", "reel", "shoot", "footage", "thumbnail",
                           "content", "podcast", "youtube", "clip", "render"],
        .development:     ["code", "build", "fix", "bug", "ship", "deploy", "api", "refactor",
                           "dsa", "leetcode", "java", "swift", "app", "feature", "pr", "merge"],
        .design:          ["design", "mockup", "logo", "banner", "poster", "figma", "canva", "ui"],
        .writing:         ["write", "draft", "blog", "post", "doc", "spec", "article", "notes"],
        .communication:   ["reply", "email", "message", "call", "meeting", "sync", "standup", "follow up"],
        .research:        ["research", "read", "learn", "study", "explore", "compare", "watch"],
        .finance:         ["invoice", "budget", "tax", "expense", "invest", "portfolio", "bill"],
        .health:          ["gym", "workout", "run", "walk", "meal", "diet", "steps"],
    ]

    /// The first open to-do whose wording belongs to this category.
    static func task(matching category: ActivityCategory, in todos: [String]) -> String? {
        guard let words = taskKeywords[category] else { return nil }
        return todos.first { todo in
            let text = todo.lowercased()
            return words.contains { text.contains($0) }
        }
    }

    /// The priority to point at when the current app is not one: the first open
    /// to-do that belongs to any productive category, else simply the first.
    static func topPriority(_ todos: [String]) -> String? {
        for category in [ActivityCategory.contentCreation, .development, .design, .writing, .finance] {
            if let match = task(matching: category, in: todos) { return match }
        }
        return todos.first
    }

    // MARK: - Focusing now

    static func focusNow(current: ActivityEvent?, todos: [String]) -> FocusNow? {
        guard let s = current else { return nil }
        let aligned = task(matching: s.category, in: todos)
        let priority = topPriority(todos)
        let minutes = s.duration / 60

        var displaced: String?
        var line: String

        switch s.productivity {
        case .productive:
            if let aligned {
                line = "You're working directly on today's priority — \(shorten(aligned))."
            } else if let priority {
                line = "Good focus. Today's stated priority is still \(shorten(priority))."
            } else {
                line = "Good focus. You're spending time on a high-value task."
            }

        case .neutral:
            let verb = neutralVerb(s.category)
            if minutes >= 20 {
                line = "\(minutes) minutes \(verb). This isn't the work — finish it and get back to your main task."
            } else {
                line = "You're \(verb). Finish this quickly and return to your main task."
            }
            displaced = priority

        case .distracting:
            displaced = priority
            if let priority {
                line = minutes >= 20
                    ? "\(minutes) minutes on \(s.appName) instead of \(shorten(priority)). Close it and go back."
                    : "You're on \(s.appName) rather than \(shorten(priority))."
            } else {
                line = minutes >= 20
                    ? "\(minutes) minutes on \(s.appName). You're drifting — pick your highest-value task."
                    : "You're drifting from your priorities. Get back to your highest-value task."
            }
        }

        return FocusNow(appName: s.appName, category: s.category, productivity: s.productivity,
                        seconds: s.duration, alignedTask: aligned, displacedTask: displaced,
                        insight: line)
    }

    private static func neutralVerb(_ category: ActivityCategory) -> String {
        switch category {
        case .utility:       return "organising"
        case .communication: return "on messages"
        case .research:      return "browsing"
        case .reading:       return "reading"
        default:             return "on \(category.label.lowercased())"
        }
    }

    /// Priorities are sentences; an insight has room for a phrase.
    static func shorten(_ task: String, limit: Int = 42) -> String {
        let trimmed = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return "“\(trimmed)”" }
        return "“\(trimmed.prefix(limit - 1))…”"
    }

    // MARK: - Verdict

    /// A verdict is a headline for the explanation, never a score on its own —
    /// which is why `verdictLine` is what the UI leads with.
    static func verdict(_ s: ActivitySummary) -> (ActivityVerdict, String)? {
        guard s.totalSeconds >= 15 * 60 else { return nil }

        let productive = s.share(.productive)
        let distracting = s.share(.distracting)
        let longest = s.longestFocus?.seconds ?? 0
        let hours = Double(s.totalSeconds) / 3600
        let switchesPerHour = hours > 0 ? Double(s.switches) / hours : 0

        var verdict: ActivityVerdict
        switch productive {
        case 0.65...:     verdict = longest >= 45 * 60 ? .excellent : .good
        case 0.50..<0.65: verdict = .good
        case 0.35..<0.50: verdict = .mixed
        case 0.20..<0.35: verdict = .needsAttention
        default:          verdict = .poor
        }
        // A day that is mostly productive but fragmented is not an excellent day.
        if verdict == .excellent && switchesPerHour >= 20 { verdict = .good }
        if distracting >= 0.30 && verdict.isPositive { verdict = .mixed }

        return (verdict, verdictExplanation(s, verdict: verdict,
                                            productive: productive,
                                            switchesPerHour: switchesPerHour,
                                            longest: longest))
    }

    /// Names the *actual* limiting factor. "Your biggest issue is context
    /// switching, not total screen time" is the useful half of a verdict.
    private static func verdictExplanation(_ s: ActivitySummary, verdict: ActivityVerdict,
                                           productive: Double, switchesPerHour: Double,
                                           longest: Int) -> String {
        let pct = Int((productive * 100).rounded())
        let head = "You spent \(pct)% of your tracked time on productive work."

        let leak = biggestLeakApps(s)
        // 12/hour is a switch every five minutes. Below that, the limiting
        // factor is almost always something else — a leak, or no deep block —
        // and naming switching would be blaming the wrong thing.
        if switchesPerHour >= 12 && s.switches >= 15 {
            return "\(head) Your biggest issue is context switching, not total screen time — \(s.switches) app switches today."
        }
        if let leak, leak.seconds >= 30 * 60 {
            return "\(head) \(leak.label) took \(Fmt.duration(leak.seconds)) of it."
        }
        if longest < 25 * 60 && s.totalSeconds >= 2 * 3600 {
            return "\(head) Nothing you did today ran uninterrupted for 25 minutes."
        }
        if verdict.isPositive, longest > 0 {
            return "\(head) Your longest uninterrupted block was \(Fmt.duration(longest))."
        }
        return head
    }

    // MARK: - The one action

    static func action(_ s: ActivitySummary, current: ActivityEvent?, todos: [String], now: Date) -> ActivityAction? {
        let priority = topPriority(todos)
        let hour = Calendar.current.component(.hour, from: now)

        // 1. A distraction that is happening *right now* outranks anything
        //    historical — it is the only thing that can still be changed.
        if let c = current, c.productivity == .distracting, c.duration >= 10 * 60 {
            let target = priority.map { " Go back to \(shorten($0))." } ?? " Pick your highest-value task."
            return ActivityAction(kind: .fixThisNow,
                                  text: "\(Fmt.duration(c.duration)) on \(c.appName).\(target)")
        }

        // 2. Fragmentation. Only worth saying once there is enough of a day to
        //    be fragmented.
        let hours = Double(s.totalSeconds) / 3600
        if hours >= 1.5, s.switchesInWorkHours >= 15,
           Double(s.switchesInWorkHours) / max(hours, 1) >= 12 {
            return ActivityAction(kind: .fixThisNow,
                                  text: "You're \(Fmt.duration(s.totalSeconds)) into the day and have switched apps \(s.switchesInWorkHours) times. Pick one task and stay with it for 30 minutes.")
        }

        // 3. Protect a block that is already working.
        if let c = current, c.productivity == .productive, c.duration >= 20 * 60 {
            return ActivityAction(kind: .goodMove,
                                  text: "\(Fmt.duration(c.duration)) in \(c.appName) without switching. Don't break it — stay here.")
        }

        // 4. A leak big enough to be worth naming.
        if let leak = biggestLeakApps(s), leak.seconds >= 40 * 60 {
            return ActivityAction(kind: .nextMove,
                                  text: "\(leak.label) has taken \(Fmt.duration(leak.seconds)) today. Close it and batch it into one slot later.")
        }

        // 5. Past midday with nothing that counts as deep work.
        if hour >= 11, s.totalSeconds >= 60 * 60, (s.longestFocus?.seconds ?? 0) < 25 * 60 {
            let target = priority.map { shorten($0) } ?? "your top task"
            return ActivityAction(kind: .nextMove,
                                  text: "No block over 25 minutes yet today. Start one now on \(target).")
        }

        // 6. Nothing wrong — point at the work.
        if let c = current, c.productivity == .productive {
            return ActivityAction(kind: .goodMove, text: "You're on productive work. Keep going.")
        }
        if let priority {
            return ActivityAction(kind: .nextMove, text: "Next up: \(shorten(priority)).")
        }
        return nil
    }

    /// The distracting apps, as one named leak.
    static func biggestLeakApps(_ s: ActivitySummary) -> (label: String, seconds: Int)? {
        let leaks = s.apps.filter { $0.productivity == .distracting }.sorted { $0.seconds > $1.seconds }
        guard !leaks.isEmpty else { return nil }
        let named = leaks.prefix(2).map(\.appName).joined(separator: " + ")
        return (named, leaks.reduce(0) { $0 + $1.seconds })
    }

    // MARK: - Time management (Productivity tab)

    static func insights(_ s: ActivitySummary) -> [TimeInsight] {
        guard !s.isEmpty else { return [] }
        var out: [TimeInsight] = []

        if let leak = biggestLeakApps(s), leak.seconds >= 5 * 60 {
            out.append(TimeInsight(title: "Your biggest leak",
                                   detail: "\(leak.label) consumed \(Fmt.duration(leak.seconds)) today.",
                                   productivity: .distracting))
        }
        if let longest = s.longestFocus {
            out.append(TimeInsight(title: "Focus quality",
                                   detail: "Your longest uninterrupted focus block was \(Fmt.duration(longest.seconds)) in \(longest.appName).",
                                   productivity: .productive))
        } else if s.totalSeconds >= 60 * 60 {
            out.append(TimeInsight(title: "Focus quality",
                                   detail: "No block of productive work ran for 10 minutes without a switch.",
                                   productivity: .distracting))
        }
        if s.switches > 0 {
            out.append(TimeInsight(title: "Context switching",
                                   detail: "You switched between apps \(s.switchesInWorkHours) times during work hours, \(s.switches) times in total.",
                                   productivity: s.switchesInWorkHours >= 25 ? .distracting : .neutral))
        }
        if let peak = s.timeline.max(by: { $0.productive < $1.productive }), peak.productive >= 15 * 60 {
            out.append(TimeInsight(title: "Strongest hour",
                                   detail: "\(ActivityTime.hourLabel(peak.hour)) – \(ActivityTime.hourLabel(peak.hour + 1)) was your most productive hour, at \(Fmt.duration(peak.productive)).",
                                   productivity: .productive))
        }
        return out
    }

    static func dayIntelligence(summary: ActivitySummary, current: ActivityEvent?,
                                todos: [String], now: Date) -> DayIntelligence {
        var out = DayIntelligence()
        out.focusNow = focusNow(current: current, todos: todos)
        if let v = verdict(summary) { out.verdict = v.0; out.verdictLine = v.1 }
        out.action = action(summary, current: current, todos: todos, now: now)
        out.insights = insights(summary)
        return out
    }

    // MARK: - The week

    static func weekIntelligence(this week: ActivityWeekSummary,
                                 previous: ActivityWeekSummary?) -> WeekIntelligence {
        var out = WeekIntelligence()
        guard !week.isEmpty else { return out }

        let pct = Int((week.share(.productive) * 100).rounded())
        var narrative = "You spent \(Fmt.duration(week.totalSeconds)) on your devices across \(week.daysTracked) tracked \(week.daysTracked == 1 ? "day" : "days"). \(pct)% of it was productive."

        let leaks = week.apps.filter { $0.productivity == .distracting }.sorted { $0.seconds > $1.seconds }
        let leakTotal = leaks.reduce(0) { $0 + $1.seconds }
        if let top = leaks.first, leakTotal >= 30 * 60 {
            let named = leaks.prefix(2).map(\.appName).joined(separator: " + ")
            narrative += " Your biggest time leak was \(named)."
            out.biggestLeak = TimeInsight(title: "Biggest time leak",
                                          detail: "\(named): \(Fmt.duration(leakTotal))",
                                          productivity: .distracting)
            _ = top
        }
        if let window = week.bestFocusWindow {
            narrative += " Your longest focus blocks happened between \(window)."
            out.bestWindow = TimeInsight(title: "Best focus window", detail: window,
                                         productivity: .productive)
        }
        out.narrative = narrative

        // Movement. Screen time and productive time are reported separately on
        // purpose — more screen time is not more work, and a week where both
        // rose is a different week from one where only the first did.
        if let previous, !previous.isEmpty {
            let totalDelta = percentChange(from: previous.totalSeconds, to: week.totalSeconds)
            let productiveDelta = percentChange(from: previous.seconds(.productive), to: week.seconds(.productive))
            if let productiveDelta {
                let direction = productiveDelta >= 0 ? "increased" : "decreased"
                var detail = "Productive time \(direction) \(abs(productiveDelta))% compared with last week."
                if let totalDelta, (totalDelta > 0) != (productiveDelta > 0) {
                    detail = "Screen time \(totalDelta >= 0 ? "increased" : "decreased") \(abs(totalDelta))%, but productive time \(direction) \(abs(productiveDelta))%."
                }
                out.biggestImprovement = TimeInsight(title: productiveDelta >= 0 ? "Biggest improvement" : "Biggest regression",
                                                     detail: detail,
                                                     productivity: productiveDelta >= 0 ? .productive : .distracting)
            }
        }

        // The week's verdict reuses the day rules over the week's totals, so a
        // good week and a good day mean the same thing.
        var asDay = ActivitySummary(day: week.days.last ?? "")
        asDay.totalSeconds = week.totalSeconds
        asDay.byProductivity = week.byProductivity
        asDay.apps = week.apps
        asDay.switches = week.switches
        asDay.focusBlocks = week.longestFocus.map { [$0] } ?? []
        if let v = verdict(asDay) {
            out.verdict = v.0
            out.verdictLine = weekVerdictLine(v.0, week: week, previous: previous, base: v.1)
        }
        out.nextWeek = nextWeekAction(week)
        return out
    }

    private static func weekVerdictLine(_ verdict: ActivityVerdict, week: ActivityWeekSummary,
                                        previous: ActivityWeekSummary?, base: String) -> String {
        guard let previous, !previous.isEmpty,
              let delta = percentChange(from: previous.seconds(.productive), to: week.seconds(.productive))
        else { return base }
        if delta > 0 {
            return "You're moving in the right direction — productive time is up \(delta)%. \(secondClause(week))"
        }
        if delta < 0 {
            return "Productive time is down \(abs(delta))% on last week. \(secondClause(week))"
        }
        return base
    }

    private static func secondClause(_ week: ActivityWeekSummary) -> String {
        let hours = Double(week.totalSeconds) / 3600
        let switchesPerHour = hours > 0 ? Double(week.switches) / hours : 0
        if switchesPerHour >= 18 { return "Frequent context switching is still costing you." }
        let leak = week.apps.filter { $0.productivity == .distracting }.reduce(0) { $0 + $1.seconds }
        if leak >= 3 * 3600 { return "Short distracting sessions are still the leak." }
        return "Keep the pattern."
    }

    private static func nextWeekAction(_ week: ActivityWeekSummary) -> String {
        let leaks = week.apps.filter { $0.productivity == .distracting }.sorted { $0.seconds > $1.seconds }
        if let window = week.bestFocusWindow, let worst = leaks.first, worst.seconds >= 45 * 60 {
            return "Protect your \(window) block for deep work and keep \(worst.appName) closed during it."
        }
        if let window = week.bestFocusWindow {
            return "Protect your \(window) block for deep work — it is already your strongest."
        }
        if let worst = leaks.first, worst.seconds >= 45 * 60 {
            return "Batch \(worst.appName) into one slot after lunch instead of throughout the day."
        }
        return "Pick one two-hour block each morning and defend it."
    }

    /// Whole-percent change, nil when there is no baseline to compare against.
    static func percentChange(from old: Int, to new: Int) -> Int? {
        guard old > 0 else { return nil }
        return Int(((Double(new) - Double(old)) / Double(old) * 100).rounded())
    }
}
