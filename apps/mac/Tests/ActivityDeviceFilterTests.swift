import XCTest
@testable import MyOS

/// The device switch is a control on the card, which means it has to change the
/// answer honestly: every number under it is recomputed from that device's
/// sessions, not scaled off the total.
final class ActivityDeviceFilterTests: XCTestCase {

    private let day = "2026-08-25"

    private func stamp(_ hour: Int, _ minute: Int) -> String {
        var c = DateComponents()
        c.year = 2026; c.month = 8; c.day = 25; c.hour = hour; c.minute = minute
        return ActivityTime.stamp(Calendar.current.date(from: c)!)
    }

    private func event(_ app: String, _ hour: Int, minutes: Int,
                       device: DeviceType,
                       category: ActivityCategory = .development,
                       worth: ProductivityType = .productive) -> ActivityEvent {
        ActivityEvent(deviceId: device.rawValue, deviceType: device, platform: "test",
                      appId: "id.\(app)", appName: app, category: category,
                      startedAt: stamp(hour, 0), endedAt: stamp(hour + minutes / 60, minutes % 60),
                      duration: minutes * 60, productivity: worth,
                      source: device == .mac ? .macFrontmost : .iosShortcut)
    }

    private var sessions: [ActivityEvent] {
        [event("Xcode", 10, minutes: 60, device: .mac),
         event("CapCut", 11, minutes: 30, device: .mac, category: .contentCreation),
         event("Instagram", 12, minutes: 20, device: .iphone, category: .social, worth: .distracting)]
    }

    func testFilteringToOneDeviceExcludesTheOther() {
        let mac = ActivityEngine.summary(sessions, day: day, device: .mac)
        XCTAssertEqual(mac.totalSeconds, 90 * 60)
        XCTAssertEqual(mac.apps.map(\.appName), ["Xcode", "CapCut"])
        XCTAssertEqual(mac.seconds(.distracting), 0)

        let phone = ActivityEngine.summary(sessions, day: day, device: .iphone)
        XCTAssertEqual(phone.totalSeconds, 20 * 60)
        XCTAssertEqual(phone.apps.map(\.appName), ["Instagram"])
    }

    func testBothIsTheSumOfTheTwo() {
        let all = ActivityEngine.summary(sessions, day: day, device: .all)
        let mac = ActivityEngine.summary(sessions, day: day, device: .mac)
        let phone = ActivityEngine.summary(sessions, day: day, device: .iphone)
        XCTAssertEqual(all.totalSeconds, mac.totalSeconds + phone.totalSeconds)
        XCTAssertEqual(all.apps.count, 3)
    }

    /// The timeline is per device too — an hour spent on the phone must not
    /// appear in the Mac's strip.
    func testTimelineFollowsTheFilter() {
        let mac = ActivityEngine.summary(sessions, day: day, device: .mac)
        XCTAssertEqual(mac.timeline[12].total, 0)
        let phone = ActivityEngine.summary(sessions, day: day, device: .iphone)
        XCTAssertEqual(phone.timeline[12].distracting, 20 * 60)
    }

    // MARK: Categories

    /// The legend reads in kinds of time, and each kind carries the worth the
    /// majority of its time carried.
    func testCategoriesRollUpBiggestFirst() {
        let all = ActivityEngine.summary(sessions, day: day, device: .all)
        XCTAssertEqual(all.categories.map(\.category), [.development, .contentCreation, .social])
        XCTAssertEqual(all.categories.first?.seconds, 60 * 60)
        XCTAssertEqual(all.categories.last?.productivity, .distracting)
    }

    func testCategorySecondsSumToTheTotal() {
        let all = ActivityEngine.summary(sessions, day: day, device: .all)
        XCTAssertEqual(all.categories.reduce(0) { $0 + $1.seconds }, all.totalSeconds)
    }
}
