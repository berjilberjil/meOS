import Foundation

// The activity data model.
//
// One sensor: the Mac. iOS gives an app no way to read another app's usage —
// not through Screen Time, which renders in a sandbox it cannot report back
// from, and not through anything else — so an "iPhone" column could only ever
// have held meOS timing itself. A number that small, sitting next to a real
// day's work, reads as data when it is an artefact, so it is gone. The iPhone
// *shows* this document; it does not write to it.

/// Where a session was recorded. `iphone` is kept only so that sessions written
/// by an older build still decode — and are then dropped by
/// `ActivityDoc.dropPhoneSessions()` rather than being silently re-labelled as
/// the Mac's.
enum DeviceType: String, Codable, CaseIterable, Hashable, Identifiable {
    case mac, iphone
    var id: String { rawValue }
    var label: String { self == .mac ? "Mac" : "iPhone" }
    var icon: String { self == .mac ? "laptopcomputer" : "iphone" }
}

/// What a session is worth. Deliberately three: a scale with more points invites
/// arguing about the middle instead of acting on the ends.
enum ProductivityType: String, Codable, CaseIterable, Hashable, Identifiable {
    case productive, neutral, distracting
    var id: String { rawValue }
    var label: String {
        switch self {
        case .productive:  return "Productive"
        case .neutral:     return "Neutral"
        case .distracting: return "Distracting"
        }
    }
    /// The one-glyph marker used in rows and the current-focus header.
    var mark: String {
        switch self {
        case .productive:  return "checkmark"
        case .neutral:     return "circle.fill"
        case .distracting: return "exclamationmark"
        }
    }
}

/// What kind of work a session is. Categories exist to make an app's *meaning*
/// legible — "CapCut" means nothing to the rules engine, "content creation"
/// does.
enum ActivityCategory: String, Codable, CaseIterable, Hashable, Identifiable {
    case development, contentCreation, design, writing, communication,
         research, reading, entertainment, social, utility, finance, health, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .development:     return "Development"
        case .contentCreation: return "Content creation"
        case .design:          return "Design"
        case .writing:         return "Writing"
        case .communication:   return "Communication"
        case .research:        return "Research"
        case .reading:         return "Reading"
        case .entertainment:   return "Entertainment"
        case .social:          return "Social"
        case .utility:         return "Utility"
        case .finance:         return "Finance"
        case .health:          return "Health"
        case .other:           return "Other"
        }
    }

    /// What a category is worth before any per-app rule is applied.
    ///
    /// Communication is neutral rather than distracting on purpose: Slack at
    /// 10am is work and Slack at 11pm is not, and that is a question about
    /// *when* and *how long*, which the rules engine answers — not a question
    /// about the app.
    var defaultProductivity: ProductivityType {
        switch self {
        case .development, .contentCreation, .design, .writing, .research, .finance:
            return .productive
        case .communication, .reading, .utility, .health, .other:
            return .neutral
        case .entertainment, .social:
            return .distracting
        }
    }
}

/// Where a session came from. Kept on the event so an honest empty state can say
/// *why* a number is missing rather than showing a zero.
enum ActivitySourceKind: String, Codable, CaseIterable, Hashable {
    /// macOS: the frontmost application, sampled by `MacActivityMonitor`.
    case macFrontmost
    /// Typed in by hand.
    case manual

    var label: String {
        switch self {
        case .macFrontmost: return "Mac"
        case .manual:       return "Added by hand"
        }
    }
}

/// One continuous stretch in one app — and, where Accessibility allows it, in
/// one *place* inside that app: a domain, a document, a file.
struct ActivityEvent: Codable, Identifiable, Hashable {
    var id: String
    var deviceId: String
    var deviceType: DeviceType
    var platform: String
    /// Bundle identifier where there is one, else a stable slug of the name.
    var appId: String
    var appName: String
    var category: ActivityCategory
    /// ISO-8601 with seconds. The `day` key is derived, not stored twice.
    var startedAt: String
    var endedAt: String
    /// Seconds. Integer units, like every other measure in meOS.
    var duration: Int
    var productivity: ProductivityType
    var source: ActivitySourceKind
    /// The host of the page in front, for a browser session. Host only — never
    /// a path, never a query. nil everywhere Accessibility could not say.
    var site: String?
    /// The window title, cleaned of the app's own name. nil when titles are
    /// switched off, or when there was nothing to read.
    var title: String?

    /// `yyyy-MM-dd` of the session's start — the bucket it belongs to.
    var day: String { String(startedAt.prefix(10)) }

    /// What this session counts *as* in a breakdown.
    ///
    /// A browser is not a thing you spend time on, it is the room the time is
    /// spent in — so a session with a site is grouped and classified under the
    /// site, and only a session without one falls back to the app. This is the
    /// whole reason the Accessibility permission is worth asking for.
    var groupId: String { site.map { "web." + $0 } ?? appId }
    var groupName: String { site ?? appName }
    /// The app whose icon should mark the row — the browser, for a web row.
    var iconId: String { appId }

    init(id: String = UUID().uuidString.lowercased(),
         deviceId: String, deviceType: DeviceType, platform: String,
         appId: String, appName: String, category: ActivityCategory,
         startedAt: String, endedAt: String, duration: Int,
         productivity: ProductivityType, source: ActivitySourceKind,
         site: String? = nil, title: String? = nil) {
        self.id = id
        self.deviceId = deviceId
        self.deviceType = deviceType
        self.platform = platform
        self.appId = appId
        self.appName = appName
        self.category = category
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.duration = duration
        self.productivity = productivity
        self.source = source
        self.site = site
        self.title = title
    }

    /// Tolerant decoding: an event written by an older build, or by a Shortcuts
    /// automation that omitted a field, must not take the whole document down
    /// with it.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id           = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString.lowercased()
        deviceId     = try c.decodeIfPresent(String.self, forKey: .deviceId) ?? ""
        deviceType   = DeviceType(rawValue: (try? c.decode(String.self, forKey: .deviceType)) ?? "") ?? .mac
        platform     = try c.decodeIfPresent(String.self, forKey: .platform) ?? ""
        appId        = try c.decodeIfPresent(String.self, forKey: .appId) ?? ""
        appName      = try c.decodeIfPresent(String.self, forKey: .appName) ?? "Unknown"
        category     = ActivityCategory(rawValue: (try? c.decode(String.self, forKey: .category)) ?? "") ?? .other
        startedAt    = try c.decodeIfPresent(String.self, forKey: .startedAt) ?? ""
        endedAt      = try c.decodeIfPresent(String.self, forKey: .endedAt) ?? startedAt
        duration     = try c.decodeIfPresent(Int.self, forKey: .duration) ?? 0
        productivity = ProductivityType(rawValue: (try? c.decode(String.self, forKey: .productivity)) ?? "")
                        ?? category.defaultProductivity
        source       = ActivitySourceKind(rawValue: (try? c.decode(String.self, forKey: .source)) ?? "") ?? .manual
        site         = try c.decodeIfPresent(String.self, forKey: .site)
        title        = try c.decodeIfPresent(String.self, forKey: .title)
    }

    /// Written by hand so the optional detail is *omitted* rather than encoded
    /// as null. Every session lives in one synced blob, and two null keys per
    /// row is a few hundred kilobytes a fortnight of nothing.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(deviceId, forKey: .deviceId)
        try c.encode(deviceType, forKey: .deviceType)
        try c.encode(platform, forKey: .platform)
        try c.encode(appId, forKey: .appId)
        try c.encode(appName, forKey: .appName)
        try c.encode(category, forKey: .category)
        try c.encode(startedAt, forKey: .startedAt)
        try c.encode(endedAt, forKey: .endedAt)
        try c.encode(duration, forKey: .duration)
        try c.encode(productivity, forKey: .productivity)
        try c.encode(source, forKey: .source)
        try c.encodeIfPresent(site, forKey: .site)
        try c.encodeIfPresent(title, forKey: .title)
    }

    enum CodingKeys: String, CodingKey {
        case id, deviceId, deviceType, platform, appId, appName, category
        case startedAt, endedAt, duration, productivity, source, site, title
    }
}

/// A per-app override. What meOS guesses about an app is a starting point; what
/// Berjil says it is wins, permanently.
struct AppRule: Codable, Hashable, Identifiable {
    var appId: String
    var appName: String
    var category: ActivityCategory
    var productivity: ProductivityType
    var id: String { appId }
}

/// A finished day, compacted. Raw events are kept for a fortnight so the day and
/// week views can be exact; beyond that only this survives, because the synced
/// state is one blob and a year of raw sessions would dominate it.
struct ActivityDayRollup: Codable, Hashable, Identifiable {
    var day: String
    var totalSeconds: Int = 0
    var byDevice: [String: Int] = [:]
    var byProductivity: [String: Int] = [:]
    var byApp: [String: Int] = [:]
    var switches: Int = 0
    var longestFocusSeconds: Int = 0
    var id: String { day }

    func seconds(_ p: ProductivityType) -> Int { byProductivity[p.rawValue] ?? 0 }
    func seconds(_ d: DeviceType) -> Int { byDevice[d.rawValue] ?? 0 }
}

/// A device meOS has seen activity from, so the breakdown can name it honestly
/// and say when it last reported.
struct ActivityDevice: Codable, Hashable, Identifiable {
    var deviceId: String
    var deviceType: DeviceType
    var name: String
    var lastSeen: String
    var id: String { deviceId }
}

/// What the Mac is doing right now, carried in the synced document.
///
/// The Mac is the only sensor, and the phone is often where the day gets read —
/// so without this the iPhone's "focusing now" would sit blank for up to five
/// minutes while the Mac happily banked a session it had not finished. It is a
/// *note*, not a session: it is never added to any total, because the seconds
/// it describes are still being recorded on the Mac and will arrive as a real
/// session. It only answers "what is he in front of".
struct ActivityLive: Codable, Hashable {
    var appId: String
    var appName: String
    var site: String?
    var title: String?
    var category: ActivityCategory
    var productivity: ProductivityType
    var deviceName: String
    var startedAt: String
    var updatedAt: String

    /// A Mac that slept, quit or lost the network must not leave the phone
    /// claiming you are still in Xcode.
    ///
    /// Six minutes, because the note rides along on pushes rather than adding
    /// any: a session that has run five minutes is banked and pushed, so an
    /// active Mac refreshes this at least that often, and sleep, lock and quit
    /// all clear it outright. What is left over is a crash or a dead network,
    /// and those should go quiet quickly.
    static let freshness: TimeInterval = 6 * 60

    func isFresh(now: Date = Date()) -> Bool {
        guard let seen = ActivityTime.date(updatedAt) else { return false }
        let age = now.timeIntervalSince(seen)
        return age >= -60 && age <= Self.freshness
    }

    /// The note as the session it stands for, so the surfaces that already read
    /// a live `ActivityEvent` need to know nothing about any of this.
    func asEvent(now: Date = Date()) -> ActivityEvent? {
        guard let start = ActivityTime.date(startedAt) else { return nil }
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return ActivityEvent(deviceId: "", deviceType: .mac, platform: "",
                             appId: appId, appName: appName, category: category,
                             startedAt: startedAt, endedAt: ActivityTime.stamp(now),
                             duration: seconds, productivity: productivity,
                             source: .macFrontmost, site: site, title: title)
    }
}

/// The synced document. One key, `myos.activity`.
struct ActivityDoc: Codable, Hashable {
    /// Raw sessions inside the retention window, oldest first.
    var events: [ActivityEvent] = []
    /// Compacted history, keyed by `yyyy-MM-dd`.
    var days: [String: ActivityDayRollup] = [:]
    /// Per-app overrides, keyed by appId.
    var rules: [String: AppRule] = [:]
    /// Devices seen, keyed by deviceId.
    var devices: [String: ActivityDevice] = [:]
    /// What the recording device is in front of right now, for the other one.
    var live: ActivityLive?
    /// When someone last asked for this history to be erased, `yyyy-MM-dd'T'HH:mm:ss`.
    ///
    /// `merged` is a union, which is what lets two devices record at once — but
    /// a union can never express a removal. Erasing on the iPhone pushed an
    /// empty doc, the Mac merged it and changed nothing, then pushed its full
    /// copy straight back, and every erased session reappeared on the phone
    /// within a couple of minutes. A tombstone is the missing half: the erase
    /// travels as a fact about time rather than as an absence.
    var erasedAt: String = ""

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        erasedAt = (try? c.decodeIfPresent(String.self, forKey: .erasedAt)) ?? ""
        events   = (try? c.decode([ActivityEvent].self, forKey: .events)) ?? []
        days     = (try? c.decode([String: ActivityDayRollup].self, forKey: .days)) ?? [:]
        rules    = (try? c.decode([String: AppRule].self, forKey: .rules)) ?? [:]
        devices  = (try? c.decode([String: ActivityDevice].self, forKey: .devices)) ?? [:]
        live     = try? c.decodeIfPresent(ActivityLive.self, forKey: .live)
    }

    enum CodingKeys: String, CodingKey { case events, days, rules, devices, live, erasedAt }

    /// Union two copies of the document.
    ///
    /// This is why activity can be written on the Mac and the iPhone at the same
    /// time. meOS state is one last-write-wins blob per key, so a naive pull
    /// would let whichever device pushed last erase the other's sessions.
    /// Sessions carry UUIDs and each device only ever creates its own, so a
    /// union by id is safe — and because every device merges before it pushes,
    /// the two copies converge after one round trip.
    func merged(with other: ActivityDoc) -> ActivityDoc {
        var out = self
        let known = Set(events.map(\.id))
        out.events = (events + other.events.filter { !known.contains($0.id) })
            .sorted { $0.startedAt < $1.startedAt }
        for (day, rollup) in other.days where out.days[day] == nil || (out.days[day]?.totalSeconds ?? 0) < rollup.totalSeconds {
            out.days[day] = rollup
        }
        // The newer erase wins, and everything it covers goes — including
        // anything the other copy is still holding. Without this the union
        // simply put it all back.
        out.erasedAt = max(erasedAt, other.erasedAt)
        if !out.erasedAt.isEmpty {
            out.events.removeAll { $0.startedAt < out.erasedAt }
            let cutoffDay = String(out.erasedAt.prefix(10))
            out.days = out.days.filter { $0.key >= cutoffDay }
        }
        // Rules and devices are edits, not measurements — the other copy is at
        // least as new as this one for anything it knows about.
        out.rules.merge(other.rules) { _, incoming in incoming }
        out.devices.merge(other.devices) { mine, incoming in
            incoming.lastSeen > mine.lastSeen ? incoming : mine
        }
        if let theirs = other.live, (out.live.map { theirs.updatedAt > $0.updatedAt } ?? true) {
            out.live = theirs
        }
        return out
    }

    /// Drop everything the iPhone ever recorded.
    ///
    /// It only ever amounted to meOS timing its own foreground, plus whatever a
    /// Shortcuts automation had been set up to report — and shown next to a real
    /// Mac day, "meOS 16m" reads like a measurement of the phone when it is an
    /// artefact of the one app allowed to measure anything. Rollups keep their
    /// totals but lose the phone's share, so a compacted day does not go on
    /// quietly counting it.
    @discardableResult
    mutating func dropPhoneSessions() -> Int {
        let before = events.count
        events.removeAll { $0.deviceType == .iphone }
        devices = devices.filter { $0.value.deviceType != .iphone }
        for (key, var rollup) in days {
            guard let phone = rollup.byDevice[DeviceType.iphone.rawValue], phone > 0 else { continue }
            let total = rollup.totalSeconds
            rollup.byDevice[DeviceType.iphone.rawValue] = nil
            rollup.totalSeconds = max(0, total - phone)
            // A rollup has no per-device worth split, so the phone's share is
            // taken off proportionally. Leaving the split untouched would make
            // the percentages under a compacted day add up to more than the day.
            let keep = total > 0 ? Double(rollup.totalSeconds) / Double(total) : 0
            rollup.byProductivity = rollup.byProductivity.mapValues { Int(Double($0) * keep) }
            days[key] = rollup
        }
        return before - events.count
    }

    /// How long raw sessions are kept before they are compacted into `days`.
    static let retentionDays = 14
}

// MARK: - Time helpers

/// Activity works in wall-clock seconds and ISO stamps; the rest of meOS works
/// in `yyyy-MM-dd` keys. This is the one place that converts.
enum ActivityTime {
    static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone.current
        return f
    }()

    static func stamp(_ date: Date) -> String { iso.string(from: date) }

    static func date(_ stamp: String) -> Date? {
        if let d = iso.date(from: stamp) { return d }
        // A Shortcuts automation may hand over a bare `yyyy-MM-dd HH:mm:ss`.
        let fallback = DateFormatter()
        fallback.locale = Locale(identifier: "en_US_POSIX")
        fallback.timeZone = .current
        fallback.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return fallback.date(from: stamp)
    }

    /// Seconds since midnight — where a session sits in the day's timeline.
    static func secondsIntoDay(_ date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        return (c.hour ?? 0) * 3600 + (c.minute ?? 0) * 60 + (c.second ?? 0)
    }

    /// "10 AM" / "10:30 AM" — used for focus-window labels.
    static func hourLabel(_ hour: Int) -> String {
        let h = ((hour % 24) + 24) % 24
        if h == 0 { return "12 AM" }
        if h == 12 { return "12 PM" }
        return h < 12 ? "\(h) AM" : "\(h - 12) PM"
    }
}
