import XCTest
@testable import meOS

/// The rules engine is the product, so what it is allowed to say is pinned.
/// Two properties matter more than any single sentence: it never speaks without
/// data, and what it says names numbers that were actually measured.
final class ActivityInsightsTests: XCTestCase {

    private let day = "2026-08-25"

    private func stamp(_ hour: Int, _ minute: Int) -> String {
        var c = DateComponents()
        c.year = 2026; c.month = 8; c.day = 25; c.hour = hour; c.minute = minute
        return ActivityTime.stamp(Calendar.current.date(from: c)!)
    }

    private func at(_ hour: Int, _ minute: Int) -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 8; c.day = 25; c.hour = hour; c.minute = minute
        return Calendar.current.date(from: c)!
    }

    private func event(_ app: String, _ h: Int, _ m: Int, minutes: Int,
                       _ p: ProductivityType, _ category: ActivityCategory) -> ActivityEvent {
        let total = h * 60 + m + minutes
        return ActivityEvent(deviceId: "d1", deviceType: .mac, platform: "test",
                             appId: "id.\(app)", appName: app, category: category,
                             startedAt: stamp(h, m), endedAt: stamp(total / 60, total % 60),
                             duration: minutes * 60, productivity: p, source: .macFrontmost)
    }

    // MARK: Task alignment

    func testCurrentAppIsMatchedToTodaysPriority() {
        let todos = ["Edit Varun's tech vlog", "Reply to invoices"]
        let capcut = event("CapCut", 14, 0, minutes: 32, .productive, .contentCreation)
        let focus = ActivityInsights.focusNow(current: capcut, todos: todos)

        XCTAssertEqual(focus?.alignedTask, "Edit Varun's tech vlog")
        XCTAssertTrue(focus!.insight.contains("today's priority"), focus!.insight)
    }

    /// The example that makes this feature worth building: the same app is fine
    /// or a problem depending on what you said you'd do today.
    func testADistractionIsNamedAgainstThePriorityItDisplaces() {
        let todos = ["Finish Java DSA practice"]
        let youtube = event("YouTube", 14, 0, minutes: 27, .distracting, .entertainment)
        let focus = ActivityInsights.focusNow(current: youtube, todos: todos)

        XCTAssertEqual(focus?.productivity, .distracting)
        XCTAssertTrue(focus!.insight.contains("YouTube"), focus!.insight)
        XCTAssertTrue(focus!.insight.contains("DSA"), focus!.insight)
    }

    func testWithNoPrioritiesItStillSaysSomethingTrue() {
        let youtube = event("YouTube", 14, 0, minutes: 27, .distracting, .entertainment)
        let focus = ActivityInsights.focusNow(current: youtube, todos: [])
        XCTAssertNotNil(focus)
        XCTAssertFalse(focus!.insight.isEmpty)
        XCTAssertNil(focus!.displacedTask)
    }

    func testNothingInFrontMeansNoClaim() {
        XCTAssertNil(ActivityInsights.focusNow(current: nil, todos: ["Ship the build"]))
    }

    // MARK: Verdict

    /// A verdict on twelve minutes of data would be noise wearing a headline.
    func testNoVerdictUntilThereIsEnoughOfADay() {
        let s = ActivityEngine.summary([event("Xcode", 10, 0, minutes: 10, .productive, .development)], day: day)
        XCTAssertNil(ActivityInsights.verdict(s))
    }

    func testStrongFocusedDayReadsExcellent() {
        let events = [
            event("Xcode", 9, 0, minutes: 90, .productive, .development),
            event("CapCut", 11, 0, minutes: 60, .productive, .contentCreation),
            event("Slack", 12, 30, minutes: 20, .neutral, .communication),
        ]
        let s = ActivityEngine.summary(events, day: day)
        let v = ActivityInsights.verdict(s)
        XCTAssertEqual(v?.0, .excellent)
    }

    /// The explanation is the point, not the grade — and it must name the real
    /// limiting factor rather than restating the percentage.
    func testFragmentedDayBlamesSwitchingNotScreenTime() {
        var events: [ActivityEvent] = []
        for i in 0..<30 {
            let app = i % 2 == 0 ? "Xcode" : "Chrome"
            events.append(event(app, 9 + i / 12, (i % 12) * 5, minutes: 4,
                                i % 2 == 0 ? .productive : .neutral,
                                i % 2 == 0 ? .development : .research))
        }
        let s = ActivityEngine.summary(events, day: day)
        let v = ActivityInsights.verdict(s)
        XCTAssertNotNil(v)
        XCTAssertTrue(v!.1.contains("context switching"), v!.1)
    }

    func testMostlyDistractingDayCannotReadPositive() {
        let events = [
            event("Xcode", 9, 0, minutes: 30, .productive, .development),
            event("Instagram", 10, 0, minutes: 90, .distracting, .social),
        ]
        let s = ActivityEngine.summary(events, day: day)
        XCTAssertEqual(ActivityInsights.verdict(s)?.0.isPositive, false)
    }

    // MARK: The one action

    func testALiveDistractionOutranksEverythingHistorical() {
        let s = ActivityEngine.summary([event("Xcode", 9, 0, minutes: 120, .productive, .development)], day: day)
        let live = event("WhatsApp", 14, 0, minutes: 18, .distracting, .social)
        let action = ActivityInsights.action(s, current: live, todos: ["Edit the vlog"], now: at(14, 18))

        XCTAssertEqual(action?.kind, .fixThisNow)
        XCTAssertTrue(action!.text.contains("WhatsApp"), action!.text)
    }

    func testAWorkingFocusBlockIsProtectedNotInterrupted() {
        let s = ActivityEngine.summary([event("CapCut", 13, 0, minutes: 40, .productive, .contentCreation)], day: day)
        let live = event("CapCut", 13, 0, minutes: 40, .productive, .contentCreation)
        let action = ActivityInsights.action(s, current: live, todos: [], now: at(13, 40))

        XCTAssertEqual(action?.kind, .goodMove)
    }

    func testFragmentationProducesTheSwitchingAction() {
        // Genuinely fragmented: three-minute stretches, ~20 switches an hour.
        var events: [ActivityEvent] = []
        for i in 0..<36 {
            events.append(event(i % 2 == 0 ? "Xcode" : "Slack", 9 + i / 20, (i % 20) * 3,
                                minutes: 3, i % 2 == 0 ? .productive : .neutral,
                                i % 2 == 0 ? .development : .communication))
        }
        let s = ActivityEngine.summary(events, day: day)
        let action = ActivityInsights.action(s, current: nil, todos: [], now: at(13, 0))
        XCTAssertEqual(action?.kind, .fixThisNow)
        XCTAssertTrue(action!.text.contains("switched apps"), action!.text)
    }

    func testNoDataMeansNoAdviceRatherThanEncouragement() {
        let s = ActivityEngine.summary([], day: day)
        XCTAssertNil(ActivityInsights.action(s, current: nil, todos: [], now: at(10, 0)))
    }

    // MARK: Insights list

    func testLeakNamesTheAppsAndTheirTotal() {
        let events = [
            event("WhatsApp", 10, 0, minutes: 22, .distracting, .social),
            event("Instagram", 11, 0, minutes: 30, .distracting, .social),
            event("Xcode", 12, 0, minutes: 60, .productive, .development),
        ]
        let s = ActivityEngine.summary(events, day: day)
        let leak = ActivityInsights.insights(s).first { $0.title == "Your biggest leak" }
        XCTAssertNotNil(leak)
        XCTAssertTrue(leak!.detail.contains("52m"), leak!.detail)
    }

    func testEmptyDayProducesNoInsights() {
        XCTAssertTrue(ActivityInsights.insights(ActivityEngine.summary([], day: day)).isEmpty)
    }

    // MARK: Week

    /// More screen time is not more work. A week where the total rose while
    /// productive time fell has to read as a warning, not a win.
    func testWeekSeparatesScreenTimeFromProductiveTime() {
        var thisWeek = ActivityWeekSummary(days: [day])
        thisWeek.totalSeconds = 42 * 3600
        thisWeek.byProductivity = [.productive: 20 * 3600, .neutral: 18 * 3600, .distracting: 4 * 3600]
        thisWeek.daysTracked = 7

        var lastWeek = ActivityWeekSummary(days: [])
        lastWeek.totalSeconds = 38 * 3600
        lastWeek.byProductivity = [.productive: 22 * 3600]
        lastWeek.daysTracked = 7

        let read = ActivityInsights.weekIntelligence(this: thisWeek, previous: lastWeek)
        let detail = read.biggestImprovement?.detail ?? ""
        XCTAssertTrue(detail.contains("Screen time increased"), detail)
        XCTAssertTrue(detail.contains("productive time decreased"), detail)
        XCTAssertEqual(read.biggestImprovement?.productivity, .distracting)
    }

    func testWeekWithNoBaselineDoesNotInventATrend() {
        var week = ActivityWeekSummary(days: [day])
        week.totalSeconds = 10 * 3600
        week.byProductivity = [.productive: 6 * 3600, .neutral: 4 * 3600]
        week.daysTracked = 5

        let read = ActivityInsights.weekIntelligence(this: week, previous: nil)
        XCTAssertNil(read.biggestImprovement)
        XCTAssertFalse(read.narrative.isEmpty)
    }

    func testEmptyWeekSaysNothingAtAll() {
        let read = ActivityInsights.weekIntelligence(this: ActivityWeekSummary(), previous: nil)
        XCTAssertTrue(read.narrative.isEmpty)
        XCTAssertNil(read.verdict)
        XCTAssertTrue(read.nextWeek.isEmpty)
    }

    func testPercentChangeNeedsABaseline() {
        XCTAssertNil(ActivityInsights.percentChange(from: 0, to: 100))
        XCTAssertEqual(ActivityInsights.percentChange(from: 100, to: 112), 12)
        XCTAssertEqual(ActivityInsights.percentChange(from: 100, to: 96), -4)
    }
}
