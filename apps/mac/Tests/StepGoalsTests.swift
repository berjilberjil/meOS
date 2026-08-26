import XCTest
@testable import MyOS

/// The streak moved from journaling to steps, and gained a second goal.
///
/// Everything here is a rule Berjil chose out loud: the streak is unforgiving
/// (no freeze day), the stretch goal always sits above the mandatory one, and a
/// goal is congratulated exactly once however many times the day is re-read.
@MainActor
final class StepGoalsTests: XCTestCase {

    private let today = "2026-08-26"

    private func days(_ counts: [String: Int]) -> [String: FitnessDay] {
        var out: [String: FitnessDay] = [:]
        for (key, n) in counts {
            var d = FitnessDay()
            d.steps = n
            out[key] = d
        }
        return out
    }

    private func back(_ n: Int) -> String { AppState.addDays(-n, to: today) }

    // MARK: - The two goals

    func testDefaultsWhenTheProfileHasNothing() {
        let g = StepGoals(daily: nil, stretch: nil)
        XCTAssertEqual(g.daily, 8_000)
        XCTAssertEqual(g.stretch, 10_000)
    }

    /// A stretch goal at or below the mandatory one is not a stretch: it would
    /// be crossed in the same stride, fire both celebrations at once, and draw
    /// the ring's second arc backwards.
    func testStretchIsForcedAboveTheDailyGoal() {
        XCTAssertGreaterThan(StepGoals(daily: 12_000, stretch: 10_000).stretch, 12_000)
        XCTAssertGreaterThan(StepGoals(daily: 9_000, stretch: 9_000).stretch, 9_000)
        // A sane pair is left exactly as typed.
        let kept = StepGoals(daily: 6_000, stretch: 9_000)
        XCTAssertEqual(kept.daily, 6_000)
        XCTAssertEqual(kept.stretch, 9_000)
    }

    func testReachedCountsBothGoals() {
        let g = StepGoals(daily: 8_000, stretch: 10_000)
        XCTAssertEqual(g.reached(0), 0)
        XCTAssertEqual(g.reached(7_999), 0)
        XCTAssertEqual(g.reached(8_000), 1)
        XCTAssertEqual(g.reached(9_999), 1)
        XCTAssertEqual(g.reached(10_000), 2)
        XCTAssertEqual(g.next(after: 1), 10_000)
        XCTAssertNil(g.next(after: 2))
    }

    // MARK: - The streak

    func testConsecutiveGoalDaysCount() {
        let fitness = days([today: 8_400, back(1): 9_000, back(2): 12_000])
        XCTAssertEqual(StepStreak.count(fitness: fitness,
                                        goals: StepGoals(daily: 8_000, stretch: 10_000),
                                        today: today), 3)
    }

    /// No freeze day. Berjil picked this over the journal's Duolingo rule: on a
    /// cut, a day under the goal is a day under the goal.
    func testOneMissedDayEndsTheRun() {
        let fitness = days([today: 8_400, back(1): 4_200, back(2): 9_000, back(3): 9_000])
        XCTAssertEqual(StepStreak.count(fitness: fitness,
                                        goals: StepGoals(daily: 8_000, stretch: 10_000),
                                        today: today), 1)
    }

    /// A day that has not finished cannot have been missed.
    func testTodayIsPendingNotMissed() {
        let fitness = days([today: 2_000, back(1): 9_000, back(2): 9_000])
        XCTAssertEqual(StepStreak.count(fitness: fitness,
                                        goals: StepGoals(daily: 8_000, stretch: 10_000),
                                        today: today), 2)
    }

    func testNoStepsAnywhereIsNoStreak() {
        XCTAssertEqual(StepStreak.count(fitness: [:],
                                        goals: StepGoals(daily: 8_000, stretch: 10_000),
                                        today: today), 0)
    }

    /// Raising the goal re-reads history against the new line rather than
    /// grandfathering days in — the streak has to mean the goal you hold now.
    func testRaisingTheGoalShortensAnExistingRun() {
        let fitness = days([today: 12_000, back(1): 9_000, back(2): 12_000])
        XCTAssertEqual(StepStreak.count(fitness: fitness,
                                        goals: StepGoals(daily: 10_000, stretch: 14_000),
                                        today: today), 1)
    }

    func testDayStates() {
        let goals = StepGoals(daily: 8_000, stretch: 10_000)
        let fitness = days([today: 1_000, back(1): 11_000, back(2): 8_500, back(3): 3_000])
        XCTAssertEqual(StepStreak.day(today, fitness: fitness, goals: goals, today: today), .pending)
        XCTAssertEqual(StepStreak.day(back(1), fitness: fitness, goals: goals, today: today), .stretch)
        XCTAssertEqual(StepStreak.day(back(2), fitness: fitness, goals: goals, today: today), .hit)
        XCTAssertEqual(StepStreak.day(back(3), fitness: fitness, goals: goals, today: today), .short)
        XCTAssertEqual(StepStreak.day(back(4), fitness: fitness, goals: goals, today: today), .none)
    }

    // MARK: - Congratulating exactly once

    func testCrossingBothGoalsAtOnceHailsBoth() {
        let g = StepGoals(daily: 8_000, stretch: 10_000)
        XCTAssertEqual(g.fresh(steps: 10_400, alreadyHailed: nil), [1, 2])
    }

    /// The pedometer re-reports the same day constantly, and the other device
    /// pulls it down again. Neither is a second achievement.
    func testAlreadyHailedGoalsStayQuiet() {
        let g = StepGoals(daily: 8_000, stretch: 10_000)
        XCTAssertEqual(g.fresh(steps: 8_400, alreadyHailed: [1]), [])
        XCTAssertEqual(g.fresh(steps: 10_400, alreadyHailed: [1]), [2])
        XCTAssertEqual(g.fresh(steps: 10_400, alreadyHailed: [1, 2]), [])
        XCTAssertEqual(g.fresh(steps: 100, alreadyHailed: nil), [])
    }

    // MARK: - What it says

    /// Opening the app twice must not reshuffle the line — Swift's own hashing
    /// is seeded per process and would do exactly that.
    func testQuoteIsStableForADayAndGoal() {
        let a = StepQuotes.line(day: today, level: 1)
        XCTAssertEqual(a, StepQuotes.line(day: today, level: 1))
        XCTAssertFalse(a.isEmpty)
        XCTAssertTrue(StepQuotes.mandatory.contains(a))
        XCTAssertTrue(StepQuotes.stretch.contains(StepQuotes.line(day: today, level: 2)))
    }

    func testQuotesMoveBetweenDays() {
        let week = (0..<7).map { StepQuotes.line(day: back($0), level: 1) }
        XCTAssertGreaterThan(Set(week).count, 1, "the same line every day is wallpaper")
    }

    func testNotificationNamesTheGoalAndWhatIsLeft() {
        let c = StepCelebration(level: 1, steps: 8_140, target: 8_000, next: 10_000,
                                streak: 12, quote: "Onward.", day: today)
        XCTAssertTrue(StepNotify.title(c).contains("8,140"))
        XCTAssertTrue(StepNotify.title(c).contains("goal hit"))
        XCTAssertTrue(StepNotify.body(c).contains("1,860"))

        let done = StepCelebration(level: 2, steps: 10_400, target: 10_000, next: nil,
                                   streak: 12, quote: "Onward.", day: today)
        XCTAssertTrue(StepNotify.title(done).contains("stretch"))
        XCTAssertTrue(StepNotify.body(done).contains("Day 12"))
        XCTAssertNil(done.remaining)
    }

    // MARK: - Comparing two photos

    private func photo(_ date: String, _ id: String = "a") -> ProgressPhoto {
        ProgressPhoto(id: "\(date)__\(id)", date: date, url: URL(fileURLWithPath: "/tmp/\(date).jpg"))
    }

    func testCompareOpensOnOldestAgainstNewest() {
        let all = [photo("2026-07-12"), photo("2026-08-26"), photo("2026-08-01")]
        let ordered = PhotoCompare.ordered(all)
        XCTAssertEqual(ordered.map(\.date), ["2026-07-12", "2026-08-01", "2026-08-26"])
        let ends = PhotoCompare.endpoints(all)
        XCTAssertEqual(ends?.left, 0)
        XCTAssertEqual(ends?.right, 2)
    }

    func testCompareNeedsTwoPhotos() {
        XCTAssertNil(PhotoCompare.endpoints([]))
        XCTAssertNil(PhotoCompare.endpoints([photo("2026-08-26")]))
    }

    /// Several photos on one day must each be reachable — stepping by day would
    /// make all but one of them impossible to select.
    func testSeveralPhotosOnOneDayAreOrderedNotCollapsed() {
        let all = [photo("2026-08-26", "b"), photo("2026-08-26", "a")]
        XCTAssertEqual(PhotoCompare.ordered(all).map(\.id),
                       ["2026-08-26__a", "2026-08-26__b"])
    }

    func testCaptionCountsDaysAndWeight() {
        let left = photo("2026-07-12"), right = photo("2026-08-26")
        XCTAssertEqual(PhotoCompare.daysApart(left.date, right.date), 45)
        let weights = ["2026-07-12": 78.4, "2026-08-26": 74.1]
        XCTAssertEqual(PhotoCompare.caption(left: left, right: right, weight: { weights[$0] }),
                       "45 days apart · −4.3 kg")
    }

    /// Nothing true to say is said as nothing — not as "0 days apart".
    func testCaptionIsNilWhenThereIsNothingToCompare() {
        let same = photo("2026-08-26")
        XCTAssertNil(PhotoCompare.caption(left: same, right: same, weight: { _ in nil }))
        XCTAssertEqual(PhotoCompare.caption(left: photo("2026-08-25"), right: same, weight: { _ in nil }),
                       "1 day apart")
    }
}
