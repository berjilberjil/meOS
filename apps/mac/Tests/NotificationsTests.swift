import XCTest
@testable import MyOS

final class NotificationsTests: XCTestCase {
    func testDefaultsHaveTheFiveReminders() {
        let all = ReminderDefaults.all()
        XCTAssertEqual(all.map(\.id), ["wake", "breakfast", "lunch", "workout", "dinner"])
        let lunch = all.first { $0.id == "lunch" }
        XCTAssertEqual(lunch?.hour, 12); XCTAssertEqual(lunch?.minute, 30)
        let wake = all.first { $0.id == "wake" }
        XCTAssertEqual(wake?.hour, 6); XCTAssertEqual(wake?.minute, 0)
    }

    func testMergedHonorsSavedTimeAndEnabledDropsUnknownRestoresLabels() {
        let saved = [
            Reminder(id: "lunch", label: "old", body: "old", hour: 13, minute: 15, enabled: false),
            Reminder(id: "ghost", label: "x", body: "x", hour: 1, minute: 1, enabled: true)
        ]
        let merged = ReminderDefaults.merged(saved: saved)
        XCTAssertEqual(merged.count, 5)                          // all defaults kept, ghost dropped
        let lunch = merged.first { $0.id == "lunch" }!
        XCTAssertEqual(lunch.hour, 13); XCTAssertEqual(lunch.minute, 15)  // saved time honored
        XCTAssertFalse(lunch.enabled)                            // saved enabled honored
        XCTAssertEqual(lunch.label, "Lunch")                    // canonical label restored
        XCTAssertFalse(merged.contains { $0.id == "ghost" })
    }
}
