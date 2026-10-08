import XCTest
@testable import meOS

final class FoodGlyphTests: XCTestCase {
    func testNamesMapToTheRightFood() {
        XCTAssertEqual(FoodGlyph.emoji(name: "Egg dosa", category: .carb), "🥚")
        XCTAssertEqual(FoodGlyph.emoji(name: "Chicken biryani", category: .protein), "🍗")
        XCTAssertEqual(FoodGlyph.emoji(name: "Grilled fish", category: .protein), "🐟")
        XCTAssertEqual(FoodGlyph.emoji(name: "Channa masala", category: .protein), "🫘")
        XCTAssertEqual(FoodGlyph.emoji(name: "Toned milk", category: .dairy), "🥛")
        XCTAssertEqual(FoodGlyph.emoji(name: "Tender coconut", category: .drink), "🥥")
        XCTAssertEqual(FoodGlyph.emoji(name: "Curd", category: .dairy), "🥣")
    }

    func testUnknownFallsBackToCategory() {
        XCTAssertEqual(FoodGlyph.emoji(name: "Mystery scoop", category: .protein), "🥩")
        XCTAssertEqual(FoodGlyph.emoji(name: "Mystery scoop", category: .carb), "🍞")
        XCTAssertEqual(FoodGlyph.emoji(name: "Mystery scoop", category: .veg), "🥬")
        XCTAssertEqual(FoodGlyph.emoji(name: "Mystery scoop", category: .fruit), "🍎")
    }

    func testRegionalFoodsAreDistinct() {
        XCTAssertEqual(FoodGlyph.emoji(name: "Plain dosa", category: .carb), "🥞")
        XCTAssertEqual(FoodGlyph.emoji(name: "Idli", category: .carb), "🍚")
        XCTAssertEqual(FoodGlyph.emoji(name: "Sambar", category: .veg), "🫘")
        XCTAssertEqual(FoodGlyph.emoji(name: "Cabbage poriyal", category: .veg), "🥬")
        XCTAssertNotEqual(
            FoodGlyph.emoji(name: "Masala dosa", category: .carb),
            FoodGlyph.emoji(name: "Idli", category: .carb)
        )
    }

    func testServingDisplayNormalizesGlasses() {
        XCTAssertEqual(FoodServing.display("1 glass"), "240 ml")
        XCTAssertEqual(FoodServing.display("1 tumbler"), "240 ml")
        XCTAssertEqual(FoodServing.display("1 dosa"), "1 dosa")
    }
}
