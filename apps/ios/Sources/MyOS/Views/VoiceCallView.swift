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

    enum Phase { case starting, listening, thinking, speaking, blocked }

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
        .background(Palette.bg.ignoresSafeArea())
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
            .fill(phase == .speaking ? Palette.brand : Palette.surface)
            .frame(width: 132, height: 132)
            .overlay(
                Image(systemName: icon)
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(phase == .speaking ? Palette.bg : Palette.text)
            )
            .animation(.knPop, value: phase)
            .knRise(1)
    }

    private var icon: String {
        switch phase {
        case .starting:  return "hourglass"
        case .listening: return "mic.fill"
        case .thinking:  return "ellipsis"
        case .speaking:  return "waveform"
        case .blocked:   return "mic.slash.fill"
        }
    }

    private var transcript: some View {
        VStack(spacing: Gap.tight) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.muted)
            Text(displayText)
                .font(.system(size: 15))
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
        case .speaking:  return agent.displayName
        case .blocked:   return "Microphone access needed"
        }
    }

    private var displayText: String {
        if phase == .blocked {
            return "Turn on Microphone and Speech Recognition for MyOS in Settings."
        }
        if phase == .speaking { return said }
        if !listener.partial.isEmpty { return listener.partial }
        return heard
    }

    private var endButton: some View {
        Button("End") { onEnd() }
            .buttonStyle(KSecondaryButtonStyle())
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
        listener.onSpeechStarted = {
            r.stop()
            turn?.cancel()
            if phase == .speaking || phase == .thinking { phase = .listening }
        }

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

    private func answer(_ text: String) {
        turn?.cancel()
        phase = .thinking
        turn = Task {
            let a = AgentConfig.shared
            let info = APIClient.AgentInfo(name: a.displayName,
                                           tone: a.tone.directive,
                                           custom: a.custom.trimmingCharacters(in: .whitespacesAndNewlines))
            let turns = state.voiceTurns()
            state.appendVoiceTurn(role: "user", content: text)

            var reply: String
            do {
                let outcome = try await state.runCatrineTurn(query: text, turns: turns, agent: info)
                if Task.isCancelled { return }
                reply = ChatAction.parse(outcome.reply).visible
            } catch {
                if Task.isCancelled { return }
                reply = "Something went wrong there."
            }

            state.appendVoiceTurn(role: "assistant", content: reply)
            said = reply
            phase = .speaking
            await router?.speak(reply: reply)
            if !Task.isCancelled { phase = .listening }
        }
    }

    private func finish() {
        turn?.cancel()
        router?.stop()
        listener.stop()
        if authorized { VoiceAudioSession.end() }
    }
}
