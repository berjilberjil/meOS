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
        XCTAssertEqual(NavTab.resolveLaunch("fold", allowed: NavTab.iosTabs), .fold)
    }

    func testResolveLaunchFallsBackToToday() {
        XCTAssertEqual(NavTab.resolveLaunch(nil), .today)
        XCTAssertEqual(NavTab.resolveLaunch("garbage"), .today)
        // events is a valid tab but not available on the iOS bottom bar
        XCTAssertEqual(NavTab.resolveLaunch("events", allowed: NavTab.iosTabs), .today)
    }
}
