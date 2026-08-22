import Foundation

/// What the chat widget is currently showing.
enum ChatScreen: Equatable { case panel, call }

/// The chat widget's presentation state, as plain logic.
///
/// This exists because voice originally shipped as a SECOND `.fullScreenCover`
/// chained onto the view that already presents the chat. SwiftUI honours one
/// cover per view, and the "Talk" button that triggered the second lived
/// *inside* the first — so tapping it did nothing at all. Same shape as the
/// `.fileImporter` bug in Events.
///
/// The rule: ONE presentation, whose contents swap. Keeping that as a testable
/// value type means it cannot quietly regress into ordinary-looking SwiftUI.
struct ChatPresentation: Equatable {
    /// Closing the widget must always disarm the call. Otherwise the next tap
    /// on the launcher drops him straight back into a call he already left.
    var open = false {
        didSet { if !open { inCall = false } }
    }
    private(set) var inCall = false

    var screen: ChatScreen { inCall ? .call : .panel }

    mutating func openChat() { open = true }

    /// A call replaces the panel inside the open cover. With nothing presented
    /// there is nothing to replace, so this is a no-op.
    mutating func startCall() {
        guard open else { return }
        inCall = true
    }

    mutating func endCall() { inCall = false }

    mutating func close() { open = false }
}
