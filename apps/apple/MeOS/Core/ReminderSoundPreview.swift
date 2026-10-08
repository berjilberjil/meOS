import Foundation
import AVFoundation
#if os(macOS)
import AppKit
#endif

/// Play a reminder sound on demand, so choosing one is done by ear.
///
/// A menu of sound *names* is not a way to pick a sound — "Sosumi" and "Tink"
/// mean nothing until you have heard them next to each other. Selecting one in
/// Settings plays it immediately.
///
/// Both platforms play the same bundled file, so what you hear while choosing on
/// the phone is exactly what the phone will play at 8am. The Mac used to reach
/// for `NSSound(named:)` and the phone had nothing to reach for at all, which
/// meant every choice there previewed as the same drop.
@MainActor
enum ReminderSoundPreview {
    private static var player: AVAudioPlayer?

    static func play(_ choice: ReminderSound) {
        let sound = choice.resolved
        guard sound != .silent else { return }

        // Standard is the system's own alert — there is no file for it, so the
        // Mac borrows the sound macOS actually uses and the phone says so with
        // its own drop rather than pretending.
        guard let file = sound.bundledFile else {
            #if os(macOS)
            NSSound(named: "Funk")?.play()
            #else
            SoundPlayer.open()
            #endif
            return
        }

        guard let url = Bundle.main.url(forResource: file.name, withExtension: file.ext) else { return }
        #if os(iOS)
        // `.playback`, not `.ambient` — the ring/silent switch mutes `.ambient`,
        // and a preview you cannot hear because the phone is on silent is worse
        // than no preview. `.mixWithOthers` leaves anything already playing alone.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        let p = try? AVAudioPlayer(contentsOf: url)
        p?.prepareToPlay()
        p?.play()
        player = p          // held, or it deallocates mid-note
    }
}
