import SwiftUI

/// iOS Notes — a compact list + a plain-text editor. The Mac app has the full rich
/// block editor (AppKit/TextKit, macOS-only); on iPhone we keep it simple: a title
/// and a body, saved through the same synced `myos.notes` store, so notes written on
/// either device show up on both.
struct NotesView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var signals = UISignals.shared
    @State private var query = ""
    @State private var openID: String?
    @State private var pendingDelete: Note?
    @State private var revealed = false
    @State private var titleTaps = 0
    @State private var tapTimer: Task<Void, Never>?
    /// One-shot: reopen the note that was open when the app was last closed.
    @State private var restored = false

    private var filtered: [Note] {
        // Locked notes are hidden from the list until revealed (5-tap + Face ID).
        let base = revealed ? state.sortedNotes : state.sortedNotes.filter { !$0.locked }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return base }
        return base.filter {
            $0.title.lowercased().contains(q) || (!$0.locked && $0.body.lowercased().contains(q))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Gap.screen) {
            HStack(alignment: .firstTextBaseline) {
                ScreenTitle(text: "Notes")
                    .contentShape(Rectangle())
                    .onTapGesture { handleTitleTap() }
                if revealed {
                    Image(systemName: "lock.open.fill").font(.caption).foregroundStyle(Palette.brand)
                }
                if !state.notes.isEmpty {
                    Text("\(state.notes.count)").font(.footnote.weight(.semibold))
                        .monospacedDigit().foregroundStyle(Palette.faint)
                }
                Spacer()
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Palette.faint)
                TextField("", text: $query, prompt: Text("Search notes…").foregroundColor(Palette.faint))
                    .textFieldStyle(.plain).foregroundStyle(Palette.text)
            }
            .knField()

            // Rows are a list, not screen blocks — they get the row beat, not
            // the screen one, or the page reads as eight separate sections.
            VStack(alignment: .leading, spacing: Gap.row) {
                if filtered.isEmpty {
                    Card {
                        Text(state.notes.isEmpty ? "No notes yet. Double-tap here to write one."
                                                 : "No notes match “\(query)”.")
                            .font(.footnote).foregroundStyle(Palette.faint)
                    }
                    .onTapGesture(count: 2) { newNote() }
                } else {
                    ForEach(filtered) { noteRow($0) }
                }
            }
        }
        // A full-screen cover, NOT `navigationDestination`: iOS MainView has no
        // NavigationStack (deliberately — a stack with a hidden bar re-negotiates
        // the scroll view's safe-area inset mid-scroll), so a push had nowhere to
        // go and silently did nothing. That is why notes opened as a blank
        // nothing and new ones could not be typed into.
        .fullScreenCover(item: Binding(get: { openID.map(OpenNote.init) },
                                       set: { openID = $0?.id })) { note in
            NoteEditor(id: note.id)
                .environmentObject(state)
        }
        .onAppear { consumeNewNoteRequest(); consumeRevealHidden(); restoreRoute() }
        // Notes arrive from the cache a beat after the view builds on a cold
        // launch, so the first attempt can find nothing to reopen.
        .onChange(of: state.notes.count) { _, _ in restoreRoute() }
        // Covers opening, creating and backing out in one hook: the tab is only
        // half of "where I left off", and `openID` dies with the process.
        .onChange(of: openID) { _, id in PrefsStore.shared.setRoute(id, for: .notes) }
        .onChange(of: state.pendingNewNote) { _, on in if on { consumeNewNoteRequest() } }
        .onChange(of: signals.revealHiddenNotes) { _, on in if on { consumeRevealHidden() } }
        .holdToDelete(
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            title: pendingDelete.map { $0.title.isEmpty ? "Delete this note?" : "Delete “\($0.title)”?" } ?? "Delete this note?",
            message: "This can't be undone."
        ) {
            if let n = pendingDelete { state.deleteNote(n.id) }
            pendingDelete = nil
        }
        .onDisappear { revealed = false; tapTimer?.cancel() }
    }

    private func noteRow(_ note: Note) -> some View {
        Button { openID = note.id } label: {
            Card {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        if note.pinned {
                            Image(systemName: "pin.fill").font(.caption2).foregroundStyle(Palette.amber)
                        }
                        Text(note.title.isEmpty ? "Untitled" : note.title)
                            .font(.callout.weight(.semibold)).foregroundStyle(Palette.text).lineLimit(1)
                        if note.locked {
                            Image(systemName: "lock.fill").font(.caption2).foregroundStyle(Palette.faint)
                        }
                        Spacer()
                        Text(Fmt.day(note.updatedAt)).font(.caption2).foregroundStyle(Palette.faint)
                    }
                    if !note.locked && !note.body.isEmpty {
                        Text(note.body).font(.footnote).foregroundStyle(Palette.muted)
                            .lineLimit(2).multilineTextAlignment(.leading)
                    }
                }
            }
        }
        .buttonStyle(KPressStyle())
        .contextMenu {
            Button { state.togglePinNote(note.id) } label: {
                Label(note.pinned ? "Unpin" : "Pin", systemImage: note.pinned ? "pin.slash" : "pin")
            }
            Button { state.toggleLockNote(note.id) } label: {
                Label(note.locked ? "Unhide" : "Hide", systemImage: note.locked ? "lock.open" : "lock")
            }
            Button(role: .destructive) { pendingDelete = note } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private func newNote() { openID = state.addBlockNote() }

    /// Reopen the note from last time. Runs once; a route pointing at a note
    /// that has since been deleted is simply dropped.
    private func restoreRoute() {
        guard !restored, openID == nil else { return }
        guard let id = PrefsStore.shared.route(for: .notes), state.note(id) != nil else {
            if !state.notes.isEmpty { restored = true }
            return
        }
        restored = true
        openID = id
    }

    private func consumeNewNoteRequest() {
        guard state.pendingNewNote else { return }
        state.pendingNewNote = false
        newNote()
    }

    private func consumeRevealHidden() {
        guard UISignals.shared.revealHiddenNotes else { return }
        UISignals.shared.revealHiddenNotes = false
        Task { await revealHidden() }
    }

    /// Every tap on the title increments a counter; after a short settle window,
    /// 2 taps = new note, 5+ taps = reveal hidden (locked) notes behind Face ID.
    private func handleTitleTap() {
        titleTaps += 1
        tapTimer?.cancel()
        tapTimer = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            if Task.isCancelled { return }
            let count = titleTaps
            titleTaps = 0
            if count >= 5 { await revealHidden() }
            else if count == 2 { newNote() }
        }
    }

    private func revealHidden() async {
        if await BiometricLock.authenticate(reason: "Show hidden notes") {
            withAnimation(.knFast) { revealed = true }
        }
    }
}

/// `fullScreenCover(item:)` wants an Identifiable; the note id is a String.
private struct OpenNote: Identifiable { let id: String }

/// Full-screen plain-text editor for one note (iOS).
private struct NoteEditor: View {
    @EnvironmentObject var state: AppState
    let id: String
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var text = ""
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button { dismiss() } label: {
                    HStack(spacing: 3) { Image(systemName: "chevron.left"); Text("Notes") }
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.brand)
                }
                Spacer()
                if let n = state.note(id) {
                    Button { state.togglePinNote(id) } label: {
                        Image(systemName: n.pinned ? "pin.fill" : "pin").font(.subheadline)
                            .foregroundStyle(n.pinned ? Palette.amber : Palette.muted)
                    }
                }
            }
            .padding(.bottom, 2)

            TextField("", text: $title, prompt: Text("Title").foregroundColor(Palette.faint))
                .font(.title2.weight(.bold)).foregroundStyle(Palette.text)
                .onChange(of: title) { save() }

            TextEditor(text: $text)
                .font(.callout).foregroundStyle(Palette.text)
                .scrollContentBackground(.hidden)
                .background(Palette.bg)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onChange(of: text) { save() }
        }
        .padding(16)
        .background(Palette.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            guard !loaded else { return }
            if let n = state.note(id) { title = n.title; text = n.body }
            loaded = true
        }
        .onDisappear {
            save()
            if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                state.deleteNote(id)
            }
        }
    }

    private func save() {
        guard loaded else { return }
        state.updateNote(id, title: title, body: text)
    }
}
