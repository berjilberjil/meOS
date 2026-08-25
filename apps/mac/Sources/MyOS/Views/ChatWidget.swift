import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// The floating mentor. A round launcher bottom-right on every screen; tap to open a
/// chat panel that talks with full context of your data. Supports multiple
/// conversations (New / History / Delete). On Mac it's a floating panel; on iPhone it
/// opens full-screen with a clear close button.
extension ChatWidget {
    /// Catherine sits in the same place on every screen and on both platforms —
    /// she is OS chrome, not per-screen decoration. It was 20/28 on Mac and
    /// 14/14 on the phone, which is close enough to look like a mistake.
    static let edgeInset: CGFloat = 20
}

struct ChatWidget: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var agent = AgentConfig.shared
    @ObservedObject private var themeStore = ThemeStore.shared
    @State private var pres = ChatPresentation()
    @State private var showHistory = false
    @State private var draft = ""
    @State private var confirmClearChat = false
    @State private var pendingHistoryDelete: String?
    @FocusState private var inputFocused: Bool

    var body: some View { content }

    #if os(macOS)
    private var content: some View {
        ZStack(alignment: .bottomTrailing) {
            if pres.open { macPanel.transition(.move(edge: .bottom).combined(with: .opacity)) }
            else { launcher.transition(.scale.combined(with: .opacity)) }
        }
        .animation(.knPop, value: pres.open)
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
            // ONE cover. Starting a call swaps its contents; a second
            // `.fullScreenCover` on this same view would silently never open,
            // because the button that triggers it lives inside this one.
            .fullScreenCover(isPresented: $pres.open) {
                Group {
                    if pres.screen == .call {
                        VoiceCallView(onEnd: { pres.endCall() })
                            .environmentObject(state)
                    } else {
                        panelBody
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.background)
                .preferredColorScheme(themeStore.theme.colorScheme)
                .animation(.knTheme, value: themeStore.theme.id)
            }
    }
    #endif

    private func handlePending(_ p: String?) {
        guard let p, !p.isEmpty else { return }
        pres.openChat(); showHistory = false
        state.pendingChatPrompt = nil
        Task { await state.sendChat(p) }
    }

    // MARK: - Launcher

    private var launcher: some View {
        Button {
            pres.openChat()
            showHistory = false
            inputFocused = true
            Task { await state.fetchSuggestions() }
        } label: {
            ZStack {
                Circle().fill(Palette.surfaceElevated)
                    .overlay(Circle().strokeBorder(Palette.border, lineWidth: 1))
                Image(systemName: "sparkles").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.muted)
            }
            .frame(width: 40, height: 40)
            .overlay(alignment: .topTrailing) {
                if state.chatBusy {
                    Circle().fill(Palette.attention).frame(width: 12, height: 12)
                        .overlay(Circle().strokeBorder(Palette.background, lineWidth: 2))
                        .offset(x: 2, y: -2)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { h in cursor(h) }
        .help("Catherine")
        .accessibilityLabel("Catherine")
    }

    // MARK: - Panel

    private var panelBody: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Palette.border)
            if showHistory { historyList } else { messages }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !showHistory {
                VStack(spacing: 0) {
                    Divider().overlay(Palette.border)
                    inputBar
                }
                .background(Palette.background)
            }
        }
        .onAppear { Task { await state.fetchSuggestions() } }
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(Palette.action)
                Image(systemName: "sparkles").font(.footnote.weight(.bold)).foregroundStyle(Palette.background)
            }
            .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(showHistory ? "Chats" : agent.displayName)
                    .font(.footnote.weight(.heavy)).foregroundStyle(Palette.text)
                Text(showHistory ? "\(state.chat.threads.count) conversation\(state.chat.threads.count == 1 ? "" : "s")"
                                 : "What’s happening today")
                    .font(.caption2).foregroundStyle(Palette.faint)
            }
            Spacer()
            #if os(iOS)
            // Mac is deliberately excluded: hardened runtime + empty entitlements
            // means it cannot open the microphone. See the voice spec, Risks.
            iconButton("phone.fill", help: "Talk") { pres.startCall() }
            #endif
            iconButton("clock.arrow.circlepath", help: "History") { showHistory.toggle() }
            iconButton("square.and.pencil", help: "New chat") {
                state.newChat(); showHistory = false; inputFocused = true
            }
            if !showHistory, let t = state.activeThread, !t.messages.isEmpty {
                iconButton("trash", help: "Delete this chat") { confirmClearChat = true }
                    .holdToDelete(isPresented: $confirmClearChat,
                                  title: "Delete this chat?") {
                        state.clearChat()
                    }
            }
            iconButton("xmark", help: "Close") { pres.close(); showHistory = false }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
    }

    private func iconButton(_ name: String, help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: name).font(.caption.weight(.bold)) }
            .buttonStyle(.borderless)
            .help(help)
    }

    // MARK: - Messages (active thread)

    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    briefing.id("briefing")
                    let msgs = state.activeThread?.messages ?? []
                    if msgs.isEmpty { emptyState }
                    ForEach(msgs) { m in bubble(m).id(m.id) }
                    if state.chatBusy, (msgs.last?.content.isEmpty ?? true) {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Thinking…").font(.caption).foregroundStyle(Palette.faint)
                        }
                    }
                    if let err = state.chatError {
                        HStack(spacing: 8) {
                            Label(err, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption2).foregroundStyle(Palette.warning)
                            Button("Retry") { Task { await state.retryLastChat() } }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Palette.action)
                                .disabled(state.chatBusy)
                        }
                    }
                    Color.clear.frame(height: 1).id("chat-bottom")
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            #if os(iOS)
            .scrollDismissesKeyboard(.interactively)
            #endif
            .onAppear { scrollDown(proxy) }
            .onChange(of: state.activeThread?.messages.count ?? 0) { _, _ in scrollDown(proxy) }
            .onChange(of: state.activeThread?.messages.last?.content.count ?? 0) { _, _ in scrollDown(proxy) }
            .onChange(of: state.chatBusy) { _, _ in scrollDown(proxy) }
            .onChange(of: state.chat.activeID) { _, _ in scrollDown(proxy) }
            .onChange(of: inputFocused) { _, on in if on { scrollDown(proxy) } }
        }
    }

    private func scrollDown(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.knFast) { proxy.scrollTo("chat-bottom", anchor: .bottom) }
        }
    }

    // MARK: - History (all threads)

    private var historyList: some View {
        ScrollView {
            VStack(spacing: 6) {
                if state.chat.threads.isEmpty {
                    Text("No conversations yet — tap the pencil to start one.")
                        .font(.footnote).foregroundStyle(Palette.faint)
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
                        .font(.footnote.weight(.semibold)).foregroundStyle(Palette.text).lineLimit(1)
                    Text(preview).font(.caption2).foregroundStyle(Palette.faint).lineLimit(1)
                }
                Spacer()
                Button { pendingHistoryDelete = th.id } label: {
                    Image(systemName: "trash").font(.caption2)
                }
                .buttonStyle(.borderless).tint(Palette.warning)
                .holdToDelete(
                    isPresented: Binding(get: { pendingHistoryDelete == th.id },
                                         set: { if !$0 { pendingHistoryDelete = nil } }),
                    title: "Delete this chat?"
                ) {
                    state.deleteChat(th.id)
                    pendingHistoryDelete = nil
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 9)
            .background(active ? Palette.action.opacity(0.14) : Palette.surfaceElevated.opacity(0.5),
                        in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(active ? Palette.action.opacity(0.5) : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var briefing: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("TODAY")
                    .font(.caption2.weight(.heavy)).tracking(0.7)
                    .foregroundStyle(Palette.muted)
                Spacer()
                if state.suggestBusy {
                    ProgressView().controlSize(.small)
                }
            }
            if let s = state.suggestions {
                if !s.headline.isEmpty {
                    Text(s.headline)
                        .font(.callout.weight(.semibold)).foregroundStyle(Palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(Array(s.suggestions.prefix(3).enumerated()), id: \.element.id) { _, item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(.footnote.weight(.semibold)).foregroundStyle(Palette.text)
                        Text(item.why).font(.footnote).foregroundStyle(Palette.muted)
                    }
                    .padding(.top, 2)
                }
            } else if state.suggestBusy {
                Text("Reading your day…").font(.footnote).foregroundStyle(Palette.faint)
            } else if let err = state.suggestError {
                Text(err).font(.footnote).foregroundStyle(Palette.warning)
            } else {
                Text("Open this and I’ll tell you what’s going on.")
                    .font(.footnote).foregroundStyle(Palette.faint)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surfaceElevated, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ask me anything after that.")
                .font(.footnote).foregroundStyle(Palette.muted)
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
                Image(systemName: "arrow.up.right").font(.caption2.weight(.bold))
                Text(text).font(.caption.weight(.medium)).multilineTextAlignment(.leading)
            }
            .foregroundStyle(Palette.text)
            .padding(.horizontal, 11).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surfaceElevated.opacity(0.55), in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .onHover { h in cursor(h) }
    }

    private func bubble(_ m: ChatMessage) -> some View {
        let isUser = m.role == "user"
        return HStack {
            if isUser { Spacer(minLength: 40) }
            Text(attributed(m.content))
                .font(.footnote).foregroundStyle(isUser ? Palette.background : Palette.text)
                .textSelection(.enabled)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(isUser ? AnyShapeStyle(Palette.action) : AnyShapeStyle(Palette.surfaceElevated),
                            in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .frame(maxWidth: 300, alignment: isUser ? .trailing : .leading)
                .contextMenu {
                    Button("Copy") { copyText(m.content) }
                }
            if !isUser { Spacer(minLength: 40) }
        }
    }

    private func copyText(_ s: String) {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        #if os(iOS)
        UIPasteboard.general.string = t
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(t, forType: .string)
        #endif
        Haptics.success()
    }

    /// Render light markdown (bold/italic/links) in the reply; fall back to plain.
    private func attributed(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("", text: $draft, prompt: Text("Ask \(agent.displayName)…").foregroundColor(Palette.faint), axis: .vertical)
                .textFieldStyle(.plain).font(.footnote).foregroundStyle(Palette.text)
                .lineLimit(1...4)
                .focused($inputFocused)
                .onSubmit(send)
            Button(action: send) {
                Image(systemName: "arrow.up").font(.footnote.weight(.heavy))
                    .foregroundStyle(Palette.background).frame(width: 30, height: 30)
                    .background(canSend ? AnyShapeStyle(Palette.action) : AnyShapeStyle(Palette.surfaceElevated), in: Circle())
            }
            .buttonStyle(.plain)
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
