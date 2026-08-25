import Foundation

/// The hand-off between an iOS Shortcuts automation and MyOS.
///
/// iOS gives an app no way to read another app's usage. The Screen Time stack
/// (FamilyControls + DeviceActivity) is the only sanctioned route and it is
/// gated twice: the `family-controls` entitlement is not provisionable on a free
/// personal team, and its report extension is sandboxed so per-app numbers can
/// be *rendered* but never handed back to your own model. Neither gate can be
/// coded around.
///
/// What does work, today, on a free account: a personal automation — "When
/// WhatsApp is opened, run MyOS" — firing an App Intent. The intent runs in the
/// background, in its own process, and cannot decrypt MyOS state, so it drops a
/// ping in the shared App Group container and the app folds those pings into
/// sessions the next time it is frontmost. Same pattern as `ShareInbox`.
///
/// Nothing sensitive lives here: an app's display name and a timestamp.
enum ActivityInbox {
    /// Must match the `com.apple.security.application-groups` entitlement on the
    /// app and on the intent's target, or the container URL comes back nil.
    static let appGroup = ShareInbox.appGroup

    enum Kind: String, Codable { case opened, closed }

    struct Ping: Codable, Equatable, Hashable {
        var appName: String
        var kind: Kind
        var at: String
    }

    /// A session with no closing ping — the automation was never set up, or iOS
    /// dropped it — is capped rather than left to run to the end of the day.
    static let unterminatedSessionCap = 30 * 60

    private static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("activity-inbox.json")
    }

    private static let lock = NSLock()

    static func pending() -> [Ping] {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Ping].self, from: data)) ?? []
    }

    /// Queue one ping. Called from the intent's process.
    @discardableResult
    static func add(appName: String, kind: Kind, at date: Date = Date()) -> Bool {
        guard let url = fileURL else { return false }
        lock.lock(); defer { lock.unlock() }
        var items = pending()
        items.append(Ping(appName: appName, kind: kind, at: ActivityTime.stamp(date)))
        // A runaway automation must not grow this file without bound.
        if items.count > 2000 { items.removeFirst(items.count - 2000) }
        guard let data = try? JSONEncoder().encode(items) else { return false }
        try? data.write(to: url, options: .atomic)
        return true
    }

    static func clear() {
        guard let url = fileURL else { return }
        lock.lock(); defer { lock.unlock() }
        try? Data("[]".utf8).write(to: url, options: .atomic)
    }

    /// Turn pings into sessions.
    ///
    /// An `opened` ping starts a session; it ends at the matching `closed` ping,
    /// at the next `opened` ping for a different app (iOS only foregrounds one
    /// app at a time), or at the cap. Sessions shorter than the floor are
    /// dropped — an accidental tap is not usage.
    static func sessions(from pings: [Ping],
                         rules: [String: AppRule] = [:],
                         now: Date = Date(),
                         minimumSeconds: Int = 10) -> [ActivityEvent] {
        let ordered = pings.sorted { $0.at < $1.at }
        var out: [ActivityEvent] = []
        var open: (name: String, at: Date)?

        func close(_ end: Date, capped: Bool) {
            guard let started = open else { return }
            open = nil
            var seconds = Int(end.timeIntervalSince(started.at))
            if capped { seconds = min(seconds, unterminatedSessionCap) }
            guard seconds >= minimumSeconds else { return }
            let endDate = started.at.addingTimeInterval(TimeInterval(seconds))
            let id = ActivityCatalog.slug(started.name)
            let classified = ActivityCatalog.classify(appId: id, appName: started.name, rules: rules)
            out.append(ActivityEvent(deviceId: ActivityDeviceIdentity.deviceId,
                                     deviceType: .iphone,
                                     platform: ActivityDeviceIdentity.platform,
                                     appId: id,
                                     appName: started.name,
                                     category: classified.category,
                                     startedAt: ActivityTime.stamp(started.at),
                                     endedAt: ActivityTime.stamp(endDate),
                                     duration: seconds,
                                     productivity: classified.productivity,
                                     source: .iosShortcut))
        }

        for ping in ordered {
            guard let at = ActivityTime.date(ping.at) else { continue }
            switch ping.kind {
            case .opened:
                close(at, capped: true)
                open = (ping.appName, at)
            case .closed:
                if let current = open, current.name.caseInsensitiveCompare(ping.appName) == .orderedSame {
                    close(at, capped: false)
                }
                // A close for an app we never saw open tells us nothing.
            }
        }
        // Whatever is still open is still running; cap it at now.
        close(now, capped: true)
        return out
    }
}
