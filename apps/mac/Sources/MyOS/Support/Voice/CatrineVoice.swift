import Foundation
import AVFoundation

/// Something that can say a sentence out loud.
///
/// `speak` returns **false** to mean "I couldn't — use the other one". It never
/// throws, because from the caller's side a spent budget and a dead network are
/// the same event: fall back and keep the conversation going.
protocol SpeechSynth: AnyObject {
    func speak(_ text: String) async -> Bool
    func stop()
}

/// Catrine's good voice — Deepgram Aura, on the Cloudflare account that already
/// holds everything else. Free until the day's allowance runs out.
final class AuraSynth: SpeechSynth, @unchecked Sendable {
    private let api: APIClient
    private let speaker: String
    private var player: AVAudioPlayer?
    private let lock = NSLock()

    init(api: APIClient, speaker: String = "athena") {
        self.api = api
        self.speaker = speaker
    }

    func speak(_ text: String) async -> Bool {
        guard let data = try? await api.speak(text: text, speaker: speaker) else { return false }
        guard let p = try? AVAudioPlayer(data: data) else { return false }
        lock.lock(); player = p; lock.unlock()
        p.prepareToPlay()
        p.play()
        // Hold the turn until the clip finishes, so sentences don't overlap.
        while p.isPlaying {
            try? await Task.sleep(nanoseconds: 60_000_000)
            if Task.isCancelled { p.stop(); return true }
        }
        return true
    }

    func stop() {
        lock.lock(); let p = player; player = nil; lock.unlock()
        p?.stop()
    }
}

/// The always-available voice. Free, offline, unlimited — and clearly synthetic,
/// which is the price of never paying. Prefers a downloaded Premium/Enhanced
/// voice over the compact default, because the difference is large.
final class SystemSynth: NSObject, SpeechSynth, @unchecked Sendable {
    private let synth = AVSpeechSynthesizer()
    private var continuation: CheckedContinuation<Bool, Never>?
    private let lock = NSLock()

    /// Best installed English voice: Premium, else Enhanced, else the default.
    static func bestVoice(language: String = "en-US") -> AVSpeechSynthesisVoice? {
        let prefix = String(language.prefix(2))
        let candidates = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(prefix) }
        return candidates.first { $0.quality == .premium }
            ?? candidates.first { $0.quality == .enhanced }
            ?? AVSpeechSynthesisVoice(language: language)
    }

    override init() {
        super.init()
        synth.delegate = self
    }

    func speak(_ text: String) async -> Bool {
        await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            lock.lock(); continuation = c; lock.unlock()
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = Self.bestVoice()
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate
            synth.speak(utterance)
        }
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
        finish()
    }

    fileprivate func finish() {
        lock.lock()
        let c = continuation
        continuation = nil
        lock.unlock()
        c?.resume(returning: true)
    }
}

extension SystemSynth: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) { finish() }
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) { finish() }
}

/// Decides which mouth speaks, sentence by sentence.
///
/// The rule that matters: once the remote voice has refused ONCE, stay on the
/// fallback for the rest of the session. The refusal means the daily budget is
/// gone, and that does not un-happen before midnight UTC — probing again on
/// every sentence would just add a wasted round trip to each one.
final class VoiceRouter: @unchecked Sendable {
    private let remote: SpeechSynth
    private let local: SpeechSynth
    private let lock = NSLock()
    private var exhausted = false
    private var speaking = false
    private var cancelled = false

    var remoteExhausted: Bool {
        lock.lock(); defer { lock.unlock() }
        return exhausted
    }

    init(remote: SpeechSynth, local: SpeechSynth) {
        self.remote = remote
        self.local = local
    }

    /// Speak a whole reply. Returns when she has finished, or when `stop()` cut in.
    ///
    /// `cancelled` is cleared here, not in `stop()`: a barge-in must kill the
    /// reply in flight, but it must NOT mute the answer to the question he just
    /// interrupted with. Cancellation is scoped to one reply, deliberately.
    func speak(reply: String) async {
        lock.lock(); cancelled = false; speaking = true; lock.unlock()
        defer { lock.lock(); speaking = false; lock.unlock() }

        for sentence in VoiceText.sentences(reply) {
            lock.lock()
            let stop = cancelled
            let useLocal = exhausted
            lock.unlock()
            if stop { return }

            if useLocal {
                _ = await local.speak(sentence)
                continue
            }
            if await remote.speak(sentence) { continue }

            lock.lock(); exhausted = true; lock.unlock()
            _ = await local.speak(sentence)
        }
    }

    /// Barge-in. Kills the current clip and drops everything queued behind it.
    func stop() {
        lock.lock(); cancelled = speaking; lock.unlock()
        remote.stop()
        local.stop()
    }
}
