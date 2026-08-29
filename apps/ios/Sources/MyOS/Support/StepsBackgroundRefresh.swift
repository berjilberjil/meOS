#if os(iOS)
import Foundation
import BackgroundTasks

/// Get the day's steps to the server without anyone opening anything.
///
/// The iPhone is the only device in MyOS with a pedometer, so every step
/// count the Mac shows arrived over sync. But the only thing that ever
/// read the pedometer was a foreground screen — so the sequence to see
/// today's steps on the Mac was: unlock the phone, open MyOS, wait for
/// the push, then go to the Mac and let it poll. Berjil's report was
/// exactly that, in those words. Steps that nobody looked at simply did
/// not exist anywhere but on the phone.
///
/// A background refresh closes it. iOS wakes the app on its own
/// schedule — typically every few tens of minutes, more often at the
/// times of day you actually use it — and that is plenty for a number
/// that only has to be roughly current. CoreMotion history is readable
/// from the background (it is a query against stored data, not a live
/// sensor session), so the wake needs no special sensor entitlement
/// beyond the Motion & Fitness permission the app already holds.
///
/// The app being *killed* is the case worth handling, not the easy one:
/// that is precisely when nothing else will push. So the handler is
/// willing to build its own `AppState` and hydrate from scratch. On iOS
/// that works, because iOS is properly signed and
/// `unlockFromKeychain` actually succeeds — the constraint that makes
/// this impossible on the Mac (see the Keychain note in the project
/// memory) does not apply here.
enum StepsBackgroundRefresh {
    /// Must also appear in Info.plist under `BGTaskSchedulerPermittedIdentifiers`,
    /// or `register` throws at launch and the whole scheme silently dies.
    static let taskId = "com.berjil.myos.steps.refresh"

    /// The live app's state, when there is one. Weak: a background wake
    /// with the app still resident should write into the state already on
    /// screen rather than fight a second copy of it over the same keys.
    @MainActor private static weak var live: AppState?

    @MainActor static func adopt(_ state: AppState) { live = state }

    /// Call once, from `didFinishLaunchingWithOptions`. Registration has
    /// to happen before launch returns; doing it later throws.
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskId, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else { return }
            let work = Task { await run(task) }
            // iOS calls this when the window closes. Cancel and report
            // failure so the next wake is scheduled normally rather than
            // the app being penalised for overrunning.
            task.expirationHandler = { work.cancel() }
        }
    }

    /// Ask for the next wake. Safe to call repeatedly — a duplicate
    /// submit replaces the pending request rather than queueing another.
    static func schedule() {
        let req = BGAppRefreshTaskRequest(identifier: taskId)
        // A floor, not a promise: iOS decides the real cadence from how
        // and when the app is used. Asking for sooner than this earns
        // nothing but throttling.
        req.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(req)
    }

    private static func run(_ task: BGAppRefreshTask) async {
        // First, always. A wake that returns without re-arming is the
        // last wake the app ever gets, and the failure is invisible —
        // steps just quietly stop being current again a day later.
        schedule()

        let ok = await sync()
        task.setTaskCompleted(success: ok)
    }

    @MainActor
    private static func sync() async -> Bool {
        let state: AppState
        if let live, live.phase == .loggedIn {
            state = live
        } else {
            // Cold: no app on screen, or one sitting locked. Build a
            // state and hydrate it. `bootstrap` unlocks from the
            // Keychain, which on iOS succeeds.
            let fresh = AppState()
            await fresh.bootstrap()
            guard fresh.phase == .loggedIn else { return false }
            state = fresh
        }

        guard !Task.isCancelled else { return false }
        await HealthSteps.syncRecent(into: state)

        // `mergeSteps` pushes through the same debounced path as any
        // other write, so returning here would suspend the process with
        // the PUT still in flight. Wait for the queue to drain — with a
        // ceiling, because a wake that hangs on a dead network is a wake
        // iOS learns to stop granting.
        return await state.waitForPushes(timeout: 12)
    }
}
#endif
