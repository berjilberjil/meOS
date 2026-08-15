import XCTest
@testable import MyOS

/// Pure-logic tests for what Siri says about events. No network, no vault — the
/// selection + phrasing is deliberately separated from `EventIntentStore` so it
/// can be verified without an unlocked device.
final class EventVoiceTests: XCTestCase {
    private let today = "2026-08-15"

    private func ev(_ date: String, _ title: String) -> EventItem {
        EventItem(date: date, title: title)
    }

    // MARK: - Day math

    func testDayDeltaCountsWholeDays() {
        XCTAssertEqual(EventVoice.dayDelta(from: today, to: "2026-08-19"), 4)
        XCTAssertEqual(EventVoice.dayDelta(from: today, to: today), 0)
        XCTAssertEqual(EventVoice.dayDelta(from: today, to: "2026-08-12"), -3)
    }

    func testDayDeltaCrossesMonthAndYear() {
        XCTAssertEqual(EventVoice.dayDelta(from: "2026-08-30", to: "2026-09-02"), 3)
        XCTAssertEqual(EventVoice.dayDelta(from: "2026-12-30", to: "2027-01-02"), 3)
    }

    func testDayDeltaRejectsGarbage() {
        XCTAssertNil(EventVoice.dayDelta(from: today, to: ""))
        XCTAssertNil(EventVoice.dayDelta(from: today, to: "next friday"))
    }

    // MARK: - Relative phrasing

    func testRelativePhraseNamesNearDays() {
        XCTAssertEqual(EventVoice.relativePhrase(from: today, to: today), "today")
        XCTAssertEqual(EventVoice.relativePhrase(from: today, to: "2026-08-16"), "tomorrow")
        XCTAssertEqual(EventVoice.relativePhrase(from: today, to: "2026-08-14"), "yesterday")
    }

    func testRelativePhraseCountsDistantDays() {
        XCTAssertEqual(EventVoice.relativePhrase(from: today, to: "2026-08-19"), "in 4 days")
        XCTAssertEqual(EventVoice.relativePhrase(from: today, to: "2026-08-12"), "3 days ago")
    }

    func testRelativePhraseFallsBackOnBadDate() {
        XCTAssertEqual(EventVoice.relativePhrase(from: today, to: "oops"), "on an unknown date")
    }

    // MARK: - Selection

    func testUpcomingIncludesTodayAndSortsAscending() {
        let events = [ev("2026-08-20", "C"), ev("2026-08-15", "A"), ev("2026-08-17", "B")]
        XCTAssertEqual(EventVoice.upcoming(events, today: today, limit: 5).map(\.title), ["A", "B", "C"])
    }

    func testUpcomingExcludesPastAndRespectsLimit() {
        let events = [ev("2026-08-01", "old"), ev("2026-08-17", "B"), ev("2026-08-20", "C")]
        XCTAssertEqual(EventVoice.upcoming(events, today: today, limit: 1).map(\.title), ["B"])
    }

    func testPastExcludesTodayAndSortsMostRecentFirst() {
        let events = [ev("2026-08-01", "old"), ev("2026-08-15", "today"), ev("2026-08-14", "recent")]
        XCTAssertEqual(EventVoice.past(events, today: today, limit: 5).map(\.title), ["recent", "old"])
    }

    func testSelectionDropsUndatedEvents() {
        let events = [ev("", "broken"), ev("2026-08-17", "B")]
        XCTAssertEqual(EventVoice.upcoming(events, today: today, limit: 5).map(\.title), ["B"])
        XCTAssertTrue(EventVoice.past(events, today: today, limit: 5).isEmpty)
    }

    func testLimitIsClamped() {
        let events = (1...20).map { ev(EventVoice.key(addingDays: $0, to: today), "E\($0)") }
        XCTAssertEqual(EventVoice.upcoming(events, today: today, limit: 0).count, 1)
        XCTAssertEqual(EventVoice.upcoming(events, today: today, limit: 99).count, 10)
    }

    // MARK: - Spoken sentences

    func testSpokenUpcomingEmpty() {
        XCTAssertEqual(EventVoice.spokenUpcoming([], today: today), "Nothing coming up.")
    }

    func testSpokenUpcomingSingle() {
        let s = EventVoice.spokenUpcoming([ev("2026-08-19", "Goa trip")], today: today)
        XCTAssertEqual(s, "Goa trip in 4 days.")
    }

    func testSpokenUpcomingJoinsWithAnd() {
        let events = [ev("2026-08-19", "Goa trip"), ev("2026-08-26", "Dad's birthday")]
        XCTAssertEqual(EventVoice.spokenUpcoming(events, today: today),
                       "Goa trip in 4 days, and Dad's birthday in 11 days.")
    }

    func testSpokenUpcomingThreeUsesSerialCommas() {
        let events = [ev("2026-08-15", "Standup"), ev("2026-08-16", "Gym"), ev("2026-08-19", "Goa trip")]
        XCTAssertEqual(EventVoice.spokenUpcoming(events, today: today),
                       "Standup today, Gym tomorrow, and Goa trip in 4 days.")
    }

    func testSpokenPastEmptyAndPopulated() {
        XCTAssertEqual(EventVoice.spokenPast([], today: today), "No past events logged.")
        let events = [ev("2026-08-14", "Dentist"), ev("2026-08-12", "Trek")]
        XCTAssertEqual(EventVoice.spokenPast(events, today: today),
                       "Dentist yesterday, and Trek 3 days ago.")
    }

    func testSpokenCreated() {
        XCTAssertEqual(EventVoice.spokenCreated(title: "Goa trip", date: "2026-08-19", today: today),
                       "Added Goa trip in 4 days.")
        XCTAssertEqual(EventVoice.spokenCreated(title: "Standup", date: today, today: today),
                       "Added Standup today.")
    }

    // MARK: - Title cleanup (Siri hands over loose dictation)

    func testTitleIsTrimmedAndTrailingPunctuationDropped() {
        XCTAssertEqual(EventVoice.cleanTitle("  Goa trip.  "), "Goa trip")
        XCTAssertEqual(EventVoice.cleanTitle("Dad's birthday!"), "Dad's birthday")
        XCTAssertEqual(EventVoice.cleanTitle("   "), "")
    }
}
