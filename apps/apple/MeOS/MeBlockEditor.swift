import SwiftUI
import PhotosUI
import LinkPresentation

/// MeOS block editor. Same BlockDoc model throughout, so notes stay compatible across devices.
/// Return splits a block, markdown prefixes convert it (`# `, `- `, `[ ] `, `> `, ``` , `1. `, `---`),
/// pasting a lone URL makes a link card.
struct MeBlockEditor: View {
    @EnvironmentObject var state: AppState
    let id: String
    @State private var title = ""
    @State private var blocks: [Block] = []
    @State private var loaded = false
    @State private var photo: PhotosPickerItem?
    @State private var saveTask: Task<Void, Never>?
    @FocusState private var focus: String?

    var body: some View {
        let ordinals = NoteEditing.ordinals(blocks)
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                TextField("Title", text: $title, axis: .vertical)
                    .font(.system(size: 34, weight: .bold)).tracking(-0.6)
                    .focused($focus, equals: "title")
                    .onSubmit { focus = blocks.first?.id }
                    .padding(.bottom, 10)
                ForEach(blocks) { b in
                    row(b, ordinal: ordinals[b.id])
                        .contextMenu {
                            Button("Delete block", systemImage: "trash", role: .destructive) { withAnimation(DS.spring) { remove(b.id) } }
                        }
                }
                Color.clear.frame(height: 240).contentShape(.rect)
                    .onTapGesture { focusLastOrAppend() }
            }
            .padding(.horizontal, DS.pad)
        }
        .scrollDismissesKeyboard(.interactively)
        .meActions { ShareLink(item: shareText) { Image(systemName: "square.and.arrow.up") } }
        #if os(iOS)
        .toolbar { ToolbarItemGroup(placement: .keyboard) { keyboardBar } }
        #endif
        .onAppear(perform: load)
        .onDisappear(perform: closeUp)
        .onChange(of: title) { scheduleSave() }
        .onChange(of: blocks) { scheduleSave() }
        .onChange(of: photo) { _, item in Task { await insertPhoto(item) } }
    }

    // MARK: rows

    @ViewBuilder private func row(_ b: Block, ordinal: Int?) -> some View {
        switch b.type {
        case .divider:
            Rectangle().fill(Color.hairline).frame(height: 2).padding(.vertical, 14)
        case .image:
            MeInlineImage(src: b.src ?? "", key: b.id).padding(.vertical, 6)
        case .linkCard:
            Link(destination: URL(string: b.url ?? "") ?? URL(string: "https://apple.com")!) {
                HStack(spacing: 14) {
                    if let t = b.linkThumb, !t.isEmpty { MeInlineImage(src: t, key: b.id + "t").frame(width: 72, height: 72).clipShape(.rect(cornerRadius: 14)) }
                    else { Image(systemName: "link").font(.title2).frame(width: 72, height: 72).background(Color.hairline, in: .rect(cornerRadius: 14)) }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(b.linkTitle ?? b.url ?? "Link").font(.headline).lineLimit(2).multilineTextAlignment(.leading)
                        Text(b.linkDomain ?? "").font(.subheadline).foregroundStyle(Color.dim)
                    }
                    Spacer(minLength: 0)
                }
                .padding(12).background(Color.card, in: .rect(cornerRadius: 20))
            }
            .foregroundStyle(.primary).padding(.vertical, 4)
        default:
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                switch b.type {
                case .bullet: Text("•").font(.title3.bold())
                case .numbered: Text("\(ordinal ?? 1).").font(.title3.weight(.semibold)).monospacedDigit()
                case .todo:
                    Button { withAnimation(DS.bouncy) { blocks = NoteEditing.toggleChecked(blocks, id: b.id) } } label: {
                        Image(systemName: b.checked == true ? "checkmark.square.fill" : "square").font(.title3)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.press).sensoryFeedback(.success, trigger: b.checked == true) { !$0 && $1 }
                case .quote: Capsule().fill(Color.ink).frame(width: 4)
                default: EmptyView()
                }
                TextField(placeholder(b), text: binding(b.id), axis: .vertical)
                    .font(font(b))
                    .strikethrough(b.type == .todo && b.checked == true)
                    .opacity(b.type == .todo && b.checked == true ? 0.45 : 1)
                    .bold(b.spans.first?.marks.contains(.bold) == true)
                    .italic(b.spans.first?.marks.contains(.italic) == true || b.type == .quote)
                    .focused($focus, equals: b.id)
            }
            .padding(.vertical, b.type == .heading ? 8 : 3)
            .padding(b.type == .code ? 12 : 0)
            .background(b.type == .code ? Color.card : Color.clear, in: .rect(cornerRadius: 14))
        }
    }

    private func font(_ b: Block) -> Font {
        switch b.type {
        case .heading: return b.level == 1 ? .system(size: 28, weight: .bold) : b.level == 2 ? .title2.bold() : .title3.bold()
        case .code: return .system(.body, design: .monospaced)
        default: return .title3
        }
    }
    private func placeholder(_ b: Block) -> String {
        if b.type == .heading { return "Heading" }
        return blocks.count == 1 ? "Start writing…" : ""
    }

    // MARK: editing

    private func binding(_ id: String) -> Binding<String> {
        Binding(
            get: { blocks.first { $0.id == id }?.plainText ?? "" },
            set: { new in edit(id, new) }
        )
    }

    private func edit(_ id: String, _ new: String) {
        guard let i = blocks.firstIndex(where: { $0.id == id }) else { return }
        // Return splits the block.
        if let nl = new.firstIndex(of: "\n"), blocks[i].type != .code {
            let head = String(new[..<nl]), tail = String(new[new.index(after: nl)...])
            // Return on an empty list item leaves the list.
            if head.isEmpty && NoteEditing.isList(blocks[i].type) {
                blocks = NoteEditing.convert(blocks, id: id, to: .paragraph); return
            }
            let r = NoteEditing.split(blocks, at: id, head: head, tail: tail)
            withAnimation(DS.spring) { blocks = r.blocks }
            focus = r.focus
            return
        }
        // Markdown shortcuts, only while the block is still a paragraph.
        if blocks[i].type == .paragraph {
            let rules: [(String, BlockType, Int?)] = [("### ", .heading, 3), ("## ", .heading, 2), ("# ", .heading, 1),
                                                      ("- ", .bullet, nil), ("* ", .bullet, nil), ("1. ", .numbered, nil),
                                                      ("[ ] ", .todo, nil), ("[] ", .todo, nil), ("> ", .quote, nil), ("```", .code, nil)]
            for (p, t, lvl) in rules where new.hasPrefix(p) {
                var out = NoteEditing.convert(blocks, id: id, to: t, level: lvl)
                out = NoteEditing.setText(String(new.dropFirst(p.count)), in: out, id: id)
                withAnimation(DS.spring) { blocks = out }
                return
            }
            if new == "---" {
                var out = NoteEditing.convert(blocks, id: id, to: .divider)
                let next = Block.paragraph()
                out = NoteEditing.insert(next, into: out, after: id)
                withAnimation(DS.spring) { blocks = out }; focus = next.id
                return
            }
            if let url = URL(string: new.trimmingCharacters(in: .whitespaces)), new.count > 10, !new.contains(" "),
               url.scheme?.hasPrefix("http") == true, url.host != nil {
                blocks[i] = Block(id: id, type: .linkCard, url: url.absoluteString, linkDomain: url.host)
                Task { await fetchLink(id: id, url: url) }
                let next = Block.paragraph()
                blocks = NoteEditing.insert(next, into: blocks, after: id); focus = next.id
                return
            }
        }
        blocks = NoteEditing.setText(new, in: blocks, id: id)
    }

    private func remove(_ id: String) {
        blocks.removeAll { $0.id == id }
        if blocks.isEmpty { blocks = [Block.paragraph()] }
    }

    private func focusLastOrAppend() {
        if let last = blocks.last, last.isEmpty, !last.isAttachment { focus = last.id; return }
        let b = Block.paragraph()
        blocks.append(b); focus = b.id
    }

    private func setType(_ t: BlockType, level: Int? = nil) {
        guard let id = focus, id != "title" else { return }
        blocks = NoteEditing.convert(blocks, id: id, to: t, level: level)
        Haptics.tap()
    }

    private var keyboardBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 18) {
                Button { setType(.paragraph) } label: { Image(systemName: "textformat") }
                Button { setType(.heading, level: 1) } label: { Text("H1").bold() }
                Button { setType(.heading, level: 2) } label: { Text("H2").bold() }
                Button { setType(.bullet) } label: { Image(systemName: "list.bullet") }
                Button { setType(.numbered) } label: { Image(systemName: "list.number") }
                Button { setType(.todo) } label: { Image(systemName: "checklist") }
                Button { setType(.quote) } label: { Image(systemName: "text.quote") }
                Button { setType(.code) } label: { Image(systemName: "chevron.left.forwardslash.chevron.right") }
                Button { if let id = focus, id != "title" { blocks = NoteEditing.toggleMark(blocks, id: id, mark: .bold) } } label: { Image(systemName: "bold") }
                Button { if let id = focus, id != "title" { blocks = NoteEditing.toggleMark(blocks, id: id, mark: .italic) } } label: { Image(systemName: "italic") }
                Button {
                    let d = Block(type: .divider), p = Block.paragraph()
                    blocks = NoteEditing.insert(p, into: NoteEditing.insert(d, into: blocks, after: focus), after: d.id); focus = p.id
                } label: { Image(systemName: "minus") }
                PhotosPicker(selection: $photo, matching: .images) { Image(systemName: "photo") }
                Button { focus = nil } label: { Image(systemName: "keyboard.chevron.compact.down") }
            }
            .font(.title3)
            .padding(.horizontal, 4)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: media

    private func insertPhoto(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data),
              let b64 = MeInlineImage.encode(img) else { return }
        let b = Block(type: .image, src: b64)
        let p = Block.paragraph()
        withAnimation(DS.spring) { blocks = NoteEditing.insert(p, into: NoteEditing.insert(b, into: blocks, after: focus), after: b.id) }
        focus = p.id; photo = nil
    }

    private func fetchLink(id: String, url: URL) async {
        let meta = try? await LPMetadataProvider().startFetchingMetadata(for: url)
        var thumb: String?
        if let provider = meta?.imageProvider,
           let img = await withCheckedContinuation({ (c: CheckedContinuation<UIImage?, Never>) in
               provider.loadObject(ofClass: UIImage.self) { o, _ in c.resume(returning: o as? UIImage) }
           }) {
            thumb = MeInlineImage.encode(img, maxDimension: 300)
        }
        guard let i = blocks.firstIndex(where: { $0.id == id }) else { return }
        blocks[i].linkTitle = meta?.title ?? url.host
        blocks[i].linkThumb = thumb
    }

    // MARK: persistence

    private var shareText: String {
        let body = BlockDoc(blocks: blocks).plainText
        return title.isEmpty ? body : "\(title)\n\n\(body)"
    }

    private func load() {
        guard !loaded else { return }
        if let n = state.note(id) { title = n.title; blocks = NoteEditing.normalized(n.effectiveDoc.blocks) }
        else { blocks = NoteEditing.normalized([]) }
        loaded = true
        if title.isEmpty && BlockDoc(blocks: blocks).isEffectivelyEmpty { focus = "title" }
    }

    private func scheduleSave() {
        guard loaded else { return }
        saveTask?.cancel()
        saveTask = Task { try? await Task.sleep(for: .milliseconds(600)); if !Task.isCancelled { save() } }
    }

    private func save() {
        guard loaded else { return }
        state.updateNoteContent(id, title: title, doc: BlockDoc(blocks: NoteEditing.normalized(blocks)))
    }

    private func closeUp() {
        saveTask?.cancel(); save()
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, BlockDoc(blocks: blocks).isEffectivelyEmpty {
            state.deleteNote(id)
        }
    }
}

/// Base64 image, decoded off the main thread and cached.
struct MeInlineImage: View {
    let src: String
    let key: String
    @State private var image: UIImage?
    private static let cache: NSCache<NSString, UIImage> = { let c = NSCache<NSString, UIImage>(); c.countLimit = 80; return c }()

    var body: some View {
        Group {
            if let img = image ?? Self.cache.object(forKey: key as NSString) {
                Image(uiImage: img).resizable().scaledToFit().clipShape(.rect(cornerRadius: 18))
            } else {
                RoundedRectangle(cornerRadius: 18).fill(Color.card).frame(height: 160)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: key) {
            guard Self.cache.object(forKey: key as NSString) == nil else { return }
            let s = src
            let img = await Task.detached { Data(base64Encoded: s).flatMap(UIImage.init(data:)) }.value
            if let img { Self.cache.setObject(img, forKey: key as NSString) }
            image = img
        }
    }

    static func encode(_ image: UIImage, maxDimension: CGFloat = 1400) -> String? {
        let w = image.size.width * image.scale, h = image.size.height * image.scale
        guard w > 0, h > 0 else { return nil }
        let s = min(1, maxDimension / max(w, h))
        let size = CGSize(width: (w * s).rounded(), height: (h * s).rounded())
        #if os(iOS)
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let out = UIGraphicsImageRenderer(size: size, format: fmt).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        #else
        let out = image.resized(to: size)
        #endif
        return out.jpegData(compressionQuality: 0.8)?.base64EncodedString()
    }
}
