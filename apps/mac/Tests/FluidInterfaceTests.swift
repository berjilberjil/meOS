import XCTest
@testable import meOS

/// Apple's fluid-interface maths, as pure functions in `Fluid` /
/// `FluidRubberband` / `VelocityTracker` / `SlideConfirmState`. These pin the
/// doc rules: exponential-decay projection (§6), velocity-sign commit (§10),
/// progressive boundary resistance (§9), and the spring-parameter defaults (§4).
final class FluidInterfaceTests: XCTestCase {

    // MARK: - Projection (§6)

    /// Apple's exact function, not the physics-textbook v²/(2·decel):
    /// 1000pt/s at d=0.998 travels ~499pt.
    func testProjectMatchesAppleExponentialDecay() {
        XCTAssertEqual(Fluid.project(initialVelocity: 1000), 499, accuracy: 1)
        XCTAssertEqual(Fluid.project(initialVelocity: 0), 0, accuracy: 0.001)
        XCTAssertEqual(Fluid.project(initialVelocity: -500), -249.5, accuracy: 1)
    }

    func testSnappierRateTravelsLessFar() {
        let normal = Fluid.project(initialVelocity: 1000, decelerationRate: 0.998)
        let snappy = Fluid.project(initialVelocity: 1000, decelerationRate: 0.99)
        XCTAssertLessThan(snappy, normal)
    }

    func testProjectedEndpointAddsToCurrent() {
        XCTAssertEqual(Fluid.projectedEndpoint(current: 50, velocity: 1000), 549, accuracy: 1)
    }

    func testSnapTargetComesFromProjectionNotReleasePoint() {
        // Released at 90 but heading fast toward 250: the flick throws it.
        let projected = Fluid.projectedEndpoint(current: 90, velocity: 2000)
        XCTAssertEqual(Fluid.nearestSnap(projected: projected, snaps: [0, 100, 250]), 250)
        // Parked at 90 with no velocity: stays.
        XCTAssertEqual(Fluid.nearestSnap(projected: 90, snaps: [0, 100, 250]), 100)
    }

    func testRelativeVelocityGuardsZeroDistance() {
        XCTAssertEqual(Fluid.relativeVelocity(gestureVelocity: 50, current: 50, target: 150), 0.5, accuracy: 0.001)
        XCTAssertEqual(Fluid.relativeVelocity(gestureVelocity: 50, current: 150, target: 150), 0, accuracy: 0.001)
    }

    // MARK: - Commit by velocity sign (§10)

    func testSlowDragUsesPosition() {
        XCTAssertTrue(Fluid.shouldCommit(progress: 0.9, threshold: 0.72, velocity: 0))
        XCTAssertFalse(Fluid.shouldCommit(progress: 0.5, threshold: 0.72, velocity: 0))
    }

    func testFlingTowardCommitsFromBelowThreshold() {
        XCTAssertTrue(Fluid.shouldCommit(progress: 0.5, threshold: 0.72, velocity: 800))
    }

    func testFlingBackReversesFromAboveThreshold() {
        XCTAssertFalse(Fluid.shouldCommit(progress: 0.9, threshold: 0.72, velocity: -800))
    }

    // MARK: - Rubber-banding (§9)

    func testNoOvershootMeansNoResistance() {
        XCTAssertEqual(FluidRubberband.apply(overshoot: 0, dimension: 300), 0)
    }

    func testResistanceGrowsProgressively() {
        let small = FluidRubberband.apply(overshoot: 20, dimension: 300)
        let large = FluidRubberband.apply(overshoot: 200, dimension: 300)
        // Both resist (less than raw) but further push still moves further.
        XCTAssertLessThan(small, 20)
        XCTAssertLessThan(large, 200)
        XCTAssertLessThan(small, large)
        // Damping ratio increases with distance: the large overshoot keeps a
        // smaller fraction of its raw value.
        XCTAssertLessThan(large / 200, small / 20)
    }

    func testRubberbandIsSymmetric() {
        XCTAssertEqual(FluidRubberband.apply(overshoot: -60, dimension: 300),
                       -FluidRubberband.apply(overshoot: 60, dimension: 300),
                       accuracy: 0.001)
    }

    func testClampLeavesInteriorAlone() {
        XCTAssertEqual(FluidRubberband.clamp(150, travel: 300), 150, accuracy: 0.001)
        XCTAssertEqual(FluidRubberband.clamp(0, travel: 300), 0, accuracy: 0.001)
        XCTAssertEqual(FluidRubberband.clamp(300, travel: 300), 300, accuracy: 0.001)
    }

    func testClampSoftensBothEnds() {
        XCTAssertLessThan(FluidRubberband.clamp(-100, travel: 300), 0)
        XCTAssertGreaterThan(FluidRubberband.clamp(-100, travel: 300), -100)
        XCTAssertGreaterThan(FluidRubberband.clamp(400, travel: 300), 300)
        XCTAssertLessThan(FluidRubberband.clamp(400, travel: 300), 400)
    }

    // MARK: - Velocity history (§2, §5)

    func testEmptyTrackerHasNoVelocity() {
        XCTAssertEqual(VelocityTracker().velocity, 0)
    }

    func testSingleSampleHasNoVelocity() {
        var t = VelocityTracker()
        t.append(10, at: 1000)
        XCTAssertEqual(t.velocity, 0)
    }

    func testVelocityIsPointsPerSecond() {
        var t = VelocityTracker()
        t.append(0, at: 1000)
        t.append(100, at: 1000.1)
        XCTAssertEqual(t.velocity, 1000, accuracy: 1)
    }

    func testStaleSamplesFallOutOfTheWindow() {
        var t = VelocityTracker()
        t.append(0, at: 1000)
        t.append(1000, at: 1001)   // a second ago — ancient history
        t.append(1010, at: 1001.05)
        // Only the recent pair counts: 10pt in 0.05s = 200pt/s, not ~1000.
        XCTAssertEqual(t.velocity, 200, accuracy: 5)
    }

    // MARK: - Slide confirm inherits velocity (§5)

    func testFlingCommitsSlideBelowThreshold() {
        var s = SlideConfirmState(threshold: 0.85)
        s.drag(translationX: 50, width: 100) // 0.5 < 0.85
        XCTAssertTrue(s.end(velocity: 800))
        XCTAssertTrue(s.confirmed)
    }

    func testFlingBackReversesSlideAboveThreshold() {
        var s = SlideConfirmState(threshold: 0.85)
        s.drag(translationX: 90, width: 100) // 0.9 >= 0.85
        XCTAssertFalse(s.end(velocity: -800))
        XCTAssertFalse(s.confirmed)
        XCTAssertEqual(s.progress, 0, accuracy: 0.001)
    }

    func testSlowSlideKeepsPositionSemantics() {
        var s = SlideConfirmState(threshold: 0.85)
        s.drag(translationX: 90, width: 100)
        XCTAssertTrue(s.end(velocity: 0))
    }

    // MARK: - Spring + type defaults (§4, §15)

    func testDefaultSpringIsCriticallyDamped() {
        XCTAssertEqual(FluidSpring.ui.damping, 1.0, accuracy: 0.001)
        XCTAssertEqual(FluidSpring.pop.damping, 1.0, accuracy: 0.001)
    }

    func testMomentumSpringCarriesBounce() {
        XCTAssertEqual(FluidSpring.momentum.damping, 0.8, accuracy: 0.001)
        XCTAssertEqual(FluidSpring.sheet.damping, 0.8, accuracy: 0.001)
    }

    func testTrackingIsSizeSpecific() {
        XCTAssertLessThan(FluidType.displayTracking, 0)   // large: tightened
        XCTAssertGreaterThan(FluidType.sectionTracking, 0) // small caps: opened
        XCTAssertEqual(FluidType.bodyTracking, 0)          // body: near zero
        XCTAssertLessThan(FluidType.displayLeading, FluidType.bodyLeading) // tight up top
    }
}
