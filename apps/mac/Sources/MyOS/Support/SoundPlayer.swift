import Foundation
import AVFoundation

/// Short UI sounds. The splash drop is a bundled wav — no system “lock” beep.
enum SoundPlayer {
    private static var player: AVAudioPlayer?

    static func drop() {
        guard let url = Bundle.main.url(forResource: "drop", withExtension: "wav") else { return }
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        player = try? AVAudioPlayer(contentsOf: url)
        player?.volume = 0.55
        player?.prepareToPlay()
        player?.play()
    }
}
