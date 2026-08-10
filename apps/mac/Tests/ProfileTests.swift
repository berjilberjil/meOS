import XCTest
@testable import MyOS

final class ProfileInitialsTests: XCTestCase {
    private func profile(named name: String) -> Profile {
        var p = Profile()
        p.name = name
        return p
    }

    func testEmptyNameFallsBackToQuestionMark() {
        XCTAssertEqual(profile(named: "").initials, "?")
    }

    func testSingleWordUsesFirstLetter() {
        XCTAssertEqual(profile(named: "berjil").initials, "B")
    }

    func testTwoWordsUsesBothInitials() {
        XCTAssertEqual(profile(named: "Berjil S").initials, "BS")
    }

    func testMoreThanTwoWordsKeepsFirstTwo() {
        XCTAssertEqual(profile(named: "John Ronald Reuel Tolkien").initials, "JR")
    }

    func testLowercaseIsUppercased() {
        XCTAssertEqual(profile(named: "john smith").initials, "JS")
    }

    func testSurroundingWhitespaceIsIgnored() {
        XCTAssertEqual(profile(named: "  Jane   Doe  ").initials, "JD")
    }

    func testOnlyWhitespaceFallsBackToQuestionMark() {
        XCTAssertEqual(profile(named: "   ").initials, "?")
    }
}

final class ProfileBmiTests: XCTestCase {
    func testNilWhenHeightMissing() {
        XCTAssertNil(Profile.bmi(heightCm: 0, weightKg: 70))
    }

    func testNilWhenWeightMissing() {
        XCTAssertNil(Profile.bmi(heightCm: 175, weightKg: 0))
    }

    func testNilWhenBothInvalid() {
        XCTAssertNil(Profile.bmi(heightCm: -10, weightKg: -5))
    }

    func testComputesStandardBmi() throws {
        let b = try XCTUnwrap(Profile.bmi(heightCm: 175, weightKg: 70))
        XCTAssertEqual(b, 22.86, accuracy: 0.01)
    }

    func testTallAndLightStaysInRange() throws {
        let b = try XCTUnwrap(Profile.bmi(heightCm: 190, weightKg: 80))
        XCTAssertEqual(b, 22.16, accuracy: 0.01)
    }
}

final class ProfileBmiCategoryTests: XCTestCase {
    func testUnderweightJustBelow18_5() {
        XCTAssertEqual(Profile.bmiCategory(17.9), "underweight")
    }

    func testNormalAtBoundary18_5() {
        XCTAssertEqual(Profile.bmiCategory(18.5), "normal range")
    }

    func testNormalJustBelow25() {
        XCTAssertEqual(Profile.bmiCategory(24.9), "normal range")
    }

    func testOverweightAtBoundary25() {
        XCTAssertEqual(Profile.bmiCategory(25), "overweight")
    }

    func testOverweightJustBelow30() {
        XCTAssertEqual(Profile.bmiCategory(29.9), "overweight")
    }

    func testObeseAtBoundary30() {
        XCTAssertEqual(Profile.bmiCategory(30), "obese range")
    }

    func testObeseWayUpHigh() {
        XCTAssertEqual(Profile.bmiCategory(45), "obese range")
    }
}

final class ProfileCodableTests: XCTestCase {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func testRoundTripPreservesEverything() throws {
        var profile = Profile()
        profile.name = "Berjil S"
        profile.dob = "2000-01-01"
        profile.age = 26
        profile.bloodGroup = "O+"
        profile.relationship = "Single"
        profile.phone = "+91 98765 43210"
        profile.email = "berjil@example.com"
        profile.city = "Bengaluru"
        profile.hometown = "Kerala"
        profile.education = "NIT, 2022"
        profile.heightCm = 175
        profile.role = "SWE — Noodlr"
        profile.work = "Building a personal OS."
        profile.website = "https://berjil.com"
        profile.instagram = "@berjil"
        profile.github = "berjil"
        profile.goalsShort = ["Ship MyOS 1.0"]
        profile.goalsMid = ["Marathon"]
        profile.goalsLong = ["Be healthy at 60"]
        profile.achievements = [Milestone(year: "2026", title: "Shipped MyOS", note: "v1.0")]
        profile.healthNotes = "No known allergies."
        profile.about = "Tech founder, night owl."
        profile.habits = ["Gym", "Read"]

        let data = try encoder.encode(profile)
        let decoded = try decoder.decode(Profile.self, from: data)
        XCTAssertEqual(decoded, profile)
    }

    func testDecodeEmptyObjectGivesSeededDefaults() throws {
        let decoded = try decoder.decode(Profile.self, from: Data("{}".utf8))
        XCTAssertEqual(decoded, Profile())
    }

    func testDecodeOldJsonWithoutNewFieldsStillWorks() throws {
        let oldJson = """
        {"name":"Berjil","email":"berjil@example.com"}
        """
        let decoded = try decoder.decode(Profile.self, from: Data(oldJson.utf8))
        XCTAssertEqual(decoded.name, "Berjil")
        XCTAssertEqual(decoded.email, "berjil@example.com")
        XCTAssertNil(decoded.age)
        XCTAssertNil(decoded.heightCm)
        XCTAssertEqual(decoded.about, "")          // field added later
        XCTAssertEqual(decoded.habits, ["Gym", "Read", "No junk", "Sleep"])  // seeded default
        XCTAssertEqual(decoded.achievements, [])
    }

    func testDecodeMissingAchievementsPreservesRest() throws {
        let json = """
        {"name":"A","goalsShort":["One"],"healthNotes":"ok"}
        """
        let decoded = try decoder.decode(Profile.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.name, "A")
        XCTAssertEqual(decoded.goalsShort, ["One"])
        XCTAssertEqual(decoded.healthNotes, "ok")
        XCTAssertEqual(decoded.achievements, [])
    }
}

final class MilestoneCodableTests: XCTestCase {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func testRoundTripPreservesAllFields() throws {
        let m = Milestone(year: "2026-06", title: "First internship", note: "At Noodlr")
        let data = try encoder.encode(m)
        let decoded = try decoder.decode(Milestone.self, from: data)
        XCTAssertEqual(decoded, m)
    }

    func testDecodeMissingIdGeneratesOne() throws {
        let json = """
        {"year":"2026","title":"Shipped"}
        """
        let decoded = try decoder.decode(Milestone.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.year, "2026")
        XCTAssertEqual(decoded.title, "Shipped")
        XCTAssertEqual(decoded.note, "")
        XCTAssertFalse(decoded.id.isEmpty, "a missing id must be generated, not empty")
    }

    func testDecodeMissingYearAndTitleDefaultsToEmpty() throws {
        let decoded = try decoder.decode(Milestone.self, from: Data("{}".utf8))
        XCTAssertEqual(decoded.year, "")
        XCTAssertEqual(decoded.title, "")
        XCTAssertEqual(decoded.note, "")
        XCTAssertFalse(decoded.id.isEmpty)
    }
}
