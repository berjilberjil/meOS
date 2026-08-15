import SwiftUI

/// iOS Notes — a compact list + a plain-text editor. The Mac app has the full rich
/// block editor (AppKit/TextKit, macOS-only); on iPhone we keep it simple: a title
/// and a body, saved through the same synced `myos.notes` store, so notes written on
/// either device show up on both.
struct NotesView: View {
    @EnvironmentObject var state: AppState
    @State private var query = ""
    @State private var openID: String?
    @State private var pendingDelete: Note?
    @State private var revealed = false
    @State private var titleTaps = 0
    @State private var tapTimer: Task<Void, Never>?

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
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Notes").font(.system(size: 24, weight: .semibold)).foregroundStyle(Palette.text)
                    .contentShape(Rectangle())
                    .onTapGesture { handleTitleTap() }
                if revealed {
                    Image(systemName: "lock.open.fill").font(.system(size: 12)).foregroundStyle(Palette.brand)
                }
                if !state.notes.isEmpty {
                    Text("\(state.notes.count)").font(.system(size: 13, weight: .semibold))
                        .monospacedDigit().foregroundStyle(Palette.faint)
                }
                Spacer()
                Button { newNote() } label: { Label("New", systemImage: "plus") }
                    .buttonStyle(KPrimaryButtonStyle())
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Palette.faint)
                TextField("", text: $query, prompt: Text("Search notes…").foregroundColor(Palette.faint))
                    .textFieldStyle(.plain).foregroundStyle(Palette.text)
            }
            .knField()

            if filtered.isEmpty {
                Card {
                    Text(state.notes.isEmpty ? "No notes yet. Tap New to capture one."
                                             : "No notes match “\(query)”.")
                        .font(.system(size: 13)).foregroundStyle(Palette.faint)
                }
            } else {
                ForEach(filtered) { noteRow($0) }
            }
        }
        .navigationDestination(item: $openID) { id in NoteEditor(id: id) }
        .confirmationDialog("Delete this note?", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }
        ), presenting: pendingDelete) { n in
            Button("Delete", role: .destructive) { state.deleteNote(n.id); pendingDelete = nil }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        }
        .onDisappear { revealed = false; tapTimer?.cancel() }
    }

    private func noteRow(_ note: Note) -> some View {
        Button { openID = note.id } label: {
            Card {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        if note.pinned {
                            Image(systemName: "pin.fill").font(.system(size: 10)).foregroundStyle(Palette.amber)
                        }
                        Text(note.title.isEmpty ? "Untitled" : note.title)
                            .font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.text).lineLimit(1)
                        if note.locked {
                            Image(systemName: "lock.fill").font(.system(size: 10)).foregroundStyle(Palette.faint)
                        }
                        Spacer()
                        Text(Fmt.day(note.updatedAt)).font(.system(size: 11)).foregroundStyle(Palette.faint)
                    }
                    if !note.locked && !note.body.isEmpty {
                        Text(note.body).font(.system(size: 13)).foregroundStyle(Palette.muted)
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
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.brand)
                }
                Spacer()
                if let n = state.note(id) {
                    Button { state.togglePinNote(id) } label: {
                        Image(systemName: n.pinned ? "pin.fill" : "pin").font(.system(size: 15))
                            .foregroundStyle(n.pinned ? Palette.amber : Palette.muted)
                    }
                }
            }
            .padding(.bottom, 2)

            TextField("", text: $title, prompt: Text("Title").foregroundColor(Palette.faint))
                .font(.system(size: 24, weight: .bold)).foregroundStyle(Palette.text)
                .onChange(of: title) { save() }

            TextEditor(text: $text)
                .font(.system(size: 16)).foregroundStyle(Palette.text)
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
