import XCTest
@testable import MyOS

final class VoiceAudioSessionTests: XCTestCase {
    func testFirstEnterActivatesAndLastExitRestores() {
        var s = AudioSessionState()
        XCTAssertTrue(s.enter(), "first enter must actually configure the session")
        XCTAssertTrue(s.exit(), "last exit must actually restore it")
    }

    func testNestedEntersOnlyConfigureOnce() {
        var s = AudioSessionState()
        XCTAssertTrue(s.enter())
        XCTAssertFalse(s.enter(), "already configured — must not reconfigure mid-call")
        XCTAssertFalse(s.exit(), "still one holder left — must not restore yet")
        XCTAssertTrue(s.exit(), "now the last holder is gone")
    }

    func testUnbalancedExitIsHarmless() {
        var s = AudioSessionState()
        XCTAssertFalse(s.exit(), "exit without enter must not claim to restore")
        XCTAssertEqual(s.depth, 0, "depth must never go negative")
    }

    func testDepthNeverGoesNegativeAcrossManyExits() {
        var s = AudioSessionState()
        _ = s.enter()
        _ = s.exit()
        _ = s.exit()
        _ = s.exit()
        XCTAssertEqual(s.depth, 0)
        XCTAssertTrue(s.enter(), "a later call must still be able to configure")
    }
}
