import Foundation
import AVFoundation
#if os(iOS)
import UIKit
#endif

/// Short UI sounds, all voiced by the one bundled drop. Playback rate splits it
/// into distinct characters — a bright drop when the app opens, a deeper settle
/// when it closes — so no second asset and no system beeps.
enum SoundPlayer {
    private static var player: AVAudioPlayer?

    /// Splash / launch.
    static func drop() { play(rate: 1.0, volume: 0.55) }

    /// The app came back to the foreground — brighter and quicker than the splash.
    static func open() { play(rate: 1.12, volume: 0.5) }

    /// The app is going away — the same drop pitched down into a soft settle.
    static func close() {
        #if os(iOS)
        // Backgrounding suspends us almost immediately, which would cut the sound
        // off mid-note. Hold a short assertion so it gets to finish.
        var task = UIBackgroundTaskIdentifier.invalid
        task = UIApplication.shared.beginBackgroundTask(withName: "myos.close.sound") {
            UIApplication.shared.endBackgroundTask(task)
            task = .invalid
        }
        play(rate: 0.66, volume: 0.42)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            guard task != .invalid else { return }
            UIApplication.shared.endBackgroundTask(task)
            task = .invalid
        }
        #else
        play(rate: 0.66, volume: 0.42)
        #endif
    }

    private static func play(rate: Float, volume: Float) {
        guard let url = Bundle.main.url(forResource: "drop", withExtension: "wav") else { return }
        #if os(iOS)
        // `.playback`, NOT `.ambient` — the ring/silent switch mutes `.ambient`,
        // which is why nothing was audible on the iPhone. `.mixWithOthers` keeps
        // whatever's already playing alive underneath.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        let p = try? AVAudioPlayer(contentsOf: url)
        p?.enableRate = true          // must be set before prepareToPlay
        p?.rate = rate
        p?.volume = volume
        p?.prepareToPlay()
        p?.play()
        player = p
    }
}
