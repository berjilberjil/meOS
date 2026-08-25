import XCTest
@testable import MyOS

/// The engine is the only thing standing between raw sessions and three screens
/// that all claim to describe the same day, so its arithmetic is pinned here.
final class ActivityEngineTests: XCTestCase {

    // MARK: Helpers

    private let day = "2026-08-25"

    private func stamp(_ hour: Int, _ minute: Int, _ second: Int = 0) -> String {
        var c = DateComponents()
        c.year = 2026; c.month = 8; c.day = 25
        c.hour = hour; c.minute = minute; c.second = second
        let date = Calendar.current.date(from: c)!
        return ActivityTime.stamp(date)
    }

    private func event(_ app: String, _ startHour: Int, _ startMinute: Int, minutes: Int,
                       _ productivity: ProductivityType = .productive,
                       device: DeviceType = .mac,
                       category: ActivityCategory = .development) -> ActivityEvent {
        let start = stamp(startHour, startMinute)
        let endMinuteTotal = startHour * 60 + startMinute + minutes
        let end = stamp(endMinuteTotal / 60, endMinuteTotal % 60)
        return ActivityEvent(deviceId: "d1", deviceType: device, platform: "test",
                             appId: "id.\(app)", appName: app, category: category,
                             startedAt: start, endedAt: end, duration: minutes * 60,
                             productivity: productivity, source: .macFrontmost)
    }

    // MARK: Totals

    func testTotalsSplitByDeviceAndWorth() {
        let events = [
            event("Xcode", 10, 0, minutes: 60),
            event("WhatsApp", 11, 0, minutes: 20, .distracting, device: .iphone, category: .social),
            event("Finder", 11, 30, minutes: 10, .neutral, category: .utility),
        ]
        let s = ActivityEngine.summary(events, day: day)

        XCTAssertEqual(s.totalSeconds, 90 * 60)
        XCTAssertEqual(s.seconds(.productive), 60 * 60)
        XCTAssertEqual(s.seconds(.distracting), 20 * 60)
        XCTAssertEqual(s.seconds(.neutral), 10 * 60)
        XCTAssertEqual(s.seconds(.mac), 70 * 60)
        XCTAssertEqual(s.seconds(.iphone), 20 * 60)
        XCTAssertEqual(s.share(.productive), 2.0 / 3.0, accuracy: 0.001)
    }

    /// Shares are of *tracked* time, never of the 24-hour day — MyOS only sees
    /// what it is watching, and dividing by the day would understate everything.
    func testSharesAreOfTrackedTimeOnly() {
        let s = ActivityEngine.summary([event("Xcode", 10, 0, minutes: 30)], day: day)
        XCTAssertEqual(s.share(.productive), 1.0, accuracy: 0.0001)
    }

    func testEmptyDayIsEmptyNotZeroFilled() {
        let s = ActivityEngine.summary([], day: day)
        XCTAssertTrue(s.isEmpty)
        XCTAssertTrue(s.apps.isEmpty)
        XCTAssertNil(s.longestFocus)
    }

    func testOnlyTheRequestedDayIsCounted() {
        var other = event("Xcode", 10, 0, minutes: 60)
        other.startedAt = "2026-08-24T10:00:00+05:30"
        other.endedAt = "2026-08-24T11:00:00+05:30"
        let s = ActivityEngine.summary([other, event("Xcode", 10, 0, minutes: 15)], day: day)
        XCTAssertEqual(s.totalSeconds, 15 * 60)
    }

    // MARK: Apps

    func testAppsAreSummedAndRanked() {
        let events = [
            event("Chrome", 9, 0, minutes: 20, .neutral, category: .research),
            event("Xcode", 10, 0, minutes: 45),
            event("Chrome", 11, 0, minutes: 30, .neutral, category: .research),
        ]
        let s = ActivityEngine.summary(events, day: day)
        XCTAssertEqual(s.apps.count, 2)
        XCTAssertEqual(s.apps.first?.appName, "Chrome")
        XCTAssertEqual(s.apps.first?.seconds, 50 * 60)
        XCTAssertEqual(s.apps.last?.seconds, 45 * 60)
    }

    // MARK: Timeline

    /// A session that spans two hours is credited to both, or a long block draws
    /// as a spike in the hour it happened to start in.
    func testASessionIsSpreadAcrossTheHoursItOccupied() {
        let s = ActivityEngine.summary([event("Xcode", 10, 30, minutes: 60)], day: day)
        XCTAssertEqual(s.timeline[10].productive, 30 * 60)
        XCTAssertEqual(s.timeline[11].productive, 30 * 60)
        XCTAssertEqual(s.timeline.reduce(0) { $0 + $1.total }, 60 * 60)
        XCTAssertEqual(s.timeline.count, 24)
    }

    // MARK: Switching

    func testSwitchesCountAppChangesNotSessions() {
        let events = [
            event("Xcode", 10, 0, minutes: 10),
            event("Xcode", 10, 10, minutes: 10),      // same app — not a switch
            event("Chrome", 10, 20, minutes: 5, .neutral, category: .research),
            event("Xcode", 10, 25, minutes: 10),
        ]
        XCTAssertEqual(ActivityEngine.countSwitches(events), 2)
    }

    func testWorkHourSwitchesExcludeTheEvening() {
        let events = [
            event("Xcode", 10, 0, minutes: 10),
            event("Chrome", 10, 10, minutes: 5, .neutral, category: .research),
            event("Xcode", 21, 0, minutes: 10),
            event("Chrome", 21, 10, minutes: 5, .neutral, category: .research),
        ]
        let s = ActivityEngine.summary(events, day: day)
        XCTAssertEqual(s.switches, 3)
        XCTAssertEqual(s.switchesInWorkHours, 1)
    }

    // MARK: Focus blocks

    func testProductiveRunsBecomeOneFocusBlock() {
        let events = [
            event("Xcode", 10, 0, minutes: 30),
            event("Xcode", 10, 30, minutes: 30),
        ]
        let blocks = ActivityEngine.focusBlocks(events)
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks.first?.seconds, 60 * 60)
    }

    /// Reaching for a terminal mid-task does not end deep work — but scrolling
    /// Instagram for ten minutes does.
    func testShortInterruptionsAreAbsorbedAndLongOnesAreNot() {
        let absorbed = [
            event("Xcode", 10, 0, minutes: 30),
            event("Finder", 10, 30, minutes: 1, .neutral, category: .utility),
            event("Xcode", 10, 31, minutes: 30),
        ]
        XCTAssertEqual(ActivityEngine.focusBlocks(absorbed).count, 1)

        let broken = [
            event("Xcode", 10, 0, minutes: 30),
            event("Instagram", 10, 30, minutes: 10, .distracting, category: .social),
            event("Xcode", 10, 40, minutes: 30),
        ]
        let blocks = ActivityEngine.focusBlocks(broken)
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks.map(\.seconds), [30 * 60, 30 * 60])
    }

    func testShortProductiveStretchesAreNotFocusBlocks() {
        XCTAssertTrue(ActivityEngine.focusBlocks([event("Xcode", 10, 0, minutes: 4)]).isEmpty)
    }

    func testLongestFocusPicksTheBiggestBlock() {
        let events = [
            event("Xcode", 9, 0, minutes: 20),
            event("Instagram", 9, 20, minutes: 15, .distracting, category: .social),
            event("CapCut", 10, 0, minutes: 78, .productive, category: .contentCreation),
        ]
        let s = ActivityEngine.summary(events, day: day)
        XCTAssertEqual(s.longestFocus?.seconds, 78 * 60)
        XCTAssertEqual(s.longestFocus?.appName, "CapCut")
    }

    // MARK: Week

    func testWeekReadsRawEventsAndCompactedRollupsTogether() {
        var doc = ActivityDoc()
        doc.events = [event("Xcode", 10, 0, minutes: 60)]
        doc.days["2026-08-20"] = {
            var r = ActivityDayRollup(day: "2026-08-20")
            r.totalSeconds = 3600
            r.byProductivity = [ProductivityType.productive.rawValue: 1800,
                                ProductivityType.distracting.rawValue: 1800]
            r.byDevice = [DeviceType.mac.rawValue: 3600]
            r.byApp = ["Chrome": 3600]
            return r
        }()

        let week = ActivityEngine.weekSummary(doc: doc, days: ["2026-08-20", day])
        XCTAssertEqual(week.totalSeconds, 2 * 3600)
        XCTAssertEqual(week.seconds(.productive), 3600 + 1800)
        XCTAssertEqual(week.daysTracked, 2)
        XCTAssertEqual(week.apps.count, 2)
    }

    func testBestFocusWindowIsTheStrongestTwoHourPair() {
        var doc = ActivityDoc()
        doc.events = [
            event("Xcode", 10, 0, minutes: 60),
            event("Xcode", 11, 0, minutes: 60),
            event("Xcode", 15, 0, minutes: 45),
        ]
        let week = ActivityEngine.weekSummary(doc: doc, days: [day])
        XCTAssertEqual(week.bestFocusHour, 10)
        XCTAssertEqual(week.bestFocusWindow, "10 AM – 12 PM")
    }

    // MARK: Retention

    /// State is one synced blob. Raw sessions past the window are compacted into
    /// a day rollup so a year of history cannot dominate every sync.
    func testCompactionRollsOldSessionsUpAndDropsThem() {
        var doc = ActivityDoc()
        var old = event("Xcode", 10, 0, minutes: 60)
        old.startedAt = "2026-07-01T10:00:00+05:30"
        old.endedAt = "2026-07-01T11:00:00+05:30"
        doc.events = [old, event("Xcode", 12, 0, minutes: 30)]

        ActivityEngine.compact(&doc, today: day)

        XCTAssertEqual(doc.events.count, 1, "the recent session must survive")
        XCTAssertEqual(doc.days["2026-07-01"]?.totalSeconds, 3600)
        XCTAssertEqual(doc.days["2026-07-01"]?.byApp["Xcode"], 3600)
    }

    // MARK: Merge

    /// Both devices append to one last-write-wins key, so a pull that replaced
    /// rather than merged would silently delete the other device's day.
    func testMergeUnionsSessionsFromBothDevices() {
        var mac = ActivityDoc(); mac.events = [event("Xcode", 10, 0, minutes: 30)]
        var phone = ActivityDoc()
        phone.events = [event("WhatsApp", 11, 0, minutes: 10, .distracting,
                              device: .iphone, category: .social)]

        let merged = mac.merged(with: phone)
        XCTAssertEqual(merged.events.count, 2)
        XCTAssertEqual(ActivityEngine.summary(merged.events, day: day).totalSeconds, 40 * 60)
    }

    func testMergeIsIdempotent() {
        var doc = ActivityDoc(); doc.events = [event("Xcode", 10, 0, minutes: 30)]
        XCTAssertEqual(doc.merged(with: doc), doc)
    }
}
