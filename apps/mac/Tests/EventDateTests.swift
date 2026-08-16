import XCTest
@testable import MyOS

final class EventDateTests: XCTestCase {
    private let sunday = "2026-08-16"   // Sunday

    func testNextWednesdayFromSunday() {
        XCTAssertEqual(EventDate.parseRelative("go to marathon on next Wednesday", today: sunday),
                       "2026-08-19")
    }

    func testNextWednesdayWhenTodayIsWednesdayIsNextWeek() {
        XCTAssertEqual(EventDate.parseRelative("next Wednesday", today: "2026-08-19"),
                       "2026-08-26")
    }

    func testThisWednesdayOnWednesdayStaysToday() {
        XCTAssertEqual(EventDate.parseRelative("this Wednesday", today: "2026-08-19"),
                       "2026-08-19")
    }

    func testTomorrowTodayYesterday() {
        XCTAssertEqual(EventDate.parseRelative("tomorrow", today: sunday), "2026-08-17")
        XCTAssertEqual(EventDate.parseRelative("today", today: sunday), sunday)
        XCTAssertEqual(EventDate.parseRelative("yesterday", today: sunday), "2026-08-15")
    }

    func testInNDays() {
        XCTAssertEqual(EventDate.parseRelative("in 3 days", today: sunday), "2026-08-19")
    }

    func testSpokenPhraseBeatsStaleISOYear() {
        // Catherine invented 30 Oct 2024. User said next Wednesday.
        XCTAssertEqual(
            EventDate.resolve(raw: "2024-10-30",
                              phrase: "Create a new event as go to marathon on next Wednesday",
                              today: sunday),
            "2026-08-19")
    }

    func testFutureISOIsKeptWhenNoPhrase() {
        XCTAssertEqual(EventDate.resolve(raw: "2026-10-30", phrase: "lock it in", today: sunday),
                       "2026-10-30")
    }

    func testPastISOWithoutPhraseRollsToThisYear() {
        XCTAssertEqual(EventDate.resolve(raw: "2024-10-30", phrase: "add the marathon", today: sunday),
                       "2026-10-30")
    }

    func testMissingDateFallsBackToToday() {
        XCTAssertEqual(EventDate.resolve(raw: nil, phrase: "make an event", today: sunday), sunday)
    }

    func testDayPlanReadsLegacyFocusStringsAsTodos() throws {
        let json = """
        {"focus":["Buy bananas","Call Ma"],"habits":{}}
        """.data(using: .utf8)!
        let plan = try JSONDecoder().decode(DayPlan.self, from: json)
        XCTAssertEqual(plan.todos.map(\.text), ["Buy bananas", "Call Ma"])
        XCTAssertFalse(plan.todos[0].done)
    }
}
