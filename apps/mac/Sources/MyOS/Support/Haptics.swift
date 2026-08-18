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
    #if os(iOS)
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let soft = UIImpactFeedbackGenerator(style: .soft)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private static let select = UISelectionFeedbackGenerator()
    private static let notify = UINotificationFeedbackGenerator()
    #endif

    /// Warm the Taptic Engine so the next tick isn't delayed.
    static func prepare() {
        #if os(iOS)
        light.prepare(); soft.prepare(); rigid.prepare()
        heavy.prepare(); select.prepare(); notify.prepare()
        #endif
    }

    /// A light tap — generic button press.
    static func tap() {
        #if os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        #else
        light.impactOccurred(intensity: 0.7)
        #endif
    }

    /// A selection tick — a value stepped (slider stop, segment / tab change).
    static func selection() {
        #if os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        #else
        select.selectionChanged()
        #endif
    }

    /// Detents along a slide-to-confirm — short clicks as the thumb travels.
    static func slideTicks(_ count: Int) {
        guard count > 0 else { return }
        #if os(macOS)
        for _ in 0..<count {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        #else
        for i in 0..<count {
            let intensity = min(1, 0.45 + CGFloat(i) * 0.12)
            soft.impactOccurred(intensity: intensity)
        }
        #endif
    }

    /// Thumb reached the end — a heavier click plus success.
    static func slideCommit() {
        #if os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        #else
        rigid.impactOccurred(intensity: 1)
        heavy.impactOccurred(intensity: 0.9)
        notify.notificationOccurred(.success)
        #endif
    }

    /// Released early — a soft bump as it snaps back.
    static func slideCancel() {
        #if os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        #else
        light.impactOccurred(intensity: 0.35)
        #endif
    }

    /// Success — a commit landed (send, confirm, log).
    static func success() {
        #if os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        #else
        notify.notificationOccurred(.success)
        #endif
    }

    /// Warning — a destructive action confirmed (delete).
    static func warning() {
        #if os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        #else
        notify.notificationOccurred(.warning)
        #endif
    }
}
