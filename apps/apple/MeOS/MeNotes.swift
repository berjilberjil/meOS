import SwiftUI

struct MeNotes: View {
    @EnvironmentObject var state: AppState
    @State private var query = ""
    @AppStorage("meos.notes.grid") private var grid = true
    @State private var opened: String?
    @Namespace private var ns

    private var shown: [Note] {
        state.sortedNotes.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || (!$0.locked && $0.body.localizedCaseInsensitiveContains(query)) }
    }

    var body: some View {
        Screen(title: "Notes", sub: "\(state.notes.count) notes") {
            LazyVGrid(columns: grid ? [.init(spacing: 12), .init()] : [.init()], spacing: 12) {
                ForEach(shown) { n in
                    NavigationLink(value: n.id) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                if n.pinned { Image(systemName: "pin.fill") }
                                if n.locked { Image(systemName: "lock.fill") }
                                Spacer()
                                Text(Fmt.day(String(n.updatedAt.prefix(10)))).font(.caption).foregroundStyle(Color.dim)
                            }
                            .font(.subheadline)
                            Text(n.title.isEmpty ? "Untitled" : n.title).font(.title3.bold()).lineLimit(2).multilineTextAlignment(.leading)
                            Text(n.locked ? "Locked" : n.body.split(separator: "\n").dropFirst().joined(separator: " "))
                                .foregroundStyle(Color.dim).lineLimit(3).multilineTextAlignment(.leading)
                        }
                        .padding(18).frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
                        .background(Color.card, in: .rect(cornerRadius: 24))
                        .matchedTransitionSource(id: n.id, in: ns)
                    }
                    .buttonStyle(.press)
                    .contextMenu {
                        Button(n.pinned ? "Unpin" : "Pin", systemImage: "pin") { withAnimation(DS.spring) { state.togglePinNote(n.id) } }
                        Button(n.locked ? "Unlock" : "Lock", systemImage: "lock") { state.toggleLockNote(n.id) }
                        Button("Delete", systemImage: "trash", role: .destructive) { withAnimation(DS.spring) { state.deleteNote(n.id) } }
                    }
                }
            }
        }
        .meSearchable(text: $query)
        .navigationDestination(for: String.self) { id in MeNoteEditor(id: id).zoomFrom(id, in: ns) }
        .navigationDestination(item: $opened) { id in MeNoteEditor(id: id) }
        .meActions {
            #if os(macOS)
            MeSearchField(text: $query)
            #endif
            Button { withAnimation(DS.spring) { grid.toggle() } } label: { Image(systemName: grid ? "list.bullet" : "square.grid.2x2") }
            Button { opened = state.addBlockNote() } label: { Image(systemName: "square.and.pencil") }.keyboardShortcut("n")
        }
        .onChange(of: state.pendingNewNote) { _, v in if v { state.pendingNewNote = false; opened = state.addBlockNote() } }
    }
}

/// Locked notes stay hidden until Face ID passes; the editor itself is MeOS's block editor.
struct MeNoteEditor: View {
    @EnvironmentObject var state: AppState
    let id: String
    @State private var unlocked = false

    var body: some View {
        Group {
            if state.note(id)?.locked == true && !unlocked {
                VStack(spacing: 20) {
                    BigIcon(name: "lock.fill", size: 36, inverted: true)
                    Text("This note is locked").font(.title2.bold())
                    Button { Task { if await BiometricLock.authenticate(reason: "Open locked note") { withAnimation(DS.spring) { unlocked = true } } } } label: {
                        Chip(text: "Unlock with \(BiometricLock.biometryName)", on: true)
                    }
                    .buttonStyle(.press)
                }
                .frame(maxHeight: .infinity)
            } else {
                MeBlockEditor(id: id)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        #if os(macOS)
        .overlay(alignment: .topLeading) { MacBack().padding(.top, 22).padding(.leading, DS.pad) }
        #endif
    }
}
