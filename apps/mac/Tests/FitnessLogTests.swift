import XCTest
@testable import meOS

final class MealLogStateTests: XCTestCase {
    func testEmptyIsUnconfirmed() { XCTAssertEqual(MealLog().state(.lunch), .unconfirmed) }

    func testItemsWinOverSkipped() {
        var l = MealLog(); l.skip(.lunch); l.meals["lunch"] = [PlanItem(foodId: "x")]
        XCTAssertEqual(l.state(.lunch), .logged)
    }

    func testSkippedWhenNoItems() {
        var l = MealLog(); l.skip(.lunch)
        XCTAssertEqual(l.state(.lunch), .skipped)
    }

    func testTickCopiesPlannedAndUnskips() {
        var l = MealLog(); l.skip(.lunch)
        l.tick(.lunch, planned: [PlanItem(foodId: "rice", quantity: 2)])
        XCTAssertEqual(l.items(.lunch).map(\.foodId), ["rice"])
        XCTAssertEqual(l.items(.lunch).first?.quantity, 2)
        XCTAssertFalse(l.skipped.contains("lunch"))
        XCTAssertEqual(l.state(.lunch), .logged)
    }

    func testTickWithNoPlannedIsNoOp() {
        var l = MealLog(); l.tick(.lunch, planned: [])
        XCTAssertTrue(l.items(.lunch).isEmpty)
        XCTAssertEqual(l.state(.lunch), .unconfirmed)
    }

    func testSkipClearsExistingItems() {
        var l = MealLog(); l.meals["dinner"] = [PlanItem(foodId: "x")]; l.skip(.dinner)
        XCTAssertTrue(l.items(.dinner).isEmpty)
        XCTAssertEqual(l.state(.dinner), .skipped)
    }

    func testUnskipReturnsToUnconfirmed() {
        var l = MealLog(); l.skip(.lunch); l.unskip(.lunch)
        XCTAssertEqual(l.state(.lunch), .unconfirmed)
    }

    func testSetItemsReplacesWhollyAndUnskips() {
        var l = MealLog(); l.meals["lunch"] = [PlanItem(foodId: "a")]; l.skip(.lunch)
        l.setItems(.lunch, [PlanItem(foodId: "b")])
        XCTAssertEqual(l.items(.lunch).map(\.foodId), ["b"])
        XCTAssertFalse(l.skipped.contains("lunch"))
    }

    func testDecodesLegacyJSONWithoutSkippedKey() throws {
        let data = Data(#"{"meals":{}}"#.utf8)
        let log = try JSONDecoder().decode(MealLog.self, from: data)
        XCTAssertTrue(log.skipped.isEmpty)
    }
}

final class WorkoutDayLogStateTests: XCTestCase {
    func testEmptyIsUnconfirmed() { XCTAssertEqual(WorkoutDayLog().state, .unconfirmed) }

    func testDoneWinsOverSkipped() {
        var d = WorkoutDayLog(); d.skip(); d.tick(items: nil)
        XCTAssertEqual(d.state, .done)
    }

    func testSkipClearsItemsAndDone() {
        var d = WorkoutDayLog(); d.tick(items: [PlanExercise(exerciseId: "x")]); d.skip()
        XCTAssertEqual(d.state, .skipped)
        XCTAssertNil(d.items)
    }

    func testTickNilMeansAsPlanned() {
        var d = WorkoutDayLog(); d.tick(items: nil)
        XCTAssertNil(d.items)
        XCTAssertEqual(d.state, .done)
    }

    func testTickWithItemsMeansEditedActual() {
        var d = WorkoutDayLog(); d.tick(items: [PlanExercise(exerciseId: "y", sets: 4, reps: 8)])
        XCTAssertEqual(d.items?.first?.exerciseId, "y")
        XCTAssertEqual(d.items?.first?.sets, 4)
    }

    func testDecodesLegacyTrainingStateWithoutDayLog() throws {
        let data = Data(#"{"customExercises":[],"weekPlan":{}}"#.utf8)
        let t = try JSONDecoder().decode(TrainingState.self, from: data)
        XCTAssertTrue(t.dayLog.isEmpty)
    }
}

final class WeekdayKeysTests: XCTestCase {
    func testOthersExcludesGivenDay() {
        XCTAssertEqual(WeekdayKeys.others(except: "3"), ["0", "1", "2", "4", "5", "6"])
    }
    func testOthersOnUnknownDayReturnsAllSeven() {
        XCTAssertEqual(WeekdayKeys.others(except: "9").count, 7)
    }
}
