import XCTest
@testable import meOS

final class FavoriteBodySyncTests: XCTestCase {
    private func shot(_ id: String, _ day: String) -> FavoriteShot {
        FavoriteShot(id: id, day: day)
    }

    func testImportsEveryUnimportedFavorite() {
        // Every hearted shot lands in Daily progress — not one per day.
        let shots = [
            shot("c", "2026-08-15"),
            shot("b", "2026-08-15"),
            shot("a", "2026-08-14")
        ]
        let picks = FavoriteBodySync.picks(shots: shots, existingDays: [], importedIds: [])
        XCTAssertEqual(picks.map(\.id), ["c", "b", "a"])
    }

    func testKeepsMultipleFavoritesOnTheSameDay() {
        let shots = [shot("c", "2026-08-15"), shot("b", "2026-08-15")]
        let picks = FavoriteBodySync.picks(shots: shots, existingDays: ["2026-08-15"], importedIds: [])
        XCTAssertEqual(picks.map(\.id), ["c", "b"])
    }

    func testJustHeartedPhotoCountsAsToday() {
        XCTAssertEqual(
            FavoriteBodySync.day(created: "2026-07-01", modified: "2026-08-15", today: "2026-08-15"),
            "2026-08-15")
    }

    func testOldFavoriteKeepsCaptureDay() {
        XCTAssertEqual(
            FavoriteBodySync.day(created: "2026-07-01", modified: "2026-07-01", today: "2026-08-15"),
            "2026-07-01")
        XCTAssertEqual(
            FavoriteBodySync.day(created: "2026-07-01", modified: nil, today: "2026-08-15"),
            "2026-07-01")
    }

    func testSkipsAlreadyImportedAssets() {
        let shots = [shot("c", "2026-08-15"), shot("b", "2026-08-15")]
        let picks = FavoriteBodySync.picks(shots: shots, existingDays: [], importedIds: ["c"])
        XCTAssertEqual(picks.map(\.id), ["b"])
    }

    func testEmptyInput() {
        XCTAssertTrue(FavoriteBodySync.picks(shots: [], existingDays: [], importedIds: []).isEmpty)
    }

    func testParsesLegacyAndMultiPhotoFilenames() {
        XCTAssertEqual(ProgressPhotoStore.parse("2026-08-15.jpg")?.date, "2026-08-15")
        XCTAssertEqual(ProgressPhotoStore.parse("2026-08-15.jpg")?.id, "2026-08-15")
        let multi = ProgressPhotoStore.parse("2026-08-15__ABC_123.jpg")
        XCTAssertEqual(multi?.date, "2026-08-15")
        XCTAssertEqual(multi?.id, "2026-08-15__ABC_123")
        XCTAssertNil(ProgressPhotoStore.parse("notes.txt"))
    }
}
