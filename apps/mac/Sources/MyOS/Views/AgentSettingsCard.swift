import SwiftUI

/// Settings editor for the in-app AI assistant — rename it, pick its tone, and add
/// any personal style notes. Writes `AgentConfig.shared` (local, per-device); the
/// chat widget and every future reply pick the change up immediately. Lives in its
/// own file so it plugs into Settings with a single line.
struct AgentSettingsCard: View {
    var boxed = true
    @ObservedObject private var agent = AgentConfig.shared
    @FocusState private var customFocused: Bool

    var body: some View {
        let inner = VStack(alignment: .leading, spacing: 16) {
                if boxed {
                    HStack {
                        SectionTitle(text: "AI assistant")
                        Spacer()
                        Text("your in-app chat").font(.system(size: 12)).foregroundStyle(Palette.faint)
                    }
                }

                KLabeledField(label: "Assistant name", placeholder: "Catherine", text: $agent.name)

                VStack(alignment: .leading, spacing: 6) {
                    KFieldLabel(text: "Tone")
                    Segmented(options: AgentTone.allCases.map { ($0, $0.label) },
                              selection: Binding(get: { agent.tone }, set: { agent.tone = $0 }))
                    Text(agent.tone.directive)
                        .font(.system(size: 14)).foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 5) {
                    KFieldLabel(text: "Extra style notes (optional)")
                    TextField("", text: $agent.custom,
                              prompt: Text("e.g. keep it under 3 lines, mix Tamil, call me by my name")
                                .foregroundColor(Palette.faint),
                              axis: .vertical)
                        .textFieldStyle(.plain).font(.system(size: 16)).foregroundStyle(Palette.text)
                        .lineLimit(2...4)
                        .focused($customFocused)
                        .knField(focused: customFocused)
                }

                Text("\(agent.displayName) keeps answers short. Talk from the chat bubble on any screen.")
                    .font(.system(size: 14)).foregroundStyle(Palette.faint)
                    .fixedSize(horizontal: false, vertical: true)
        }
        // `boxed` off means this is already a full settings PAGE on iOS, which
        // supplies its own padding and background. Wrapping in a Card there adds
        // a second surface and shoves the content 18pt further in than the pages
        // that get this right — which is what made Settings look misaligned.
        if boxed { Card { inner } } else { inner }
    }
}
