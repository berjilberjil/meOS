import SwiftUI

/// Lightweight, transient app-wide UI signals (NOT persisted). Lets a container
/// — e.g. the iOS tab bar — ask a deeper screen to do something without
/// threading bindings through the shared views. Lives in Support/ so both
/// platforms compile it (only iOS uses it today).
final class UISignals: ObservableObject {
    static let shared = UISignals()
    private init() {}

    /// Set true when the user double-taps the Journal tab; the Events screen
    /// consumes it to open a fresh event editor, then resets it.
    @Published var pendingNewEvent = false
}
