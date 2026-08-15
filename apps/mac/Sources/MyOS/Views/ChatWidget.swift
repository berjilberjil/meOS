import SwiftUI

/// The floating mentor. A round launcher bottom-right on every screen; tap to open a
/// chat panel that talks with full context of your data. Supports multiple
/// conversations (New / History / Delete). On Mac it's a floating panel; on iPhone it
/// opens full-screen with a clear close button.
struct ChatWidget: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var agent = AgentConfig.shared
    @State private var open = false
    @State private var showHistory = false
    @State private var draft = ""
    @FocusState private var inputFocused: Bool

    var body: some View { content }

    #if os(macOS)
    private var content: some View {
        ZStack(alignment: .bottomTrailing) {
            if open { macPanel.transition(.move(edge: .bottom).combined(with: .opacity)) }
            else { launcher.transition(.scale.combined(with: .opacity)) }
        }
        .animation(.knPop, value: open)
        .onChange(of: state.pendingChatPrompt) { _, p in handlePending(p) }
    }

    private var macPanel: some View {
        panelBody
            .frame(width: 384, height: 544)
            .background(Palette.elevated, in: RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 1))
            .knShadow(true)
    }
    #else
    private var content: some View {
        launcher
            .onChange(of: state.pendingChatPrompt) { _, p in handlePending(p) }
            .fullScreenCover(isPresented: $open) {
                panelBody
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .background(Palette.bg.ignoresSafeArea())
            }
    }
    #endif

    private func handlePending(_ p: String?) {
        guard let p, !p.isEmpty else { return }
        open = true; showHistory = false
        state.pendingChatPrompt = nil
        Task { await state.sendChat(p) }
    }

    // MARK: - Launcher

    private var launcher: some View {
        Button { open = true; showHistory = false; inputFocused = true } label: {
            ZStack {
                Circle().fill(LinearGradient(colors: [Palette.brand, Palette.brandDeep],
                                             startPoint: .top, endPoint: .bottom))
                Image(systemName: "sparkles").font(.system(size: 22, weight: .bold)).foregroundStyle(Palette.bg)
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

    private var panelBody: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Palette.border)
            if showHistory { historyList } else { messages }
            if !showHistory {
                Divider().overlay(Palette.border)
                inputBar
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(LinearGradient(colors: [Palette.brand, Palette.brandDeep],
                                             startPoint: .top, endPoint: .bottom))
                Image(systemName: "sparkles").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.bg)
            }
            .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(showHistory ? "Chats" : agent.displayName)
                    .font(.system(size: 14, weight: .heavy, design: .rounded)).foregroundStyle(Palette.text)
                Text(showHistory ? "\(state.chat.threads.count) conversation\(state.chat.threads.count == 1 ? "" : "s")"
                                 : "Knows your whole app")
                    .font(.system(size: 10)).foregroundStyle(Palette.faint)
            }
            Spacer()
            iconButton("clock.arrow.circlepath", help: "History") { showHistory.toggle() }
            iconButton("square.and.pencil", help: "New chat") {
                state.newChat(); showHistory = false; inputFocused = true
            }
            if !showHistory, let t = state.activeThread, !t.messages.isEmpty {
                iconButton("trash", help: "Delete this chat") { state.clearChat() }
            }
            iconButton("xmark", help: "Close") { open = false; showHistory = false }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
    }

    private func iconButton(_ name: String, help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: name).font(.system(size: 12, weight: .bold)) }
            .buttonStyle(KIconButtonStyle(size: 28))
            .help(help)
    }

    // MARK: - Messages (active thread)

    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    let msgs = state.activeThread?.messages ?? []
                    if msgs.isEmpty { emptyState }
                    ForEach(msgs) { m in bubble(m).id(m.id) }
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
            .onChange(of: state.activeThread?.messages.count ?? 0) { _, _ in scrollDown(proxy) }
            .onChange(of: state.chatBusy) { _, _ in scrollDown(proxy) }
            .onChange(of: state.chat.activeID) { _, _ in scrollDown(proxy) }
        }
    }

    private func scrollDown(_ proxy: ScrollViewProxy) {
        withAnimation(.knFast) {
            if state.chatBusy { proxy.scrollTo("typing", anchor: .bottom) }
            else { proxy.scrollTo(state.activeThread?.messages.last?.id, anchor: .bottom) }
        }
    }

    // MARK: - History (all threads)

    private var historyList: some View {
        ScrollView {
            VStack(spacing: 6) {
                if state.chat.threads.isEmpty {
                    Text("No conversations yet — tap the pencil to start one.")
                        .font(.system(size: 13)).foregroundStyle(Palette.faint)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                }
                ForEach(state.chat.threads.sorted { $0.updatedAt > $1.updatedAt }) { th in historyRow(th) }
            }
            .padding(12)
        }
    }

    private func historyRow(_ th: ChatThread) -> some View {
        let active = th.id == state.chat.activeID
        let preview = th.messages.last?.content ?? "Empty"
        return Button { state.selectChat(th.id); showHistory = false } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(th.title.isEmpty ? "New chat" : th.title)
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.text).lineLimit(1)
                    Text(preview).font(.system(size: 11)).foregroundStyle(Palette.faint).lineLimit(1)
                }
                Spacer()
                Button { state.deleteChat(th.id) } label: {
                    Image(systemName: "trash").font(.system(size: 11))
                }
                .buttonStyle(KIconButtonStyle(size: 24, color: Palette.red))
            }
            .padding(.horizontal, 10).padding(.vertical, 9)
            .background(active ? Palette.brand.opacity(0.14) : Palette.surface2.opacity(0.5),
                        in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(active ? Palette.brand.opacity(0.5) : .clear, lineWidth: 1))
        }
        .buttonStyle(KPressStyle())
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Talk to me about anything — your fitness and life, or markets, tech, content and the world. Short answers unless you ask for the long version.")
                .font(.system(size: 13)).foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 7) {
                starter("What should I focus on this week?")
                starter("What's moving in the markets today?")
                starter("Give me a reel hook on this week's tech news")
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
                .font(.system(size: 13)).foregroundStyle(isUser ? Palette.bg : Palette.text)
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
                    .foregroundStyle(Palette.bg).frame(width: 30, height: 30)
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
