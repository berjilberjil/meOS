import XCTest
@testable import MyOS

/// Recurrence is arithmetic that looks right until the one month it does not.
/// February and the 31st are where every naive implementation goes wrong, so
/// they get most of the tests.
final class EventRecurrenceTests: XCTestCase {

    private func event(_ date: String,
                       _ unit: Recurrence.Unit = .none,
                       every n: Int = 1,
                       until: String? = nil,
                       reminders: [ReminderLead] = [],
                       time: String? = nil) -> EventItem {
        EventItem(id: "e", date: date, title: "T", time: time,
                  recurrence: Recurrence(unit: unit, interval: n, until: until),
                  reminders: reminders)
    }

    // MARK: - No rule at all

    func testAOneOffIsItselfUntilItPasses() {
        let e = event("2026-09-10")
        XCTAssertEqual(EventRecurrence.next(e, onOrAfter: "2026-08-30"), "2026-09-10")
        XCTAssertEqual(EventRecurrence.next(e, onOrAfter: "2026-09-10"), "2026-09-10")
        XCTAssertNil(EventRecurrence.next(e, onOrAfter: "2026-09-11"))
    }

    // MARK: - Yearly

    func testABirthdayRollsToNextYearOnceItHasPassed() {
        let e = event("1965-03-12", .yearly)
        XCTAssertEqual(EventRecurrence.next(e, onOrAfter: "2026-08-30"), "2027-03-12")
        XCTAssertEqual(EventRecurrence.next(e, onOrAfter: "2026-03-12"), "2026-03-12")
        XCTAssertEqual(EventRecurrence.next(e, onOrAfter: "2026-03-13"), "2027-03-12")
    }

    /// The one everybody gets wrong.
    func testFebruaryTwentyNinthFallsBackToTheTwentyEighthInCommonYears() {
        let e = event("2024-02-29", .yearly)
        XCTAssertEqual(EventRecurrence.next(e, onOrAfter: "2025-01-01"), "2025-02-28")
        XCTAssertEqual(EventRecurrence.next(e, onOrAfter: "2026-01-01"), "2026-02-28")
        XCTAssertEqual(EventRecurrence.next(e, onOrAfter: "2027-01-01"), "2027-02-28")
    }

    /// And the reason it has to clamp from the anchor, not from the last result:
    /// the 29th must come back when the leap year does.
    func testFebruaryTwentyNinthReturnsOnTheNextLeapYear() {
        let e = event("2024-02-29", .yearly)
        XCTAssertEqual(EventRecurrence.next(e, onOrAfter: "2028-01-01"), "2028-02-29")
    }

    func testEveryNYears() {
        let e = event("2020-06-01", .yearly, every: 3)
        XCTAssertEqual(EventRecurrence.next(e, onOrAfter: "2026-08-30"), "2029-06-01")
        XCTAssertEqual(EventRecurrence.next(e, onOrAfter: "2023-06-01"), "2023-06-01")
        XCTAssertEqual(EventRecurrence.next(e, onOrAfter: "2023-06-02"), "2026-06-01")
    }

    // MARK: - Monthly

    func testMonthlyOnTheThirtyFirstClampsToShortMonthsWithoutDriftingDown() {
        let e = event("2026-01-31", .monthly)
        XCTAssertEqual(EventRecurrence.next(e, onOrAfter: "2026-02-01"), "2026-02-28")
        // The clamp must not stick — March still gets the 31st.
        XCTAssertEqual(EventRecurrence.next(e, onOrAfter: "2026-03-01"), "2026-03-31")
        XCTAssertEqual(EventRecurrence.next(e, onOrAfter: "2026-04-01"), "2026-04-30")
        XCTAssertEqual(EventRecurrence.next(e, onOrAfter: "2026-05-01"), "2026-05-31")
    }

    /// A day that does not exist is not a day to search from.
    ///
    /// 2026 is not a leap year, so "on or after 2026-02-29" is a question with
    /// no answer rather than one worth guessing at. In practice the probe is
    /// always `todayKey`, which is always real — this pins the safe answer for
    /// the case where it is not.
    func testAProbeDateThatIsNotARealDayHasNoNextOccurrence() {
        let e = event("2026-01-31", .monthly)
        XCTAssertNil(EventRecurrence.next(e, onOrAfter: "2026-02-29"))
        XCTAssertNil(EventRecurrence.next(e, onOrAfter: "2026-13-01"))
    }

    /// The last day of a short month is still reachable, and the next one after
    /// it is the anchor day again.
    func testTheClampedDayIsItselfAValidTarget() {
        let e = event("2026-01-31", .monthly)
        XCTAssertEqual(EventRecurrence.next(e, onOrAfter: "2026-02-28"), "2026-02-28")
        XCTAssertEqual(EventRecurrence.next(e, after: "2026-02-28"), "2026-03-31")
    }

    func testEveryNMonths() {
        let e = event("2026-01-15", .monthly, every: 2)
        XCTAssertEqual(EventRecurrence.next(e, onOrAfter: "2026-01-16"), "2026-03-15")
        XCTAssertEqual(EventRecurrence.next(e, onOrAfter: "2026-04-01"), "2026-05-15")
    }

    // MARK: - Daily and weekly

    func testDailyLandsOnTheAskedDay() {
        let e = event("2026-08-01", .daily)
        XCTAssertEqual(EventRecurrence.next(e, onOrAfter: "2026-08-30"), "2026-08-30")
    }

    func testEveryThreeDaysKeepsItsPhase() {
        let e = event("2026-08-01", .daily, every: 3)
        XCTAssertEqual(EventRecurrence.next(e, onOrAfter: "2026-08-02"), "2026-08-04")
        XCTAssertEqual(EventRecurrence.next(e, onOrAfter: "2026-08-04"), "2026-08-04")
        XCTAssertEqual(EventRecurrence.next(e, onOrAfter: "2026-08-05"), "2026-08-07")
    }

    func testWeeklyStaysOnItsWeekday() {
        let e = event("2026-08-03", .weekly)         // a Monday
        XCTAssertEqual(EventRecurrence.next(e, onOrAfter: "2026-08-30"), "2026-08-31")
        XCTAssertEqual(EventRecurrence.next(e, onOrAfter: "2026-09-01"), "2026-09-07")
    }

    func testFortnightly() {
        let e = event("2026-08-03", .weekly, every: 2)
        XCTAssertEqual(EventRecurrence.next(e, onOrAfter: "2026-08-04"), "2026-08-17")
    }

    // MARK: - Ending

    func testUntilStopsTheSeriesAndIsInclusive() {
        let e = event("2026-01-01", .monthly, until: "2026-03-01")
        XCTAssertEqual(EventRecurrence.next(e, onOrAfter: "2026-03-01"), "2026-03-01")
        XCTAssertNil(EventRecurrence.next(e, onOrAfter: "2026-03-02"))
    }

    // MARK: - Bad input

    func testAnUnparseableAnchorHasNoOccurrences() {
        XCTAssertNil(EventRecurrence.next(event("nonsense", .yearly), onOrAfter: "2026-08-30"))
        XCTAssertNil(EventRecurrence.next(event("2026-02-30", .yearly), onOrAfter: "2026-08-30"))
    }

    /// An interval of zero would be an infinite loop, so the model refuses it.
    func testIntervalIsClampedToAtLeastOne() {
        XCTAssertEqual(Recurrence(unit: .daily, interval: 0).interval, 1)
        XCTAssertEqual(Recurrence(unit: .daily, interval: -5).interval, 1)
        let e = event("2026-08-01", .daily, every: 0)
        XCTAssertEqual(EventRecurrence.next(e, onOrAfter: "2026-08-30"), "2026-08-30")
    }

    // MARK: - Windows

    func testOccurrencesFillACalendarMonth() {
        let e = event("2026-08-03", .weekly)
        XCTAssertEqual(EventRecurrence.occurrences(e, from: "2026-08-01", to: "2026-08-31"),
                       ["2026-08-03", "2026-08-10", "2026-08-17", "2026-08-24", "2026-08-31"])
    }

    func testAOneOffAppearsOnceOrNotAtAll() {
        let e = event("2026-08-14")
        XCTAssertEqual(EventRecurrence.occurrences(e, from: "2026-08-01", to: "2026-08-31"),
                       ["2026-08-14"])
        XCTAssertEqual(EventRecurrence.occurrences(e, from: "2026-09-01", to: "2026-09-30"), [])
    }

    func testAYearlyEventAppearsInItsMonthOnly() {
        let e = event("1965-03-12", .yearly)
        XCTAssertEqual(EventRecurrence.occurrences(e, from: "2026-03-01", to: "2026-03-31"),
                       ["2026-03-12"])
        XCTAssertEqual(EventRecurrence.occurrences(e, from: "2026-04-01", to: "2026-04-30"), [])
    }

    /// A daily rule over a long window must not run away.
    func testTheWindowIsCapped() {
        let e = event("2020-01-01", .daily)
        XCTAssertEqual(EventRecurrence.occurrences(e, from: "2020-01-01", to: "2030-01-01", cap: 50).count, 50)
    }

    // MARK: - Wording

    func testDescriptions() {
        XCTAssertEqual(EventRecurrence.describe(.none), "Does not repeat")
        XCTAssertEqual(EventRecurrence.describe(Recurrence(unit: .yearly)), "Every year")
        XCTAssertEqual(EventRecurrence.describe(Recurrence(unit: .weekly, interval: 2)), "Every 2 weeks")
        XCTAssertEqual(EventRecurrence.describe(Recurrence(unit: .daily, interval: 3, until: "2027-01-01")),
                       "Every 3 days, until 2027-01-01")
        XCTAssertEqual(EventRecurrence.shortDescribe(Recurrence(unit: .monthly)), "Monthly")
        XCTAssertEqual(EventRecurrence.shortDescribe(.none), "")
    }

    // MARK: - Anniversaries

    func testAYearlyEventKnowsWhichOneThisIs() {
        let e = event("1965-03-12", .yearly)
        XCTAssertEqual(EventRecurrence.ordinal(e, on: "2026-03-12"), 61)
        XCTAssertNil(EventRecurrence.ordinal(e, on: "1965-03-12"), "the first one is not an anniversary")
    }

    func testNonYearlyEventsHaveNoOrdinal() {
        XCTAssertNil(EventRecurrence.ordinal(event("2026-01-01", .monthly), on: "2026-05-01"))
        XCTAssertNil(EventRecurrence.ordinal(event("2026-01-01"), on: "2026-01-01"))
    }

    func testOrdinalLabels() {
        XCTAssertEqual(EventRecurrence.ordinalLabel(1), "1st")
        XCTAssertEqual(EventRecurrence.ordinalLabel(2), "2nd")
        XCTAssertEqual(EventRecurrence.ordinalLabel(3), "3rd")
        XCTAssertEqual(EventRecurrence.ordinalLabel(4), "4th")
        XCTAssertEqual(EventRecurrence.ordinalLabel(11), "11th")
        XCTAssertEqual(EventRecurrence.ordinalLabel(12), "12th")
        XCTAssertEqual(EventRecurrence.ordinalLabel(13), "13th")
        XCTAssertEqual(EventRecurrence.ordinalLabel(21), "21st")
        XCTAssertEqual(EventRecurrence.ordinalLabel(61), "61st")
        XCTAssertEqual(EventRecurrence.ordinalLabel(111), "111th")
    }

    // MARK: - Decoding

    /// Every event ever written is an all-day one-off with no reminders.
    func testAnEventFromBeforeAnyOfThisDecodes() throws {
        let json = Data(#"{"id":"e1","date":"2026-08-10","title":"Trip","tagIDs":["travel"]}"#.utf8)
        let e = try JSONDecoder().decode(EventItem.self, from: json)
        XCTAssertNil(e.time)
        XCTAssertEqual(e.recurrence, .none)
        XCTAssertFalse(e.recurrence.repeats)
        XCTAssertTrue(e.reminders.isEmpty)
    }

    func testRoundTripKeepsTheRuleAndTheReminders() throws {
        let e = event("2026-03-12", .yearly, reminders: [.thirtyDays, .oneDay], time: "18:30")
        let back = try JSONDecoder().decode(EventItem.self, from: JSONEncoder().encode(e))
        XCTAssertEqual(back.recurrence, e.recurrence)
        XCTAssertEqual(back.reminders, [.thirtyDays, .oneDay])
        XCTAssertEqual(back.time, "18:30")
    }

    func testLeadDaysAreOrderedAndDistinct() {
        let days = ReminderLead.ordered.map(\.days)
        XCTAssertEqual(days, days.sorted())
        XCTAssertEqual(Set(days).count, days.count)
        XCTAssertEqual(ReminderLead.sameDay.days, 0)
        XCTAssertEqual(ReminderLead.thirtyDays.days, 30)
    }
}
