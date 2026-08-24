import XCTest
@testable import MyOS

final class PrefsTests: XCTestCase {
    // MARK: - Fold privacy masking

    func testFoldINRMasksWhenHidden() {
        XCTAssertEqual(foldINR(1234567, hidden: true), "₹ ••••")
        XCTAssertEqual(foldINR(0, hidden: true), "₹ ••••")
    }

    func testFoldINRFormatsIndianGroupingWhenVisible() {
        XCTAssertEqual(foldINR(1234567, hidden: false), "₹12,34,567")
        XCTAssertEqual(foldINR(0, hidden: false), "₹0")
    }

    // MARK: - Launch tab resolution

    func testResolveLaunchReturnsKnownTab() {
        XCTAssertEqual(NavTab.resolveLaunch("fitness"), .fitness)
        XCTAssertEqual(NavTab.resolveLaunch("productivity", allowed: NavTab.iosTabs), .productivity)
    }

    func testResolveLaunchFallsBackToToday() {
        XCTAssertEqual(NavTab.resolveLaunch(nil), .today)
        XCTAssertEqual(NavTab.resolveLaunch("garbage"), .today)
        // events is a valid tab but not available on the iOS bottom bar
        XCTAssertEqual(NavTab.resolveLaunch("events", allowed: NavTab.iosTabs), .today)
    }

    // MARK: - Where the app opens

    /// The store is a singleton over UserDefaults, so put it back afterwards.
    private func withPrefs(_ body: () -> Void) {
        let prefs = PrefsStore.shared
        let launch = prefs.launchTab, last = prefs.lastTab
        let route = prefs.route(for: .notes)
        defer { prefs.launchTab = launch; prefs.lastTab = last; prefs.setRoute(route, for: .notes) }
        body()
    }

    func testOpensWhereYouLeftOffByDefault() {
        withPrefs {
            let prefs = PrefsStore.shared
            prefs.launchTab = nil
            prefs.lastTab = .events
            XCTAssertEqual(prefs.resolveOpeningTab(), .events)
        }
    }

    func testAPinnedTabBeatsResuming() {
        withPrefs {
            let prefs = PrefsStore.shared
            prefs.launchTab = .notes
            prefs.lastTab = .events
            XCTAssertEqual(prefs.resolveOpeningTab(), .notes)
        }
    }

    func testResumingIsClampedToTheTabsAPlatformHas() {
        withPrefs {
            let prefs = PrefsStore.shared
            prefs.launchTab = nil
            prefs.lastTab = .events            // no Events on the iOS bottom bar
            XCTAssertEqual(prefs.resolveOpeningTab(allowed: NavTab.iosTabs), .today)
            prefs.lastTab = .fold              // Fold left the iOS bar too
            XCTAssertEqual(prefs.resolveOpeningTab(allowed: NavTab.iosTabs), .today)
            prefs.lastTab = .productivity
            XCTAssertEqual(prefs.resolveOpeningTab(allowed: NavTab.iosTabs), .productivity)
        }
    }

    // MARK: - Where you were inside a tab

    func testRouteRoundTrips() {
        withPrefs {
            let prefs = PrefsStore.shared
            prefs.setRoute("note-123", for: .notes)
            XCTAssertEqual(prefs.route(for: .notes), "note-123")
        }
    }

    func testRouteClearsOnNilAndOnEmpty() {
        withPrefs {
            let prefs = PrefsStore.shared
            prefs.setRoute("note-123", for: .notes)
            prefs.setRoute(nil, for: .notes)
            XCTAssertNil(prefs.route(for: .notes))
            prefs.setRoute("", for: .notes)
            XCTAssertNil(prefs.route(for: .notes), "an empty id is not a place to go back to")
        }
    }

    func testRoutesAreKeptPerTab() {
        withPrefs {
            let prefs = PrefsStore.shared
            let journal = prefs.route(for: .journal)
            defer { prefs.setRoute(journal, for: .journal) }
            prefs.setRoute("note-1", for: .notes)
            prefs.setRoute("entry-9", for: .journal)
            XCTAssertEqual(prefs.route(for: .notes), "note-1")
            XCTAssertEqual(prefs.route(for: .journal), "entry-9")
        }
    }

    // MARK: - Appearance

    func testSettingsOffersSystemLightAndDark() {
        XCTAssertEqual(AppTheme.all.map(\.name), ["System", "Light", "Dark"])
        XCTAssertEqual(AppTheme.all.count, 3)
    }

    func testRetiredColourThemeIdsMigrateToSystem() {
        // "foldDark" and "midnight" named colour SETS. Since the palette became
        // the system's, an appearance is all that is left to choose, so anyone
        // upgrading lands on System rather than an id that no longer exists.
        XCTAssertEqual(AppTheme.by(id: "foldDark").id, "system")
        XCTAssertEqual(AppTheme.by(id: "midnight").id, "system")
        XCTAssertEqual(AppTheme.by(id: "light").name, "Light")
    }

    func testThemeColorSchemeMatchesAppearance() {
        // nil is the point: it hands the decision back to the OS.
        XCTAssertNil(AppTheme.system.colorScheme)
        XCTAssertEqual(AppTheme.dark.colorScheme, .dark)
        XCTAssertEqual(AppTheme.light.colorScheme, .light)
    }
}
