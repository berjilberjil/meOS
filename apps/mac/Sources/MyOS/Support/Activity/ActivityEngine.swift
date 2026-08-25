import Foundation

// Aggregation. Pure functions over `[ActivityEvent]` — no AppState, no clock of
// its own, nothing platform-specific — so every number the three screens show
// can be pinned by a test.

/// One app's share of a period.
struct AppUsage: Identifiable, Hashable {
    var appId: String
    var appName: String
    var category: ActivityCategory
    var productivity: ProductivityType
    var seconds: Int
    var id: String { appId }
}

/// One hour of the day, split by worth. The timeline strip is a stacked bar over
/// these — the same question Apple's Screen Time answers, asked in MyOS's terms.
struct TimelineHour: Identifiable, Hashable {
    var hour: Int
    var productive: Int = 0
    var neutral: Int = 0
    var distracting: Int = 0
    var id: Int { hour }
    var total: Int { productive + neutral + distracting }
    func seconds(_ p: ProductivityType) -> Int {
        switch p {
        case .productive: return productive
        case .neutral: return neutral
        case .distracting: return distracting
        }
    }
}

/// An uninterrupted run of productive work.
struct FocusBlock: Identifiable, Hashable {
    var id: String { startedAt }
    var startedAt: String
    var endedAt: String
    var seconds: Int
    /// The app the block spent most of its time in.
    var appName: String
}

/// Everything the UI needs about one day, computed once.
struct ActivitySummary: Hashable {
    var day: String
    var totalSeconds: Int = 0
    var byDevice: [DeviceType: Int] = [:]
    var byProductivity: [ProductivityType: Int] = [:]
    var apps: [AppUsage] = []
    var timeline: [TimelineHour] = []
    var switches: Int = 0
    var switchesInWorkHours: Int = 0
    var focusBlocks: [FocusBlock] = []
    var sessionCount: Int = 0

    var isEmpty: Bool { totalSeconds == 0 }
    func seconds(_ p: ProductivityType) -> Int { byProductivity[p] ?? 0 }
    func seconds(_ d: DeviceType) -> Int { byDevice[d] ?? 0 }
    var longestFocus: FocusBlock? { focusBlocks.max { $0.seconds < $1.seconds } }

    /// Share of *tracked* time, not of the day. A number out of 24 hours would
    /// be dishonest — MyOS only sees what it is watching.
    func share(_ p: ProductivityType) -> Double {
        totalSeconds > 0 ? Double(seconds(p)) / Double(totalSeconds) : 0
    }
    var productiveShare: Double { share(.productive) }
}

/// A week, and how it moved.
struct ActivityWeekSummary: Hashable {
    var days: [String] = []
    var totalSeconds: Int = 0
    var byDevice: [DeviceType: Int] = [:]
    var byProductivity: [ProductivityType: Int] = [:]
    var apps: [AppUsage] = []
    var dailyTotals: [String: Int] = [:]
    var dailyProductive: [String: Int] = [:]
    var longestFocus: FocusBlock?
    var switches: Int = 0
    /// Hour of day where productive time concentrates, as a two-hour window.
    var bestFocusHour: Int?
    var daysTracked: Int = 0

    var isEmpty: Bool { totalSeconds == 0 }
    func seconds(_ p: ProductivityType) -> Int { byProductivity[p] ?? 0 }
    func seconds(_ d: DeviceType) -> Int { byDevice[d] ?? 0 }
    func share(_ p: ProductivityType) -> Double {
        totalSeconds > 0 ? Double(seconds(p)) / Double(totalSeconds) : 0
    }
    var bestFocusWindow: String? {
        guard let h = bestFocusHour else { return nil }
        return "\(ActivityTime.hourLabel(h)) – \(ActivityTime.hourLabel(h + 2))"
    }
}

enum ActivityEngine {

    /// Work hours, for the "you switched apps N times during work hours" line.
    /// Context switching at 9pm on a Saturday is not the same finding.
    static let workHours = 9..<19

    /// A gap this long or shorter does not end a focus block — reaching for a
    /// terminal or a doc mid-task is part of the task.
    static let focusGapTolerance = 180

    /// A non-productive interruption shorter than this is absorbed into the
    /// block around it, for the same reason.
    static let focusInterruptionTolerance = 60

    // MARK: - Day

    static func sessions(_ events: [ActivityEvent], on day: String) -> [ActivityEvent] {
        events.filter { $0.day == day }.sorted { $0.startedAt < $1.startedAt }
    }

    static func summary(_ events: [ActivityEvent], day: String) -> ActivitySummary {
        let sessions = sessions(events, on: day)
        var out = ActivitySummary(day: day)
        out.sessionCount = sessions.count
        guard !sessions.isEmpty else { return out }

        var apps: [String: AppUsage] = [:]
        var hours = (0..<24).map { TimelineHour(hour: $0) }

        for s in sessions {
            out.totalSeconds += s.duration
            out.byDevice[s.deviceType, default: 0] += s.duration
            out.byProductivity[s.productivity, default: 0] += s.duration

            if var existing = apps[s.appId] {
                existing.seconds += s.duration
                apps[s.appId] = existing
            } else {
                apps[s.appId] = AppUsage(appId: s.appId, appName: s.appName,
                                         category: s.category, productivity: s.productivity,
                                         seconds: s.duration)
            }

            spread(session: s, into: &hours)
        }

        out.apps = apps.values.sorted { $0.seconds > $1.seconds }
        out.timeline = hours
        out.switches = countSwitches(sessions)
        out.switchesInWorkHours = countSwitches(sessions.filter { inWorkHours($0) })
        out.focusBlocks = focusBlocks(sessions)
        return out
    }

    /// A session can straddle midnight-adjacent hours; its time is credited to
    /// each hour it actually occupied rather than all of it to the hour it
    /// started in, or a two-hour block would draw as a spike.
    private static func spread(session s: ActivityEvent, into hours: inout [TimelineHour]) {
        guard let start = ActivityTime.date(s.startedAt) else { return }
        var remaining = s.duration
        var cursor = ActivityTime.secondsIntoDay(start)
        while remaining > 0 && cursor < 24 * 3600 {
            let hour = cursor / 3600
            let untilNextHour = (hour + 1) * 3600 - cursor
            let chunk = min(remaining, untilNextHour)
            switch s.productivity {
            case .productive:  hours[hour].productive += chunk
            case .neutral:     hours[hour].neutral += chunk
            case .distracting: hours[hour].distracting += chunk
            }
            remaining -= chunk
            cursor += chunk
        }
    }

    private static func inWorkHours(_ s: ActivityEvent) -> Bool {
        guard let start = ActivityTime.date(s.startedAt) else { return false }
        return workHours.contains(ActivityTime.secondsIntoDay(start) / 3600)
    }

    /// Consecutive sessions in different apps. Re-entering the same app after a
    /// gap is not a switch — it is the same thread of work resumed.
    static func countSwitches(_ sessions: [ActivityEvent]) -> Int {
        var count = 0
        var previous: String?
        for s in sessions {
            if let previous, previous != s.appId { count += 1 }
            previous = s.appId
        }
        return count
    }

    /// Runs of productive work, tolerating short gaps and short interruptions.
    static func focusBlocks(_ sessions: [ActivityEvent], minimumSeconds: Int = 600) -> [FocusBlock] {
        var blocks: [FocusBlock] = []
        var current: (start: String, end: String, seconds: Int, byApp: [String: Int])?

        func close() {
            guard let c = current, c.seconds >= minimumSeconds else { current = nil; return }
            let app = c.byApp.max { $0.value < $1.value }?.key ?? ""
            blocks.append(FocusBlock(startedAt: c.start, endedAt: c.end, seconds: c.seconds, appName: app))
            current = nil
        }

        for s in sessions {
            let productive = s.productivity == .productive
            let absorbable = !productive && s.duration <= focusInterruptionTolerance

            if productive || (absorbable && current != nil) {
                if var c = current {
                    let gap = secondsBetween(c.end, s.startedAt)
                    if gap > focusGapTolerance {
                        close()
                        current = (s.startedAt, s.endedAt, s.duration, [s.appName: s.duration])
                    } else {
                        c.end = s.endedAt
                        c.seconds += s.duration
                        if productive { c.byApp[s.appName, default: 0] += s.duration }
                        current = c
                    }
                } else if productive {
                    current = (s.startedAt, s.endedAt, s.duration, [s.appName: s.duration])
                }
            } else {
                close()
            }
        }
        close()
        return blocks
    }

    private static func secondsBetween(_ a: String, _ b: String) -> Int {
        guard let da = ActivityTime.date(a), let db = ActivityTime.date(b) else { return 0 }
        return max(0, Int(db.timeIntervalSince(da)))
    }

    // MARK: - Week

    /// Summarise a set of days, reading raw sessions where they are still held
    /// and the compacted rollups where they are not.
    static func weekSummary(doc: ActivityDoc, days: [String]) -> ActivityWeekSummary {
        var out = ActivityWeekSummary(days: days)
        var apps: [String: AppUsage] = [:]
        var productiveByHour = [Int](repeating: 0, count: 24)

        for day in days {
            let daySessions = sessions(doc.events, on: day)
            if !daySessions.isEmpty {
                let s = summary(doc.events, day: day)
                guard s.totalSeconds > 0 else { continue }
                out.daysTracked += 1
                out.totalSeconds += s.totalSeconds
                out.dailyTotals[day] = s.totalSeconds
                out.dailyProductive[day] = s.seconds(.productive)
                out.switches += s.switches
                for (d, v) in s.byDevice { out.byDevice[d, default: 0] += v }
                for (p, v) in s.byProductivity { out.byProductivity[p, default: 0] += v }
                for a in s.apps {
                    if var e = apps[a.appId] { e.seconds += a.seconds; apps[a.appId] = e }
                    else { apps[a.appId] = a }
                }
                for h in s.timeline { productiveByHour[h.hour] += h.productive }
                if let longest = s.longestFocus,
                   longest.seconds > (out.longestFocus?.seconds ?? 0) { out.longestFocus = longest }
            } else if let rollup = doc.days[day], rollup.totalSeconds > 0 {
                // Compacted history: totals survive, per-hour detail does not.
                out.daysTracked += 1
                out.totalSeconds += rollup.totalSeconds
                out.dailyTotals[day] = rollup.totalSeconds
                out.dailyProductive[day] = rollup.seconds(.productive)
                out.switches += rollup.switches
                for (k, v) in rollup.byDevice {
                    if let d = DeviceType(rawValue: k) { out.byDevice[d, default: 0] += v }
                }
                for (k, v) in rollup.byProductivity {
                    if let p = ProductivityType(rawValue: k) { out.byProductivity[p, default: 0] += v }
                }
                for (name, v) in rollup.byApp {
                    let id = ActivityCatalog.slug(name)
                    if var e = apps[id] { e.seconds += v; apps[id] = e }
                    else {
                        let c = ActivityCatalog.classify(appId: id, appName: name, rules: doc.rules)
                        apps[id] = AppUsage(appId: id, appName: name, category: c.category,
                                            productivity: c.productivity, seconds: v)
                    }
                }
            }
        }

        out.apps = apps.values.sorted { $0.seconds > $1.seconds }
        // The best window is the two-hour pair with the most productive time.
        if out.totalSeconds > 0 {
            var best = (hour: 0, seconds: -1)
            for h in 0..<23 {
                let pair = productiveByHour[h] + productiveByHour[h + 1]
                if pair > best.seconds { best = (h, pair) }
            }
            out.bestFocusHour = best.seconds > 0 ? best.hour : nil
        }
        return out
    }

    // MARK: - Retention

    /// Compact anything older than the retention window into a day rollup and
    /// drop its raw sessions. MyOS state is one synced blob; a year of raw
    /// sessions would dominate every sync.
    static func compact(_ doc: inout ActivityDoc, today: String) {
        guard let todayDate = CalMath.date(fromKey: today),
              let cutoffDate = Calendar.current.date(byAdding: .day,
                                                     value: -ActivityDoc.retentionDays,
                                                     to: todayDate) else { return }
        let c = Calendar.current.dateComponents([.year, .month, .day], from: cutoffDate)
        let cutoff = CalMath.key(c.year ?? 0, c.month ?? 1, c.day ?? 1)

        let stale = Set(doc.events.filter { $0.day < cutoff }.map(\.day))
        guard !stale.isEmpty else { return }
        for day in stale {
            doc.days[day] = rollup(doc.events, day: day)
        }
        doc.events.removeAll { $0.day < cutoff }
    }

    static func rollup(_ events: [ActivityEvent], day: String) -> ActivityDayRollup {
        let s = summary(events, day: day)
        var out = ActivityDayRollup(day: day)
        out.totalSeconds = s.totalSeconds
        out.switches = s.switches
        out.longestFocusSeconds = s.longestFocus?.seconds ?? 0
        for (d, v) in s.byDevice { out.byDevice[d.rawValue] = v }
        for (p, v) in s.byProductivity { out.byProductivity[p.rawValue] = v }
        // Only the apps worth remembering — a rollup is a summary, not an archive.
        for a in s.apps.prefix(12) { out.byApp[a.appName] = a.seconds }
        return out
    }
}
