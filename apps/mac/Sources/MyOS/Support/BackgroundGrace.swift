import Foundation
#if os(iOS)
import UIKit
#endif

/// A few extra seconds of CPU after the app leaves the screen.
///
/// iOS suspends a process almost immediately once you swipe home.
/// Anything in flight at that moment does not fail — it stops,
/// mid-request. For a state push that was the quietest data-loss path in
/// the app: the PUT was cancelled, the retry that would have saved it
/// never got scheduled, and the next poll after unlock handed the local
/// edit back the server's older copy. Logging a meal and pocketing the
/// phone was enough to lose it.
///
/// Holding a background-task assertion buys the request time to land. It
/// is a request, not a guarantee — the system can still call time — so
/// this is belt on top of the retry ladder, not instead of it.
///
/// On the Mac this is an empty shell: the process is not suspended for
/// being in the background, so there is nothing to ask for.
///
/// Callable from any thread. `UIApplication` is main-actor-only and the
/// pushes that use this do run off it, so both ends hop to the main
/// queue — in FIFO order, which is what stops an `end()` from racing
/// ahead of the `begin` it belongs to.
final class BackgroundGrace: @unchecked Sendable {
    #if os(iOS)
    /// Written and read only on the main queue.
    private final class Box { var id: UIBackgroundTaskIdentifier = .invalid }
    private let box = Box()

    init(name: String) {
        let box = self.box
        DispatchQueue.main.async {
            var handle: UIBackgroundTaskIdentifier = .invalid
            // The expiry handler MUST end the task. iOS kills an app
            // outright for holding an assertion past its deadline.
            handle = UIApplication.shared.beginBackgroundTask(withName: name) {
                guard box.id != .invalid else { return }
                UIApplication.shared.endBackgroundTask(box.id)
                box.id = .invalid
            }
            box.id = handle
        }
    }

    /// Idempotent — safe from a `defer` that runs on any exit path, and
    /// safe if the expiry handler already fired.
    func end() {
        let box = self.box
        DispatchQueue.main.async {
            guard box.id != .invalid else { return }
            UIApplication.shared.endBackgroundTask(box.id)
            box.id = .invalid
        }
    }
    #else
    init(name: String) {}
    func end() {}
    #endif
}
