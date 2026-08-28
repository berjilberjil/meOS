import XCTest
@testable import MyOS

/// The weight dial's maths.
///
/// The dial is the one control in MyOS you use by *feel* — thumb on the glass,
/// eyes on the number, one tick of haptics per 50 g. Everything that decides
/// what a turn is worth lives here rather than in the view, because a dial that
/// counts a full reverse revolution when your thumb crosses nine o'clock is not
/// something you notice in a screenshot.
final class WeightDialTests: XCTestCase {

    // MARK: - Steps

    func testTheTwoStepsAreWhatWasAskedFor() {
        XCTAssertEqual(WeightDial.fineStep, 0.05, accuracy: 1e-9)    // 50 g — one detent
        XCTAssertEqual(WeightDial.coarseStep, 0.5, accuracy: 1e-9)   // one tap of a cap
    }

    func testOneDetentMovesFiftyGrams() {
        XCTAssertEqual(WeightDial.stepped(72, detents: 1), 72.05, accuracy: 1e-9)
        XCTAssertEqual(WeightDial.stepped(72, detents: -1), 71.95, accuracy: 1e-9)
    }

    func testTappingACapMovesHalfAKilo() {
        XCTAssertEqual(WeightDial.nudged(72.35, by: WeightDial.coarseStep), 72.85, accuracy: 1e-9)
        XCTAssertEqual(WeightDial.nudged(72.35, by: -WeightDial.coarseStep), 71.85, accuracy: 1e-9)
    }

    /// Twenty detents of 0.05 is 1.0 — but only if the float drift is snapped
    /// away each time. Accumulated naively this lands on 72.99999999999999 and
    /// the readout says 72.99.
    func testAThousandDetentsDoNotDrift() {
        var kg = 72.0
        for _ in 0..<20 { kg = WeightDial.stepped(kg, detents: 1) }
        XCTAssertEqual(kg, 73.0, accuracy: 1e-9)
        XCTAssertEqual(WeightDial.format(kg), "73")
    }

    // MARK: - Clamping

    func testWeightStaysInAHumanRange() {
        XCTAssertEqual(WeightDial.clamp(5), WeightDial.minKg)
        XCTAssertEqual(WeightDial.clamp(5_000), WeightDial.maxKg)
        XCTAssertEqual(WeightDial.clamp(72.35), 72.35, accuracy: 1e-9)
    }

    /// Spinning down into the floor and back out again must come straight back
    /// out. If the rotation banked those detents instead of the value absorbing
    /// them, you would turn the dial for half a minute before the number moved.
    func testTheFloorDoesNotBankRotation() {
        var kg = WeightDial.minKg
        for _ in 0..<100 { kg = WeightDial.stepped(kg, detents: -1) }
        XCTAssertEqual(kg, WeightDial.minKg)
        kg = WeightDial.stepped(kg, detents: 1)
        XCTAssertEqual(kg, WeightDial.minKg + WeightDial.fineStep, accuracy: 1e-9)
    }

    func testNonsenseNeverBecomesAWeight() {
        XCTAssertEqual(WeightDial.clamp(.nan), WeightDial.fallbackKg)
        XCTAssertEqual(WeightDial.clamp(.infinity), WeightDial.maxKg)
        XCTAssertEqual(WeightDial.clamp(-.infinity), WeightDial.minKg)
    }

    // MARK: - Where the first number comes from

    func testTodaysLoggedWeightWinsOverEverything() {
        XCTAssertEqual(WeightDial.seed(logged: 71.5, latest: 80, target: 65), 71.5, accuracy: 1e-9)
    }

    func testOtherwiseTheLastDayYouLogged() {
        XCTAssertEqual(WeightDial.seed(logged: nil, latest: 80, target: 65), 80, accuracy: 1e-9)
    }

    /// Nothing ever logged: the goal weight is the only number the app holds
    /// about your body, so the dial opens there rather than at a stranger's 70.
    func testOtherwiseTheGoalWeight() {
        XCTAssertEqual(WeightDial.seed(logged: nil, latest: nil, target: 65), 65, accuracy: 1e-9)
    }

    func testAndOnlyThenAFallback() {
        XCTAssertEqual(WeightDial.seed(logged: nil, latest: nil, target: nil), WeightDial.fallbackKg)
    }

    /// A zero or an infinity that reached state from sync is not a weight.
    func testASeedThatIsNotAWeightIsSkipped() {
        XCTAssertEqual(WeightDial.seed(logged: 0, latest: 80, target: 65), 80, accuracy: 1e-9)
        XCTAssertEqual(WeightDial.seed(logged: .infinity, latest: 80, target: 65), 80, accuracy: 1e-9)
        XCTAssertEqual(WeightDial.seed(logged: .nan, latest: nil, target: nil), WeightDial.fallbackKg)
    }

    // MARK: - The readout

    func testTheNumberReadsTheWayYouWouldSayIt() {
        XCTAssertEqual(WeightDial.format(73), "73")
        XCTAssertEqual(WeightDial.format(72.5), "72.5")
        XCTAssertEqual(WeightDial.format(72.35), "72.35")
        XCTAssertEqual(WeightDial.format(72.30), "72.3")
    }

    func testTheReadoutNeverCrashesOnGarbage() {
        XCTAssertEqual(WeightDial.format(.nan), WeightDial.format(WeightDial.fallbackKg))
        XCTAssertEqual(WeightDial.format(1e300), WeightDial.format(WeightDial.maxKg))
    }

    // MARK: - The delta line

    func testTheDeltaSaysWhichWayYouWent() {
        XCTAssertEqual(WeightDial.deltaLabel(72.35, from: 72), "+0.35")
        XCTAssertEqual(WeightDial.deltaLabel(71.5, from: 72), "\u{2212}0.5")
    }

    func testNoDeltaWhenThereIsNothingToCompareOrNothingMoved() {
        XCTAssertNil(WeightDial.deltaLabel(72, from: nil))
        XCTAssertNil(WeightDial.deltaLabel(72, from: 72))
    }

    // MARK: - Turning it

    /// Fifteen degrees is one detent, so a quarter turn is six of them and a
    /// full revolution is 1.2 kg.
    func testAQuarterTurnIsSixDetents() {
        var r = DialRotation()
        _ = r.update(radians: 0)
        XCTAssertEqual(r.update(radians: .pi / 2), 6)
    }

    func testAFullRevolutionIsOnePointTwoKilos() {
        var r = DialRotation()
        _ = r.update(radians: 0)
        var detents = 0
        // Fed in eighths, because a real finger arrives in small deltas.
        for i in 1...8 { detents += r.update(radians: Double(i) * .pi / 4) }
        XCTAssertEqual(detents, 24)
        XCTAssertEqual(Double(detents) * WeightDial.fineStep, 1.2, accuracy: 1e-9)
    }

    /// The bug this type exists to prevent. `atan2` wraps from +π to −π at nine
    /// o'clock; a naive difference reads that hair of movement as a full turn
    /// backwards, so the weight jumps 1.2 kg the wrong way mid-spin.
    func testCrossingTheSeamIsNotAReverseRevolution() {
        var r = DialRotation()
        _ = r.update(radians: .pi - 0.01)
        let crossed = r.update(radians: -.pi + 0.01)
        XCTAssertEqual(crossed, 0, "a 0.02 rad step across the seam is not a detent, let alone 24")
    }

    func testTurningBackTakesTheSameDetentsAway() {
        var r = DialRotation()
        _ = r.update(radians: 0)
        XCTAssertEqual(r.update(radians: .pi / 2), 6)
        XCTAssertEqual(r.update(radians: 0), -6)
    }

    /// Partial rotation is kept, not thrown away: three separate nudges of
    /// nine degrees are 27 degrees, which is one detent — not zero.
    func testPartialTurnsAccumulate() {
        var r = DialRotation()
        let nine = 9 * Double.pi / 180
        _ = r.update(radians: 0)
        XCTAssertEqual(r.update(radians: nine), 0)
        XCTAssertEqual(r.update(radians: nine * 2), 1)
        XCTAssertEqual(r.update(radians: nine * 3), 0)
        XCTAssertEqual(r.update(radians: nine * 4), 1)
    }

    func testTheFirstTouchNeverMovesTheNumber() {
        var r = DialRotation()
        XCTAssertEqual(r.update(radians: 2.7), 0, "putting a thumb down is not a turn")
    }

    func testLiftingAndTouchingDownElsewhereIsNotATurn() {
        var r = DialRotation()
        _ = r.update(radians: 0)
        XCTAssertEqual(r.update(radians: .pi / 2), 6)
        r.reset()
        XCTAssertEqual(r.update(radians: -2.5), 0)
    }
}
