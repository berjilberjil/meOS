import XCTest
@testable import MyOS

/// Pure parsing of a Gemini scan payload — food vs object. No network.
final class ScanInsightTests: XCTestCase {
    func testFoodPayloadKeepsMacros() {
        let raw: [String: Any] = [
            "kind": "food",
            "summary": "Masala dosa — about 350 kcal.",
            "foods": [[
                "name": "Masala dosa",
                "category": "carb",
                "servingLabel": "1 plate",
                "calories": 350,
                "protein": 8,
                "carbs": 52,
                "fiber": 4,
                "fats": 10,
                "vitamins": "B1"
            ]]
        ]
        let r = ScanInsight.parse(raw)
        XCTAssertEqual(r.kind, .food)
        XCTAssertEqual(r.summary, "Masala dosa — about 350 kcal.")
        XCTAssertEqual(r.foods.first?.name, "Masala dosa")
        XCTAssertEqual(r.foods.first?.calories, 350)
        XCTAssertNil(r.object)
    }

    func testObjectPayloadKeepsNeededVerdict() {
        let raw: [String: Any] = [
            "kind": "object",
            "summary": "An adjustable dumbbell.",
            "object": [
                "name": "Adjustable dumbbell",
                "needed": "yes",
                "why": "You already train; this covers more loads at home.",
                "useful": "Replaces a rack of plates if space is tight."
            ]
        ]
        let r = ScanInsight.parse(raw)
        XCTAssertEqual(r.kind, .object)
        XCTAssertEqual(r.object?.needed, .yes)
        XCTAssertEqual(r.object?.name, "Adjustable dumbbell")
        XCTAssertTrue(r.foods.isEmpty)
    }

    func testGarbageIsAFailedRead() {
        let r = ScanInsight.parse(nil)
        XCTAssertTrue(r.failed)
    }

    func testNamedObjectIsNotAFailedRead() {
        let r = ScanInsight.parse([
            "kind": "object",
            "object": ["name": "Hydro flask", "needed": "yes", "why": "You skip water.", "useful": "Carry it to the gym."]
        ])
        XCTAssertFalse(r.failed)
        XCTAssertEqual(r.object?.name, "Hydro flask")
    }

    func testBadNeededValueIsMaybe() {
        let r = ScanInsight.parse([
            "kind": "object",
            "object": ["name": "Thing", "needed": "absolutely", "why": "x", "useful": "y"]
        ])
        XCTAssertEqual(r.object?.needed, .maybe)
    }
}
