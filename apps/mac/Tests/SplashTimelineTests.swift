import XCTest
@testable import MyOS

/// The launch sequence. The point of testing choreography is the one promise it
/// has to keep: the splash is never what makes the app feel slow.
final class SplashTimelineTests: XCTestCase {

    func testTheWholeSequenceLandsInsideOneAndAHalfSeconds() {
        XCTAssertLessThanOrEqual(SplashTimeline.settled, 1.5,
                                 "a launch animation nobody can skip has to be over quickly")
    }

    func testTheMarkArrivesBeforeTheName() {
        XCTAssertLessThan(SplashTimeline.mark, SplashTimeline.name)
    }

    func testTheMarkHasSettledBeforeTheNameStarts() {
        // Otherwise the two fades overlap and the screen reads as busy.
        XCTAssertLessThanOrEqual(SplashTimeline.mark + SplashTimeline.markDuration,
                                 SplashTimeline.name + 0.06)
    }

    func testNothingIsOnScreenOnTheFirstFrame() {
        // Green first. A mark already there at t=0 reads as a static image.
        XCTAssertGreaterThan(SplashTimeline.mark, 0.0)
    }
}
