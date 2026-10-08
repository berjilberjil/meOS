import XCTest
@testable import meOS

/// The purchase-logging contract the Stuff MCP depends on: how a payback window
/// in months maps to what the app stores, and that an item saved before product
/// links existed still loads.
final class StuffBridgeTests: XCTestCase {

    // MARK: Payback window

    /// 36 months is the documented default for anything bought — the MCP relies
    /// on this constant, so it is pinned rather than assumed.
    func testDefaultPaybackIsThirtySixMonths() {
        XCTAssertEqual(BelongingMath.defaultROIMonths, 36)
    }

    /// The Stuff editor stores `lifeMonths * 30`. The bridge has to agree exactly,
    /// or an item logged by Catherine would read back as a different length than
    /// one typed in by hand.
    func testMonthsMatchTheEditorsConversion() {
        for months in [1, 12, 24, 36, 60, 120] {
            XCTAssertEqual(BelongingMath.lifeDays(months: months), months * 30, "\(months) months")
        }
    }

    /// Round-trip through what the tool reports back (`lifeDays / 30`).
    func testMonthsSurviveTheRoundTrip() {
        for months in [1, 12, 36, 60] {
            XCTAssertEqual(BelongingMath.lifeDays(months: months) / 30, months)
        }
    }

    func testNonsenseMonthsClampInsteadOfCrashing() {
        XCTAssertEqual(BelongingMath.lifeDays(months: 0), 30)
        XCTAssertEqual(BelongingMath.lifeDays(months: -5), 30)
    }

    // MARK: The item itself

    func testLinkSurvivesEncodingAndDecoding() throws {
        let item = BelongingItem(name: "CMF Buds Pro 2", kind: .gadgets, pricePaise: 249900,
                                 boughtOn: "2026-08-19",
                                 lifeDays: BelongingMath.lifeDays(months: 36),
                                 link: "https://www.amazon.in/dp/B0D9G1YQPZ")
        let back = try JSONDecoder().decode(BelongingItem.self, from: try JSONEncoder().encode(item))
        XCTAssertEqual(back.link, "https://www.amazon.in/dp/B0D9G1YQPZ")
        XCTAssertEqual(back.lifeDays, 1080)
        XCTAssertEqual(back.pricePaise, 249900)
    }

    /// Everything already in the vault was written before `link` existed.
    func testItemsSavedBeforeLinksStillLoad() throws {
        let legacy = """
        {"id":"a1","name":"Kettle","kind":"home","pricePaise":150000,
         "boughtOn":"2025-01-04","lifeDays":1800,"note":"","retired":false,
         "photoBase64":"","categoryID":"home"}
        """
        let item = try JSONDecoder().decode(BelongingItem.self, from: Data(legacy.utf8))
        XCTAssertEqual(item.link, "", "a missing link decodes to empty, not a failure")
        XCTAssertEqual(item.name, "Kettle")
        XCTAssertEqual(item.lifeDays, 1800)
    }

    func testLinkIsTrimmedOnTheWayIn() {
        let item = BelongingItem(name: "Thing", kind: .other, pricePaise: 100,
                                 boughtOn: "2026-08-19", link: "  https://example.com/x \n")
        XCTAssertEqual(item.link, "https://example.com/x")
    }

    // MARK: What a logged purchase is worth per day

    /// A ₹2,499 pair of buds over 36 months is the worked example in the README —
    /// the ROI maths the tool reports has to hold up.
    func testThirtySixMonthPaybackCostsUnderThreeRupeesADay() {
        let life = BelongingMath.lifeDays(months: 36)
        let perDay = BelongingMath.paisePerDay(price: 249900, days: life)
        XCTAssertEqual(perDay, 231)   // ₹2.31/day
        XCTAssertEqual(BelongingMath.daysLeft(owned: life, life: life), 0, "paid off at the end of the window")
    }
}
