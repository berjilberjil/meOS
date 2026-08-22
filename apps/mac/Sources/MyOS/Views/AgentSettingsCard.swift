import SwiftUI

/// Settings editor for the in-app AI assistant — rename it, pick its tone, and add
/// any personal style notes. Writes `AgentConfig.shared` (local, per-device); the
/// chat widget and every future reply pick the change up immediately.
///
/// On the phone the tone is a list, not a five-way segmented control: five labels
/// across a 393pt screen are unreadable, and a list has room to say what each
/// tone actually does — which is the thing you are choosing between.
struct AgentSettingsCard: View {
    var boxed = true
    @ObservedObject private var agent = AgentConfig.shared
    @FocusState private var customFocused: Bool

    var body: some View {
        if boxed { Card { boxedInner } } else { page }
    }

    // MARK: - Phone: a page

    private var page: some View {
        SettingsPage {
            SettingsIntro(text: "How \(agent.displayName) answers you. She keeps replies short; talk to her from the chat bubble on any screen.")

            SettingsGroup(title: "Name") {
                SettingsFieldRow(label: "Assistant", placeholder: "Catherine", text: $agent.name)
            }

            SettingsGroup(title: "Tone", footer: agent.tone.directive) {
                ForEach(Array(AgentTone.allCases.enumerated()), id: \.element) { i, tone in
                    if i > 0 { SettingsDivider(inset: SettingsMetrics.plainInset) }
                    SettingsPickRow(title: tone.label, selected: agent.tone == tone) {
                        Haptics.selection()
                        withAnimation(.knFast) { agent.tone = tone }
                    }
                }
            }

            SettingsGroup(title: "Style notes",
                          footer: "Optional. Anything she should always do.") {
                SettingsTextArea(
                    placeholder: "e.g. keep it under 3 lines, mix Tamil, call me by my name",
                    minHeight: 72,
                    text: $agent.custom)
            }
        }
    }

    // MARK: - Mac: a card

    private var boxedInner: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                SectionTitle(text: "AI assistant")
                Spacer()
                Text("your in-app chat").font(.system(size: 12)).foregroundStyle(Palette.faint)
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
    }
}
