import SwiftUI

/// How the notes browse screen lays out — grid (default) or single-column list.
enum NotesLayout: String { case grid, list }

struct NotesView: View {
    @EnvironmentObject var state: AppState
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    // Full-page editor state. `openNoteID == nil` → list mode.
    @State private var openNoteID: String?
    @State private var draftTitle = ""
    @State private var draftDoc = BlockDoc()

    @State private var pendingDelete: Note?

    // View-mode preference (grid default). A UI pref, kept in UserDefaults — not
    // synced app data.
    private static let kLayout = "myos.notes.layout"
    @State private var layout: NotesLayout =
        NotesLayout(rawValue: UserDefaults.standard.string(forKey: NotesView.kLayout) ?? "") ?? .grid
    private let gridCols = [GridItem(.adaptive(minimum: 250), spacing: 14)]

    private var filtered: [Note] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return state.sortedNotes }
        return state.sortedNotes.filter {
            $0.title.lowercased().contains(q) || $0.body.lowercased().contains(q)
        }
    }

    var body: some View {
        Group {
            if openNoteID != nil {
                editor
            } else {
                list
            }
        }
        .confirmationDialog(
            "Delete this note?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete
        ) { note in
            Button("Delete", role: .destructive) {
                // Deleting the note that's open must also close its editor.
                if note.id == openNoteID { openNoteID = nil }
                state.deleteNote(note.id)
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { note in
            Text(note.title.isEmpty ? "This can’t be undone." : "“\(note.title)” — this can’t be undone.")
        }
    }

    // MARK: - List mode

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                searchField

                if filtered.isEmpty {
                    Card {
                        Text(state.notes.isEmpty
                             ? "No notes yet. Capture your first idea."
                             : "No notes match “\(query)”.")
                            .font(.system(size: 13)).foregroundStyle(Palette.faint)
                    }
                } else if layout == .grid {
                    LazyVGrid(columns: gridCols, alignment: .leading, spacing: 14) {
                        ForEach(Array(filtered.enumerated()), id: \.element.id) { idx, note in
                            noteCard(note, grid: true).knRise(min(idx, 8))
                        }
                    }
                } else {
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { idx, note in
                        noteCard(note).knRise(min(idx, 8))
                    }
                }
            }
            .padding(.horizontal, 28).padding(.top, 6).padding(.bottom, 28)
            .frame(maxWidth: 1120)
            .frame(maxWidth: .infinity)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Notes").font(.system(size: 24, weight: .semibold)).foregroundStyle(Palette.text)
            if !state.notes.isEmpty {
                Text("\(state.notes.count)")
                    .font(.system(size: 13, weight: .semibold)).monospacedDigit().foregroundStyle(Palette.faint)
            }
            Spacer()
            if !state.notes.isEmpty { layoutToggle }
            Button { startNew() } label: {
                Label("New note", systemImage: "plus")
            }
            .buttonStyle(KPrimaryButtonStyle())
            .keyboardShortcut("n", modifiers: .command)
        }
    }

    // Grid / list switch — persists the choice.
    private var layoutToggle: some View {
        HStack(spacing: 2) {
            layoutButton(.grid, "square.grid.2x2.fill")
            layoutButton(.list, "list.bullet")
        }
        .padding(3)
        .background(Palette.bg, in: Capsule())
        .overlay(Capsule().strokeBorder(Palette.border, lineWidth: 2))
    }

    private func layoutButton(_ l: NotesLayout, _ icon: String) -> some View {
        let on = layout == l
        return Button {
            withAnimation(.knNormal) { layout = l }
            UserDefaults.standard.set(l.rawValue, forKey: Self.kLayout)
        } label: {
            Image(systemName: icon).font(.system(size: 12, weight: .bold))
                .foregroundStyle(on ? Palette.text : Palette.muted)
                .frame(width: 32, height: 26)
                .background { if on { Capsule().fill(Palette.surface2) } }
                .contentShape(Capsule())
        }
        .buttonStyle(KPressStyle())
        .onHover { h in cursor(h) }
        .help(l == .grid ? "Grid view" : "List view")
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Palette.faint)
            TextField("", text: $query, prompt: Text("Search notes…").foregroundColor(Palette.faint))
                .textFieldStyle(.plain).foregroundStyle(Palette.text)
                .focused($searchFocused)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 12))
                }
                .buttonStyle(KIconButtonStyle(size: 20))
            }
        }
        .knField(focused: searchFocused)
    }

    private func noteCard(_ note: Note, grid: Bool = false) -> some View {
        Button { open(note) } label: {
            Card {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        if note.pinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 10)).foregroundStyle(Palette.brand)
                        }
                        Text(note.title.isEmpty ? "Untitled" : note.title)
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
                            .lineLimit(1)
                        Spacer()
                        Button { state.togglePinNote(note.id) } label: {
                            Image(systemName: note.pinned ? "pin.slash" : "pin").font(.system(size: 11))
                        }
                        .buttonStyle(KIconButtonStyle(size: 24))
                        .help(note.pinned ? "Unpin" : "Pin to top")
                        Button { pendingDelete = note } label: {
                            Image(systemName: "trash").font(.system(size: 11))
                        }
                        .buttonStyle(KIconButtonStyle(size: 24))
                        .help("Delete")
                    }
                    if !note.body.isEmpty {
                        Text(note.body).font(.system(size: 13)).foregroundStyle(Palette.muted)
                            .lineLimit(grid ? 7 : 3).multilineTextAlignment(.leading)
                    }
                    if grid { Spacer(minLength: 0) }
                    Text(Fmt.day(note.updatedAt))
                        .font(.system(size: 11)).foregroundStyle(Palette.faint)
                }
                .frame(minHeight: grid ? 120 : 0, alignment: .topLeading)
            }
        }
        .buttonStyle(KPressStyle())
        .knHoverLift()
    }

    // MARK: - Editor mode (full page)

    private var editor: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Button { closeEditor() } label: {
                    Label("Notes", systemImage: "chevron.left")
                }
                .buttonStyle(KGhostButtonStyle())
                .keyboardShortcut(.escape, modifiers: [])
                Spacer()
                if let id = openNoteID, let note = state.note(id) {
                    Button { state.togglePinNote(id) } label: {
                        Image(systemName: note.pinned ? "pin.fill" : "pin")
                            .font(.system(size: 12)).foregroundStyle(note.pinned ? Palette.brand : Palette.faint)
                    }
                    .buttonStyle(KIconButtonStyle(size: 28))
                    .help(note.pinned ? "Unpin" : "Pin to top")
                    Button { pendingDelete = note } label: {
                        Image(systemName: "trash").font(.system(size: 12))
                    }
                    .buttonStyle(KIconButtonStyle(size: 28))
                    .help("Delete")
                }
            }
            .padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 10)

            TextField("", text: $draftTitle, prompt: Text("Untitled").foregroundColor(Palette.faint))
                .textFieldStyle(.plain)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Palette.text)
                .padding(.horizontal, 24)
                .onChange(of: draftTitle) { saveDraft() }

            BlockEditor(initialDoc: draftDoc) { doc in
                draftDoc = doc
                saveDraft()
            }
            .id(openNoteID)
            .padding(.horizontal, 20)
            .padding(.top, 6)
        }
        .frame(maxWidth: 1120, alignment: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func startNew() {
        let id = state.addBlockNote()
        openNoteID = id
        draftTitle = ""
        draftDoc = BlockDoc()
    }

    private func open(_ note: Note) {
        openNoteID = note.id
        draftTitle = note.title
        draftDoc = note.effectiveDoc
    }

    private func saveDraft() {
        guard let id = openNoteID else { return }
        state.updateNoteContent(id, title: draftTitle, doc: draftDoc)
    }

    private func closeEditor() {
        if let id = openNoteID {
            state.updateNoteContent(id, title: draftTitle, doc: draftDoc)
            // Never leave an untouched, empty note behind.
            if draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, draftDoc.isEffectivelyEmpty {
                state.deleteNote(id)
            }
        }
        openNoteID = nil
    }
}
