import Foundation

/// The write-ahead log for activity.
///
/// MyOS state is one end-to-end encrypted blob that only exists once the vault
/// is unlocked, and `AppState.push` is a network call — so before this file
/// existed, three ordinary things silently threw away a day's tracking:
///
///   1. **The app was locked.** The Mac asks for the passphrase on every launch.
///      Until it was answered there was no `AppState` to record into, so the
///      sensor either did not run or wrote into nothing.
///   2. **The app quit or crashed** between two pushes. Sessions live in memory
///      until the 2-minute flush; anything newer than the last flush was gone.
///   3. **The network was down.** A failed push leaves the sessions in memory
///      only, which is the same as (2) one quit later.
///
/// So every finished session is appended here first, on disk, in the clear —
/// an app's name, where inside it, and two timestamps. The document folds this
/// in on the next unlock and dedupes by session id.
///
/// This is what lets the Mac record from launch rather than from unlock.
enum ActivityJournal {

    /// Consecutive stretches in the same app separated by no more than this are
    /// one session. Must match the coordinator's rule, because after this file
    /// the journal is the thing doing the merging.
    static let mergeGap = 90

    /// How much history the journal keeps. It only exists to bridge the gap
    /// between a session ending and it reaching the synced document; anything
    /// older than a couple of days has either made it or never will.
    static let retentionDays = 3

    /// The App Group container where there is one, else Application Support —
    /// the Mac is unsandboxed and has no group container at all.
    private static var fileURL: URL? {
        let fm = FileManager.default
        if let group = fm.containerURL(forSecurityApplicationGroupIdentifier: ShareInbox.appGroup) {
            return group.appendingPathComponent("activity-journal.json")
        }
        guard let support = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                        appropriateFor: nil, create: true) else { return nil }
        let dir = support.appendingPathComponent("MyOS", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("activity-journal.json")
    }

    private static let lock = NSLock()

    static func events() -> [ActivityEvent] {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([ActivityEvent].self, from: data)) ?? []
    }

    private static func write(_ events: [ActivityEvent]) {
        guard let url = fileURL, let data = try? JSONEncoder().encode(events) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Take one finished session, merging it into the tail if it continues the
    /// app that is already there. Returns what is now on disk for that session —
    /// the merged event, keeping the original id, so the caller can upsert the
    /// same row into the document rather than appending a second one.
    @discardableResult
    static func record(_ event: ActivityEvent) -> ActivityEvent {
        lock.lock(); defer { lock.unlock() }
        let (items, stored) = appending(event, to: events())
        write(prune(items))
        return stored
    }

    /// The merge rule, without the disk — so it can be pinned by a test.
    static func appending(_ event: ActivityEvent,
                          to items: [ActivityEvent]) -> (items: [ActivityEvent], stored: ActivityEvent) {
        var items = items
        if let last = items.last,
           last.appId == event.appId,
           // Same app is not the same *place*: two tabs, or two files, are two
           // rows however close together they ran.
           last.site == event.site,
           last.title == event.title,
           last.deviceId == event.deviceId,
           last.day == event.day,
           gap(from: last.endedAt, to: event.startedAt) <= mergeGap {
            var merged = last
            merged.endedAt = event.endedAt
            merged.duration += event.duration
            items[items.count - 1] = merged
            return (items, merged)
        }
        items.append(event)
        return (items, event)
    }

    /// Fold the journal into a document. Union by session id, keeping whichever
    /// copy ran longer: the document may hold a *newer* merged version of a
    /// session than the journal does, and a blind overwrite either way loses
    /// real time. Returns how many sessions the document did not already have.
    @discardableResult
    static func fold(into doc: inout ActivityDoc) -> Int {
        fold(events(), into: &doc)
    }

    /// The same fold against an explicit journal, for tests.
    @discardableResult
    static func fold(_ journal: [ActivityEvent], into doc: inout ActivityDoc) -> Int {
        guard !journal.isEmpty else { return 0 }
        var index: [String: Int] = [:]
        for (i, e) in doc.events.enumerated() { index[e.id] = i }

        var added = 0
        for entry in journal {
            if let i = index[entry.id] {
                if entry.duration > doc.events[i].duration {
                    doc.events[i].duration = entry.duration
                    doc.events[i].endedAt = max(doc.events[i].endedAt, entry.endedAt)
                }
            } else {
                index[entry.id] = doc.events.count
                doc.events.append(entry)
                added += 1
            }
        }
        if added > 0 { doc.events.sort { $0.startedAt < $1.startedAt } }
        return added
    }

    static func clear() {
        lock.lock(); defer { lock.unlock() }
        write([])
    }

    /// Drop anything past the retention window. Pure so the rule is testable
    /// without a clock.
    static func prune(_ events: [ActivityEvent], now: Date = Date()) -> [ActivityEvent] {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: now) else { return events }
        // `AppState.dateKey` is main-actor isolated and the journal is written
        // from the sensor, so the key is formed here rather than borrowed.
        let c = Calendar.current.dateComponents([.year, .month, .day], from: cutoff)
        let key = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 1, c.day ?? 1)
        return events.filter { $0.day >= key }
    }

    private static func gap(from end: String, to start: String) -> Int {
        guard let a = ActivityTime.date(end), let b = ActivityTime.date(start) else { return .max }
        return max(0, Int(b.timeIntervalSince(a)))
    }
}
