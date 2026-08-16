import XCTest
@testable import MyOS

final class BelongingMathTests: XCTestCase {
    func testDaysOwnedIsAtLeastOne() {
        XCTAssertEqual(BelongingMath.daysOwned(bought: "2026-08-16", today: "2026-08-16"), 1)
        XCTAssertEqual(BelongingMath.daysOwned(bought: "2026-08-01", today: "2026-08-16"), 16)
    }

    func testShirtCostPerDayFallsAsYouUseIt() {
        // ₹400 = 40_000 paise
        let month = BelongingMath.paisePerDay(price: 40_000, days: 30)
        let year  = BelongingMath.paisePerDay(price: 40_000, days: 365)
        XCTAssertGreaterThan(month, year)
        XCTAssertEqual(year, 110) // ₹1.10
    }

    func testBikeFullROIAtExpectedLife() {
        let life = 365 * 5
        XCTAssertEqual(BelongingMath.roiProgress(owned: 0, life: life), 0, accuracy: 0.001)
        XCTAssertEqual(BelongingMath.roiProgress(owned: life, life: life), 1, accuracy: 0.001)
        XCTAssertEqual(BelongingMath.daysLeft(owned: 100, life: life), life - 100)
        XCTAssertEqual(BelongingMath.daysLeft(owned: life + 10, life: life), 0)
    }

    func testMonthlyBurnAndSalaryHealth() {
        // Two gadgets, ₹3/day and ₹7/day planned → ₹300 / month
        let month = BelongingMath.monthlyBurnPaise(items: [
            (price: 3_00 * 365, life: 365),
            (price: 7_00 * 365, life: 365)
        ])
        XCTAssertEqual(month, 10_00 * 30)
        let salary = 40_000_00 // ₹40,000
        XCTAssertEqual(BelongingMath.health(monthlyBurn: 15_000_00, salary: salary), .good)
        XCTAssertEqual(BelongingMath.health(monthlyBurn: 35_000_00, salary: salary), .tight)
        XCTAssertEqual(BelongingMath.health(monthlyBurn: 45_000_00, salary: salary), .over)
    }

    func testDefaultLifeForClothesIsAYear() {
        XCTAssertEqual(BelongingKind.clothes.defaultLifeDays, 365)
        XCTAssertEqual(BelongingKind.wheels.defaultLifeDays, 365 * 5)
    }

    func testKindsHaveDistinctColors() {
        let hexes = Set(BelongingKind.allCases.map(\.tintHex))
        XCTAssertEqual(hexes.count, BelongingKind.allCases.count)
    }

    func testPhotoIsOptionalOnDecode() throws {
        let json = """
        {"id":"a","name":"Tee","kind":"clothes","pricePaise":40000,"boughtOn":"2026-01-01","lifeDays":365,"note":"","retired":false}
        """.data(using: .utf8)!
        let item = try JSONDecoder().decode(BelongingItem.self, from: json)
        XCTAssertEqual(item.photoBase64, "")
        XCTAssertEqual(item.name, "Tee")
    }

    func testPhotoRoundTrips() throws {
        let item = BelongingItem(name: "Activa", kind: .wheels, pricePaise: 80_000_00,
                                 boughtOn: "2024-06-01", photoBase64: "abc123")
        let data = try JSONEncoder().encode(item)
        let back = try JSONDecoder().decode(BelongingItem.self, from: data)
        XCTAssertEqual(back.photoBase64, "abc123")
        XCTAssertEqual(back.kind, .wheels)
        XCTAssertEqual(back.categoryID, "wheels")
    }

    func testCategoryIDFallsBackToKind() throws {
        let json = """
        {"id":"a","name":"Tee","kind":"clothes","pricePaise":40000,"boughtOn":"2026-01-01","lifeDays":365}
        """.data(using: .utf8)!
        let item = try JSONDecoder().decode(BelongingItem.self, from: json)
        XCTAssertEqual(item.categoryID, "clothes")
    }

    func testFoodApologyIsNotAProductTitle() {
        XCTAssertFalse(BelongingGuess.isProductTitle(
            "No food items were found in the image, which appears to show a CMF by Nothing electronic device."))
        XCTAssertTrue(BelongingGuess.isProductTitle("CMF Buds"))
    }

    func testGuessCleansFoodBlurbIntoCMFBuds() {
        let r = ImageParseResult(summary: "No food items were found in the image, which appears to show a CMF by Nothing electronic device.",
                                 kind: "food", foods: [], object: nil,
                                 name: nil, category: nil, priceInr: nil, lifeMonths: nil)
        let g = BelongingGuess.from(result: r, allowed: ["gadgets", "clothes", "other"])
        XCTAssertEqual(g?.name, "CMF Buds")
        XCTAssertEqual(g?.categoryID, "gadgets")
        XCTAssertEqual(g?.priceInr, 2499)
    }

    func testGuessPrefersObjectName() {
        let r = ImageParseResult(summary: "A gadget.",
                                 kind: "object", foods: nil,
                                 object: .init(name: "CMF Buds", needed: "maybe", why: "",
                                               useful: "category=gadgets price_inr=1999 life_months=24"),
                                 name: nil, category: nil, priceInr: nil, lifeMonths: nil)
        let g = BelongingGuess.from(result: r, allowed: ["gadgets", "clothes"])
        XCTAssertEqual(g?.name, "CMF Buds")
        XCTAssertEqual(g?.priceInr, 1999)
        XCTAssertEqual(g?.lifeMonths, 24)
    }

    func testCustomCategoryRoundTrips() throws {
        var state = BelongingsState()
        state.categories = [BelongingCategory(id: "shoes", name: "Shoes", icon: "shoe.fill", tintHex: 0xFF6B9A)]
        let data = try JSONEncoder().encode(state)
        let back = try JSONDecoder().decode(BelongingsState.self, from: data)
        XCTAssertEqual(back.categories.first?.name, "Shoes")
        XCTAssertEqual(back.categories.first?.icon, "shoe.fill")
    }
}
