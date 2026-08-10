import SwiftUI

/// The floating mentor. A round button bottom-right on every screen; tap to open a
/// chat panel that talks with full context of your data. Read-only advisor.
struct ChatWidget: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var agent = AgentConfig.shared
    @State private var open = false
    @State private var draft = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if open { panel.transition(.move(edge: .bottom).combined(with: .opacity)) }
            else { launcher.transition(.scale.combined(with: .opacity)) }
        }
        .animation(.knPop, value: open)
        // Opened from elsewhere (e.g. "Ask AI" on a news story) — pop open and send.
        .onChange(of: state.pendingChatPrompt) { _, p in
            guard let p, !p.isEmpty else { return }
            open = true
            state.pendingChatPrompt = nil
            Task { await state.sendChat(p) }
        }
    }

    // MARK: - Launcher

    private var launcher: some View {
        Button { open = true; inputFocused = true } label: {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Palette.brand, Palette.brandDeep],
                                         startPoint: .top, endPoint: .bottom))
                Image(systemName: "sparkles")
                    .font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
            }
            .frame(width: 56, height: 56)
            .knShadow(true)
            .overlay(alignment: .topTrailing) {
                if state.chatBusy {
                    Circle().fill(Palette.amber).frame(width: 12, height: 12)
                        .overlay(Circle().strokeBorder(Palette.bg, lineWidth: 2))
                        .offset(x: 2, y: -2)
                }
            }
        }
        .buttonStyle(KPressStyle(scale: 0.92))
        .onHover { h in cursor(h) }
        .help("Ask \(agent.displayName)")
    }

    // MARK: - Panel

    private var panel: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Palette.border)
            messages
            Divider().overlay(Palette.border)
            inputBar
        }
        .frame(width: 384, height: 544)
        .background(Palette.elevated, in: RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .strokeBorder(Palette.border, lineWidth: 2))
        .knShadow(true)
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(LinearGradient(colors: [Palette.brand, Palette.brandDeep],
                                             startPoint: .top, endPoint: .bottom))
                Image(systemName: "sparkles").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
            }
            .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(agent.displayName).font(.system(size: 14, weight: .heavy, design: .rounded)).foregroundStyle(Palette.text)
                Text("Knows your whole app").font(.system(size: 10)).foregroundStyle(Palette.faint)
            }
            Spacer()
            if !state.chat.messages.isEmpty {
                Button { state.clearChat() } label: { Image(systemName: "trash").font(.system(size: 12)) }
                    .buttonStyle(KIconButtonStyle(size: 28)).help("Clear chat")
            }
            Button { open = false } label: { Image(systemName: "xmark").font(.system(size: 12, weight: .bold)) }
                .buttonStyle(KIconButtonStyle(size: 28)).help("Close")
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
    }

    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if state.chat.messages.isEmpty { emptyState }
                    ForEach(state.chat.messages) { m in bubble(m).id(m.id) }
                    if state.chatBusy {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Thinking…").font(.system(size: 12)).foregroundStyle(Palette.faint)
                        }
                        .id("typing")
                    }
                    if let err = state.chatError {
                        Label(err, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 11)).foregroundStyle(Palette.amber)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: state.chat.messages.count) { _, _ in scrollDown(proxy) }
            .onChange(of: state.chatBusy) { _, _ in scrollDown(proxy) }
        }
    }

    private func scrollDown(_ proxy: ScrollViewProxy) {
        withAnimation(.knFast) {
            if state.chatBusy { proxy.scrollTo("typing", anchor: .bottom) }
            else { proxy.scrollTo(state.chat.messages.last?.id, anchor: .bottom) }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Talk to me about anything — your money and fitness, or markets, tech, content and the world. Short answers unless you ask for the long version.")
                .font(.system(size: 13)).foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 7) {
                starter("Am I on track to clear the gold loan?")
                starter("What's moving in the markets today?")
                starter("Give me a reel hook on this week's finance news")
                starter("Am I eating enough protein for my goal?")
            }
        }
        .padding(.vertical, 6)
    }

    private func starter(_ text: String) -> some View {
        Button { draft = text; send() } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .bold))
                Text(text).font(.system(size: 12, weight: .medium)).multilineTextAlignment(.leading)
            }
            .foregroundStyle(Palette.text)
            .padding(.horizontal, 11).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface2.opacity(0.55), in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
        }
        .buttonStyle(KPressStyle())
        .onHover { h in cursor(h) }
    }

    private func bubble(_ m: ChatMessage) -> some View {
        let isUser = m.role == "user"
        return HStack {
            if isUser { Spacer(minLength: 40) }
            Text(attributed(m.content))
                .font(.system(size: 13)).foregroundStyle(isUser ? .white : Palette.text)
                .textSelection(.enabled)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(isUser ? AnyShapeStyle(Palette.brand) : AnyShapeStyle(Palette.surface2),
                            in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .frame(maxWidth: 300, alignment: isUser ? .trailing : .leading)
            if !isUser { Spacer(minLength: 40) }
        }
    }

    /// Render light markdown (bold/italic/links) in the reply; fall back to plain.
    private func attributed(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("", text: $draft, prompt: Text("Ask \(agent.displayName)…").foregroundColor(Palette.faint), axis: .vertical)
                .textFieldStyle(.plain).font(.system(size: 13)).foregroundStyle(Palette.text)
                .lineLimit(1...4)
                .focused($inputFocused)
                .onSubmit(send)
            Button(action: send) {
                Image(systemName: "arrow.up").font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(.white).frame(width: 30, height: 30)
                    .background(canSend ? AnyShapeStyle(Palette.brand) : AnyShapeStyle(Palette.surface2), in: Circle())
            }
            .buttonStyle(KPressStyle(scale: 0.9))
            .disabled(!canSend)
            .onHover { h in cursor(h) }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !state.chatBusy
    }

    private func send() {
        let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !state.chatBusy else { return }
        draft = ""
        Task { await state.sendChat(t) }
    }
}
