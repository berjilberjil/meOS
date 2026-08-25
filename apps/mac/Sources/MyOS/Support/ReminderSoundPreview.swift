import Foundation
#if os(macOS)
import AppKit
#else
import AVFoundation
#endif

/// Play a reminder sound on demand, so choosing one is done by ear.
///
/// A menu of sound *names* is not a way to pick a sound — "Sosumi" and "Tink"
/// mean nothing until you have heard them next to each other. Selecting one in
/// Settings plays it immediately.
@MainActor
enum ReminderSoundPreview {

    static func play(_ choice: ReminderSound) {
        switch choice.resolved {
        case .silent:
            return
        case .drop:
            #if os(iOS)
            SoundPlayer.open()
            #else
            playBundled("drop", ext: "wav")
            #endif
        case .standard:
            #if os(macOS)
            NSSound(named: "Funk")?.play()   // the system's own default alert
            #else
            // iOS has no way to preview the standard notification sound from
            // inside the app; the bundled one is the only audible answer.
            SoundPlayer.open()
            #endif
        default:
            #if os(macOS)
            if let name = choice.systemName { NSSound(named: name)?.play() }
            #endif
        }
    }

    #if os(macOS)
    private static func playBundled(_ name: String, ext: String) {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext),
              let sound = NSSound(contentsOf: url, byReference: true) else { return }
        sound.play()
    }
    #endif
}
