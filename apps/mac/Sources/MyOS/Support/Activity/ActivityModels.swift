import Foundation

// The activity data model.
//
// One shape, whatever the device. A Mac session recorded by watching the
// frontmost app and an iPhone session assembled from a Shortcuts automation
// produce the same `ActivityEvent`; nothing above this layer is allowed to care
// where a session came from, which is what lets Today, Productivity and the
// Weekly Report all read one aggregate.

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
    /// iOS: MyOS's own foreground time, from scenePhase.
    case iosForeground
    /// iOS: an app-open reported by a Shortcuts personal automation.
    case iosShortcut
    /// Typed in by hand.
    case manual

    var label: String {
        switch self {
        case .macFrontmost:  return "Mac"
        case .iosForeground: return "MyOS on iPhone"
        case .iosShortcut:   return "iPhone automation"
        case .manual:        return "Added by hand"
        }
    }
}

/// One continuous stretch in one app.
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
    /// Seconds. Integer units, like every other measure in MyOS.
    var duration: Int
    var productivity: ProductivityType
    var source: ActivitySourceKind

    /// `yyyy-MM-dd` of the session's start — the bucket it belongs to.
    var day: String { String(startedAt.prefix(10)) }

    init(id: String = UUID().uuidString.lowercased(),
         deviceId: String, deviceType: DeviceType, platform: String,
         appId: String, appName: String, category: ActivityCategory,
         startedAt: String, endedAt: String, duration: Int,
         productivity: ProductivityType, source: ActivitySourceKind) {
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
    }

    enum CodingKeys: String, CodingKey {
        case id, deviceId, deviceType, platform, appId, appName, category
        case startedAt, endedAt, duration, productivity, source
    }
}

/// A per-app override. What MyOS guesses about an app is a starting point; what
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

/// A device MyOS has seen activity from, so the breakdown can name it honestly
/// and say when it last reported.
struct ActivityDevice: Codable, Hashable, Identifiable {
    var deviceId: String
    var deviceType: DeviceType
    var name: String
    var lastSeen: String
    var id: String { deviceId }
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

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        events   = (try? c.decode([ActivityEvent].self, forKey: .events)) ?? []
        days     = (try? c.decode([String: ActivityDayRollup].self, forKey: .days)) ?? [:]
        rules    = (try? c.decode([String: AppRule].self, forKey: .rules)) ?? [:]
        devices  = (try? c.decode([String: ActivityDevice].self, forKey: .devices)) ?? [:]
    }

    enum CodingKeys: String, CodingKey { case events, days, rules, devices }

    /// Union two copies of the document.
    ///
    /// This is why activity can be written on the Mac and the iPhone at the same
    /// time. MyOS state is one last-write-wins blob per key, so a naive pull
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
        // Rules and devices are edits, not measurements — the other copy is at
        // least as new as this one for anything it knows about.
        out.rules.merge(other.rules) { _, incoming in incoming }
        out.devices.merge(other.devices) { mine, incoming in
            incoming.lastSeen > mine.lastSeen ? incoming : mine
        }
        return out
    }

    /// How long raw sessions are kept before they are compacted into `days`.
    static let retentionDays = 14
}

// MARK: - Time helpers

/// Activity works in wall-clock seconds and ISO stamps; the rest of MyOS works
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
