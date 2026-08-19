import XCTest
@testable import MyOS

/// Today's focus: how a day is judged, how the streak counts back, and that day
/// plans written before the timer existed still decode.
final class FocusRecordTests: XCTestCase {

    private func day(_ flags: [Bool], spent: [Int] = []) -> DayPlan {
        var p = DayPlan()
        p.todos = flags.enumerated().map { i, done in
            FocusItem(text: "t\(i)", done: done, spent: i < spent.count ? spent[i] : 0)
        }
        return p
    }

    private func date(_ key: String) -> Date { CalMath.date(fromKey: key)! }

    // MARK: Verdict

    func testVerdicts() {
        XCTAssertEqual(FocusRecord.verdict([]), .empty)
        XCTAssertEqual(FocusRecord.verdict(day([false, false]).todos), .missed)
        XCTAssertEqual(FocusRecord.verdict(day([true, false]).todos), .partial)
        XCTAssertEqual(FocusRecord.verdict(day([true, true]).todos), .done)
    }

    // MARK: Streak

    func testStreakCountsConsecutiveCleanDays() {
        let days = [
            "2026-08-19": day([true]),
            "2026-08-18": day([true, true]),
            "2026-08-17": day([true]),
            "2026-08-16": day([true, false])   // breaks it
        ]
        XCTAssertEqual(FocusRecord.streak(days: days, today: date("2026-08-19")), 3)
    }

    func testUnfinishedTodayDoesNotBreakTheStreak() {
        // The day isn't over — yesterday's run still counts.
        let days = [
            "2026-08-19": day([true, false]),
            "2026-08-18": day([true]),
            "2026-08-17": day([true])
        ]
        XCTAssertEqual(FocusRecord.streak(days: days, today: date("2026-08-19")), 2)
    }

    func testEmptyTodayDoesNotBreakTheStreak() {
        let days = ["2026-08-18": day([true])]
        XCTAssertEqual(FocusRecord.streak(days: days, today: date("2026-08-19")), 1)
    }

    func testMissedYesterdayEndsTheStreakAtZero() {
        let days = [
            "2026-08-19": day([false]),
            "2026-08-18": day([false]),
            "2026-08-17": day([true])
        ]
        XCTAssertEqual(FocusRecord.streak(days: days, today: date("2026-08-19")), 0)
    }

    func testNoHistoryIsNoStreak() {
        XCTAssertEqual(FocusRecord.streak(days: [:], today: date("2026-08-19")), 0)
    }

    // MARK: Focused time

    func testFocusedMinutesSumsSecondsAcrossTasks() {
        let todos = day([true, true], spent: [1500, 300]).todos
        XCTAssertEqual(FocusRecord.focusedMinutes(todos), 30)
    }

    // MARK: Model back-compat

    func testFocusItemDecodesPlansWrittenBeforeTheTimer() throws {
        let legacy = #"{"id":"abc","text":"ship it","done":true}"#.data(using: .utf8)!
        let item = try JSONDecoder().decode(FocusItem.self, from: legacy)
        XCTAssertEqual(item.text, "ship it")
        XCTAssertTrue(item.done)
        XCTAssertNil(item.mins)
        XCTAssertEqual(item.spent, 0)
    }

    func testFocusItemRoundTripsTimerFields() throws {
        let item = FocusItem(text: "deep work", mins: 45, spent: 2700)
        let back = try JSONDecoder().decode(FocusItem.self, from: JSONEncoder().encode(item))
        XCTAssertEqual(back.mins, 45)
        XCTAssertEqual(back.spent, 2700)
    }
}
