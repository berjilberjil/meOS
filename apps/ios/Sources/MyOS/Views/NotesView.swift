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
        List {
            if filtered.isEmpty {
                ContentUnavailableView {
                    Label(state.notes.isEmpty ? "No Notes" : "No Results", systemImage: "note.text")
                } description: {
                    Text(state.notes.isEmpty
                         ? "Tap the compose button to write one."
                         : "No notes match \u{201C}\(query)\u{201D}.")
                }
            } else {
                ForEach(filtered) { note in
                    Button { openID = note.id } label: { noteRow(note) }
                        .buttonStyle(.plain)
                        // Notes are not colour-coded. A note's identity is its
                        // title, and a list of randomly tinted rows was one of
                        // the loudest sources of visual noise in the app.
                        .listRowBackground(Palette.surface)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) { pendingDelete = note } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button { state.toggleLockNote(note.id) } label: {
                                Label(note.locked ? "Unhide" : "Hide",
                                      systemImage: note.locked ? "lock.open" : "lock")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button { state.togglePinNote(note.id) } label: {
                                Label(note.pinned ? "Unpin" : "Pin",
                                      systemImage: note.pinned ? "pin.slash" : "pin")
                            }
                            .tint(Palette.attention)
                        }
                        .contextMenu {
                            Button { state.togglePinNote(note.id) } label: {
                                Label(note.pinned ? "Unpin" : "Pin", systemImage: note.pinned ? "pin.slash" : "pin")
                            }
                            Button { state.toggleLockNote(note.id) } label: {
                                Label(note.locked ? "Unhide" : "Hide", systemImage: note.locked ? "lock.open" : "lock")
                            }
                            Button(role: .destructive) { pendingDelete = note } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
        }
        .listStyle(.insetGrouped)
        // The grouped list paints its own grey; hide it so the tab's canvas
        // shows through behind the coloured rows.
        .scrollContentBackground(.hidden)
        .background(Palette.background)
        .searchable(text: $query, prompt: "Search notes")
        // A real push now that MainView gives every tab a NavigationStack. This
        // used to be a `fullScreenCover` purely because there was no stack to
        // push into, so a NavigationLink silently did nothing.
        .navigationDestination(item: $openID) { id in
            NoteEditor(id: id)
                .environmentObject(state)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { newNote() } label: { Label("New Note", systemImage: "square.and.pencil") }
            }
            // The 5-tap-the-title gesture that used to reveal locked notes has
            // no target left once the title belongs to the navigation bar, so
            // it is an explicit menu item behind the same Face ID check.
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { Task { await revealHidden() } } label: {
                        Label("Show Hidden Notes", systemImage: "lock.open")
                    }
                    .disabled(revealed)
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
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
            title: pendingDelete.map { $0.title.isEmpty ? "Delete this note?" : "Delete \u{201C}\($0.title)\u{201D}?" } ?? "Delete this note?",
            message: "This can't be undone."
        ) {
            if let n = pendingDelete { state.deleteNote(n.id) }
            pendingDelete = nil
        }
        .onDisappear { revealed = false; tapTimer?.cancel() }
    }

    /// A grouped-list cell. The Card wrapper is gone — List draws the surface.
    private func noteRow(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                if note.pinned {
                    Image(systemName: "pin.fill").font(.caption2).foregroundStyle(Palette.attention)
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
        .contentShape(Rectangle())
    }

    private func newNote() { openID = state.addBlockNote() }

    /// Reopen the note from last time. Runs once; a route pointing at a note
    /// that has since been deleted is simply dropped.
    private func restoreRoute() {
        guard !restored, openID == nil else { return }
        // Never restore straight into a locked note. The route is persisted on
        // open, so leaving a hidden note on screen and swipe-killing the app put
        // it back on relaunch with `revealed` reset to false — the list hid it
        // while the editor showed the whole body, no authentication asked.
        guard let id = PrefsStore.shared.route(for: .notes),
              let n = state.note(id), !n.locked else {
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
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.action)
                }
                Spacer()
                if let n = state.note(id) {
                    Button { state.togglePinNote(id) } label: {
                        Image(systemName: n.pinned ? "pin.fill" : "pin").font(.subheadline)
                            .foregroundStyle(n.pinned ? Palette.attention : Palette.muted)
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
                .background(Palette.background)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onChange(of: text) { save() }
        }
        .padding(16)
        .background(Palette.background)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            guard !loaded else { return }
            if let n = state.note(id) { title = n.title; text = n.body }
            loaded = true
        }
        .onDisappear {
            save()
            // Blank title and body is not the same as empty. A note holding only
            // a photo has exactly that — `plainText` for [image, paragraph("")]
            // is "\n" and the derived title is "" — so merely opening one on the
            // phone and tapping back destroyed it, and the image with it, on
            // both devices.
            if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               state.note(id)?.content?.isEffectivelyEmpty ?? true {
                state.deleteNote(id)
            }
        }
    }

    private func save() {
        guard loaded else { return }
        state.updateNote(id, title: title, body: text)
    }
}
