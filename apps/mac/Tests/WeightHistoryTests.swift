import XCTest
@testable import MyOS

/// The weight chart draws something plausible from almost any input, so
/// the window and the scale are pinned here rather than eyeballed.
@MainActor
final class WeightHistoryTests: XCTestCase {

    private let today = "2026-08-29"

    private func fitness(_ pairs: [(String, Double?)]) -> [String: FitnessDay] {
        var out: [String: FitnessDay] = [:]
        for (day, kg) in pairs {
            var d = FitnessDay()
            d.weightKg = kg
            out[day] = d
        }
        return out
    }

    // MARK: area baseline

    /// The bug this pins: the area fill used to run out of the bottom of the card.
    ///
    /// `AreaMark` with only a `y` fills down to a baseline of zero. Nothing on
    /// this chart is anywhere near zero — a weight window is 76 to 81 — and
    /// Charts does not clip marks to the plot area, so the gradient painted
    /// down the page over whatever was below it. The fill has to start at the
    /// floor of the window, and the floor is never zero for real weigh-ins.
    func testAreaBaselineIsTheWindowFloorAndNotZero() {
        let f = fitness([("2026-08-20", 80), ("2026-08-25", 78), ("2026-08-27", 79)])
        let pts = WeightHistory.series(f, range: .all, today: today)
        let window = WeightHistory.domain(pts, target: nil)
        XCTAssertEqual(window.lowerBound, 77.5, accuracy: 0.0001)   // 78 − 0.5 floor pad
        XCTAssertGreaterThan(window.lowerBound, 70,
                             "an area starting here would paint far below the plot")
    }

    /// A goal well under the data drags the floor down — but only to the goal,
    /// never to zero.
    func testAreaBaselineFollowsAGoalBelowTheData() {
        let f = fitness([("2026-08-20", 80), ("2026-08-25", 79)])
        let pts = WeightHistory.series(f, range: .all, today: today)
        let window = WeightHistory.domain(pts, target: 74)
        XCTAssertEqual(window.lowerBound, 74 - 0.6, accuracy: 0.0001)   // pad = (80−74)*0.1
        XCTAssertGreaterThan(window.lowerBound, 0)
    }

    // MARK: series

    func testSeriesIsOldestFirst() {
        let f = fitness([("2026-08-20", 80), ("2026-08-10", 82), ("2026-08-25", 79)])
        let s = WeightHistory.series(f, range: .all, today: today)
        XCTAssertEqual(s.map(\.day), ["2026-08-10", "2026-08-20", "2026-08-25"])
        XCTAssertEqual(s.map(\.kg), [82, 80, 79])
    }

    func testSeriesSkipsDaysWithNoWeighIn() {
        let f = fitness([("2026-08-20", 80), ("2026-08-21", nil), ("2026-08-22", 79)])
        XCTAssertEqual(WeightHistory.series(f, range: .all, today: today).count, 2)
    }

    /// A cleared weight was written as 0 by older paths. Plotted, it
    /// drags the y-axis to the floor and flattens every real reading.
    func testSeriesTreatsZeroAsNotLogged() {
        let f = fitness([("2026-08-20", 80), ("2026-08-21", 0), ("2026-08-22", 79)])
        let s = WeightHistory.series(f, range: .all, today: today)
        XCTAssertEqual(s.map(\.kg), [80, 79])
    }

    func testRangeCutoffIsInclusiveOfTheBoundaryDay() {
        // 30 days back from 2026-08-29 is 2026-07-30.
        let f = fitness([("2026-07-29", 85), ("2026-07-30", 84), ("2026-08-29", 80)])
        let s = WeightHistory.series(f, range: .month, today: today)
        XCTAssertEqual(s.map(\.day), ["2026-07-30", "2026-08-29"],
                       "the boundary day itself is inside the window")
    }

    func testAllRangeKeepsEverythingHoweverOld() {
        let f = fitness([("2019-01-01", 95), ("2026-08-29", 80)])
        XCTAssertEqual(WeightHistory.series(f, range: .all, today: today).count, 2)
    }

    // MARK: summary

    func testSummaryChangeIsNewestMinusOldest() {
        let f = fitness([("2026-08-01", 84), ("2026-08-15", 86), ("2026-08-29", 80)])
        let s = WeightHistory.summary(WeightHistory.series(f, range: .all, today: today))
        XCTAssertEqual(s?.change, -4, "lost four since the start of the window")
        XCTAssertEqual(s?.lightest, 80)
        XCTAssertEqual(s?.heaviest, 86, "the peak in the middle still counts")
        XCTAssertEqual(s?.latest, 80)
        XCTAssertEqual(s?.count, 3)
    }

    func testSummaryOfASingleWeighInHasNoChange() {
        let f = fitness([("2026-08-29", 80)])
        let s = WeightHistory.summary(WeightHistory.series(f, range: .all, today: today))
        XCTAssertEqual(s?.change, 0)
        XCTAssertEqual(s?.count, 1)
    }

    func testSummaryOfNothingIsNil() {
        XCTAssertNil(WeightHistory.summary([]))
    }

    // MARK: domain

    func testDomainNeverIncludesZero() {
        let f = fitness([("2026-08-01", 80), ("2026-08-29", 82)])
        let d = WeightHistory.domain(WeightHistory.series(f, range: .all, today: today), target: nil)
        XCTAssertGreaterThan(d.lowerBound, 70, "a weight chart anchored at zero is a flat line")
        XCTAssertLessThan(d.lowerBound, 80)
        XCTAssertGreaterThan(d.upperBound, 82)
    }

    /// Otherwise a week of near-identical readings renders as a mountain
    /// range across a 0.05kg axis.
    func testDomainHasAFloorSoFlatWeeksStayFlat() {
        let f = fitness([("2026-08-01", 80.0), ("2026-08-02", 80.05)])
        let d = WeightHistory.domain(WeightHistory.series(f, range: .all, today: today), target: nil)
        XCTAssertGreaterThanOrEqual(d.upperBound - d.lowerBound, 1.0,
                                    "padding is floored at 0.5 each side")
    }

    func testDomainStretchesToHoldTheGoalLine() {
        let f = fitness([("2026-08-01", 85), ("2026-08-29", 84)])
        let d = WeightHistory.domain(WeightHistory.series(f, range: .all, today: today), target: 75)
        XCTAssertLessThan(d.lowerBound, 75,
                          "a goal outside the window is drawn clipped to an edge, which reads as being on target")
    }

    func testDomainOfNothingIsSafe() {
        let d = WeightHistory.domain([], target: nil)
        XCTAssertLessThan(d.lowerBound, d.upperBound)
    }
}
