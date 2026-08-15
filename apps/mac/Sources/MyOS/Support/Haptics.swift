import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Thin cross-platform haptic feedback shim. On macOS this fires only on a
/// Force Touch trackpad (a no-op otherwise); on iOS it uses the UIKit feedback
/// generators. Call from the main actor.
enum Haptics {
    /// A light tap — generic button press.
    static func tap() {
        #if os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        #else
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    /// A selection tick — a value stepped (slider stop, segment / tab change).
    static func selection() {
        #if os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        #else
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }

    /// Success — a commit landed (send, confirm, log).
    static func success() {
        #if os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        #else
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    /// Warning — a destructive action confirmed (delete).
    static func warning() {
        #if os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        #else
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #endif
    }
}
