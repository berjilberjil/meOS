import XCTest
@testable import MyOS

/// Regressions for the UI-audit pass: bugs that were visible on screen but are
/// really data/logic rules. Kept together so the rule, not the pixel, is pinned.
final class RestDayRuleTests: XCTestCase {
    func testEmptyRestFlagIsARestDay() {
        XCTAssertTrue(WorkoutDayPlan(rest: true, items: []).isRestDay)
    }

    func testPlainEmptyDayIsNotARestDay() {
        XCTAssertFalse(WorkoutDayPlan(rest: false, items: []).isRestDay)
    }

    /// The reported bug: Friday said "Rest day" with five exercises under it.
    /// A stale `rest` flag must never win over real work.
    func testExercisesBeatAStaleRestFlag() {
        let plan = WorkoutDayPlan(rest: true, items: [
            PlanExercise(exerciseId: "incline-db-press"),
            PlanExercise(exerciseId: "arnold-press")
        ])
        XCTAssertFalse(plan.isRestDay)
    }

    func testTrainingDayWithItemsIsNotRest() {
        XCTAssertFalse(WorkoutDayPlan(rest: false, items: [PlanExercise(exerciseId: "row")]).isRestDay)
    }
}

final class FoldNonSpendTests: XCTestCase {
    /// "Returns" showed up inside "Top spends this month" — money coming back
    /// is not a spend.
    func testReturnsAreNotSpends() {
        XCTAssertTrue(FoldSpend.isNonSpend("Returns"))
        XCTAssertTrue(FoldSpend.isNonSpend("Refund"))
        XCTAssertTrue(FoldSpend.isNonSpend("Cashback"))
        XCTAssertTrue(FoldSpend.isNonSpend("Interest"))
        XCTAssertTrue(FoldSpend.isNonSpend("Dividend"))
    }

    func testMatchIsCaseAndWhitespaceInsensitive() {
        XCTAssertTrue(FoldSpend.isNonSpend("  returns "))
        XCTAssertTrue(FoldSpend.isNonSpend("REFUNDS"))
    }

    func testRealSpendCategoriesSurvive() {
        XCTAssertFalse(FoldSpend.isNonSpend("Transport"))
        XCTAssertFalse(FoldSpend.isNonSpend("Food & Drinks"))
        XCTAssertFalse(FoldSpend.isNonSpend("Hidden Charges"))
        XCTAssertFalse(FoldSpend.isNonSpend("Shopping"))
    }
}

final class JournalPresetRewriteTests: XCTestCase {
    /// The Wins preset chip rendered as "+ ate". Old saves are rewritten on
    /// decode so existing installs pick up the wording fix.
    func testStalePresetIsRewrittenOnDecode() throws {
        let json = Data(#"{"wins":["ate","Posted content","Ate clean"]}"#.utf8)
        let p = try JSONDecoder().decode(JournalPresets.self, from: json)
        XCTAssertFalse(p.wins.contains("ate"))
        XCTAssertFalse(p.wins.contains("Ate clean"))
        XCTAssertTrue(p.wins.contains("Ate a clean meal"))
        XCTAssertTrue(p.wins.contains("Posted content"))
    }

    func testMissingSectionsFallBackToSeed() throws {
        let p = try JSONDecoder().decode(JournalPresets.self, from: Data("{}".utf8))
        XCTAssertEqual(p.morning, JournalPresets.Seed.morning)
        XCTAssertEqual(p.gratitude, JournalPresets.Seed.gratitude)
    }
}
