import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Task Mode — the app with everything else taken away. No sidebar, no dock, no
/// chat widget: one task, its timer, and what is left of today.
///
/// `RootView` swaps this in for `MainView`, which is why one switch covers both
/// platforms. The screen itself is `FocusSessionView`; this view's whole job is
/// to give it the window, start the first block, and hand back the way out.
struct TaskModeView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var timer = FocusTimer.shared
    @AppStorage("focus.defaultMinutes") private var defaultMinutes = 25

    private var items: [FocusItem] { state.todayPlan().todos }

    var body: some View {
        ZStack {
            HueCanvas()
            FocusSessionView(defaultMinutes: defaultMinutes) { leave() }
        }
        .overlay(alignment: .bottom) { origin }
        .onAppear { arm(); keepAwake(timer.running) }
        // Adding the first to-do from inside the mode starts it — no second tap.
        .onChange(of: items.count) { _, _ in arm() }
        .onChange(of: timer.running) { _, running in keepAwake(running) }
        .onDisappear { keepAwake(false) }
        #if os(macOS)
        .onExitCommand { leave() }
        #endif
    }

    /// The mode is synced, so a device can find itself in it without having done
    /// anything. Say where it came from instead of just going blank.
    @ViewBuilder private var origin: some View {
        if state.taskModeCameFromElsewhere {
            Text("Turned on from your \(state.taskMode.device)")
                .font(.caption2.weight(.heavy))
                .foregroundStyle(Palette.faint)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(.hueFillStrong, in: Capsule())
                .padding(.bottom, 14)
        }
    }

    /// Entering with nothing running drops straight into the first thing left —
    /// the mode is for crushing, not for choosing.
    private func arm() {
        guard !timer.isActive, let next = TaskMode.nextTask(in: items) else { return }
        timer.begin(next, minutes: next.mins ?? defaultMinutes)
    }

    private func leave() {
        // `endSession` already paused and banked; this catches the case where the
        // mode is left some other way with seconds still unbanked.
        if let id = timer.itemID { state.addTodoSpent(id, seconds: timer.drainSpent()) }
        keepAwake(false)
        state.setTaskMode(false)
    }

    /// A countdown you are watching should not be interrupted by the lock screen.
    private func keepAwake(_ on: Bool) {
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = on
        #endif
    }
}
