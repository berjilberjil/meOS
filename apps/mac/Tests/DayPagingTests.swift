import XCTest
@testable import meOS

/// The Today page pages by day on swipe. The gesture itself needs hands on a
/// device, but the date arithmetic and clamping are pure and testable.
@MainActor
final class DayPagingTests: XCTestCase {
    private let today = "2026-08-21"

    func testStepsBackwardWithoutLimit() {
        XCTAssertEqual(DayPaging.step(today, by: -1, today: today), "2026-08-20")
        XCTAssertEqual(DayPaging.step("2026-01-01", by: -1, today: today), "2025-12-31",
                       "must cross a year boundary")
    }

    func testStepsForwardUpToTheLimit() {
        var d = today
        for _ in 0..<DayPaging.maxForwardDays { d = DayPaging.step(d, by: 1, today: today) }
        XCTAssertEqual(d, "2026-08-28", "seven days ahead is allowed")
    }

    /// Without the clamp you could swipe into empty future forever.
    func testForwardIsClampedAndDoesNotDrift() {
        var d = today
        for _ in 0..<40 { d = DayPaging.step(d, by: 1, today: today) }
        XCTAssertEqual(d, "2026-08-28", "further swipes must be a no-op, not creep forward")
    }

    func testClampDoesNotBlockComingBack() {
        var d = today
        for _ in 0..<20 { d = DayPaging.step(d, by: 1, today: today) }
        d = DayPaging.step(d, by: -1, today: today)
        XCTAssertEqual(d, "2026-08-27", "you can always page back out of the clamp")
    }

    func testLabelsNearbyDaysInWords() {
        XCTAssertEqual(DayPaging.label(today, today: today), "Today")
        XCTAssertEqual(DayPaging.label("2026-08-20", today: today), "Yesterday")
        XCTAssertEqual(DayPaging.label("2026-08-22", today: today), "Tomorrow")
    }

    func testLabelsDistantDaysAsADate() {
        let label = DayPaging.label("2026-08-10", today: today)
        XCTAssertNotEqual(label, "Today")
        XCTAssertTrue(label.contains("Aug"), "expected a readable date, got \(label)")
    }
}
