import XCTest
@testable import meOS

/// The Accessibility pass, and what it changes about a day.
///
/// Every assertion here is about one claim: a browser is a room, not an
/// activity. Before this, two hours of Chrome was two hours of "research,
/// neutral" whatever was in it — the single biggest way the numbers lied.
final class ActivityPlaceTests: XCTestCase {

    private let day = "2026-08-26"

    private func stamp(_ hour: Int, _ minute: Int) -> String {
        var c = DateComponents()
        c.year = 2026; c.month = 8; c.day = 26; c.hour = hour; c.minute = minute; c.second = 0
        return ActivityTime.stamp(Calendar.current.date(from: c)!)
    }

    private func event(_ app: String, id: String = "com.google.Chrome",
                       site: String? = nil, title: String? = nil,
                       at hour: Int, _ minute: Int = 0, minutes: Int,
                       device: DeviceType = .mac) -> ActivityEvent {
        let classified = ActivityCatalog.classify(appId: id, appName: app, site: site)
        let endTotal = hour * 60 + minute + minutes
        return ActivityEvent(deviceId: "d1", deviceType: device, platform: "test",
                             appId: id, appName: app, category: classified.category,
                             startedAt: stamp(hour, minute),
                             endedAt: stamp(endTotal / 60, endTotal % 60),
                             duration: minutes * 60, productivity: classified.productivity,
                             source: .macFrontmost, site: site, title: title)
    }

    // MARK: - Address bars

    func testAddressBarBecomesABareHost() {
        XCTAssertEqual(WindowSense.host(fromAddressBar: "youtube.com/watch?v=abc"), "youtube.com")
        XCTAssertEqual(WindowSense.host(fromAddressBar: "https://www.github.com/berjilberjil/meOS"), "github.com")
        XCTAssertEqual(WindowSense.host(fromAddressBar: "HTTPS://Mail.Google.com/mail/u/0"), "mail.google.com")
        XCTAssertEqual(WindowSense.host(fromAddressBar: "localhost:5173/app"), nil)
    }

    /// The address bar is a text field, and half the time it holds a search
    /// being typed. A half-typed phrase stored as a "site" is worse than no
    /// site, so anything ambiguous is refused.
    func testHalfTypedSearchesAreNotSites() {
        XCTAssertNil(WindowSense.host(fromAddressBar: "how to fix ax permission"))
        XCTAssertNil(WindowSense.host(fromAddressBar: "youtub"))
        XCTAssertNil(WindowSense.host(fromAddressBar: ""))
        XCTAssertNil(WindowSense.host(fromAddressBar: "chrome://settings"))
        XCTAssertNil(WindowSense.host(fromAddressBar: "about:blank"))
    }

    func testTitleLosesTheAppsOwnName() {
        XCTAssertEqual(WindowSense.cleanTitle("Revamp Finance Page - Google Chrome – Berjil",
                                              appName: "Google Chrome"), "Revamp Finance Page")
        XCTAssertEqual(WindowSense.cleanTitle("Inbox (3) — Mail", appName: "Mail"), "Inbox (3)")
        // A title that is only the app's name says nothing the row does not.
        XCTAssertNil(WindowSense.cleanTitle("meOS", appName: "meOS"))
        XCTAssertNil(WindowSense.cleanTitle("   ", appName: "Finder"))
    }

    /// Typing a search into the address bar must not read as leaving the site.
    func testTypingInTheAddressBarHoldsTheSiteRatherThanClearingIt() {
        let onSite = WindowContext(title: "berjilberjil/meOS", site: "github.com")
        let typing = WindowContext(title: "berjilberjil/meOS", site: nil)

        let held = WindowSense.settling(typing, after: onSite, isBrowser: true)
        XCTAssertEqual(held.site, "github.com")

        // A real navigation still lands.
        let moved = WindowSense.settling(WindowContext(title: "some reel", site: "youtube.com"),
                                         after: onSite, isBrowser: true)
        XCTAssertEqual(moved.site, "youtube.com")

        // And nothing is held for an app that never had a site to begin with.
        let editor = WindowSense.settling(WindowContext(title: "ActivityEngine.swift", site: nil),
                                          after: onSite, isBrowser: false)
        XCTAssertNil(editor.site)
    }

    // MARK: - Classification

    func testSiteBeatsTheBrowserItWasOpenedIn() {
        let leak = ActivityCatalog.classify(appId: "com.google.Chrome", appName: "Google Chrome",
                                            site: "youtube.com")
        XCTAssertEqual(leak.productivity, .distracting)
        let work = ActivityCatalog.classify(appId: "com.google.Chrome", appName: "Google Chrome",
                                            site: "github.com")
        XCTAssertEqual(work.category, .development)
        XCTAssertEqual(work.productivity, .productive)
    }

    /// A domain nobody wrote a seed for must not inherit the browser's "research,
    /// neutral" — that is how every unknown site quietly reads as work.
    func testUnknownSiteDoesNotInheritTheBrowser() {
        let unknown = ActivityCatalog.classify(appId: "com.google.Chrome", appName: "Google Chrome",
                                               site: "some-random-blog.xyz")
        XCTAssertEqual(unknown.category, .other)
        XCTAssertEqual(unknown.productivity, .neutral)
    }

    func testSubdomainFallsBackToItsParent() {
        XCTAssertEqual(ActivityCatalog.matchSite("gist.github.com")?.category, .development)
        XCTAssertEqual(ActivityCatalog.matchSite("m.youtube.com")?.productivity, .distracting)
    }

    /// Berjil's own rule wins, and it wins on the *row* — a rule on youtube.com
    /// must not repaint the rest of the browser.
    func testRuleOnASiteBeatsTheSeedAndStaysOnThatSite() {
        let rules = ["web.youtube.com": AppRule(appId: "web.youtube.com", appName: "youtube.com",
                                                category: .contentCreation, productivity: .productive)]
        let tube = ActivityCatalog.classify(appId: "com.google.Chrome", appName: "Google Chrome",
                                            site: "youtube.com", rules: rules)
        XCTAssertEqual(tube.productivity, .productive)
        let hub = ActivityCatalog.classify(appId: "com.google.Chrome", appName: "Google Chrome",
                                           site: "github.com", rules: rules)
        XCTAssertEqual(hub.category, .development)
    }

    // MARK: - The breakdown

    func testBrowserTimeSplitsIntoSitesNotOneChromeBlock() {
        let events = [
            event("Google Chrome", site: "github.com", title: "berjilberjil/meOS", at: 10, minutes: 60),
            event("Google Chrome", site: "youtube.com", title: "some reel", at: 11, minutes: 40),
            event("Xcode", id: "com.apple.dt.Xcode", title: "ActivityEngine.swift", at: 12, minutes: 30),
        ]
        let s = ActivityEngine.summary(events, day: day)

        XCTAssertEqual(s.apps.map(\.appName), ["github.com", "youtube.com", "Xcode"])
        XCTAssertNil(s.apps.first { $0.appName == "Google Chrome" })
        // The worth split is the point: an hour of GitHub is not the same hour
        // as forty minutes of YouTube, and "Chrome 1h40m" said they were.
        XCTAssertEqual(s.seconds(.productive), 60 * 60 + 30 * 60)
        XCTAssertEqual(s.seconds(.distracting), 40 * 60)
    }

    func testRowsCarryTheBrowsersIconAndTheirWindowTitles() {
        let events = [
            event("Google Chrome", site: "github.com", title: "berjilberjil/meOS", at: 10, minutes: 40),
            event("Google Chrome", site: "github.com", title: "anthropics/claude", at: 11, minutes: 20),
        ]
        let row = ActivityEngine.summary(events, day: day).apps.first
        XCTAssertEqual(row?.appId, "web.github.com")
        XCTAssertEqual(row?.iconId, "com.google.Chrome")
        XCTAssertEqual(row?.seconds, 60 * 60)
        XCTAssertEqual(row?.details.map(\.title), ["berjilberjil/meOS", "anthropics/claude"])
        XCTAssertEqual(row?.details.first?.seconds, 40 * 60)
    }

    /// Switching tabs inside one browser window is a context switch. Counting it
    /// as "still in Chrome" is how a day of tab-flipping reads as focus.
    func testSwitchingSiteCountsAsASwitch() {
        let events = [
            event("Google Chrome", site: "github.com", at: 10, minutes: 20),
            event("Google Chrome", site: "youtube.com", at: 10, 20, minutes: 20),
            event("Google Chrome", site: "github.com", at: 10, 40, minutes: 20),
        ]
        XCTAssertEqual(ActivityEngine.summary(events, day: day).switches, 2)
    }

    // MARK: - The phone comes out

    func testPhoneSessionsAreDroppedRatherThanRelabelled() {
        var doc = ActivityDoc()
        doc.events = [
            event("Xcode", id: "com.apple.dt.Xcode", at: 10, minutes: 60),
            event("meOS", id: "com.berjil.myos", at: 11, minutes: 16, device: .iphone),
        ]
        doc.devices["p1"] = ActivityDevice(deviceId: "p1", deviceType: .iphone,
                                           name: "iPhone", lastSeen: stamp(11, 0))

        XCTAssertEqual(doc.dropPhoneSessions(), 1)
        XCTAssertEqual(doc.events.map(\.appName), ["Xcode"])
        XCTAssertTrue(doc.devices.isEmpty)
        // And it stays dropped — running it again is a no-op, not a second bite.
        XCTAssertEqual(doc.dropPhoneSessions(), 0)
    }

    /// A compacted day has no per-device app detail, so the phone's share comes
    /// off the totals proportionally rather than being left to count itself.
    func testCompactedDaysLoseThePhonesShareToo() {
        var doc = ActivityDoc()
        doc.days["2026-08-10"] = ActivityDayRollup(
            day: "2026-08-10", totalSeconds: 100 * 60,
            byDevice: ["mac": 80 * 60, "iphone": 20 * 60],
            byProductivity: ["productive": 50 * 60, "neutral": 50 * 60])

        doc.dropPhoneSessions()
        let rollup = doc.days["2026-08-10"]
        XCTAssertEqual(rollup?.totalSeconds, 80 * 60)
        XCTAssertNil(rollup?.byDevice["iphone"])
        XCTAssertEqual(rollup?.seconds(.productive), 40 * 60)
        XCTAssertEqual((rollup?.byProductivity.values.reduce(0, +) ?? 0), rollup?.totalSeconds)
    }

    // MARK: - What the Mac is doing, read on the phone

    func testLiveNoteGoesStaleRatherThanLying() {
        let note = ActivityLive(appId: "com.apple.dt.Xcode", appName: "Xcode", site: nil,
                                title: "ActivityEngine.swift", category: .development,
                                productivity: .productive, deviceName: "Berjil's MacBook",
                                startedAt: stamp(10, 0), updatedAt: stamp(10, 5))
        let soon = ActivityTime.date(stamp(10, 8))!
        let later = ActivityTime.date(stamp(10, 30))!
        XCTAssertTrue(note.isFresh(now: soon))
        XCTAssertFalse(note.isFresh(now: later))
    }

    func testLiveNoteReadsAsASessionOfTheRightLength() {
        let note = ActivityLive(appId: "com.google.Chrome", appName: "Google Chrome",
                                site: "youtube.com", title: "some reel", category: .entertainment,
                                productivity: .distracting, deviceName: "Berjil's MacBook",
                                startedAt: stamp(10, 0), updatedAt: stamp(10, 4))
        let live = note.asEvent(now: ActivityTime.date(stamp(10, 12))!)
        XCTAssertEqual(live?.duration, 12 * 60)
        XCTAssertEqual(live?.groupName, "youtube.com")

        // And it reaches the card as the place, not as the browser.
        let focus = ActivityInsights.focusNow(current: live, todos: [], device: "Berjil's MacBook")
        XCTAssertEqual(focus?.appName, "youtube.com")
        XCTAssertEqual(focus?.detail, "some reel")
        XCTAssertEqual(focus?.device, "Berjil's MacBook")
    }

    /// The newer note wins a merge whichever copy it arrives in, or the phone
    /// would flicker between "focusing now" and nothing on every sync.
    func testNewerLiveNoteSurvivesTheMerge() {
        var older = ActivityDoc()
        older.live = ActivityLive(appId: "a", appName: "A", site: nil, title: nil,
                                  category: .other, productivity: .neutral, deviceName: "Mac",
                                  startedAt: stamp(10, 0), updatedAt: stamp(10, 0))
        var newer = ActivityDoc()
        newer.live = ActivityLive(appId: "b", appName: "B", site: nil, title: nil,
                                  category: .other, productivity: .neutral, deviceName: "Mac",
                                  startedAt: stamp(10, 5), updatedAt: stamp(10, 5))

        XCTAssertEqual(older.merged(with: newer).live?.appId, "b")
        XCTAssertEqual(newer.merged(with: older).live?.appId, "b")
    }

    // MARK: - Storage

    /// Two optional fields on every session, in a blob that syncs whole. Null is
    /// not free at this volume.
    func testDetailIsOmittedRatherThanEncodedAsNull() throws {
        let bare = event("Finder", id: "com.apple.finder", at: 10, minutes: 5)
        let json = String(data: try JSONEncoder().encode(bare), encoding: .utf8) ?? ""
        XCTAssertFalse(json.contains("site"))
        XCTAssertFalse(json.contains("title"))
        XCTAssertFalse(json.contains("null"))
    }

    func testOlderSessionsWithoutDetailStillDecode() throws {
        let legacy = """
        {"id":"1","deviceId":"d","deviceType":"mac","platform":"macOS","appId":"com.apple.dt.Xcode",
         "appName":"Xcode","category":"development","startedAt":"\(stamp(10, 0))",
         "endedAt":"\(stamp(11, 0))","duration":3600,"productivity":"productive","source":"macFrontmost"}
        """
        let decoded = try JSONDecoder().decode(ActivityEvent.self, from: Data(legacy.utf8))
        XCTAssertNil(decoded.site)
        XCTAssertEqual(decoded.groupId, "com.apple.dt.Xcode")
        XCTAssertEqual(decoded.groupName, "Xcode")
    }
}
