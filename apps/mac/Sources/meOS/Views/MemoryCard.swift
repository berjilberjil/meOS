import SwiftUI

/// Settings → Memory. Everything Catherine remembers, in the open.
///
/// The whole point is that long-term memory stays under your control: read it,
/// search it, correct it, pin what matters, delete what's wrong. Nothing is
/// remembered that you can't see here, and anything deleted here is gone from
/// her context on the very next message.
struct MemoryCard: View {
    var boxed = true
    @EnvironmentObject var state: AppState

    @State private var query = ""
    @State private var filter: MemoryCategory?
    @State private var editing: MemoryItem?
    @State private var pendingDelete: String?
    @State private var showTrace = false
    @FocusState private var searchFocused: Bool

    private var shown: [MemoryItem] {
        var items = state.sortedMemory
        if let filter { items = items.filter { $0.category == filter } }
        let q = query.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            items = items.filter { $0.content.localizedCaseInsensitiveContains(q) }
        }
        return items
    }

    /// Only the categories actually in use — an empty shelf is noise.
    private var usedCategories: [MemoryCategory] {
        MemoryCategory.allCases.filter { c in state.memory.items.contains { $0.category == c } }
    }

    var body: some View {
        Group {
            if boxed { Card { boxedInner } } else { page }
        }
            .sheet(item: $editing) { item in chrome(MemoryEditorSheet(item: item), width: 460) }
            .sheet(isPresented: $showTrace) {
                chrome(TraceSheet(trace: state.lastTrace ?? CatrineTrace()), width: 560)
            }
            .holdToDelete(
                isPresented: Binding(get: { pendingDelete != nil },
                                     set: { if !$0 { pendingDelete = nil } }),
                title: "Forget this?",
                message: "Catherine stops using it from the next message. This can't be undone."
            ) {
                if let id = pendingDelete { state.deleteMemory(id) }
                pendingDelete = nil
            }
    }

    // MARK: - Phone: a page

    private var page: some View {
        VStack(alignment: .leading, spacing: Gap.screen) {
            SettingsIntro(text: "What Catherine has learned about you. She uses only what’s relevant to each message — edit or delete anything that’s wrong.")

            if !state.memory.items.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    searchRow
                    categoryRow
                }
            }

            if shown.isEmpty {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: SettingsMetrics.labelGap) {
                    SectionTitle(text: shown.count == 1 ? "1 memory" : "\(shown.count) memories")
                        .padding(.leading, 4)
                    VStack(spacing: 8) { ForEach(shown) { row($0) } }
                }
            }

            actions
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(state.memory.items.isEmpty ? "Nothing remembered yet" : "Nothing matches that")
                .font(.callout.weight(.semibold)).foregroundStyle(Palette.text)
            Text(state.memory.items.isEmpty
                 ? "Tell her something durable — “remember that my main project is meOS” — or add one by hand."
                 : "Try a different word, or clear the filter.")
                .font(.footnote).foregroundStyle(Palette.faint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Palette.surfaceElevated.opacity(0.5),
                    in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button { editing = MemoryItem(content: "", source: .manual) } label: {
                Label("Add a memory", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered).tint(Palette.success)

            if state.lastTrace != nil {
                Button { showTrace = true } label: {
                    Label("What the last answer was built from", systemImage: "waveform.path.ecg")
                        .font(.footnote.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    // MARK: - Mac: a card

    private var boxedInner: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionTitle(text: "Memory")
                Spacer()
                Text(state.memory.items.isEmpty ? "nothing yet"
                                                : "\(state.memory.items.count) remembered")
                    .font(.caption).foregroundStyle(Palette.faint)
            }

            Text("What Catherine has learned about you. She uses only what’s relevant to each message — edit or delete anything that’s wrong.")
                .font(.footnote).foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)

            if !state.memory.items.isEmpty { searchRow; categoryRow }

            if shown.isEmpty {
                Text(state.memory.items.isEmpty
                     ? "Nothing yet. Tell her something durable — “remember that my main project is meOS” — or add one by hand."
                     : "Nothing matches that.")
                    .font(.footnote).foregroundStyle(Palette.faint)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 8) { ForEach(shown) { row($0) } }
            }

            HStack(spacing: 10) {
                Button { editing = MemoryItem(content: "", source: .manual) } label: {
                    Label("Add a memory", systemImage: "plus.circle.fill")
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.bordered).tint(Palette.success)
                Spacer(minLength: 0)
                if state.lastTrace != nil {
                    Button { showTrace = true } label: {
                        Label("Last answer", systemImage: "waveform.path.ecg")
                            .font(.footnote.weight(.semibold))
                    }
                    .buttonStyle(.borderless)
                    .help("What the last reply was built from")
                }
            }
        }
    }

    /// A sheet is a full screen on the phone and a floating panel on the Mac.
    /// Sizing for one and letting the other inherit it is how a sheet ends up
    /// with the wrong margins.
    @ViewBuilder
    private func chrome<V: View>(_ view: V, width: CGFloat) -> some View {
        #if os(iOS)
        view.presentationDetents([.large]).presentationBackground(Palette.background)
        #else
        view.frame(width: width).background(Palette.background)
        #endif
    }

    private var searchRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.caption.weight(.bold))
                .foregroundStyle(Palette.faint)
            TextField("", text: $query,
                      prompt: Text("Search what she remembers…").foregroundColor(Palette.faint))
                .textFieldStyle(.plain).font(.subheadline).foregroundStyle(Palette.text)
                .focused($searchFocused)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.caption)
                        .foregroundStyle(Palette.faint)
                }
                .buttonStyle(.plain)
            }
        }
        .knField(focused: searchFocused)
    }

    private var categoryRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                chip(nil, "All")
                ForEach(usedCategories) { c in chip(c, c.label) }
            }
            .padding(.vertical, 1)
        }
    }

    private func chip(_ c: MemoryCategory?, _ label: String) -> some View {
        let on = filter == c
        return Button { withAnimation(.knFast) { filter = on ? nil : c } } label: {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(on ? .white : Palette.muted)
                .padding(.horizontal, 11).padding(.vertical, 6)
                .background(on ? Palette.action : Palette.surfaceElevated, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    /// What she remembers reads first; where it came from and what you can do
    /// about it sit underneath, in that order.
    private func row(_ m: MemoryItem) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: m.category.icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.success)
                    .frame(width: 18)
                    .padding(.top, 3)
                Text(m.content)
                    .font(.subheadline).foregroundStyle(Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if m.pinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2.weight(.bold)).foregroundStyle(Palette.attention)
                        .padding(.top, 4)
                }
            }

            HStack(spacing: 6) {
                tag(m.category.label, Palette.success)
                if m.importance >= 4 { tag("important", Palette.attention) }
                // Where it came from matters: something inferred from chat
                // deserves more suspicion than something you typed.
                if m.source == .extracted {
                    tag(m.confidence < 0.85 ? "learned · unsure" : "learned", Palette.muted)
                }
                Spacer(minLength: 8)

                Button { togglePin(m) } label: {
                    Image(systemName: m.pinned ? "pin.slash" : "pin")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(m.pinned ? Palette.attention : Palette.faint)
                }
                .buttonStyle(.borderless)
                .help(m.pinned ? "Stop always including it" : "Pin so it's always in context")

                Button { editing = m } label: {
                    Image(systemName: "pencil").font(.caption.weight(.bold))
                }
                .buttonStyle(.borderless)
                .help("Edit")

                Button { pendingDelete = m.id } label: {
                    Image(systemName: "trash").font(.caption2.weight(.bold))
                }
                .buttonStyle(.borderless).tint(Palette.warning)
                .help("Forget this")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 11)
        .background(Palette.surfaceElevated, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func tag(_ text: String, _ tint: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.heavy))
            .foregroundStyle(tint)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(tint.opacity(0.14), in: Capsule())
    }

    private func togglePin(_ m: MemoryItem) {
        var next = m
        next.pinned.toggle()
        state.updateMemory(next)
        Haptics.tap()
    }
}

/// Add or correct one memory by hand.
private struct MemoryEditorSheet: View {
    let item: MemoryItem
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var content = ""
    @State private var category: MemoryCategory = .other
    @State private var importance = 3
    @State private var pinned = false
    @FocusState private var bodyFocused: Bool

    private var isNew: Bool { item.content.isEmpty }

    var body: some View {
        ScrollView {
            form
        }
        .scrollBounceBehavior(.basedOnSize)
        .onAppear {
            content = item.content
            category = item.category
            importance = item.importance
            pinned = item.pinned
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isNew ? "Add a memory" : "Edit memory")
                .font(.body.weight(.heavy)).foregroundStyle(Palette.text)

            VStack(alignment: .leading, spacing: 5) {
                KFieldLabel(text: "What she should remember")
                TextField("", text: $content,
                          prompt: Text("e.g. Uses PostgreSQL for every project")
                            .foregroundColor(Palette.faint),
                          axis: .vertical)
                    .textFieldStyle(.plain).font(.subheadline).foregroundStyle(Palette.text)
                    .lineLimit(2...5)
                    .focused($bodyFocused)
                    .knField(focused: bodyFocused)
                Text("Write it as a standing fact about you, not as a message to her.")
                    .font(.caption2).foregroundStyle(Palette.faint)
            }

            VStack(alignment: .leading, spacing: 6) {
                KFieldLabel(text: "Kind")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(MemoryCategory.allCases) { c in
                            Button { category = c } label: {
                                Text(c.label)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(category == c ? .white : Palette.muted)
                                    .padding(.horizontal, 11).padding(.vertical, 6)
                                    .background(category == c ? Palette.action : Palette.surfaceElevated, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                KFieldLabel(text: "How important")
                Stepper("\(importance) of 5", value: $importance, in: 1...5)
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.text)
            }

            Toggle(isOn: $pinned) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Always in context").font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.text)
                    Text("Pinned memories are included even when they don't match the question.")
                        .font(.caption2).foregroundStyle(Palette.faint)
                }
            }
            .tint(Palette.action)

            HStack(spacing: 10) {
                Button("Cancel") { dismiss() }.buttonStyle(.bordered)
                Button(isNew ? "Remember it" : "Save", action: save)
                    .buttonStyle(.borderedProminent)
                    .disabled(content.trimmingCharacters(in: .whitespaces).count < 3)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func save() {
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if isNew {
            state.addMemory(MemoryItem(content: text, category: category, importance: importance,
                                       source: .manual, createdAt: AppState.nowStamp(), pinned: pinned))
        } else {
            var next = item
            next.content = text
            next.category = category
            next.importance = importance
            next.pinned = pinned
            // Correcting a learned memory by hand makes it yours, and stops the
            // "unsure" hedge following it around forever.
            next.source = .manual
            next.confidence = 1
            state.updateMemory(next)
        }
        dismiss()
    }
}

/// Debug view: exactly what the last answer was assembled from. Read-only, in
/// memory only — nothing here is written to disk or sent anywhere.
private struct TraceSheet: View {
    let trace: CatrineTrace
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("How she answered")
                        .font(.body.weight(.heavy))
                        .foregroundStyle(Palette.text)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.caption.weight(.bold))
                    }
                    .buttonStyle(.borderless)
                }

                stat("Asked", trace.query)
                stat("Model", trace.model.isEmpty ? "—" : trace.model)
                stat("Rounds", "\(trace.steps)")
                stat("Took", "\(trace.latencyMs) ms")
                stat("Context", "\(trace.contextCharacters) characters")

                list("Tools called", trace.toolCalls, empty: "None — answered from context alone.")
                list("Memories used", trace.memories, empty: "None matched.")
                list("Retrieved from meOS", trace.documents, empty: "Nothing matched.")
                list("Sections included", trace.includedSections, empty: "—")
                if !trace.droppedSections.isEmpty {
                    list("Dropped (over budget)", trace.droppedSections, empty: "—")
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label).font(.caption2.weight(.heavy))
                .foregroundStyle(Palette.faint).frame(width: 84, alignment: .leading)
            Text(value.isEmpty ? "—" : value).font(.footnote).foregroundStyle(Palette.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func list(_ title: String, _ items: [String], empty: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption2.weight(.heavy))
                .foregroundStyle(Palette.faint)
            if items.isEmpty {
                Text(empty).font(.caption).foregroundStyle(Palette.faint)
            } else {
                ForEach(Array(items.enumerated()), id: \.offset) { _, line in
                    Text("· \(line)").font(.caption.monospaced())
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
