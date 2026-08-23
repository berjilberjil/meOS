import XCTest
@testable import MyOS

/// Macro Intelligence's display rules — the ones that decide whether a number is
/// read correctly at a glance.
final class MacroTests: XCTestCase {

    private func metric(id: String = "m", kind: String = "price", unit: String = "",
                        value: Double? = 100, quality: String = "verified",
                        d1: MacroDelta? = nil, history: [MacroPoint] = []) -> MacroMetric {
        MacroMetric(id: id, name: id, category: "Rates", country: "US", unit: unit, kind: kind,
                    frequency: "Daily", source: "FRED", sourceUrl: "", priority: 0,
                    value: value, asOf: "2026-08-21", change1D: d1, change7D: nil, change30D: nil,
                    changeYTD: nil, change1Y: nil, history: history, quality: quality, note: nil)
    }

    // MARK: Reading a change

    func testRatesMoveInBasisPointsNotPercent() {
        // 6.50 → 6.59 is nine basis points. Calling it "+1.38%" is how a repo
        // rate gets misread as a market move.
        let m = metric(kind: "rate", unit: "%", value: 6.59, d1: MacroDelta(abs: 0.09, pct: 1.38))
        XCTAssertEqual(MacroFormat.change(m.change1D, isRate: true), "+9 bp")
    }

    func testPricesMoveInPercent() {
        let m = metric(value: 7674, d1: MacroDelta(abs: 41.2, pct: 0.54))
        XCTAssertEqual(MacroFormat.change(m.change1D, isRate: false), "+0.54%")
    }

    func testNegativeChangesKeepTheirSign() {
        XCTAssertEqual(MacroFormat.change(MacroDelta(abs: -0.12, pct: -2.5), isRate: false), "-2.50%")
        XCTAssertEqual(MacroFormat.change(MacroDelta(abs: -0.12, pct: -2.5), isRate: true), "-12 bp")
    }

    func testAMissingChangeIsADashNotAZero() {
        XCTAssertEqual(MacroFormat.change(nil, isRate: false), "—")
        XCTAssertEqual(MacroFormat.tint(nil), Palette.faint, "no data is not a flat day")
    }

    // MARK: Values

    func testPercentUnitsSitAfterTheNumber() {
        XCTAssertEqual(MacroFormat.value(metric(kind: "rate", unit: "%", value: 4.69)), "4.69%")
    }

    func testCurrencyUnitsSitBefore() {
        XCTAssertEqual(MacroFormat.value(metric(unit: "₹", value: 95.43)), "₹95.43")
        XCTAssertEqual(MacroFormat.value(metric(unit: "$", value: 95.29)), "$95.29")
    }

    func testAnUnavailableMetricShowsNothingRatherThanZero() {
        XCTAssertEqual(MacroFormat.value(metric(value: nil)), "—")
        XCTAssertFalse(metric(value: nil).available)
    }

    // MARK: Provenance

    func testEstimatedIsNotDressedUpAsVerified() {
        XCTAssertEqual(metric(quality: "estimated").grade, .estimated)
        XCTAssertEqual(MacroQuality.estimated.label, "Estimated")
        XCTAssertNotEqual(MacroQuality.estimated.tint, MacroQuality.verified.tint,
                          "a number read off the web must not wear the verified colour")
    }

    func testAnUnknownQualityFallsBackToUnavailable() {
        XCTAssertEqual(metric(quality: "nonsense").grade, .unavailable)
    }

    // MARK: Ranges

    func testRangeClipsTheSeriesToItsWindow() {
        let points = (1...40).map { MacroPoint(d: MacroFormat.shift("2026-08-21", by: -40 + $0), v: Double($0)) }
        XCTAssertEqual(MacroFormat.series(points, range: .w1).count, 8)
        XCTAssertEqual(MacroFormat.series(points, range: .max).count, 40)
    }

    func testDateShiftCrossesMonthBoundaries() {
        XCTAssertEqual(MacroFormat.shift("2026-08-01", by: -1), "2026-07-31")
        XCTAssertEqual(MacroFormat.shift("2026-12-31", by: 1), "2027-01-01")
    }

    // MARK: The snapshot

    func testPulseIsOnlyTheTopPriorityMetrics() {
        let p0 = metric(id: "a")
        var p1 = metric(id: "b")
        p1 = MacroMetric(id: "b", name: "b", category: "Rates", country: "US", unit: "", kind: "price",
                         frequency: "Daily", source: "FRED", sourceUrl: "", priority: 1, value: 1,
                         asOf: nil, change1D: nil, change7D: nil, change30D: nil, changeYTD: nil,
                         change1Y: nil, history: [], quality: "verified", note: nil)
        let snap = MacroSnapshot(date: "2026-08-21", generatedAt: "", metrics: [p0, p1], regime: [], brief: nil)
        XCTAssertEqual(snap.pulse.map(\.id), ["a"])
    }

    func testMoversAreRankedByHowFarTheyMoved() {
        let small = metric(id: "small", d1: MacroDelta(abs: 0.1, pct: 0.4))
        let big = metric(id: "big", d1: MacroDelta(abs: 2, pct: -3.1))
        let none = metric(id: "none")
        let snap = MacroSnapshot(date: "2026-08-21", generatedAt: "", metrics: [small, big, none], regime: [], brief: nil)
        XCTAssertEqual(snap.movers.map(\.id), ["big", "small"], "and a metric with no change is not a mover")
    }
}
