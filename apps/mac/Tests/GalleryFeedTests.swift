import XCTest
@testable import meOS

/// The gallery is a join across four stores that agree on nothing — different
/// date fields, different storage, different ideas of what a title is. These
/// pin the join.
final class GalleryFeedTests: XCTestCase {

    private func event(_ id: String, date: String, title: String,
                       media: [EventMedia]) -> EventItem {
        EventItem(id: id, date: date, title: title, media: media)
    }

    private func scan(_ id: String, date: String, summary: String, key: String?) -> ScanRecord {
        ScanRecord(id: id, at: "\(date)T12:00:00", date: date, kind: "food",
                   summary: summary, photoKey: key)
    }

    private func note(_ id: String, updated: String, title: String,
                      images: [String], locked: Bool = false) -> Note {
        var doc = BlockDoc(blocks: images.map { Block(type: .image, src: $0) })
        if images.isEmpty { doc = BlockDoc() }
        return Note(id: id, createdAt: updated, updatedAt: updated, title: title,
                    body: "", pinned: false, locked: locked, content: doc)
    }

    // MARK: Gathering

    func testEveryStoreContributes() {
        let items = GalleryFeed.items(
            events: [event("e1", date: "2026-08-20", title: "Goa",
                           media: [EventMedia(id: "m1", kind: .image, r2Key: "k1")])],
            scans: [scan("s1", date: "2026-08-21", summary: "Dosa", key: "k2")],
            notes: [note("n1", updated: "2026-08-22T09:00:00Z", title: "Ideas", images: ["AAAA"])],
            progress: [ProgressPhoto(id: "2026-08-23", date: "2026-08-23",
                                     url: URL(fileURLWithPath: "/tmp/2026-08-23.jpg"))])

        XCTAssertEqual(items.map(\.source), [.progress, .notes, .scans, .events],
                       "newest day first, whichever store it came from")
        XCTAssertEqual(items.map(\.day), ["2026-08-23", "2026-08-22", "2026-08-21", "2026-08-20"])
    }

    /// An event photo belongs to the event's date, not to whenever the file was
    /// written — that is the whole reason the gallery reads a date per source.
    func testEventMediaTakesTheEventsDate() {
        let items = GalleryFeed.items(
            events: [event("e1", date: "2019-12-25", title: "Christmas",
                           media: [EventMedia(id: "m1", kind: .image, r2Key: "k")])],
            scans: [], notes: [], progress: [])
        XCTAssertEqual(items.first?.day, "2019-12-25")
        XCTAssertEqual(items.first?.title, "Christmas")
    }

    func testVideosKeepTheirPosterKey() {
        let items = GalleryFeed.items(
            events: [event("e1", date: "2026-08-20", title: "Trip",
                           media: [EventMedia(id: "m1", kind: .video, r2Key: "vid", posterKey: "post")])],
            scans: [], notes: [], progress: [])
        XCTAssertEqual(items.first?.kind, .video)
        XCTAssertEqual(items.first?.location, .sealed(key: "vid", posterKey: "post"))
    }

    /// Legacy event media has inline base64 and no R2 key. Both shapes must
    /// reach the grid.
    func testLegacyInlineMediaStillAppears() {
        let items = GalleryFeed.items(
            events: [event("e1", date: "2026-08-20", title: "Old",
                           media: [EventMedia(id: "m1", kind: .image, data: "BBBB")])],
            scans: [], notes: [], progress: [])
        XCTAssertEqual(items.first?.location, .inline(base64: "BBBB", poster: nil))
    }

    /// A scan without a photo is a text record. It is not a picture and must not
    /// occupy a square.
    func testScansWithoutAPhotoAreSkipped() {
        let items = GalleryFeed.items(events: [], scans: [scan("s1", date: "2026-08-21",
                                                               summary: "no photo", key: nil)],
                                      notes: [], progress: [])
        XCTAssertTrue(items.isEmpty)
    }

    /// Locking a note is a decision about its contents. The gallery is a
    /// convenience, not a way around it.
    func testLockedNotesKeepTheirPicturesHidden() {
        let items = GalleryFeed.items(
            events: [], scans: [],
            notes: [note("n1", updated: "2026-08-22T09:00:00Z", title: "Private",
                         images: ["SECRET"], locked: true)],
            progress: [])
        XCTAssertTrue(items.isEmpty)
    }

    // MARK: Sections

    func testMonthsGroupNewestFirstAndKeepInnerOrder() {
        let items = GalleryFeed.items(
            events: [event("e1", date: "2026-08-20", title: "A",
                           media: [EventMedia(id: "m1", kind: .image, r2Key: "k1")]),
                     event("e2", date: "2026-07-04", title: "B",
                           media: [EventMedia(id: "m2", kind: .image, r2Key: "k2")]),
                     event("e3", date: "2026-08-02", title: "C",
                           media: [EventMedia(id: "m3", kind: .image, r2Key: "k3")])],
            scans: [], notes: [], progress: [])

        let months = GalleryFeed.months(items)
        XCTAssertEqual(months.map(\.month), ["2026-08", "2026-07"])
        XCTAssertEqual(months[0].items.map(\.title), ["A", "C"])
        XCTAssertEqual(months[1].items.count, 1)
    }

    func testMonthLabelReadsAsAMonth() {
        XCTAssertEqual(GalleryFeed.monthLabel("2026-08"), "August 2026")
        XCTAssertEqual(GalleryFeed.monthLabel("2026-01"), "January 2026")
        // Garbage in, the key back out — never a crash and never a wrong month.
        XCTAssertEqual(GalleryFeed.monthLabel("nonsense"), "nonsense")
        XCTAssertEqual(GalleryFeed.monthLabel("2026-13"), "2026-13")
    }

    /// A grid that reshuffles when a sync poll lands is a grid you cannot click.
    func testOrderIsStableForTheSameInput() {
        let events = [event("e1", date: "2026-08-20", title: "A",
                            media: [EventMedia(id: "m1", kind: .image, r2Key: "k1"),
                                    EventMedia(id: "m2", kind: .image, r2Key: "k2")])]
        let first = GalleryFeed.items(events: events, scans: [], notes: [], progress: [])
        let again = GalleryFeed.items(events: events, scans: [], notes: [], progress: [])
        XCTAssertEqual(first.map(\.id), again.map(\.id))
    }
}
