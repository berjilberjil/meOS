import SwiftUI

/// Lightweight, transient app-wide UI signals (NOT persisted). Lets a container
/// — e.g. the iOS tab bar — ask a deeper screen to do something without
/// threading bindings through the shared views. Lives in Support/ so both
/// platforms compile it (only iOS uses it today).
final class UISignals: ObservableObject {
    static let shared = UISignals()
    private init() {}

    /// Set true to ask the Events screen to open a fresh event editor; the
    /// screen consumes it, then resets it.
    @Published var pendingNewEvent = false
    /// Dock Scan tap — open the camera immediately, skip the library chooser.
    @Published var openScanCamera = false
    /// Five taps on Notes in the dock — reveal hidden notes (Face ID).
    @Published var revealHiddenNotes = false
    /// Tapped the Friday report notification — open Settings on the report.
    @Published var openWeeklyReport = false
    /// A Home Screen widget tap — open the Six-Pack tracker. Parked like
    /// `pendingRoute` so it survives a cold launch that stops at the vault lock.
    @Published var openSixPack = false

    /// A tapped notification's destination, waiting for a screen to take it.
    ///
    /// It is *parked* rather than acted on because of when a tap arrives. From
    /// a killed app the notification response is delivered before any SwiftUI
    /// view exists, and MeOS then sits at the vault lock until Face ID or the
    /// Keychain lets it through. A signal consumed only by `.onChange` is
    /// therefore swallowed on exactly the journey that matters most — the phone
    /// in your pocket, hours after you last opened the app. Screens consume this
    /// on appear *and* on change; whichever happens second finds it already nil.
    @Published var pendingRoute: NotifRoute?

    /// Scroll the Today page to this section (a `TodaySection` raw value).
    @Published var todayAnchor: String?

    /// Open Today's editor for this meal.
    @Published var pendingMeal: MealKey?
    /// Settings lives at the bottom of the iOS Today page, not in the toolbar.
    @Published var openSettings = false
    /// Macro Intelligence opens over the whole content area rather than in a
    /// sheet — it is a screen, not a dialog.
    @Published var openMacro = false
}
