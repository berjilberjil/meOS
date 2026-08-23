import XCTest
@testable import MyOS

/// The launch sequence. The point of testing a piece of choreography is the one
/// promise it has to keep: the splash is never what makes the app feel slow.
final class SplashTimelineTests: XCTestCase {

    func testTheWholeSequenceLandsInsideOneAndAHalfSeconds() {
        XCTAssertLessThanOrEqual(SplashTimeline.settled, 1.5,
                                 "a launch animation nobody can skip has to be over quickly")
    }

    func testBeatsRunInTheOrderTheyAreRead() {
        // A point, then the form it opens into, then breath, then her name.
        XCTAssertLessThan(SplashTimeline.point, SplashTimeline.form)
        XCTAssertLessThan(SplashTimeline.form, SplashTimeline.breathe)
        XCTAssertLessThan(SplashTimeline.breathe, SplashTimeline.word)
        XCTAssertLessThan(SplashTimeline.word, SplashTimeline.status)
    }

    func testTheFormHasFinishedArrivingBeforeItStartsBreathing() {
        // Otherwise the breath animation and the reveal fight over the same layer.
        XCTAssertLessThanOrEqual(SplashTimeline.form + SplashTimeline.formDuration,
                                 SplashTimeline.breathe + 0.001)
    }

    func testNothingStartsOnTheFirstFrame() {
        // Black first. A form already on screen at t=0 reads as a static image.
        XCTAssertGreaterThan(SplashTimeline.point, 0.1)
    }
}
