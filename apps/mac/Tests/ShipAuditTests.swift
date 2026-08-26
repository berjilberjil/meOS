import XCTest
@testable import MyOS

/// Regressions from the pre-ship logic audit. Each test here stands for a bug
/// that was live, not a hypothetical — the comment says what used to happen.
final class ShipAuditTests: XCTestCase {

    private func photo(_ dateKey: String, _ id: String) -> ProgressPhoto {
        ProgressPhoto(id: id, date: dateKey, url: URL(fileURLWithPath: "/tmp/\(id).jpg"))
    }

    // MARK: - Weekly report photo thinning

    // `pick` divided by `limit - 1`. At limit 1 that is a division by zero, and
    // the infinity went straight into an `Int(...)` conversion — which traps in
    // Swift rather than saturating. Asking for one photo crashed the app.
    func testPickOfOneDoesNotDivideByZero() {
        let week = "2026-08-17"..."2026-08-23"
        let photos = (17...22).map { photo("2026-08-\($0)", "2026-08-\($0)__a") }
        let picked = WeeklyReportMath.pick(photos, in: week, limit: 1)
        XCTAssertEqual(picked.count, 1)
        XCTAssertEqual(picked.first?.id, "2026-08-22__a", "one photo asked for is the newest one")
    }

    func testPickOfNoneIsEmpty() {
        let week = "2026-08-17"..."2026-08-23"
        let photos = (17...22).map { photo("2026-08-\($0)", "2026-08-\($0)__a") }
        XCTAssertEqual(WeeklyReportMath.pick(photos, in: week, limit: 0).count, 0)
    }

    func testPickStillSpreadsAcrossTheWindow() {
        let week = "2026-08-17"..."2026-08-23"
        let photos = (17...22).map { photo("2026-08-\($0)", "2026-08-\($0)__a") }
        let picked = WeeklyReportMath.pick(photos, in: week, limit: 4)
        XCTAssertEqual(picked.count, 4)
        XCTAssertEqual(picked.first?.id, "2026-08-17__a")
        XCTAssertEqual(picked.last?.id, "2026-08-22__a")
    }

    // MARK: - Calorie floors

    // `goalCalories` was floored at 1000 but the cut/bulk figures beside it on
    // the Calories card were not, so the card could offer a "Cut" number the app
    // would refuse to actually use — and under a small enough profile, one below
    // zero.
    func testCutAndBulkShareTheSameFloorAsTheSelectedGoal() {
        // Deliberately tiny, so TDEE + the cut offset lands under the floor.
        let t = Nutrition.targets(sex: .female, weightKg: 35, heightCm: 120, age: 70,
                                  activity: .sedentary, goal: .cut)
        XCTAssertGreaterThanOrEqual(t.cut, 1000)
        XCTAssertGreaterThanOrEqual(t.bulk, 1000)
        XCTAssertEqual(t.goalCalories, t.cut, "the selected goal is the cut figure shown")
    }

    func testNormalProfileIsUntouchedByTheFloor() {
        let t = Nutrition.targets(sex: .male, weightKg: 90, heightCm: 175, age: 28,
                                  activity: .moderate, goal: .cut)
        XCTAssertGreaterThan(t.cut, 1000)
        XCTAssertGreaterThan(t.bulk, t.maintain)
        XCTAssertGreaterThan(t.maintain, t.cut)
    }

    // Protein is set from the weight passed in — which is why the caller must
    // pass the *current* weight and not the goal weight.
    func testProteinFollowsTheWeightItIsGiven() {
        let heavy = Nutrition.targets(sex: .male, weightKg: 90, heightCm: 175, age: 28,
                                      activity: .moderate, goal: .cut)
        let goalWeight = Nutrition.targets(sex: .male, weightKg: 70, heightCm: 175, age: 28,
                                           activity: .moderate, goal: .cut)
        XCTAssertGreaterThan(heavy.proteinG, goalWeight.proteinG,
                             "computing off the goal weight under-feeds protein by ~40g")
        XCTAssertGreaterThan(heavy.goalCalories, goalWeight.goalCalories)
    }

    // MARK: - Progress photo deletion

    // Deleting a photo removed it locally and asked the server to drop the cloud
    // copy with `try?`. When that request failed nothing recorded the intent, so
    // the next pull saw a remote photo this device didn't have and downloaded it
    // straight back — the deleted photo reappeared, every time.
    func testDeletedPhotoStaysTombstonedUntilTheServerConfirms() {
        let id = "2026-08-26__audit-\(UUID().uuidString)"
        addTeardownBlock { ProgressPhotoStore.clearDeleted(id) }

        XCTAssertFalse(ProgressPhotoStore.isDeleted(id))
        ProgressPhotoStore.markDeleted(id)
        XCTAssertTrue(ProgressPhotoStore.isDeleted(id), "a failed cloud delete stays queued")
        XCTAssertTrue(ProgressPhotoStore.deletedIds.contains(id), "and pull() filters against this set")

        ProgressPhotoStore.clearDeleted(id)
        XCTAssertFalse(ProgressPhotoStore.isDeleted(id), "confirmed gone — stop tracking it")
    }

    func testMarkingTheSameDeletionTwiceIsNotADuplicate() {
        let id = "2026-08-26__audit-\(UUID().uuidString)"
        addTeardownBlock { ProgressPhotoStore.clearDeleted(id) }
        ProgressPhotoStore.markDeleted(id)
        ProgressPhotoStore.markDeleted(id)
        XCTAssertEqual(ProgressPhotoStore.deletedIds.filter { $0 == id }.count, 1)
    }

    // MARK: - Food identity

    // `upsert_food` ran through `addFood`, which prepends unconditionally, so
    // re-running an import appended the whole library again instead of updating
    // it. Matching is by name because that is all an importer has.
    func testFoodMatchKeyIgnoresCaseAndSurroundingSpace() {
        XCTAssertEqual(Food.matchKey("  MuscleBlaze Creatine "), Food.matchKey("muscleblaze creatine"))
        XCTAssertNotEqual(Food.matchKey("Whey"), Food.matchKey("Whey Isolate"))
    }

    func testFoodMatchKeyOfBlankIsEmptySoItNeverMatches() {
        XCTAssertEqual(Food.matchKey("   "), "")
        XCTAssertEqual(Food.matchKey(""), "")
    }
}
