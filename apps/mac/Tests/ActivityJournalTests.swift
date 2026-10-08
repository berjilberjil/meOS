import XCTest
@testable import meOS

/// The journal is what makes tracking survive a locked vault, a quit, a crash
/// and an offline day, so its two rules — merge the tail, union by id keeping
/// the longer run — are pinned here. Both are tested against explicit arrays
/// rather than the real file, so the suite never touches Application Support.
final class ActivityJournalTests: XCTestCase {

    private func event(_ id: String, _ app: String, start: String, end: String, seconds: Int,
                       device: DeviceType = .mac) -> ActivityEvent {
        ActivityEvent(id: id, deviceId: "d1", deviceType: device, platform: "test",
                      appId: "id.\(app)", appName: app, category: .development,
                      startedAt: start, endedAt: end, duration: seconds,
                      productivity: .productive, source: .macFrontmost)
    }

    private func stamp(_ hour: Int, _ minute: Int, _ second: Int = 0) -> String {
        var c = DateComponents()
        c.year = 2026; c.month = 8; c.day = 25
        c.hour = hour; c.minute = minute; c.second = second
        return ActivityTime.stamp(Calendar.current.date(from: c)!)
    }

    // MARK: Merging the tail

    /// A session banked every five minutes must not read as a pile of five
    /// minute sessions — that would inflate the switch count and the blob.
    func testBankedHalvesMergeBackIntoOneSession() {
        let first = event("a", "Xcode", start: stamp(10, 0), end: stamp(10, 5), seconds: 300)
        let second = event("b", "Xcode", start: stamp(10, 5), end: stamp(10, 10), seconds: 300)

        let (items, stored) = ActivityJournal.appending(second, to: [first])
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(stored.id, "a", "the merged row keeps the first id so the document upserts it")
        XCTAssertEqual(stored.duration, 600)
        XCTAssertEqual(stored.endedAt, stamp(10, 10))
    }

    /// A different app is a different session, however close together.
    func testDifferentAppDoesNotMerge() {
        let first = event("a", "Xcode", start: stamp(10, 0), end: stamp(10, 5), seconds: 300)
        let second = event("b", "Slack", start: stamp(10, 5), end: stamp(10, 6), seconds: 60)
        let (items, stored) = ActivityJournal.appending(second, to: [first])
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(stored.id, "b")
    }

    /// Coming back to the same app an hour later is a new session, not a
    /// continuation — otherwise a lunch break disappears into the morning.
    func testLongGapDoesNotMerge() {
        let first = event("a", "Xcode", start: stamp(10, 0), end: stamp(10, 5), seconds: 300)
        let second = event("b", "Xcode", start: stamp(11, 5), end: stamp(11, 10), seconds: 300)
        let (items, _) = ActivityJournal.appending(second, to: [first])
        XCTAssertEqual(items.count, 2)
    }

    // MARK: Folding into the document

    /// The case this whole file exists for: the app was locked or quit, so the
    /// document never heard about these sessions.
    func testFoldAddsSessionsTheDocumentNeverSaw() {
        var doc = ActivityDoc()
        doc.events = [event("a", "Xcode", start: stamp(9, 0), end: stamp(9, 30), seconds: 1800)]
        let journal = [event("b", "Slack", start: stamp(10, 0), end: stamp(10, 15), seconds: 900)]

        XCTAssertEqual(ActivityJournal.fold(journal, into: &doc), 1)
        XCTAssertEqual(doc.events.count, 2)
        XCTAssertEqual(doc.events.map(\.startedAt), doc.events.map(\.startedAt).sorted())
    }

    /// Folding twice must not double a day. Sessions carry ids for exactly this.
    func testFoldIsIdempotent() {
        var doc = ActivityDoc()
        let journal = [event("a", "Xcode", start: stamp(9, 0), end: stamp(9, 30), seconds: 1800)]
        XCTAssertEqual(ActivityJournal.fold(journal, into: &doc), 1)
        XCTAssertEqual(ActivityJournal.fold(journal, into: &doc), 0)
        XCTAssertEqual(doc.events.count, 1)
        XCTAssertEqual(doc.events[0].duration, 1800)
    }

    /// The document can hold a *longer* version of a session than the journal —
    /// it kept running after the last write — and neither copy may clobber the
    /// other's extra minutes.
    func testFoldKeepsWhicheverRanLonger() {
        var doc = ActivityDoc()
        doc.events = [event("a", "Xcode", start: stamp(9, 0), end: stamp(9, 30), seconds: 1800)]
        let shorter = [event("a", "Xcode", start: stamp(9, 0), end: stamp(9, 10), seconds: 600)]
        XCTAssertEqual(ActivityJournal.fold(shorter, into: &doc), 0)
        XCTAssertEqual(doc.events[0].duration, 1800)

        let longer = [event("a", "Xcode", start: stamp(9, 0), end: stamp(9, 45), seconds: 2700)]
        XCTAssertEqual(ActivityJournal.fold(longer, into: &doc), 0)
        XCTAssertEqual(doc.events[0].duration, 2700)
        XCTAssertEqual(doc.events[0].endedAt, stamp(9, 45))
    }

    // MARK: Retention

    /// The journal is a bridge, not an archive.
    func testPruneDropsAnythingPastTheWindow() {
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 25))!
        let fresh = event("a", "Xcode", start: stamp(9, 0), end: stamp(9, 30), seconds: 1800)
        var stale = fresh
        stale.id = "old"
        stale.startedAt = "2026-08-01T09:00:00+05:30"
        stale.endedAt = "2026-08-01T09:30:00+05:30"

        let kept = ActivityJournal.prune([stale, fresh], now: now)
        XCTAssertEqual(kept.map(\.id), ["a"])
    }

    // MARK: Where it is written

    /// The regression that made this whole file a no-op on the Mac.
    ///
    /// `containerURL(forSecurityApplicationGroupIdentifier:)` returns a path
    /// even when the app has no App Group entitlement — a path to a directory
    /// that does not exist. Treating that as "there is a container" sent every
    /// write into a `try?` that threw, so the write-ahead log stored nothing on
    /// the only device that records anything.
    func testGroupContainerAnswersExistenceNotNilness() {
        let fm = FileManager.default
        let raw = fm.containerURL(forSecurityApplicationGroupIdentifier: ShareInbox.appGroup)
        let resolved = ShareInbox.groupContainer()

        if let raw, !fm.fileExists(atPath: raw.path) {
            XCTAssertNil(resolved, "a path to a directory that does not exist is not a container")
        }
        if let resolved {
            XCTAssertTrue(fm.fileExists(atPath: resolved.path),
                          "a container that is handed out must be somewhere a write can land")
        }
    }
}
