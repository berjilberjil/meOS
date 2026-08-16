import XCTest
@testable import MyOS

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
}
