import Foundation
#if os(iOS)
import AVFoundation
#endif

/// Balance tracking for the audio session, split out so it can be tested.
///
/// `AVAudioSession` is iOS-only and cannot be exercised from the macOS test
/// bundle, so the part that actually goes wrong — forgetting to restore, or
/// restoring while a call is still running — lives here as plain arithmetic.
struct AudioSessionState {
    private(set) var depth = 0

    /// Returns true when the caller should configure the session for a call.
    mutating func enter() -> Bool {
        depth += 1
        return depth == 1
    }

    /// Returns true when the caller should restore the previous configuration.
    mutating func exit() -> Bool {
        guard depth > 0 else { return false }
        depth -= 1
        return depth == 0
    }
}

/// Putting the phone into call mode, and — the part that matters — putting it back.
///
/// `SoundPlayer` runs the app's UI sound on `.playback` + `.mixWithOthers`
/// (fixed 2026-08-19 so the ring/silent switch stops muting it). A call needs
/// `.playAndRecord` + `.voiceChat`. If the swap is not undone on EVERY exit
/// path, UI sound dies after the first call — so `end()` belongs in a `defer`
/// or an `onDisappear`, never at the bottom of a happy path.
enum VoiceAudioSession {
    private static var state = AudioSessionState()
    private static let lock = NSLock()

    static var isActive: Bool {
        lock.lock(); defer { lock.unlock() }
        return state.depth > 0
    }

    static func begin() {
        lock.lock()
        let shouldConfigure = state.enter()
        lock.unlock()
        guard shouldConfigure else { return }
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord,
                                 mode: .voiceChat,
                                 options: [.defaultToSpeaker, .allowBluetooth])
        try? session.setActive(true)
        #endif
    }

    static func end() {
        lock.lock()
        let shouldRestore = state.exit()
        lock.unlock()
        guard shouldRestore else { return }
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: [.notifyOthersOnDeactivation])
        // Back to what SoundPlayer expects, or the drop sound goes silent.
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        #endif
    }
}
