import SwiftUI
import PhotosUI
import UIKit

/// One note, on the phone — a real block editor rather than a text box.
///
/// What was here before was a single `TextEditor` bound to the note's plain-text
/// mirror, saved through `updateNote(_:title:body:)`. That path rebuilds the
/// document with `BlockDoc.merging(plainText:)`, which carries attachments over
/// and turns *everything else* back into paragraphs. So a checklist written on
/// the Mac stopped being a checklist the moment it was opened and touched on the
/// phone, and the checkbox, heading and bullet buttons in the toolbar had
/// nothing they could honestly do. That is the "functionality not working".
///
/// This edits `BlockDoc` directly — one row per block, each with its own field —
/// and saves through `updateNoteContent(_:title:doc:)`, so structure survives
/// the round trip in both directions. The rules for Return, ticking and
/// retyping a line live in `NoteEditing`, in front of tests.
///
/// The one thing it cannot do that the Mac can is format *part* of a line:
/// SwiftUI's `TextField` never exposes the caret's selection, so bold and italic
/// apply to the whole line. Marks made on the Mac survive editing here either
/// way — they are carried, not rebuilt.
struct NoteBlockEditor: View {
    @EnvironmentObject var state: AppState
    let id: String
    @Environment(\.dismiss) private var dismiss

    private enum Field: Hashable {
        case title
        case block(String)
    }

    @State private var title = ""
    @State private var blocks: [Block] = []
    @State private var loaded = false
    @FocusState private var focused: Field?

    // Chrome
    @State private var showShare = false
    @State private var showDeleteConfirm = false
    @State private var showLockConfirm = false
    @State private var showPicker = false
    @State private var pickerItem: PhotosPickerItem?

    // Find
    @State private var showFind = false
    @State private var findQuery = ""
    @State private var findIndex = 0

    private var note: Note? { state.note(id) }
    private var hits: [String] { NoteEditing.matches(blocks, query: findQuery) }
    /// The line the caret is on — where a toolbar action lands. Falls back to
    /// the last line, so the buttons work before you have tapped into anything.
    private var target: String? {
        if case .block(let b) = focused { return b }
        return blocks.last?.id
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if showFind { findBar }
            Divider().background(Palette.divider)
            document
            Divider().background(Palette.divider)
            bottomBar
        }
        .background(Palette.background)
        .toolbar(.hidden, for: .navigationBar)
        // Apple's editor is the whole screen. Ours was drawing its own bottom
        // bar directly on top of the app's tab bar — two rows of icons, one of
        // them belonging to a screen you had already left.
        .toolbar(.hidden, for: .tabBar)
        .sheet(isPresented: $showShare) {
            NoteShareSheet(activityItems: [shareText])
                .presentationDetents([.medium, .large])
        }
        .alert("Delete Note?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { state.deleteNote(id); dismiss() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
        .alert("Lock Note?", isPresented: $showLockConfirm) {
            Button("Lock") { state.toggleLockNote(id); dismiss() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Locked notes are hidden from the list until revealed with Face ID.")
        }
        .photosPicker(isPresented: $showPicker, selection: $pickerItem, matching: .images)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await attach(item); pickerItem = nil }
        }
        .onAppear(perform: load)
        .onDisappear(perform: closeUp)
    }

    // MARK: - Document

    private var document: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    titleField
                    ForEach(blocks) { block in
                        row(block)
                            .id(block.id)
                            .padding(.vertical, block.isAttachment ? 6 : 1)
                    }
                    // Tap anywhere under the last line to carry on writing, the
                    // way a page of paper behaves.
                    Color.clear
                        .frame(height: 160)
                        .contentShape(Rectangle())
                        .onTapGesture { focusLast() }
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: findIndex) { _, _ in scrollToHit(proxy) }
            .onChange(of: findQuery) { _, _ in findIndex = 0; scrollToHit(proxy) }
        }
    }

    private var titleField: some View {
        TextField("", text: $title, prompt: Text("Title").foregroundColor(Palette.faint), axis: .vertical)
            .font(.title.weight(.bold))
            .foregroundStyle(Palette.text)
            .textInputAutocapitalization(.sentences)
            .focused($focused, equals: .title)
            .padding(.bottom, 4)
            .onChange(of: title) { _, _ in save() }
    }

    @ViewBuilder
    private func row(_ block: Block) -> some View {
        switch block.type {
        case .divider:
            Rectangle()
                .fill(Palette.divider)
                .frame(height: 1)
                .padding(.vertical, 10)
                .contextMenu { deleteBlockButton(block) }
        case .image:
            NoteImage(src: block.src ?? "", key: block.id)
                .contextMenu { deleteBlockButton(block) }
        case .linkCard:
            linkCard(block)
                .contextMenu { deleteBlockButton(block) }
        default:
            textRow(block)
        }
    }

    private func textRow(_ block: Block) -> some View {
        let isHit = hits.indices.contains(findIndex) && hits[findIndex] == block.id
        return HStack(alignment: .firstTextBaseline, spacing: 9) {
            marker(block)
            TextField("", text: text(of: block.id), axis: .vertical)
                .focused($focused, equals: .block(block.id))
                .font(font(for: block))
                .foregroundStyle(colour(for: block))
                .strikethrough(block.type == .todo && block.checked == true, color: Palette.faint)
                .textInputAutocapitalization(block.type == .heading ? .words : .sentences)
        }
        .padding(.leading, block.type == .quote ? 10 : 0)
        .overlay(alignment: .leading) {
            if block.type == .quote {
                Rectangle().fill(Palette.action.opacity(0.5)).frame(width: 3)
            }
        }
        .padding(.horizontal, block.type == .code ? 10 : 0)
        .padding(.vertical, block.type == .code ? 6 : 0)
        .background(codeBackground(block))
        // Find highlights the line it has landed on. A `TextField` cannot paint
        // a range of its own text, so the line is what there is to show — and a
        // line is enough to find your place on a phone screen.
        .background(isHit ? Palette.action.opacity(0.18) : .clear)
        .animation(.knFast, value: isHit)
        .contextMenu { blockMenu(block) }
    }

    @ViewBuilder
    private func marker(_ block: Block) -> some View {
        switch block.type {
        case .todo:
            Button {
                blocks = NoteEditing.toggleChecked(blocks, id: block.id)
                Haptics.selection()
                save()
            } label: {
                Image(systemName: block.checked == true ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19))
                    .foregroundStyle(block.checked == true ? Palette.action : Palette.faint)
            }
            .buttonStyle(.plain)
        case .bullet:
            Text("\u{2022}").font(.body.weight(.black)).foregroundStyle(Palette.action)
        case .numbered:
            Text("\(NoteEditing.ordinals(blocks)[block.id] ?? 1).")
                .font(.body.weight(.semibold)).monospacedDigit()
                .foregroundStyle(Palette.action)
        default:
            EmptyView()
        }
    }

    private func linkCard(_ block: Block) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "link").font(.footnote).foregroundStyle(Palette.action)
            VStack(alignment: .leading, spacing: 2) {
                Text(block.linkTitle ?? block.url ?? "Link")
                    .font(.footnote.weight(.semibold)).foregroundStyle(Palette.text).lineLimit(2)
                if let domain = block.linkDomain, !domain.isEmpty {
                    Text(domain).font(.caption2).foregroundStyle(Palette.faint)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    @ViewBuilder
    private func codeBackground(_ block: Block) -> some View {
        if block.type == .code {
            RoundedRectangle(cornerRadius: Radius.xs, style: .continuous).fill(Palette.surface)
        }
    }

    // MARK: - Type

    private func font(for block: Block) -> Font {
        var f: Font
        switch block.type {
        case .heading:
            switch block.level ?? 1 {
            case 1:  f = .title2.weight(.bold)
            case 2:  f = .title3.weight(.semibold)
            default: f = .headline
            }
        case .code:  f = .system(.callout, design: .monospaced)
        case .quote: f = .body.italic()
        default:     f = .body
        }
        let marks = block.spans.first?.marks ?? []
        if marks.contains(.bold) { f = f.bold() }
        if marks.contains(.italic) { f = f.italic() }
        return f
    }

    private func colour(for block: Block) -> Color {
        if block.type == .todo && block.checked == true { return Palette.faint }
        if block.type == .quote { return Palette.muted }
        return Palette.text
    }

    // MARK: - Editing

    /// Every keystroke arrives here. A newline in the incoming value is a Return
    /// that has just been pressed — `TextField(axis:.vertical)` inserts it as
    /// text — so this is where a line becomes two.
    private func text(of blockID: String) -> Binding<String> {
        Binding(
            get: { blocks.first { $0.id == blockID }?.spans.map(\.text).joined() ?? "" },
            set: { new in
                guard let newline = new.firstIndex(of: "\n") else {
                    blocks = NoteEditing.setText(new, in: blocks, id: blockID)
                    save()
                    return
                }
                let head = String(new[new.startIndex..<newline])
                let tail = String(new[new.index(after: newline)...])
                let result = NoteEditing.split(blocks, at: blockID, head: head, tail: tail)
                blocks = result.blocks
                save()
                // A hop, so focus moves after SwiftUI has taken the new row in.
                if let next = result.focus {
                    DispatchQueue.main.async { focused = .block(next) }
                }
            }
        )
    }

    private func focusLast() {
        if let last = blocks.last, !last.isAttachment {
            focused = .block(last.id)
        } else {
            blocks.append(Block.paragraph())
            save()
            if let last = blocks.last {
                DispatchQueue.main.async { focused = .block(last.id) }
            }
        }
    }

    private func retype(_ type: BlockType, level: Int? = nil) {
        guard let target else { return }
        let current = blocks.first { $0.id == target }?.type
        // Pressing Checklist on a checklist takes you back out of it — the same
        // button both ways, which is how the toolbar behaves in Notes.
        let next: BlockType = (current == type && type != .paragraph) ? .paragraph : type
        blocks = NoteEditing.convert(blocks, id: target, to: next, level: level)
        Haptics.tap()
        save()
    }

    private func mark(_ m: Mark) {
        guard let target else { return }
        blocks = NoteEditing.toggleMark(blocks, id: target, mark: m)
        Haptics.tap()
        save()
    }

    private func insertDivider() {
        blocks = NoteEditing.insert(Block(type: .divider), into: blocks, after: target)
        Haptics.tap()
        save()
    }

    @ViewBuilder
    private func blockMenu(_ block: Block) -> some View {
        Button {
            blocks = NoteEditing.convert(blocks, id: block.id, to: .paragraph)
            save()
        } label: {
            Label("Body Text", systemImage: "textformat")
        }
        deleteBlockButton(block)
    }

    private func deleteBlockButton(_ block: Block) -> some View {
        Button(role: .destructive) {
            blocks = NoteEditing.normalized(blocks.filter { $0.id != block.id })
            Haptics.warning()
            save()
        } label: {
            Label("Delete Line", systemImage: "trash")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            Button { dismiss() } label: {
                HStack(spacing: 2) {
                    Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold))
                    Text("Notes").font(.system(size: 17))
                }
                .foregroundStyle(Palette.action)
            }
            Spacer()
            Button { showShare = true } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 19))
                    .foregroundStyle(Palette.action)
            }
            Menu {
                Button {
                    if note?.locked == true { state.toggleLockNote(id) } else { showLockConfirm = true }
                } label: {
                    Label(note?.locked == true ? "Unlock Note" : "Lock Note",
                          systemImage: note?.locked == true ? "lock.open" : "lock")
                }
                Button { state.togglePinNote(id) } label: {
                    Label(note?.pinned == true ? "Unpin" : "Pin",
                          systemImage: note?.pinned == true ? "pin.slash" : "pin")
                }
                Button {
                    withAnimation(.knFast) { showFind.toggle() }
                    if !showFind { findQuery = "" }
                } label: {
                    Label("Find in Note", systemImage: "magnifyingglass")
                }
                Divider()
                Button(role: .destructive) { showDeleteConfirm = true } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 19))
                    .foregroundStyle(Palette.action)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }

    // MARK: - Find

    private var findBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.footnote).foregroundStyle(Palette.faint)
            TextField("Find in note", text: $findQuery)
                .font(.subheadline).foregroundStyle(Palette.text)
                .autocorrectionDisabled()
            if !findQuery.isEmpty {
                Text(hits.isEmpty ? "None" : "\(min(findIndex + 1, hits.count)) of \(hits.count)")
                    .font(.caption2.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(Palette.faint)
                Button { stepHit(-1) } label: { Image(systemName: "chevron.up") }
                    .disabled(hits.isEmpty)
                Button { stepHit(1) } label: { Image(systemName: "chevron.down") }
                    .disabled(hits.isEmpty)
            }
            Button {
                withAnimation(.knFast) { showFind = false }
                findQuery = ""
            } label: {
                Text("Done").font(.subheadline.weight(.semibold))
            }
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(Palette.action)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func stepHit(_ by: Int) {
        guard !hits.isEmpty else { return }
        findIndex = ((findIndex + by) % hits.count + hits.count) % hits.count
        Haptics.selection()
    }

    private func scrollToHit(_ proxy: ScrollViewProxy) {
        guard hits.indices.contains(findIndex) else { return }
        withAnimation(.knNormal) { proxy.scrollTo(hits[findIndex], anchor: .center) }
    }

    // MARK: - Bottom bar

    /// Apple's four, in Apple's order, at Apple's size — and every one of them
    /// does the thing its glyph promises. The old bar had `list.bullet` (which
    /// dismissed the editor), a `highlighter` wired to nothing, and a "Move
    /// Note" that opened an alert saying the feature did not exist.
    private var bottomBar: some View {
        HStack {
            barButton("checklist") { retype(.todo) }
            Spacer()
            barButton("paperclip") { showPicker = true }
            Spacer()
            Menu {
                Section("Style") {
                    Button { retype(.heading, level: 1) } label: { Label("Title", systemImage: "textformat.size.larger") }
                    Button { retype(.heading, level: 2) } label: { Label("Heading", systemImage: "textformat.size") }
                    Button { retype(.paragraph) } label: { Label("Body", systemImage: "textformat") }
                    Button { retype(.quote) } label: { Label("Quote", systemImage: "text.quote") }
                    Button { retype(.code) } label: { Label("Monospaced", systemImage: "chevron.left.forwardslash.chevron.right") }
                }
                Section("Format") {
                    Button { mark(.bold) } label: { Label("Bold", systemImage: "bold") }
                    Button { mark(.italic) } label: { Label("Italic", systemImage: "italic") }
                }
                Section("Lists") {
                    Button { retype(.bullet) } label: { Label("Bulleted List", systemImage: "list.bullet") }
                    Button { retype(.numbered) } label: { Label("Numbered List", systemImage: "list.number") }
                    Button { retype(.todo) } label: { Label("Checklist", systemImage: "checklist") }
                    Button { insertDivider() } label: { Label("Divider", systemImage: "minus") }
                }
            } label: {
                Image(systemName: "pencil.tip.crop.circle")
                    .font(.system(size: 20))
                    .foregroundStyle(Palette.action)
                    .frame(width: 44, height: 40)
            }
            Spacer()
            barButton("square.and.pencil") {
                closeUp()
                state.pendingNewNote = true
                dismiss()
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 6)
        .background(Palette.background)
    }

    private func barButton(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 20))
                .foregroundStyle(Palette.action)
                .frame(width: 44, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Attachments

    private func attach(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data),
              let encoded = NoteImage.encode(image) else { return }
        blocks = NoteEditing.insert(Block(type: .image, src: encoded), into: blocks, after: target)
        Haptics.success()
        save()
    }

    // MARK: - Persistence

    private var shareText: String {
        let body = BlockDoc(blocks: blocks).plainText
        return title.isEmpty ? body : "\(title)\n\n\(body)"
    }

    private func load() {
        guard !loaded else { return }
        if let n = state.note(id) {
            title = n.title
            blocks = NoteEditing.normalized(n.effectiveDoc.blocks)
        } else {
            blocks = NoteEditing.normalized([])
        }
        loaded = true
    }

    private func save() {
        guard loaded else { return }
        state.updateNoteContent(id, title: title, doc: BlockDoc(blocks: NoteEditing.normalized(blocks)))
    }

    /// Leaving. Save, and drop the note if nothing was ever put in it — opening
    /// a new note and changing your mind should not leave "Untitled" behind.
    private func closeUp() {
        save()
        let doc = BlockDoc(blocks: NoteEditing.normalized(blocks))
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, doc.isEffectivelyEmpty {
            state.deleteNote(id)
        }
    }
}

// MARK: - Inline photo

/// A picture inside a note. Decoded off the main thread and cached by block id,
/// because SwiftUI re-runs a body far more often than a JPEG should be decoded.
struct NoteImage: View {
    let src: String
    let key: String

    @State private var image: UIImage?

    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 60
        return c
    }()

    var body: some View {
        Group {
            if let image = image ?? Self.cache.object(forKey: key as NSString) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(Palette.surface)
                    .frame(height: 160)
                    .overlay(ProgressView().tint(Palette.faint))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: key) {
            guard Self.cache.object(forKey: key as NSString) == nil else { return }
            let source = src
            let decoded = await Task.detached(priority: .userInitiated) { () -> UIImage? in
                guard let data = Data(base64Encoded: source) else { return nil }
                return UIImage(data: data)
            }.value
            if let decoded { Self.cache.setObject(decoded, forKey: key as NSString) }
            image = decoded
        }
    }

    /// Downscale before storing: note content is synced as JSON, so a full
    /// camera frame in base64 is several megabytes on every save.
    static func encode(_ image: UIImage, maxDimension: CGFloat = 1400) -> String? {
        let pxW = image.size.width * image.scale
        let pxH = image.size.height * image.scale
        guard pxW > 0, pxH > 0 else { return nil }
        let scale = min(1, maxDimension / max(pxW, pxH))
        let w = max(1, Int((pxW * scale).rounded()))
        let h = max(1, Int((pxH * scale).rounded()))
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: w, height: h))
        let resized = renderer.image { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return resized.jpegData(compressionQuality: 0.7)?.base64EncodedString()
    }
}

// MARK: - Share

struct NoteShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
