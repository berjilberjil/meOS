import SwiftUI
import PhotosUI

/// iOS Notes — the list. The editor is `NoteBlockEditor`, which works the same
/// `BlockDoc` the Mac's AppKit editor does, so a checklist written on either
/// device is still a checklist on the other.
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
                    Button { Haptics.tap(); openID = note.id } label: { noteRow(note) }
                        .fluidPressable(scale: 0.99)
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
        .scrollContentBackground(.hidden)
        .background(Palette.background)
        .searchable(text: $query, prompt: "Search notes")
        .navigationDestination(item: $openID) { id in
            NoteBlockEditor(id: id)
                .environmentObject(state)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { newNote() } label: { Label("New Note", systemImage: "square.and.pencil") }
            }
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
        .onChange(of: state.notes.count) { _, _ in restoreRoute() }
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

    private func restoreRoute() {
        guard !restored, openID == nil else { return }
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
