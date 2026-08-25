import SwiftUI

/// Talking to Catrine.
///
/// The loop is deliberately the same one the text chat uses: a transcript goes
/// into `runCatrineTurn` and a reply comes out, so her tools, retrieval, memory
/// and bounded reasoning are identical whether he typed or spoke. Voice is an
/// I/O change, not a brain change.
struct VoiceCallView: View {
    /// Called when he ends the call. The call is a screen INSIDE the chat
    /// widget's cover, not its own presentation, so it cannot use `dismiss` —
    /// that would tear down the whole widget instead of returning to the chat.
    let onEnd: () -> Void

    @EnvironmentObject private var state: AppState
    @StateObject private var listener = SpeechListener()
    @ObservedObject private var agent = AgentConfig.shared

    @State private var phase: Phase = .starting
    @State private var heard = ""
    @State private var said = ""
    @State private var router: VoiceRouter?
    @State private var turn: Task<Void, Never>?
    @State private var authorized = false
    @State private var failures = 0
    @State private var lastError = ""

    enum Phase { case starting, listening, thinking, speaking, blocked, failed }

    var body: some View {
        VStack(spacing: Gap.screen) {
            header
            Spacer(minLength: 0)
            orb
            transcript
            Spacer(minLength: 0)
            endButton
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background)
        .task { await begin() }
        .onDisappear { finish() }
    }

    // MARK: - Pieces

    private var header: some View {
        HStack {
            ScreenTitle(text: agent.displayName)
            Spacer()
        }
        .knRise(0)
    }

    private var orb: some View {
        Circle()
            .fill(phase == .speaking ? Palette.action : Palette.surface)
            .frame(width: 132, height: 132)
            .overlay(
                Image(systemName: icon)
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(phase == .speaking ? Palette.background : Palette.text)
            )
            .animation(.knPop, value: phase)
            .contentShape(Circle())
            .onTapGesture { interrupt() }
            .knRise(1)
    }

    private var icon: String {
        switch phase {
        case .starting:  return "hourglass"
        case .listening: return "mic.fill"
        case .thinking:  return "ellipsis"
        case .speaking:  return "waveform"
        case .blocked:   return "mic.slash.fill"
        case .failed:    return "exclamationmark.triangle.fill"
        }
    }

    private var transcript: some View {
        VStack(spacing: Gap.tight) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.muted)
            Text(displayText)
                .font(.subheadline)
                .foregroundStyle(Palette.text)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 72, alignment: .top)
        }
        .knRise(2)
    }

    private var label: String {
        switch phase {
        case .starting:  return "Connecting"
        case .listening: return "Listening"
        case .thinking:  return "Thinking"
        case .speaking:  return router?.remoteExhausted == true
                            ? "\(agent.displayName) · basic voice"
                            : agent.displayName
        case .blocked:   return "Microphone access needed"
        case .failed:    return "She could not answer"
        }
    }

    private var displayText: String {
        if phase == .blocked {
            return "Turn on Microphone and Speech Recognition for MyOS in Settings."
        }
        if phase == .failed { return lastError }
        if phase == .speaking { return said }
        if !listener.partial.isEmpty { return listener.partial }
        return heard
    }

    private var endButton: some View {
        Button("End") { onEnd() }
            .buttonStyle(.bordered)
            .knRise(3)
    }

    // MARK: - Lifecycle

    private func begin() async {
        guard await listener.requestAuthorization() else {
            phase = .blocked
            return
        }
        authorized = true

        VoiceAudioSession.begin()
        let r = VoiceRouter(remote: AuraSynth(api: state.api), local: SystemSynth())
        router = r

        // Barge-in: the moment he speaks, she stops. This fires on the first
        // partial result, not the final transcript — a final would be far too late.
        // NOTE: no voice-triggered barge-in. The mic is muted while she
        // speaks, so it cannot hear her; interrupting is a tap on the orb.

        listener.onFinal = { text in
            heard = text
            answer(text)
        }

        do {
            try listener.start()
            phase = .listening
        } catch {
            phase = .blocked
        }
    }

    /// Spoken answers are a different medium from written ones.
    ///
    /// Without this she writes a document and then reads it aloud: numbered
    /// lists, bold headings, 700 characters. That is slow to generate, slow to
    /// speak, and sounds nothing like a person. It rides in on `custom`, which
    /// the server injects as "this overrides the defaults above".
    ///
    /// It goes FIRST so that if the server's 600-character cap truncates
    /// anything, it truncates his styling and not the thing keeping her short.
    private static let voiceDirective = """
    YOU ARE BEING SPOKEN ALOUD ON A PHONE CALL. Reply in at most two or three     short sentences, the way a person actually talks. Never use markdown,     asterisks, bullet points, numbered lists or headings — they get read out as     words. Do not enumerate options: pick the single most important thing and     say that. He will ask if he wants more.
    """

    private func answer(_ text: String) {
        turn?.cancel()
        phase = .thinking
        turn = Task {
            let a = AgentConfig.shared
            let info = APIClient.AgentInfo(name: a.displayName,
                                           tone: a.tone.directive,
                                           custom: Self.voiceDirective + " " +
                                                   a.custom.trimmingCharacters(in: .whitespacesAndNewlines))
            let turns = state.voiceTurns()
            state.appendVoiceTurn(role: "user", content: text)

            var reply: String
            do {
                let outcome = try await state.runCatrineTurn(
                    query: text, turns: turns, agent: info,
                    maxRounds: 2, timeout: 25)
                if Task.isCancelled { return }
                reply = ChatAction.parse(outcome.reply).visible
                failures = 0
            } catch is CancellationError {
                return
            } catch {
                if Task.isCancelled { return }
                failures += 1

                // Say the ACTUAL error, once. A generic "something went wrong"
                // told us nothing and was impossible to diagnose from the phone.
                let detail = (error as? APIError)?.message ?? error.localizedDescription
                lastError = detail

                // Two failures in a row means it is not going to fix itself.
                // Stop talking and put the error on screen instead of reciting
                // it forever — a spoken error the mic can hear is a loop.
                if failures >= 2 {
                    phase = .failed
                    return
                }
                reply = detail
            }

            state.appendVoiceTurn(role: "assistant", content: reply)
            said = reply
            phase = .speaking

            // Deaf while she talks, or she answers her own voice forever.
            listener.isMuted = true
            await router?.speak(reply: reply)
            listener.isMuted = false

            if !Task.isCancelled { phase = .listening }
        }
    }

    /// Cut her off. The mic is deaf while she speaks (see `listener.isMuted`),
    /// so interrupting is a deliberate tap rather than talking over her.
    private func interrupt() {
        guard phase == .speaking || phase == .thinking else { return }
        turn?.cancel()
        router?.stop()
        listener.isMuted = false
        phase = .listening
    }

    private func finish() {
        turn?.cancel()
        router?.stop()
        listener.stop()
        if authorized { VoiceAudioSession.end() }
    }
}
