import XCTest
@testable import MyOS

/// iPhone activity arrives as bare open/close pings from a Shortcuts automation.
/// Turning those into sessions is where it can go wrong, so the shapes that
/// actually occur — a missing close, a double open, a close for something that
/// was never open — are pinned.
final class ActivityInboxTests: XCTestCase {

    private func ping(_ app: String, _ kind: ActivityInbox.Kind, _ h: Int, _ m: Int) -> ActivityInbox.Ping {
        var c = DateComponents()
        c.year = 2026; c.month = 8; c.day = 25; c.hour = h; c.minute = m
        return ActivityInbox.Ping(appName: app, kind: kind,
                                  at: ActivityTime.stamp(Calendar.current.date(from: c)!))
    }

    private func now(_ h: Int, _ m: Int) -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 8; c.day = 25; c.hour = h; c.minute = m
        return Calendar.current.date(from: c)!
    }

    func testAnOpenAndCloseBecomeOneSession() {
        let sessions = ActivityInbox.sessions(
            from: [ping("WhatsApp", .opened, 10, 0), ping("WhatsApp", .closed, 10, 18)],
            now: now(11, 0))

        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].duration, 18 * 60)
        XCTAssertEqual(sessions[0].appName, "WhatsApp")
        XCTAssertEqual(sessions[0].deviceType, .iphone)
        XCTAssertEqual(sessions[0].source, .iosShortcut)
        // Classified, not left as "other" — the insight layer needs the meaning.
        XCTAssertEqual(sessions[0].category, .communication)
    }

    /// iOS foregrounds one app at a time, so opening a second app ends the first
    /// even when its close automation was never set up.
    func testOpeningAnotherAppClosesThePreviousSession() {
        let sessions = ActivityInbox.sessions(
            from: [ping("WhatsApp", .opened, 10, 0), ping("Instagram", .opened, 10, 12)],
            now: now(10, 20))

        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions[0].appName, "WhatsApp")
        XCTAssertEqual(sessions[0].duration, 12 * 60)
        XCTAssertEqual(sessions[1].appName, "Instagram")
        XCTAssertEqual(sessions[1].duration, 8 * 60)
    }

    /// A session with no close must not run to the end of the day. Capping is
    /// the honest answer: we know it started, we do not know it continued.
    func testAnUnterminatedSessionIsCappedNotExtended() {
        let sessions = ActivityInbox.sessions(
            from: [ping("YouTube", .opened, 10, 0)], now: now(18, 0))

        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].duration, ActivityInbox.unterminatedSessionCap)
    }

    func testACloseWithoutAnOpenIsIgnored() {
        XCTAssertTrue(ActivityInbox.sessions(from: [ping("Slack", .closed, 10, 0)], now: now(11, 0)).isEmpty)
    }

    func testAccidentalTapsAreDropped() {
        let sessions = ActivityInbox.sessions(
            from: [ping("Instagram", .opened, 10, 0), ping("Instagram", .closed, 10, 0)],
            now: now(11, 0))
        XCTAssertTrue(sessions.isEmpty)
    }

    func testPingsOutOfOrderAreSortedFirst() {
        let sessions = ActivityInbox.sessions(
            from: [ping("WhatsApp", .closed, 10, 15), ping("WhatsApp", .opened, 10, 0)],
            now: now(11, 0))
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].duration, 15 * 60)
    }

    func testRulesBeatTheCatalogue() {
        let rules = ["app.whatsapp": AppRule(appId: "app.whatsapp", appName: "WhatsApp",
                                             category: .communication, productivity: .distracting)]
        let sessions = ActivityInbox.sessions(
            from: [ping("WhatsApp", .opened, 10, 0), ping("WhatsApp", .closed, 10, 20)],
            rules: rules, now: now(11, 0))
        XCTAssertEqual(sessions[0].productivity, .distracting)
    }
}
