import SwiftUI

/// The AI command bar — the soul of MyOS. Type one line about your day; Gemini
/// splits it across Finance / Fitness / Journal / Notes and files each piece.
/// Focus lights it with the accent; a soft glow signals it's listening.
struct QuickLogBar: View {
    @EnvironmentObject var state: AppState
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 11) {
                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(focused ? Palette.brand : Palette.muted)
                    .animation(.knFast, value: focused)

                TextField("", text: $text,
                          prompt: Text("Log anything — “spent 200 on auto, 40g protein, gold loan down 5k, felt tired”")
                            .foregroundColor(Palette.faint))
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.text)
                    .focused($focused)
                    .onSubmit(send)

                if state.quickLogBusy {
                    ProgressView().controlSize(.small).tint(Palette.brand)
                } else if !text.isEmpty {
                    Button(action: send) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 22)).foregroundStyle(Palette.brand)
                    }
                    .buttonStyle(KPressStyle())
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 15).padding(.vertical, 12)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(focused ? Palette.brand.opacity(0.75) : Palette.border,
                                  lineWidth: focused ? 1.5 : 1)
            )
            .shadow(color: focused ? Palette.brand.opacity(0.15) : .black.opacity(0.18),
                    radius: focused ? 14 : 7, x: 0, y: focused ? 0 : 3)
            .animation(.knNormal, value: focused)
            .animation(.knFast, value: text.isEmpty)

            if let result = state.quickLogResult {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 12))
                    Text(result).font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(Palette.green)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.knNormal, value: state.quickLogResult)
    }

    private func send() {
        let t = text
        guard !t.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        text = ""
        Task { await state.quickLog(t) }
    }
}
