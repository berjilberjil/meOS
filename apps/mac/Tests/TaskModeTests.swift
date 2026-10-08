import XCTest
@testable import meOS

/// Task Mode's rules: which block runs next, what the menu bar says, and that a
/// payload written before the mode existed still decodes.
final class TaskModeTests: XCTestCase {

    private func todos(_ spec: [(String, Bool)]) -> [FocusItem] {
        spec.map { FocusItem(id: $0.0, text: $0.0, done: $0.1) }
    }

    // MARK: Which task runs

    func testNextTakesTheFirstUndone() {
        let list = todos([("a", true), ("b", false), ("c", false)])
        XCTAssertEqual(TaskMode.nextTask(in: list)?.id, "b")
    }

    func testNextStaysOnTheRunningBlock() {
        let list = todos([("a", false), ("b", false)])
        XCTAssertEqual(TaskMode.nextTask(in: list, current: "b")?.id, "b",
                       "entering the mode must not yank you off the block already running")
    }

    func testNextMovesOnOnceTheRunningBlockIsDone() {
        let list = todos([("a", false), ("b", true)])
        XCTAssertEqual(TaskMode.nextTask(in: list, current: "b")?.id, "a")
    }

    func testNextIsNilWhenEverythingIsDone() {
        XCTAssertNil(TaskMode.nextTask(in: todos([("a", true)])))
        XCTAssertNil(TaskMode.nextTask(in: []))
    }

    func testRemainingExcludesDoneAndTheCurrentBlock() {
        let list = todos([("a", true), ("b", false), ("c", false)])
        XCTAssertEqual(TaskMode.remaining(list, excluding: "b").map(\.id), ["c"])
        XCTAssertEqual(TaskMode.remaining(list).map(\.id), ["b", "c"])
    }

    func testDayCrushedNeedsAList() {
        XCTAssertFalse(TaskMode.dayCrushed([]), "an empty day is not a crushed day")
        XCTAssertFalse(TaskMode.dayCrushed(todos([("a", true), ("b", false)])))
        XCTAssertTrue(TaskMode.dayCrushed(todos([("a", true), ("b", true)])))
        XCTAssertEqual(TaskMode.doneCount(todos([("a", true), ("b", false)])), 1)
    }

    // MARK: The menu bar label

    func testMenuLabelPairsTaskAndClock() {
        XCTAssertEqual(TaskMode.menuLabel(task: "Call bank", clock: "18:42"), "Call bank · 18:42")
    }

    func testMenuLabelIsJustTheClockWithoutATask() {
        XCTAssertEqual(TaskMode.menuLabel(task: nil, clock: "5:00"), "5:00")
        XCTAssertEqual(TaskMode.menuLabel(task: "   ", clock: "5:00"), "5:00")
    }

    func testMenuLabelClipsOnAWordBoundary() {
        XCTAssertEqual(TaskMode.clip("Ship the scan history", to: 16), "Ship the scan…")
    }

    func testMenuLabelClipsMidWordWhenThereIsNoBoundaryToUse() {
        XCTAssertEqual(TaskMode.clip("Refactoringtheentireapp", to: 10), "Refactori…")
    }

    func testMenuLabelLeavesShortNamesAlone() {
        XCTAssertEqual(TaskMode.clip("Call bank", to: 16), "Call bank")
    }

    // MARK: The synced switch

    func testStateRoundTrips() throws {
        let on = TaskModeState(on: true, since: "2026-08-23T09:00:00", device: "Mac")
        let back = try JSONDecoder().decode(TaskModeState.self, from: JSONEncoder().encode(on))
        XCTAssertEqual(back, on)
    }

    func testStateDecodesFromAnEmptyObject() throws {
        // What a payload written before Task Mode existed looks like.
        let back = try JSONDecoder().decode(TaskModeState.self, from: Data("{}".utf8))
        XCTAssertFalse(back.on)
        XCTAssertEqual(back.device, "")
    }

    func testPayloadCarriesTheModeUnderItsSyncKey() throws {
        let raw = Data(#"{"myos.taskMode":{"on":true,"since":"2026-08-23T09:00:00","device":"iPhone"}}"#.utf8)
        let payload = try JSONDecoder().decode(AppStatePayload.self, from: raw)
        XCTAssertEqual(payload.taskMode?.on, true)
        XCTAssertEqual(payload.taskMode?.device, "iPhone")
    }
}
