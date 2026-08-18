import XCTest
@testable import MyOS

final class InteractionTests: XCTestCase {
    func testDragClampsProgressBetweenZeroAndOne() {
        var s = SlideConfirmState()
        s.drag(translationX: -20, width: 100)
        XCTAssertEqual(s.progress, 0, accuracy: 0.001)
        s.drag(translationX: 50, width: 100)
        XCTAssertEqual(s.progress, 0.5, accuracy: 0.001)
        s.drag(translationX: 300, width: 100)
        XCTAssertEqual(s.progress, 1, accuracy: 0.001)
    }

    func testEndBelowThresholdDoesNotFireAndResets() {
        var s = SlideConfirmState(threshold: 0.85)
        s.drag(translationX: 50, width: 100) // 0.5 < 0.85
        XCTAssertFalse(s.end())
        XCTAssertEqual(s.progress, 0, accuracy: 0.001)
        XCTAssertFalse(s.confirmed)
    }

    func testEndAtThresholdFiresExactlyOnce() {
        var s = SlideConfirmState(threshold: 0.85)
        s.drag(translationX: 90, width: 100) // 0.9 >= 0.85
        XCTAssertTrue(s.end())      // fires
        XCTAssertTrue(s.confirmed)
        XCTAssertEqual(s.progress, 1, accuracy: 0.001)
        XCTAssertFalse(s.end())     // does not fire again
    }

    func testResetClearsConfirmedState() {
        var s = SlideConfirmState(threshold: 0.85)
        s.drag(translationX: 90, width: 100)
        _ = s.end()
        s.reset()
        XCTAssertFalse(s.confirmed)
        XCTAssertEqual(s.progress, 0, accuracy: 0.001)
    }

    func testDragReportsNewlyCrossedTicks() {
        var s = SlideConfirmState()
        XCTAssertEqual(s.drag(translationX: 10, width: 100), 0)   // 0.10 — none
        XCTAssertEqual(s.drag(translationX: 40, width: 100), 2)   // 0.40 — 0.18 + 0.36
        XCTAssertEqual(s.drag(translationX: 40, width: 100), 0)   // same stop — no new
        XCTAssertEqual(s.drag(translationX: 90, width: 100), 3)   // 0.54, 0.72, 0.88
    }

    func testDragBackwardsDoesNotRetick() {
        var s = SlideConfirmState()
        _ = s.drag(translationX: 80, width: 100)
        XCTAssertEqual(s.drag(translationX: 20, width: 100), 0)
    }

    // MARK: - Mood slider stop mapping

    func testMoodStopMapsPositionToOneThroughFive() {
        XCTAssertEqual(moodStop(atX: 0, width: 100), 1)
        XCTAssertEqual(moodStop(atX: 20, width: 100), 2)
        XCTAssertEqual(moodStop(atX: 50, width: 100), 3)
        XCTAssertEqual(moodStop(atX: 99, width: 100), 5)
        XCTAssertEqual(moodStop(atX: 100, width: 100), 5)   // clamped
        XCTAssertEqual(moodStop(atX: -10, width: 100), 1)   // clamped
        XCTAssertEqual(moodStop(atX: 10, width: 0), 1)      // zero width guard
    }
}
