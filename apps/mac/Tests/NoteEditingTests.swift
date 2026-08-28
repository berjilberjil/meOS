import XCTest
@testable import MyOS

/// The rules the phone's note editor follows when you press Return, tick a box,
/// or change a line's type.
///
/// These are Apple Notes' rules, and they are the difference between a checklist
/// and a list of lines that happen to have circles next to them. Every one of
/// them is here rather than in the view because "Return made another checkbox"
/// is not something a screenshot can tell you.
final class NoteEditingTests: XCTestCase {

    private func doc(_ blocks: [Block]) -> [Block] { blocks }

    private func para(_ t: String) -> Block { Block.paragraph(t) }
    private func item(_ type: BlockType, _ t: String, checked: Bool? = nil) -> Block {
        Block(type: type, spans: t.isEmpty ? [] : [TextSpan(text: t)], checked: checked)
    }
    private func text(_ b: Block) -> String { b.spans.map(\.text).joined() }

    // MARK: - Return

    func testReturnSplitsAParagraphAndTakesTheTailWithIt() {
        let blocks = doc([para("hello world")])
        let r = NoteEditing.split(blocks, at: blocks[0].id, head: "hello", tail: " world")
        XCTAssertEqual(r.blocks.count, 2)
        XCTAssertEqual(text(r.blocks[0]), "hello")
        XCTAssertEqual(text(r.blocks[1]), " world")
        XCTAssertEqual(r.focus, r.blocks[1].id, "the caret follows the text it was in front of")
    }

    func testReturnAtTheEndOfABulletMakesAnotherBullet() {
        let blocks = doc([item(.bullet, "milk")])
        let r = NoteEditing.split(blocks, at: blocks[0].id, head: "milk", tail: "")
        XCTAssertEqual(r.blocks.count, 2)
        XCTAssertEqual(r.blocks[1].type, .bullet)
        XCTAssertEqual(text(r.blocks[1]), "")
    }

    func testReturnOnAChecklistMakesAnotherCheckboxAndNeverInheritsTheTick() {
        let blocks = doc([item(.todo, "call mum", checked: true)])
        let r = NoteEditing.split(blocks, at: blocks[0].id, head: "call mum", tail: "")
        XCTAssertEqual(r.blocks[1].type, .todo)
        XCTAssertEqual(r.blocks[1].checked, false, "a fresh item is not already done")
        XCTAssertEqual(r.blocks[0].checked, true, "and the one above keeps its tick")
    }

    /// The rule that ends a list. Without it the only way out of a checklist is
    /// to reach for a menu, which is why lists in bad editors never end.
    func testReturnOnAnEmptyListItemEndsTheList() {
        let blocks = doc([item(.bullet, "milk"), item(.bullet, "")])
        let r = NoteEditing.split(blocks, at: blocks[1].id, head: "", tail: "")
        XCTAssertEqual(r.blocks.count, 2, "no new line — the empty one is reused")
        XCTAssertEqual(r.blocks[1].type, .paragraph)
        XCTAssertEqual(r.focus, r.blocks[1].id)
    }

    func testReturnAfterAHeadingGivesYouBodyText() {
        let blocks = doc([Block(type: .heading, spans: [TextSpan(text: "Groceries")], level: 1)])
        let r = NoteEditing.split(blocks, at: blocks[0].id, head: "Groceries", tail: "")
        XCTAssertEqual(r.blocks[1].type, .paragraph, "nobody wants a second title")
        XCTAssertNil(r.blocks[1].level)
    }

    func testReturnAtTheStartOfALineOpensAnEmptyOneAboveIt() {
        let blocks = doc([item(.bullet, "milk")])
        let r = NoteEditing.split(blocks, at: blocks[0].id, head: "", tail: "milk")
        XCTAssertEqual(r.blocks.count, 2)
        XCTAssertEqual(text(r.blocks[0]), "")
        XCTAssertEqual(text(r.blocks[1]), "milk")
        XCTAssertEqual(r.focus, r.blocks[1].id, "the caret stays with the words")
    }

    /// Pasting five lines in should give five lines, not one line with four
    /// newlines hiding inside it that the Mac would then render as one run-on
    /// paragraph.
    func testPastingSeveralLinesBecomesSeveralLines() {
        let blocks = doc([para("")])
        let r = NoteEditing.split(blocks, at: blocks[0].id, head: "one", tail: "two\nthree")
        XCTAssertEqual(r.blocks.count, 3)
        XCTAssertEqual(text(r.blocks[0]), "one")
        XCTAssertEqual(text(r.blocks[1]), "two")
        XCTAssertEqual(text(r.blocks[2]), "three")
        XCTAssertEqual(r.focus, r.blocks[2].id, "the caret ends up at the end of what you pasted")
    }

    func testPastingIntoAChecklistMakesEveryLineAnItem() {
        let blocks = doc([item(.todo, "", checked: false)])
        let r = NoteEditing.split(blocks, at: blocks[0].id, head: "", tail: "milk\neggs")
        XCTAssertEqual(r.blocks.count, 3)
        XCTAssertTrue(r.blocks.allSatisfy { $0.type == .todo })
        XCTAssertTrue(r.blocks.allSatisfy { $0.checked == false })
    }

    func testSplittingSomethingThatIsNotThereChangesNothing() {
        let blocks = doc([para("a")])
        let r = NoteEditing.split(blocks, at: "nope", head: "x", tail: "y")
        XCTAssertEqual(r.blocks, blocks)
        XCTAssertNil(r.focus)
    }

    // MARK: - Typing

    /// Bold made on the Mac has to survive typing on the phone. The old editor
    /// round-tripped everything through plain text, which is exactly how it got
    /// lost.
    func testTypingKeepsTheFormattingTheLineAlreadyHad() {
        let bold = Block(type: .paragraph, spans: [TextSpan(text: "hi", marks: [.bold])])
        let out = NoteEditing.setText("hi there", in: [bold], id: bold.id)
        XCTAssertEqual(text(out[0]), "hi there")
        XCTAssertEqual(out[0].spans.first?.marks, [.bold])
    }

    func testEmptyingALineLeavesItEmptyRatherThanHoldingABlankSpan() {
        let b = para("hi")
        let out = NoteEditing.setText("", in: [b], id: b.id)
        XCTAssertTrue(out[0].spans.isEmpty)
        XCTAssertEqual(text(out[0]), "")
    }

    // MARK: - Ticking

    func testTickingABoxTicksOnlyThatBox() {
        let blocks = doc([item(.todo, "a", checked: false), item(.todo, "b", checked: false)])
        let out = NoteEditing.toggleChecked(blocks, id: blocks[0].id)
        XCTAssertEqual(out[0].checked, true)
        XCTAssertEqual(out[1].checked, false)
    }

    func testTickingSomethingThatIsNotACheckboxDoesNothing() {
        let blocks = doc([para("a")])
        XCTAssertEqual(NoteEditing.toggleChecked(blocks, id: blocks[0].id), blocks)
    }

    // MARK: - Changing a line's type

    func testTurningALineIntoAChecklistGivesItAnUntickedBox() {
        let blocks = doc([para("call mum")])
        let out = NoteEditing.convert(blocks, id: blocks[0].id, to: .todo)
        XCTAssertEqual(out[0].type, .todo)
        XCTAssertEqual(out[0].checked, false)
        XCTAssertEqual(text(out[0]), "call mum", "changing the shape does not lose the words")
    }

    func testGoingBackToBodyTextDropsTheBoxAndTheHeadingLevel() {
        let h = Block(type: .heading, spans: [TextSpan(text: "T")], level: 2)
        let out = NoteEditing.convert([h], id: h.id, to: .paragraph)
        XCTAssertEqual(out[0].type, .paragraph)
        XCTAssertNil(out[0].level)
        XCTAssertNil(out[0].checked)
    }

    func testAHeadingRemembersWhichSizeItIs() {
        let blocks = doc([para("Title")])
        let out = NoteEditing.convert(blocks, id: blocks[0].id, to: .heading, level: 1)
        XCTAssertEqual(out[0].level, 1)
    }

    // MARK: - Numbering

    func testNumberedListsCountFromOne() {
        let blocks = doc([item(.numbered, "a"), item(.numbered, "b"), item(.numbered, "c")])
        let n = NoteEditing.ordinals(blocks)
        XCTAssertEqual(n[blocks[0].id], 1)
        XCTAssertEqual(n[blocks[1].id], 2)
        XCTAssertEqual(n[blocks[2].id], 3)
    }

    /// Two lists separated by a line of prose are two lists, not one that counts
    /// to five.
    func testASecondListStartsAtOneAgain() {
        let blocks = doc([item(.numbered, "a"), item(.numbered, "b"),
                          para("and then"),
                          item(.numbered, "c")])
        let n = NoteEditing.ordinals(blocks)
        XCTAssertEqual(n[blocks[1].id], 2)
        XCTAssertEqual(n[blocks[3].id], 1)
    }

    // MARK: - Find

    func testFindIsCaseInsensitiveAndReportsEveryLineItIsOn() {
        let blocks = doc([para("Compounding"), para("asset allocation"), para("XIRR")])
        let hits = NoteEditing.matches(blocks, query: "a")
        XCTAssertEqual(hits, [blocks[1].id])
        XCTAssertEqual(NoteEditing.matches(blocks, query: "COMPOUND"), [blocks[0].id])
    }

    func testAnEmptyQueryFindsNothingRatherThanEverything() {
        let blocks = doc([para("a"), para("b")])
        XCTAssertTrue(NoteEditing.matches(blocks, query: "   ").isEmpty)
    }

    // MARK: - Marks

    func testBoldGoesOnAndComesBackOff() {
        let b = para("hi")
        var out = NoteEditing.toggleMark([b], id: b.id, mark: .bold)
        XCTAssertEqual(out[0].spans.first?.marks, [.bold])
        out = NoteEditing.toggleMark(out, id: b.id, mark: .bold)
        XCTAssertEqual(out[0].spans.first?.marks, [])
    }

    func testBoldOnAnEmptyLineIsNotLostBeforeYouTypeIntoIt() {
        let b = Block(type: .paragraph)
        let out = NoteEditing.toggleMark([b], id: b.id, mark: .bold)
        XCTAssertEqual(out[0].spans.first?.marks, [.bold])
        let typed = NoteEditing.setText("now bold", in: out, id: b.id)
        XCTAssertEqual(typed[0].spans.first?.marks, [.bold])
    }

    // MARK: - Never an empty document

    func testAnEmptyDocumentAlwaysHasSomewhereToType() {
        XCTAssertEqual(NoteEditing.normalized([]).count, 1)
        XCTAssertEqual(NoteEditing.normalized([]).first?.type, .paragraph)
    }

    /// A note that is only a photo still needs a line under it, or there is
    /// nowhere to put the caret.
    func testADocumentOfOnlyAttachmentsGainsALineToTypeOn() {
        let image = Block(type: .image, src: "AAAA")
        let out = NoteEditing.normalized([image])
        XCTAssertEqual(out.count, 2)
        XCTAssertEqual(out.last?.type, .paragraph)
    }

    func testInsertingAPhotoPutsItAfterTheLineYouWereOn() {
        let blocks = doc([para("before"), para("after")])
        let image = Block(type: .image, src: "AAAA")
        let out = NoteEditing.insert(image, into: blocks, after: blocks[0].id)
        XCTAssertEqual(out.count, 4, "the photo, plus a line to carry on typing on")
        XCTAssertEqual(out[1].type, .image)
        XCTAssertEqual(out[2].type, .paragraph)
        XCTAssertEqual(text(out[3]), "after")
    }
}
