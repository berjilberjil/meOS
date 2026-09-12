import XCTest
import Combine
@testable import MyOS

/// Phase 1 of the native-smoothness pass: high-frequency UI state must not
/// broadcast through `AppState.objectWillChange`.
///
/// `AppState` is one `ObservableObject`. Before this pass, the live-activity
/// tick (app switch + every 20s), `chatBusy` flips, busy flags, and
/// `isForeground` were all `@Published` on it — so every screen observing the
/// store (both shells, every Today page, the chat overlay) rebuilt on each
/// tick. These tests pin the isolation: hot values live in narrow stores, and
/// writing them never fires `AppState.objectWillChange`.
@MainActor
final class HotStateTests: XCTestCase {

    private var cancellables = Set<AnyCancellable>()

    override func tearDown() {
        cancellables.removeAll()
        // Leave the shared stores clean for the next test / the host app.
        LiveActivityStore.shared.event = nil
        ChatUIStore.shared.busy = false
        ChatUIStore.shared.pendingPrompt = nil
        ChatUIStore.shared.chatError = nil
        SuggestUIStore.shared.result = nil
        SuggestUIStore.shared.busy = false
        SuggestUIStore.shared.error = nil
        NewsUIStore.shared.result = nil
        NewsUIStore.shared.busy = false
        NewsUIStore.shared.error = nil
        ModuleBusyStore.shared.fold = false
        ModuleBusyStore.shared.macro = false
        ModuleBusyStore.shared.image = false
        ModuleBusyStore.shared.weekly = false
        ModuleBusyStore.shared.plan = false
        ModuleBusyStore.shared.quickLog = false
        super.tearDown()
    }

    private func sampleEvent() -> ActivityEvent {
        ActivityEvent(deviceId: "test", deviceType: .mac, platform: "mac",
                      appId: "com.test.app", appName: "Test",
                      category: .development, startedAt: "2026-09-12T10:00:00",
                      endedAt: "2026-09-12T10:01:00", duration: 60,
                      productivity: .productive, source: .macFrontmost)
    }

    /// Subscribing to `objectWillChange` counts broadcasts without rendering.
    private func broadcastCount(of state: AppState, during work: () -> Void) -> Int {
        var count = 0
        state.objectWillChange.sink { _ in count += 1 }.store(in: &cancellables)
        work()
        return count
    }

    func testLiveActivityDoesNotBroadcastThroughAppState() {
        let state = AppState()
        let count = broadcastCount(of: state) {
            state.liveActivity = sampleEvent()
            state.liveActivity = nil
        }
        XCTAssertEqual(count, 0, "liveActivity must reach only LiveActivityStore observers")
        XCTAssertNil(LiveActivityStore.shared.event)
    }

    func testLiveActivityStorePublishesToItsOwnObservers() {
        let store = LiveActivityStore.shared
        var seen: [ActivityEvent?] = []
        store.$event.sink { seen.append($0) }.store(in: &cancellables)
        store.event = sampleEvent()
        XCTAssertEqual(seen.count, 2)
        XCTAssertEqual(seen.last??.appId, "com.test.app")
    }

    func testChatPresenceDoesNotBroadcastThroughAppState() {
        let state = AppState()
        let count = broadcastCount(of: state) {
            state.chatBusy = true
            state.pendingChatPrompt = "hello"
            state.chatError = "boom"
            state.chatBusy = false
            state.pendingChatPrompt = nil
            state.chatError = nil
        }
        XCTAssertEqual(count, 0, "chat presence must reach only ChatWidget observers")
    }

    func testSuggestionsAndNewsDoNotBroadcastThroughAppState() {
        let state = AppState()
        let count = broadcastCount(of: state) {
            state.suggestBusy = true
            state.suggestBusy = false
            state.suggestError = "e"
            state.suggestError = nil
            state.newsBusy = true
            state.newsBusy = false
            state.newsError = "e"
            state.newsError = nil
        }
        XCTAssertEqual(count, 0, "suggest/news fetches must reach only their own cards")
    }

    func testModuleBusyFlagsDoNotBroadcastThroughAppState() {
        let state = AppState()
        let count = broadcastCount(of: state) {
            state.foldBusy = true
            state.macroBusy = true
            state.imageBusy = true
            state.weeklyBusy = true
            state.planBusy = true
            state.quickLogBusy = true
            state.foldBusy = false
            state.macroBusy = false
            state.imageBusy = false
            state.weeklyBusy = false
            state.planBusy = false
            state.quickLogBusy = false
        }
        XCTAssertEqual(count, 0, "busy flags must reach only their own screens")
    }

    func testForegroundFlagDoesNotBroadcastThroughAppState() {
        let state = AppState()
        let count = broadcastCount(of: state) {
            state.isForeground = false
            state.isForeground = true
        }
        XCTAssertEqual(count, 0, "isForeground drives the poll speed only; no view reads it")
    }

    func testModuleDataStillPublishes() {
        // The point is isolation, not silence: real data changes must still
        // reach observers.
        let state = AppState()
        let count = broadcastCount(of: state) {
            state.notes = []
        }
        XCTAssertGreaterThan(count, 0, "module data must keep publishing through AppState")
    }
}
