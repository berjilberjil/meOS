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
    /// Dock Scan tap — open the camera immediately, skip the library chooser.
    @Published var openScanCamera = false
    /// Five taps on Notes in the dock — reveal hidden notes (Face ID).
    @Published var revealHiddenNotes = false
    /// Open Journal on this `yyyy-MM-dd` (Today streak calendar tap).
    @Published var pendingJournalDate: String?
    /// Tapped the Friday report notification — open Settings on the report.
    @Published var openWeeklyReport = false
    /// Macro Intelligence opens over the whole content area rather than in a
    /// sheet — it is a screen, not a dialog.
    @Published var openMacro = false
}
