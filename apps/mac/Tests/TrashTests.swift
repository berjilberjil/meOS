import XCTest
@testable import MyOS

/// The bin's two jobs are giving a thing back exactly as it was, and letting go
/// of it on the right day. Both are the kind of wrong you only find out about
/// when you needed the thing back, so they are pinned here.
final class TrashTests: XCTestCase {

    private let today = "2026-08-30"

    private func entry(kind: TrashKind = .note,
                       deletedOn day: String,
                       payload: String = "{}",
                       media: [String] = []) -> TrashEntry {
        TrashEntry(itemID: "item-1", kind: kind, title: "A note",
                   deletedAt: "\(day)T09:15:00", payload: payload, mediaKeys: media)
    }

    // MARK: - Retention

    func testAFreshDeleteHasTheWholeWindow() {
        XCTAssertEqual(TrashRetention.daysLeft(entry(deletedOn: today), todayKey: today), 30)
    }

    func testTheWindowCountsDown() {
        XCTAssertEqual(TrashRetention.daysLeft(entry(deletedOn: "2026-08-27"), todayKey: today), 27)
        // 1 Aug + 30 days is 31 Aug, and today is the 30th — one day left, not two.
        XCTAssertEqual(TrashRetention.daysLeft(entry(deletedOn: "2026-08-01"), todayKey: today), 1)
    }

    /// Day 30 is the last day it is still there; day 31 is gone.
    func testExpiryIsOnTheThirtiethDayAndNotBefore() {
        let lastDay = entry(deletedOn: "2026-07-31")     // +30 = 2026-08-30, today
        XCTAssertEqual(TrashRetention.daysLeft(lastDay, todayKey: today), 0)
        XCTAssertTrue(TrashRetention.isExpired(lastDay, todayKey: today))

        let oneMore = entry(deletedOn: "2026-08-01")     // +30 = 2026-08-31, tomorrow
        XCTAssertFalse(TrashRetention.isExpired(oneMore, todayKey: today))
    }

    func testSpanningAMonthBoundaryUsesRealDaysNotThirtyOfThem() {
        // Feb is short: 2026-02-10 + 30 days is 2026-03-12, not 2026-03-10.
        let e = entry(deletedOn: "2026-02-10")
        XCTAssertEqual(TrashRetention.purgeDay(e), "2026-03-12")
    }

    /// The safe direction to be wrong in. A stamp nobody can parse must cost a
    /// row that lingers, never a note that disappears.
    func testAnUnparseableStampIsKeptRatherThanPurged() {
        var broken = entry(deletedOn: today)
        broken.deletedAt = "not a date"
        XCTAssertFalse(TrashRetention.isExpired(broken, todayKey: today))
        XCTAssertEqual(TrashRetention.daysLeft(broken, todayKey: today), TrashRetention.days)
    }

    func testSplitSeparatesTheSweepFromTheRest() {
        let entries = [entry(deletedOn: today),
                       entry(deletedOn: "2026-07-01"),      // long gone
                       entry(deletedOn: "2026-08-20")]
        let (kept, expired) = TrashRetention.split(entries, todayKey: today)
        XCTAssertEqual(kept.count, 2)
        XCTAssertEqual(expired.count, 1)
        XCTAssertEqual(expired.first?.deletedDay, "2026-07-01")
    }

    // MARK: - Wording

    func testRowWording() {
        XCTAssertEqual(TrashRetention.deletedPhrase(entry(deletedOn: today), todayKey: today),
                       "deleted today")
        XCTAssertEqual(TrashRetention.deletedPhrase(entry(deletedOn: "2026-08-29"), todayKey: today),
                       "deleted yesterday")
        XCTAssertEqual(TrashRetention.deletedPhrase(entry(deletedOn: "2026-08-27"), todayKey: today),
                       "deleted 3 days ago")
        XCTAssertEqual(TrashRetention.remainingPhrase(entry(deletedOn: "2026-08-29"), todayKey: today),
                       "29 days left")
        XCTAssertEqual(TrashRetention.remainingPhrase(entry(deletedOn: "2026-07-31"), todayKey: today),
                       "goes today")
    }

    // MARK: - Round trip

    /// The whole point: what comes out is what went in.
    func testANoteSurvivesTheRoundTrip() throws {
        let note = Note(id: "n-1", createdAt: "2026-08-01T10:00:00",
                        updatedAt: "2026-08-02T10:00:00", title: "Ideas",
                        body: "one\ntwo", pinned: true)
        let e = TrashEntry(itemID: note.id, kind: .note, title: note.title,
                           deletedAt: "\(today)T09:00:00",
                           payload: TrashEntry.encode(note))
        let back = try XCTUnwrap(e.decoded(Note.self))
        XCTAssertEqual(back, note)
    }

    func testAnEventKeepsItsMediaThroughTheRoundTrip() throws {
        let media = [EventMedia(id: "m-1", kind: .image, r2Key: "evt/abc"),
                     EventMedia(id: "m-2", kind: .video, r2Key: "evt/def", posterKey: "evt/def-p")]
        let event = EventItem(id: "e-1", date: "2026-08-10", title: "Kodaikanal",
                              tagIDs: ["travel"], note: "the drive up", media: media)
        let e = TrashEntry(itemID: event.id, kind: .event, title: event.title,
                           deletedAt: "\(today)T09:00:00",
                           payload: TrashEntry.encode(event),
                           mediaKeys: ["evt/abc", "evt/def", "evt/def-p"])
        let back = try XCTUnwrap(e.decoded(EventItem.self))
        XCTAssertEqual(back.media.map(\.r2Key), ["evt/abc", "evt/def"])
        XCTAssertEqual(back.title, "Kodaikanal")
        // The keys the entry is holding alive must cover every object the event
        // referenced, or a restore comes back with grey placeholders.
        for key in back.media.flatMap({ [$0.r2Key, $0.posterKey] }).compactMap({ $0 }) {
            XCTAssertTrue(e.mediaKeys.contains(key), "\(key) would have been purged early")
        }
    }

    /// A payload that no longer decodes must not be silently thrown away.
    func testAnUndecodablePayloadReturnsNilRatherThanCrashing() {
        var e = entry(deletedOn: today)
        e.payload = "{ this is not json"
        XCTAssertNil(e.decoded(Note.self))
    }

    // MARK: - Shape

    func testEntriesDecodeFromAnOlderShape() throws {
        let json = Data(#"{"itemID":"x","kind":"note","title":"T","deletedAt":"2026-08-30T09:00:00","payload":"{}"}"#.utf8)
        let e = try JSONDecoder().decode(TrashEntry.self, from: json)
        XCTAssertEqual(e.itemID, "x")
        XCTAssertEqual(e.kind, .note)
        XCTAssertTrue(e.mediaKeys.isEmpty)
        XCTAssertNil(e.context)
        XCTAssertFalse(e.id.isEmpty, "an entry with no id of its own must still get one")
    }

    func testUntitledThingsStillHaveSomethingToPointAt() {
        var e = entry(deletedOn: today)
        e.title = "   "
        XCTAssertEqual(e.displayTitle, "Untitled note")
    }

    /// Raw values are a wire format — a rename strands everything already deleted.
    func testKindRawValuesArePinned() {
        XCTAssertEqual(Set(TrashKind.allCases.map(\.rawValue)),
                       ["note", "event", "belonging", "watch", "todo", "scan",
                        "chatThread", "progressPhoto",
                        "food", "exercise", "program"])
    }

    func testEveryKindSortsSomewhereDistinct() {
        XCTAssertEqual(Set(TrashKind.allCases.map(\.rank)).count, TrashKind.allCases.count)
    }
}
