import SwiftUI

/// Notes has two screens: a **browse** listing (single-column list of all notes,
/// the home screen) and a **detail** two-pane (Apple-Notes style — notes-list
/// column + full editor). Clicking a note in browse drills into detail; a back
/// button returns.
struct NotesView: View {
    @EnvironmentObject var state: AppState
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    /// false → browse listing; true → two-pane detail.
    @State private var inDetail = false

    // Which note the editor is showing. nil → empty state.
    @State private var selectedID: String?
    @State private var draftTitle = ""
    @State private var draftDoc = BlockDoc()
    /// Once the user types in the title field, stop auto-filling it from the body.
    @State private var titleEdited = false
    @FocusState private var titleFocused: Bool

    @State private var pendingDelete: Note?
    /// Most-recently-opened note ids (for the "Recent Notes" submenu), newest first.
    @State private var recentIDs: [String] = []
    /// Locked notes the user has revealed this session.
    @State private var unlocked: Set<String> = []
    /// Bumped to open the editor's native find bar.
    @State private var findToken = 0
    /// One-shot: reopen the note that was open when the app was last closed.
    @State private var restored = false

    private var filtered: [Note] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return state.sortedNotes }
        return state.sortedNotes.filter {
            $0.title.lowercased().contains(q) || (!$0.locked && $0.body.lowercased().contains(q))
        }
    }

    var body: some View {
        Group {
            if inDetail { detailView } else { browseView }
        }
        .onAppear { restoreRoute() }
        // Notes arrive from the cache a beat after the view builds on a cold
        // launch, so the first attempt can find nothing to reopen.
        .onChange(of: state.notes.count) { _, _ in restoreRoute() }
        .onDisappear { persistCurrent() }   // flush + drop an untouched empty note
        .holdToDelete(
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            title: pendingDelete.map { $0.title.isEmpty ? "Delete this note?" : "Delete “\($0.title)”?" } ?? "Delete this note?",
            message: "This can't be undone."
        ) {
            guard let note = pendingDelete else { return }
            let wasOpen = note.id == selectedID
            state.deleteNote(note.id)
            recentIDs.removeAll { $0 == note.id }
            unlocked.remove(note.id)
            if wasOpen { selectFirstAfterDelete() }
            pendingDelete = nil
        }
    }

    // MARK: - Browse listing (home)

    private var browseView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                browseHeader
                browseSearch

                if filtered.isEmpty {
                    Card {
                        Text(state.notes.isEmpty
                             ? "No notes yet. Capture your first idea."
                             : "No notes match “\(query)”.")
                            .font(.footnote).foregroundStyle(Palette.faint)
                    }
                } else {
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { idx, note in
                        noteCard(note).knRise(min(idx, 8))
                    }
                }
            }
            .padding(.horizontal, 28).padding(.top, 30).padding(.bottom, 104)
            .frame(maxWidth: 1120)
            .frame(maxWidth: .infinity)
        }
    }

    private var browseHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            ScreenTitle(text: "Notes")
                .onTapGesture(count: 2) { startNew() }
                .help("Double-click to write a note")
            if !state.notes.isEmpty {
                Text("\(state.notes.count)")
                    .font(.footnote.weight(.semibold)).monospacedDigit().foregroundStyle(Palette.faint)
            }
            Spacer()
            // A real, visible affordance. This used to be an invisible zero-sized
            // button that existed only to register ⌘N, which left the screen with
            // no way to create a note unless you already knew the shortcut or that
            // double-clicking the title works.
            Button(action: startNew) {
                HStack(spacing: 5) {
                    Image(systemName: "square.and.pencil").font(.caption.weight(.bold))
                    Text("New note").font(.caption.weight(.semibold))
                }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("n", modifiers: .command)
            .help("New note (⌘N)")
                .accessibilityHidden(true)
        }
    }

    private var browseSearch: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Palette.faint)
            TextField("", text: $query, prompt: Text("Search notes…").foregroundColor(Palette.faint))
                .textFieldStyle(.plain).foregroundStyle(Palette.text)
                .focused($searchFocused)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.caption)
                }
                .buttonStyle(.borderless)
            }
        }
        .knField(focused: searchFocused)
    }

    private func noteCard(_ note: Note) -> some View {
        let hidden = note.locked && !unlocked.contains(note.id)
        return Button { openFromBrowse(note) } label: {
            Card {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        if note.pinned {
                            Image(systemName: "pin.fill").font(.caption2).foregroundStyle(Palette.attention)
                        }
                        Text(note.title.isEmpty ? "Untitled" : note.title)
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.text)
                            .lineLimit(1)
                        if note.locked {
                            Image(systemName: "lock.fill").font(.caption2).foregroundStyle(Palette.faint)
                        }
                        Spacer()
                        Button { state.togglePinNote(note.id) } label: {
                            Image(systemName: note.pinned ? "pin.slash" : "pin").font(.caption2)
                        }
                        .buttonStyle(.borderless)
                        .help(note.pinned ? "Unpin" : "Pin to top")
                        Button { pendingDelete = note } label: {
                            Image(systemName: "trash").font(.caption2)
                        }
                        .buttonStyle(.borderless)
                        .help("Delete")
                    }
                    let preview = hidden ? "Locked" : note.body
                    if !preview.isEmpty {
                        Text(preview).font(.footnote).foregroundStyle(Palette.muted)
                            .lineLimit(3).multilineTextAlignment(.leading)
                    }
                    Text(Fmt.day(note.updatedAt))
                        .font(.caption2).foregroundStyle(Palette.faint)
                }
                .frame(minHeight: 0, alignment: .topLeading)
            }
        }
        .buttonStyle(.plain)
        .knHoverLift()
        .contextMenu { noteMenu(note) }
    }

    // MARK: - Detail (two-pane: notes list + editor)

    private var detailView: some View {
        HStack(spacing: 0) {
            listColumn
                .frame(width: 288)
                .background(Palette.sidebar.opacity(0.55))
            Rectangle().fill(Palette.border).frame(width: 1)
            editorColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - List column

    private var listColumn: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Button { backToBrowse() } label: {
                    Image(systemName: "square.grid.2x2").font(.footnote.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .help("All notes")
                Text("Notes").font(.title3.weight(.bold)).foregroundStyle(Palette.text)
                    .onTapGesture(count: 2) { startNew() }
                    .help("Double-click to write a note")
                if !state.notes.isEmpty {
                    Text("\(state.notes.count)")
                        .font(.caption.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(Palette.faint)
                }
                Spacer()
                Button(action: startNew) {
                    Image(systemName: "square.and.pencil").font(.footnote.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .help("New note (⌘N)")
            }
            .padding(.horizontal, 12).padding(.top, 26).padding(.bottom, 8)

            searchField.padding(.horizontal, 12).padding(.bottom, 6)

            if filtered.isEmpty {
                Spacer()
                VStack(spacing: 10) {
                    Text(state.notes.isEmpty ? "No notes yet." : "No matches for “\(query)”.")
                        .font(.caption).foregroundStyle(Palette.faint)
                    if state.notes.isEmpty {
                        Button("Write your first note", action: startNew)
                            .buttonStyle(.bordered)
                    }
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(sections) { section in
                            Text(section.title.uppercased())
                                .font(.caption2.weight(.heavy)).tracking(0.6)
                                .foregroundStyle(Palette.faint)
                                .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 4)
                            ForEach(section.notes) { note in row(note) }
                        }
                    }
                    .padding(.bottom, 120)   // clear the floating log bar
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.caption).foregroundStyle(Palette.faint)
            TextField("", text: $query, prompt: Text("Search").foregroundColor(Palette.faint))
                .textFieldStyle(.plain).font(.footnote).foregroundStyle(Palette.text)
                .focused($searchFocused)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.caption)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(Palette.surfaceElevated.opacity(0.6), in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
            .strokeBorder(searchFocused ? Palette.blue : .clear, lineWidth: 1.5))
    }

    private func row(_ note: Note) -> some View {
        let selected = note.id == selectedID
        let hidden = note.locked && !unlocked.contains(note.id)
        return Button { open(note) } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    if note.pinned {
                        Image(systemName: "pin.fill").font(.caption2).foregroundStyle(Palette.attention)
                    }
                    Text(note.title.isEmpty ? "New Note" : note.title)
                        .font(.footnote.weight(.semibold)).foregroundStyle(Palette.text)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if note.locked {
                        Image(systemName: "lock.fill").font(.caption2).foregroundStyle(Palette.faint)
                    }
                }
                HStack(spacing: 6) {
                    Text(Fmt.day(note.updatedAt))
                        .font(.caption2.weight(.medium)).foregroundStyle(Palette.muted)
                    Text(hidden ? "Locked" : snippet(note))
                        .font(.caption2).foregroundStyle(Palette.faint).lineLimit(1)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Palette.attention.opacity(0.16) : .clear,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(selected ? Palette.attention.opacity(0.5) : .clear, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .contextMenu { noteMenu(note) }
    }

    /// The preview line under a row's title — the body with its first line dropped
    /// when that line already is the title.
    private func snippet(_ note: Note) -> String {
        var lines = note.body.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let t = note.title.trimmingCharacters(in: .whitespaces)
        if let first = lines.first, first.trimmingCharacters(in: .whitespaces) == t, !t.isEmpty {
            lines.removeFirst()
        }
        let joined = lines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? "No additional text" : joined
    }

    // MARK: - Editor column

    @ViewBuilder private var editorColumn: some View {
        if let id = selectedID, let note = state.note(id) {
            if note.locked && !unlocked.contains(id) {
                lockedScreen(note)
            } else {
                editor(id: id, note: note)
            }
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            NoteGlyph(s: 64).opacity(0.5)
            Text("No note selected").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.muted)
            Text("Double-click Notes to write one.").font(.caption).foregroundStyle(Palette.faint)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { startNew() }
    }

    private func lockedScreen(_ note: Note) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.fill").font(.largeTitle).foregroundStyle(Palette.attention)
            Text(note.title.isEmpty ? "Locked Note" : note.title)
                .font(.body.weight(.bold)).foregroundStyle(Palette.text)
            Text("This note is locked.").font(.footnote).foregroundStyle(Palette.muted)
            Button { unlocked.insert(note.id) } label: { Label("Unlock", systemImage: "lock.open.fill") }
                .buttonStyle(.borderedProminent).tint(Palette.attention)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func editor(id: String, note: Note) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Spacer()
                Button { state.togglePinNote(id) } label: {
                    Image(systemName: note.pinned ? "pin.fill" : "pin")
                        .font(.footnote).foregroundStyle(note.pinned ? Palette.attention : Palette.muted)
                }
                .buttonStyle(.borderless)
                .help(note.pinned ? "Unpin" : "Pin to top")

                Button { findToken += 1 } label: {
                    Image(systemName: "magnifyingglass").font(.footnote)
                }
                .buttonStyle(.borderless)
                .help("Find in Note")

                ShareLink(item: shareText(note)) {
                    Image(systemName: "square.and.arrow.up").font(.footnote)
                }
                .buttonStyle(.borderless)
                .help("Share")

                Menu {
                    noteMenu(note)
                } label: {
                    Image(systemName: "ellipsis").font(.footnote.weight(.bold))
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .menuIndicator(.hidden)
                .frame(width: 30)
                .help("More")
            }
            .padding(.horizontal, 18).padding(.top, 20).padding(.bottom, 6)

            TextField("", text: $draftTitle, prompt: Text("Untitled").foregroundColor(Palette.faint))
                .textFieldStyle(.plain)
                .font(.title.weight(.bold))
                .foregroundStyle(Palette.text)
                .padding(.horizontal, 26)
                .focused($titleFocused)
                .onChange(of: titleFocused) { _, now in if now { titleEdited = true } }
                .onChange(of: draftTitle) { saveDraft() }

            BlockEditor(initialDoc: draftDoc, findToken: findToken, bottomInset: 96) { doc in
                draftDoc = doc
                if !titleEdited {
                    let auto = Self.derivedTitle(from: doc)
                    if auto != draftTitle { draftTitle = auto }
                }
                saveDraft()
            }
            .id(id)
            .padding(.horizontal, 22)
            .padding(.top, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: 900, alignment: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Shared note menu (context menu + the "…" button)

    @ViewBuilder private func noteMenu(_ note: Note) -> some View {
        Button { state.togglePinNote(note.id) } label: {
            Label(note.pinned ? "Unpin Note" : "Pin Note", systemImage: note.pinned ? "pin.slash" : "pin")
        }
        Button { toggleLock(note) } label: {
            Label(note.locked ? "Unlock Note" : "Lock Note", systemImage: note.locked ? "lock.open" : "lock")
        }
        Button {
            openFromBrowse(note)
            findToken += 1
        } label: {
            Label("Find in Note", systemImage: "magnifyingglass")
        }

        Divider()

        Menu {
            let recents = recentIDs.filter { $0 != note.id }.compactMap { state.note($0) }.prefix(8)
            if recents.isEmpty {
                Text("No recent notes")
            } else {
                ForEach(Array(recents)) { n in
                    Button { openFromBrowse(n) } label: { Text(n.title.isEmpty ? "New Note" : n.title) }
                }
            }
        } label: {
            Label("Recent Notes", systemImage: "clock")
        }

        Divider()

        Button(role: .destructive) { pendingDelete = note } label: {
            Label("Delete Note", systemImage: "trash")
        }
    }

    private func shareText(_ note: Note) -> String {
        let title = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = note.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty { return body }
        if body.isEmpty || body.hasPrefix(title) { return body.isEmpty ? title : body }
        return title + "\n\n" + body
    }

    // MARK: - Actions

    /// Open a note from the browse listing and drill into the detail two-pane.
    private func openFromBrowse(_ note: Note) {
        open(note)
        inDetail = true
    }

    /// Return from the detail two-pane to the browse listing.
    private func backToBrowse() {
        persistCurrent()
        selectedID = nil
        remember(nil)
        inDetail = false
    }

    private func startNew() {
        persistCurrent()
        let id = state.addBlockNote()
        selectedID = id
        remember(id)
        draftTitle = ""
        draftDoc = BlockDoc()
        titleEdited = false
        pushRecent(id)
        inDetail = true
        titleFocused = true
    }

    private func open(_ note: Note) {
        if note.id == selectedID { return }
        persistCurrent()
        selectedID = note.id
        remember(note.id)
        draftTitle = note.title
        draftDoc = note.effectiveDoc
        titleEdited = !note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        pushRecent(note.id)
    }

    private func toggleLock(_ note: Note) {
        state.toggleLockNote(note.id)
        if note.locked {
            unlocked.remove(note.id)          // was locked → now unlocked, drop session flag
        } else {
            unlocked.insert(note.id)          // just locked it → keep it readable this session
        }
    }

    private func pushRecent(_ id: String) {
        recentIDs.removeAll { $0 == id }
        recentIDs.insert(id, at: 0)
        if recentIDs.count > 12 { recentIDs = Array(recentIDs.prefix(12)) }
    }

    /// The note's title when the user hasn't set one: the first non-empty line of
    /// the body, capped so a long first line doesn't become an unwieldy title.
    static func derivedTitle(from doc: BlockDoc) -> String {
        for b in doc.blocks {
            let t = b.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return String(t.prefix(80)) }
        }
        return ""
    }

    private func saveDraft() {
        guard let id = selectedID else { return }
        let imgs = draftDoc.blocks.filter { $0.type == .image }.count
        Log.notes.info("persist \(id): \(draftDoc.blocks.count) block(s), \(imgs) image(s), title=\(draftTitle.isEmpty ? "<empty>" : "set")")
        state.updateNoteContent(id, title: draftTitle, doc: draftDoc)
    }

    /// Flush the open note; drop it if it was never given a title or any content.
    private func persistCurrent() {
        guard let id = selectedID else { return }
        state.updateNoteContent(id, title: draftTitle, doc: draftDoc)
        // Deliberately no auto-delete of "empty" notes here. `BlockDoc()` seeds a
        // single empty paragraph, so a freshly created note is `isEffectivelyEmpty`
        // from birth — this branch deleted every new note the moment you clicked
        // away without typing, which reads as "I can't create notes". Removing an
        // unwanted note is one click on the trash; silently destroying one the
        // user just asked for is not recoverable.
    }

    /// The tab is only half of "where I left off" — which note was open is view
    /// state, and view state dies with the process. Park it on disk instead.
    private func remember(_ id: String?) {
        PrefsStore.shared.setRoute(id, for: .notes)
    }

    /// Reopen the note from last time. Runs once; a route pointing at a note
    /// that has since been deleted is simply dropped.
    private func restoreRoute() {
        guard !restored, selectedID == nil else { return }
        guard let id = PrefsStore.shared.route(for: .notes), let note = state.note(id) else {
            // Only give up once the notes have actually loaded.
            if !state.notes.isEmpty { restored = true }
            return
        }
        restored = true
        open(note)
        inDetail = true
    }

    private func selectFirstAfterDelete() {
        if let next = state.sortedNotes.first {
            selectedID = nil            // force the editor to re-key onto the new note
            open(next)
        } else {
            // No notes left — fall back to the browse listing.
            selectedID = nil
            remember(nil)
            draftTitle = ""
            draftDoc = BlockDoc()
            inDetail = false
        }
    }
}

/// A titled run of notes in the list (Pinned, Today, Previous 7 Days, …).
private struct NoteSection: Identifiable {
    let id: String
    let title: String
    let notes: [Note]
}

private extension NotesView {
    /// Group the filtered notes the way Apple Notes does: a Pinned section, then
    /// date buckets in recency order.
    var sections: [NoteSection] {
        var pinned: [Note] = []
        var rest: [Note] = []
        for n in filtered { if n.pinned { pinned.append(n) } else { rest.append(n) } }

        var out: [NoteSection] = []
        if !pinned.isEmpty { out.append(NoteSection(id: "pinned", title: "Pinned", notes: pinned)) }

        var order: [String] = []
        var groups: [String: [Note]] = [:]
        for n in rest {
            let label = Self.dateBucket(n.updatedAt)
            if groups[label] == nil { order.append(label); groups[label] = [] }
            groups[label]?.append(n)
        }
        for label in order { out.append(NoteSection(id: label, title: label, notes: groups[label] ?? [])) }
        return out
    }

    static func dateBucket(_ iso: String) -> String {
        let inFmt = DateFormatter()
        inFmt.calendar = Calendar(identifier: .gregorian)
        inFmt.locale = Locale(identifier: "en_US_POSIX")
        inFmt.dateFormat = "yyyy-MM-dd"
        guard let date = inFmt.date(from: String(iso.prefix(10))) else { return "Earlier" }

        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        if let days = cal.dateComponents([.day], from: cal.startOfDay(for: date),
                                         to: cal.startOfDay(for: Date())).day {
            if days < 7 { return "Previous 7 Days" }
            if days < 30 { return "Previous 30 Days" }
        }
        let out = DateFormatter()
        out.locale = Locale(identifier: "en_US")
        out.dateFormat = cal.isDate(date, equalTo: Date(), toGranularity: .year) ? "MMMM" : "MMMM yyyy"
        return out.string(from: date)
    }
}
