import XCTest
@testable import MyOS

final class ChatActionTests: XCTestCase {
    func testStripsActionsFromSpokenReply() {
        let raw = """
        Done — I locked it.
        ACTION lock_note title="Passwords"
        """
        let parsed = ChatAction.parse(raw)
        XCTAssertEqual(parsed.visible, "Done — I locked it.")
        XCTAssertEqual(parsed.actions.count, 1)
        XCTAssertEqual(parsed.actions[0].kind, .lockNote)
        XCTAssertEqual(parsed.actions[0].fields["title"], "Passwords")
    }

    func testParsesCreateEventAndShoot() {
        let raw = """
        Booked it.
        ACTION create_event title="Ma dinner" date="2026-08-20"
        ACTION create_shoot title="Body check"
        """
        let parsed = ChatAction.parse(raw)
        XCTAssertEqual(parsed.actions.map(\.kind), [.createEvent, .createShoot])
        XCTAssertEqual(parsed.actions[0].fields["date"], "2026-08-20")
    }

    func testNoActionLineLeavesTextAlone() {
        let parsed = ChatAction.parse("Just drink water.")
        XCTAssertEqual(parsed.visible, "Just drink water.")
        XCTAssertTrue(parsed.actions.isEmpty)
    }
}
