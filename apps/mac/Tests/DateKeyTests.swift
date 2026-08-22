import XCTest
@testable import MyOS

/// `dateKey` / `addDays` / `date(fromKey:)` stopped building a `DateFormatter`
/// per call and now parse `yyyy-MM-dd` by hand — these run in view bodies and
/// the formatters were being allocated in their thousands mid-swipe. Hand-rolled
/// date maths is exactly the kind that fails silently at a boundary, so the
/// boundaries are pinned here.
@MainActor
final class DateKeyTests: XCTestCase {

    // MARK: Round-trip

    func testKeyRoundTripsThroughDate() {
        for key in ["2026-08-22", "2024-02-29", "1999-12-31", "2000-01-01"] {
            guard let d = AppState.date(fromKey: key) else { return XCTFail("no date for \(key)") }
            XCTAssertEqual(AppState.dateKey(d), key)
        }
    }

    func testMonthAndDayAreZeroPadded() {
        guard let d = AppState.date(fromKey: "2026-01-05") else { return XCTFail("no date") }
        XCTAssertEqual(AppState.dateKey(d), "2026-01-05")
    }

    // MARK: Stepping

    func testStepsWithinAMonth() {
        XCTAssertEqual(AppState.addDays(1, to: "2026-08-22"), "2026-08-23")
        XCTAssertEqual(AppState.addDays(-1, to: "2026-08-22"), "2026-08-21")
        XCTAssertEqual(AppState.addDays(0, to: "2026-08-22"), "2026-08-22")
    }

    func testCrossesMonthAndYearBoundaries() {
        XCTAssertEqual(AppState.addDays(1, to: "2026-08-31"), "2026-09-01")
        XCTAssertEqual(AppState.addDays(-1, to: "2026-09-01"), "2026-08-31")
        XCTAssertEqual(AppState.addDays(1, to: "2026-12-31"), "2027-01-01")
        XCTAssertEqual(AppState.addDays(-1, to: "2026-01-01"), "2025-12-31")
    }

    func testHandlesLeapAndCommonFebruary() {
        XCTAssertEqual(AppState.addDays(1, to: "2024-02-28"), "2024-02-29", "2024 is a leap year")
        XCTAssertEqual(AppState.addDays(1, to: "2024-02-29"), "2024-03-01")
        XCTAssertEqual(AppState.addDays(1, to: "2026-02-28"), "2026-03-01", "2026 is not")
        XCTAssertEqual(AppState.addDays(-1, to: "2100-03-01"), "2100-02-28", "2100 is not a leap year")
    }

    /// The Today pager builds a 128-day window in one go, so a long run has to
    /// land on the same place a day-at-a-time walk does.
    func testLongStepMatchesRepeatedSingleSteps() {
        var walked = "2026-08-22"
        for _ in 0..<128 { walked = AppState.addDays(-1, to: walked) }
        XCTAssertEqual(AppState.addDays(-128, to: "2026-08-22"), walked)
    }

    // MARK: Bad input

    func testMalformedKeysAreReturnedUnchanged() {
        for junk in ["", "not-a-date", "2026-13-01", "2026-00-10", "2026-01-32", "26-01-01", "2026-01"] {
            XCTAssertEqual(AppState.addDays(1, to: junk), junk, "\(junk) should pass through")
            XCTAssertNil(AppState.date(fromKey: junk), "\(junk) should not parse")
        }
    }
}
