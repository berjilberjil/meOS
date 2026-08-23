import XCTest
@testable import MyOS

/// The Friday report: when it runs, which two weeks it compares, and what the
/// model is actually told.
final class WeeklyReportTests: XCTestCase {

    private func date(_ key: String, hour: Int = 12) -> Date {
        var c = DateComponents()
        let parts = key.split(separator: "-").map { Int($0)! }
        c.year = parts[0]; c.month = parts[1]; c.day = parts[2]; c.hour = hour
        return WeeklyReportMath.calendar.date(from: c)!
    }

    private func photo(_ dateKey: String, _ id: String) -> ProgressPhoto {
        ProgressPhoto(id: id, date: dateKey, url: URL(fileURLWithPath: "/tmp/\(id).jpg"))
    }

    // MARK: Friday 6pm

    func testNotDueBeforeFridayEvening() {
        XCTAssertFalse(WeeklyReportMath.isDue(now: date("2026-08-21", hour: 17), lastReportWeek: nil))
        XCTAssertFalse(WeeklyReportMath.isDue(now: date("2026-08-20", hour: 23), lastReportWeek: nil),
                       "Thursday night is not Friday")
    }

    func testDueFromSixOnFriday() {
        XCTAssertTrue(WeeklyReportMath.isDue(now: date("2026-08-21", hour: 18), lastReportWeek: nil))
        XCTAssertTrue(WeeklyReportMath.isDue(now: date("2026-08-21", hour: 21), lastReportWeek: nil))
    }

    /// Sunday is weekday 1 but the LAST day of a Monday-first week — comparing
    /// raw weekday numbers would make a missed Friday unreachable all weekend.
    func testStillDueOverTheWeekend() {
        XCTAssertTrue(WeeklyReportMath.isDue(now: date("2026-08-22", hour: 9), lastReportWeek: nil))
        XCTAssertTrue(WeeklyReportMath.isDue(now: date("2026-08-23", hour: 9), lastReportWeek: nil))
    }

    func testNotDueTwiceInOneWeek() {
        let now = date("2026-08-22", hour: 9)
        let key = WeeklyReportMath.weekKey(now)
        XCTAssertFalse(WeeklyReportMath.isDue(now: now, lastReportWeek: key))
        // Last week's report doesn't stop this week's.
        XCTAssertTrue(WeeklyReportMath.isDue(now: now, lastReportWeek: "2026-W33"))
    }

    // MARK: Weeks

    func testWeekKeyIsISOAndMondayFirst() {
        XCTAssertEqual(WeeklyReportMath.weekKey(date("2026-08-17")),
                       WeeklyReportMath.weekKey(date("2026-08-23")),
                       "Monday and the Sunday after it are the same week")
        XCTAssertNotEqual(WeeklyReportMath.weekKey(date("2026-08-16")),
                          WeeklyReportMath.weekKey(date("2026-08-17")))
        XCTAssertTrue(WeeklyReportMath.weekKey(date("2026-08-21")).hasPrefix("2026-W"))
    }

    func testWindowsAreThisWeekSoFarAndAllOfLastWeek() {
        let (thisWeek, lastWeek) = WeeklyReportMath.windows(now: date("2026-08-21"))
        XCTAssertEqual(thisWeek.lowerBound, "2026-08-17")
        XCTAssertEqual(thisWeek.upperBound, "2026-08-21")
        XCTAssertEqual(lastWeek.lowerBound, "2026-08-10")
        XCTAssertEqual(lastWeek.upperBound, "2026-08-16")
    }

    // MARK: Picking photos

    func testPickKeepsEverythingWhenThereAreFewEnough() {
        let photos = [photo("2026-08-18", "b"), photo("2026-08-17", "a")]
        let picked = WeeklyReportMath.pick(photos, in: "2026-08-17"..."2026-08-21")
        XCTAssertEqual(picked.map(\.id), ["a", "b"], "oldest first")
    }

    func testPickIgnoresPhotosOutsideTheWindow() {
        let photos = [photo("2026-08-16", "old"), photo("2026-08-18", "in")]
        let picked = WeeklyReportMath.pick(photos, in: "2026-08-17"..."2026-08-21")
        XCTAssertEqual(picked.map(\.id), ["in"])
    }

    func testPickThinsALongWeekToFourSpreadAcrossIt() {
        let photos = (1...9).map { photo("2026-08-17", "p\($0)") }
        let picked = WeeklyReportMath.pick(photos, in: "2026-08-17"..."2026-08-21")
        XCTAssertEqual(picked.count, 4)
        XCTAssertEqual(picked.first?.id, "p1")
        XCTAssertEqual(picked.last?.id, "p9", "the newest is always one of them")
    }

    // MARK: The report itself

    func testPercentLabelSigned() {
        var r = WeeklyReport(id: "2026-W34", at: "", weekStart: "", weekEnd: "")
        r.percent = -1.84
        XCTAssertEqual(r.percentLabel, "−1.8%")
        r.percent = 2.0
        XCTAssertEqual(r.percentLabel, "+2.0%")
    }

    func testPercentIsHiddenWhenThereWasNothingToCompare() {
        var r = WeeklyReport(id: "2026-W34", at: "", weekStart: "", weekEnd: "")
        r.percent = 4
        r.needsPhotos = true
        XCTAssertEqual(r.percentLabel, "", "a percentage with no second week to measure against is a lie")
    }

    func testRoundTrip() throws {
        var r = WeeklyReport(id: "2026-W34", at: "2026-08-21T18:00:00",
                             weekStart: "2026-08-17", weekEnd: "2026-08-21")
        r.verdict = "gaining"; r.percent = -1.2; r.headline = "Down and holding form"
        r.workouts = ["zone-2 walk"]; r.diet = ["2100 kcal"]; r.seen = true
        let back = try JSONDecoder().decode(WeeklyReport.self, from: JSONEncoder().encode(r))
        XCTAssertEqual(back, r)
        XCTAssertEqual(back.kind, .gaining)
    }

    func testDecodesAThinRecord() throws {
        let back = try JSONDecoder().decode(WeeklyReport.self, from: Data(#"{"id":"2026-W34"}"#.utf8))
        XCTAssertEqual(back.kind, .unknown)
        XCTAssertFalse(back.seen)
        XCTAssertEqual(back.workouts, [])
    }

    func testPayloadCarriesReportsUnderTheirSyncKey() throws {
        let raw = Data(#"{"myos.weekly":[{"id":"2026-W34","verdict":"slipping"}]}"#.utf8)
        let payload = try JSONDecoder().decode(AppStatePayload.self, from: raw)
        XCTAssertEqual(payload.weekly?.first?.kind, .slipping)
    }

    // MARK: What the model is told

    private func brief(fitness: [String: FitnessDay], training: TrainingState = TrainingState()) -> String {
        WeeklyBrief.text(name: "Berjil", goal: .cut, targetWeightKg: 72,
                         calorieTarget: 2100, proteinTarget: 150,
                         fitness: fitness, training: training,
                         lastWeek: .init(label: "LAST WEEK", range: "2026-08-10"..."2026-08-16", photos: 3),
                         thisWeek: .init(label: "THIS WEEK", range: "2026-08-17"..."2026-08-21", photos: 2))
    }

    func testBriefCarriesGoalTargetsAndPhotoCounts() {
        let text = brief(fitness: [:])
        XCTAssertTrue(text.contains("Goal: cut (target 72 kg)"), text)
        XCTAssertTrue(text.contains("Daily targets: 2100 kcal, 150 g protein"), text)
        XCTAssertTrue(text.contains("3 photos attached"), text)
        XCTAssertTrue(text.contains("2 photos attached"), text)
    }

    func testBriefSaysNotLoggedRatherThanZero() {
        let text = brief(fitness: [:])
        XCTAssertTrue(text.contains("weight: not logged"), text)
        XCTAssertTrue(text.contains("calories: not logged"), text)
        XCTAssertFalse(text.contains("avg 0"), "an unlogged week must not read as a zero-calorie week")
    }

    func testBriefShowsTheWeightMoveAcrossTheWeek() {
        var mon = FitnessDay(); mon.weightKg = 78.4
        var fri = FitnessDay(); fri.weightKg = 77.6
        let text = brief(fitness: ["2026-08-17": mon, "2026-08-21": fri,
                                   "2026-08-10": FitnessDay()])
        XCTAssertTrue(text.contains("weight: 78.4 to 77.6 kg"), text)
    }

    func testBriefCountsWorkoutsInTheRightWeek() {
        var training = TrainingState()
        var done = WorkoutDayLog(); done.done = true
        var skipped = WorkoutDayLog(); skipped.skipped = true
        training.dayLog = ["2026-08-17": done, "2026-08-18": done,
                           "2026-08-19": skipped, "2026-08-11": done]
        let text = brief(fitness: [:], training: training)
        let blocks = text.components(separatedBy: "THIS WEEK")
        XCTAssertTrue(blocks.last!.contains("workouts: 2 done, 1 skipped"), text)
        XCTAssertTrue(blocks.first!.contains("workouts: 1 done, 0 skipped"), text)
    }
}
