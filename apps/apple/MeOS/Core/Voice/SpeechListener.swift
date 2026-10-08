import Foundation
import os
import Speech
import AVFoundation

/// Catrine's ears — entirely on the device.
///
/// `requiresOnDeviceRecognition = true` is the whole privacy story: the audio is
/// transcribed by the phone's own model and the microphone stream never reaches
/// a server. It is also why listening is unlimited and free, which is what makes
/// the daily budget in `/api/voice/speak` cover only her half of the conversation.
///
/// iOS 26's `SpeechAnalyzer` is faster and more accurate, but the deployment
/// target is 17, so `SFSpeechRecognizer` is the floor. Both are on-device; the
/// newer one is a later upgrade behind `#available`, not a prerequisite.
@MainActor
final class SpeechListener: ObservableObject {

    /// What he is saying right now, updated as he says it.
    @Published private(set) var partial = ""

    /// A complete utterance — this is what gets sent to Catrine.
    var onFinal: ((String) -> Void)?

    /// Voice detected while she was talking. This is the barge-in trigger, and
    /// it fires on the FIRST partial result, not on a final transcript —
    /// waiting for a final would be far too late to feel like an interruption.
    var onSpeechStarted: (() -> Void)?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-IN"))
        ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silenceTimer: Timer?
    private var sawSpeechThisUtterance = false

    /// Deaf while Catrine talks.
    ///
    /// On speakerphone the microphone hears HER, transcribes it, and feeds it
    /// back as a new question — she then answers herself forever. Hardware echo
    /// cancellation (below) removes most of it, but "most" is not good enough
    /// for a loop that never terminates, so audio is simply not fed to the
    /// recogniser while she is speaking. Interrupting her is a tap on the orb.
    var isMuted = false {
        // Copy out first: the lock's closure is Sendable and cannot capture a
        // main-actor-isolated property.
        didSet {
            let muted = isMuted
            mutedFlag.withLock { $0 = muted }
        }
    }

    /// `isMuted` read from the audio tap, which is not on the main actor.
    private let mutedFlag = OSAllocatedUnfairLock(initialState: false)
    nonisolated var isMutedUnsafe: Bool { mutedFlag.withLock { $0 } }

    /// How long a pause ends an utterance. Short enough to feel responsive,
    /// long enough to survive thinking mid-sentence.
    private let endpointSilence: TimeInterval = 1.1

    enum ListenerError: Error { case unavailable }

    func requestAuthorization() async -> Bool {
        let speech = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
        guard speech else { return false }
        #if os(iOS)
        return await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            AVAudioApplication.requestRecordPermission { c.resume(returning: $0) }
        }
        #else
        return true
        #endif
    }

    func start() throws {
        guard let recognizer, recognizer.isAvailable else { throw ListenerError.unavailable }
        stop()

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.requiresOnDeviceRecognition = true      // never leaves the device
        request = req

        let input = engine.inputNode
        // Hardware echo cancellation — stops the mic hearing the speaker.
        // Must be set before the engine starts.
        try? input.setVoiceProcessingEnabled(true)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { [weak self] buffer, _ in
            if self?.isMutedUnsafe == true { return }
            req.append(buffer)
        }
        engine.prepare()
        try engine.start()

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let failed = error != nil
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let text, !text.isEmpty {
                    if !self.sawSpeechThisUtterance {
                        self.sawSpeechThisUtterance = true
                        self.onSpeechStarted?()
                    }
                    self.partial = text
                    self.armEndpoint()
                }
                if failed { self.flush() }
            }
        }
    }

    func stop() {
        silenceTimer?.invalidate(); silenceTimer = nil
        task?.cancel(); task = nil
        request?.endAudio(); request = nil
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        partial = ""
        sawSpeechThisUtterance = false
    }

    /// Restart the "has he stopped talking?" clock on every new word.
    private func armEndpoint() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: endpointSilence, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.flush() }
        }
    }

    private func flush() {
        let text = partial.trimmingCharacters(in: .whitespacesAndNewlines)
        partial = ""
        sawSpeechThisUtterance = false
        silenceTimer?.invalidate(); silenceTimer = nil
        guard !text.isEmpty else { return }
        onFinal?(text)
    }
}
