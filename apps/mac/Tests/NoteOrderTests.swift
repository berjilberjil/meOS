import XCTest
@testable import meOS

/// Two rules stand between the notes list and the "notes come and go randomly
/// on click" bug: a save that changes nothing must write nothing, and the list
/// must hold still while you are typing into it.
final class NoteOrderTests: XCTestCase {

    private func note(_ id: String, title: String = "", body: String = "",
                      updated: String, pinned: Bool = false) -> Note {
        Note(id: id, createdAt: "2026-08-01T09:00:00Z", updatedAt: updated,
             title: title, body: body, pinned: pinned,
             content: BlockDoc.from(plainText: body))
    }

    // MARK: Saving a note that did not change

    /// The exact case that reordered the list: opening a note persists whatever
    /// was open, unchanged.
    func testUnchangedSaveIsANoOp() {
        let n = note("a", title: "Ideas", body: "one\ntwo", updated: "2026-08-20T10:00:00Z")
        XCTAssertFalse(n.wouldChange(title: "Ideas", doc: n.effectiveDoc))
    }

    func testChangedTitleOrBodyDoesWrite() {
        let n = note("a", title: "Ideas", body: "one", updated: "2026-08-20T10:00:00Z")
        XCTAssertTrue(n.wouldChange(title: "Ideas!", doc: n.effectiveDoc))
        XCTAssertTrue(n.wouldChange(title: "Ideas", doc: BlockDoc.from(plainText: "one\ntwo")))
    }

    /// A note written before rich content existed has `content == nil`. Opening
    /// it hands the editor `effectiveDoc`, and handing that straight back is not
    /// an edit — comparing against `content` would rewrite every legacy note the
    /// first time it was so much as opened.
    func testLegacyPlainTextNoteThatRoundTripsIsNotAChange() {
        var n = note("a", title: "Old", body: "hello", updated: "2026-08-20T10:00:00Z")
        n.content = nil
        XCTAssertFalse(n.wouldChange(title: "Old", doc: n.effectiveDoc))
    }

    // MARK: Display order

    func testUnfrozenOrderIsMostRecentFirstWithPinnedOnTop() {
        let notes = [
            note("old", updated: "2026-08-01T10:00:00Z"),
            note("new", updated: "2026-08-25T10:00:00Z"),
            note("pin", updated: "2026-07-01T10:00:00Z", pinned: true),
        ]
        XCTAssertEqual(orderedNotes(notes, frozen: nil).map(\.id), ["pin", "new", "old"])
    }

    /// The list must not move while you type into the note beside it.
    func testFrozenOrderSurvivesAnUpdatedAtBump() {
        let frozen = ["a", "b", "c"]
        var notes = [
            note("a", updated: "2026-08-25T10:00:00Z"),
            note("b", updated: "2026-08-24T10:00:00Z"),
            note("c", updated: "2026-08-23T10:00:00Z"),
        ]
        // "c" is the one being edited; every keystroke bumps it to newest.
        notes[2].updatedAt = "2026-08-25T23:59:00Z"
        XCTAssertEqual(orderedNotes(notes, frozen: frozen).map(\.id), ["a", "b", "c"])
    }

    /// A note created or synced in after the snapshot joins the list; it does
    /// not reshuffle it.
    func testNotesMissingFromTheSnapshotSortAfterIt() {
        let frozen = ["a", "b"]
        let notes = [
            note("a", updated: "2026-08-20T10:00:00Z"),
            note("b", updated: "2026-08-21T10:00:00Z"),
            note("fresh", updated: "2026-08-25T23:00:00Z"),
        ]
        XCTAssertEqual(orderedNotes(notes, frozen: frozen).map(\.id), ["a", "b", "fresh"])
    }

    /// Pinning is a deliberate act whose whole point is to move the note, so it
    /// still wins over a frozen order.
    func testPinningStillMovesANoteWhileFrozen() {
        let frozen = ["a", "b", "c"]
        var notes = [
            note("a", updated: "2026-08-25T10:00:00Z"),
            note("b", updated: "2026-08-24T10:00:00Z"),
            note("c", updated: "2026-08-23T10:00:00Z"),
        ]
        notes[2].pinned = true
        XCTAssertEqual(orderedNotes(notes, frozen: frozen).map(\.id), ["c", "a", "b"])
    }
}
