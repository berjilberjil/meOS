import XCTest
@testable import meOS

/// Scan history: what a saved scan keeps, how the list is capped, and which R2
/// objects a delete leaves behind.
final class ScanHistoryTests: XCTestCase {

    private func foodInsight() -> ScanInsight {
        ScanInsight(kind: .food, summary: "Chicken and rice",
                    foods: [ScanInsight.Food(name: "Chicken breast", serving: "150 g",
                                             calories: 248, protein: 46, carbs: 0, fats: 5.4,
                                             detail: "B6"),
                            ScanInsight.Food(name: "Rice", serving: "1 cup",
                                             calories: 205, protein: 4, carbs: 45, fats: 0.4,
                                             detail: "")],
                    object: nil)
    }

    private func objectInsight(_ needed: ScanInsight.Needed) -> ScanInsight {
        ScanInsight(kind: .object, summary: "A second mechanical keyboard", foods: [],
                    object: ScanInsight.Object(name: "Mechanical keyboard", needed: needed,
                                               why: "You already own two.",
                                               useful: "Use the one on your desk."))
    }

    private func record(_ insight: ScanInsight, id: String = "s1", date: String = "2026-08-23") -> ScanRecord {
        ScanRecord(insight, id: id, at: "\(date)T10:00:00", date: date)
    }

    // MARK: Round trip

    func testFoodSurvivesTheTripThroughTheRecord() {
        let back = record(foodInsight()).insight
        XCTAssertEqual(back.kind, .food)
        XCTAssertEqual(back.foods.count, 2)
        XCTAssertEqual(back.foods.first?.name, "Chicken breast")
        XCTAssertEqual(back.foods.first?.protein, 46)
        XCTAssertEqual(back.summary, "Chicken and rice")
    }

    func testObjectVerdictSurvivesTheTripThroughTheRecord() {
        let back = record(objectInsight(.no)).insight
        XCTAssertEqual(back.kind, .object)
        XCTAssertEqual(back.object?.needed, .no)
        XCTAssertEqual(back.object?.why, "You already own two.")
    }

    func testAnUnknownVerdictLandsOnMaybe() {
        var r = record(objectInsight(.yes))
        r.object?.needed = "nonsense"
        XCTAssertEqual(r.insight.object?.needed, .maybe)
    }

    func testCodableRoundTrip() throws {
        var r = record(foodInsight())
        r.photoKey = "scan-abc"
        r.logged = true
        let back = try JSONDecoder().decode(ScanRecord.self, from: JSONEncoder().encode(r))
        XCTAssertEqual(back, r)
    }

    func testDecodesARecordFromBeforePhotosExisted() throws {
        let raw = Data(#"{"id":"s1","at":"2026-08-01T09:30:00","kind":"object","summary":"A lamp"}"#.utf8)
        let back = try JSONDecoder().decode(ScanRecord.self, from: raw)
        XCTAssertNil(back.photoKey)
        XCTAssertFalse(back.logged)
        XCTAssertEqual(back.foods, [])
        XCTAssertEqual(back.date, "2026-08-01", "the day falls out of the timestamp when it wasn't stored")
    }

    // MARK: Display

    func testFoodRowsShowTheirTotalCalories() {
        let r = record(foodInsight())
        XCTAssertEqual(r.calories, 453)
        XCTAssertEqual(r.badge, "453 kcal")
        XCTAssertEqual(r.title, "Chicken breast +1")
    }

    func testObjectRowsShowTheVerdict() {
        XCTAssertEqual(record(objectInsight(.no)).badge, "Not wanted")
        XCTAssertEqual(record(objectInsight(.yes)).badge, "Wanted")
        XCTAssertEqual(record(objectInsight(.maybe)).badge, "Maybe")
        XCTAssertEqual(record(objectInsight(.yes)).title, "Mechanical keyboard")
    }

    func testDayLabels() {
        XCTAssertEqual(ScanRecord.dayLabel("2026-08-23", today: "2026-08-23"), "Today")
        XCTAssertEqual(ScanRecord.dayLabel("2026-08-22", today: "2026-08-23"), "Yesterday")
        XCTAssertEqual(ScanRecord.dayLabel("2026-08-12", today: "2026-08-23"), "12 Aug")
        // Across a month boundary, where naive string math would break.
        XCTAssertEqual(ScanRecord.dayLabel("2026-07-31", today: "2026-08-01"), "Yesterday")
    }

    // MARK: The list

    func testNewestFirst() {
        let list = ScanRecord.adding(record(objectInsight(.yes), id: "b"),
                                     to: [record(foodInsight(), id: "a")])
        XCTAssertEqual(list.map(\.id), ["b", "a"])
    }

    func testAddingReplacesRatherThanDuplicatesTheSameId() {
        var r = record(foodInsight(), id: "a")
        r.photoKey = "scan-a"
        let list = ScanRecord.adding(r, to: [record(foodInsight(), id: "a")])
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list.first?.photoKey, "scan-a")
    }

    func testTheListIsCapped() {
        var list: [ScanRecord] = []
        for i in 0..<(ScanRecord.cap + 25) {
            list = ScanRecord.adding(record(foodInsight(), id: "s\(i)"), to: list)
        }
        XCTAssertEqual(list.count, ScanRecord.cap)
        XCTAssertEqual(list.first?.id, "s\(ScanRecord.cap + 24)", "the newest is kept")
        XCTAssertFalse(list.contains { $0.id == "s0" }, "the oldest fell off")
    }

    func testOnlyRealPhotosCountAsOrphans() {
        var withPhoto = record(foodInsight(), id: "a"); withPhoto.photoKey = "scan-a"
        var blank = record(foodInsight(), id: "b"); blank.photoKey = ""
        let none = record(foodInsight(), id: "c")
        XCTAssertEqual(ScanRecord.orphanedKeys([withPhoto, blank, none]), ["scan-a"])
    }

    func testPayloadCarriesScansUnderTheirSyncKey() throws {
        let raw = Data(#"{"myos.scans":[{"id":"s1","at":"2026-08-23T10:00:00","date":"2026-08-23","kind":"food","summary":"Eggs","foods":[],"logged":false}]}"#.utf8)
        let payload = try JSONDecoder().decode(AppStatePayload.self, from: raw)
        XCTAssertEqual(payload.scans?.count, 1)
        XCTAssertEqual(payload.scans?.first?.summary, "Eggs")
    }
}
