import AppKit
import SwiftUI

// A native, single-surface block editor (Engine A). One NSTextView (TextKit 1)
// edits a styled attributed string. Inline edits mutate the string directly;
// structural edits round-trip through BlockDoc, re-render, and restore the caret.

struct BlockEditor: NSViewRepresentable {
    let initialDoc: BlockDoc
    var placeholder: String = "Write something, or press ‘/’ for commands…"
    /// Bumped from SwiftUI to reveal the native find bar (Find in Note).
    var findToken: Int = 0
    /// Extra scroll inset so the last lines clear the floating log bar.
    var bottomInset: CGFloat = 0
    /// The channel the format bar talks over. Optional so an editor that wants
    /// no chrome — a preview, a test — simply doesn't pass one.
    var commands: EditorCommands? = nil
    var onChange: (BlockDoc) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        // Force TextKit 1 by building the classic stack explicitly.
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)

        let tv = BlockTextView(frame: .zero, textContainer: container)
        tv.coordinator = context.coordinator
        tv.delegate = context.coordinator
        tv.isRichText = true
        tv.allowsUndo = true
        tv.isEditable = true
        tv.isSelectable = true
        tv.drawsBackground = false
        tv.backgroundColor = NSColor.clear
        tv.insertionPointColor = EditorTheme.brand
        tv.textContainerInset = NSSize(width: 0, height: 8)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        // Without an unbounded maxSize the text view can't grow past its initial
        // frame, so long notes get clipped and there's nothing to scroll.
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.usesFindBar = true
        tv.isIncrementalSearchingEnabled = true
        tv.placeholderText = placeholder
        tv.typingAttributes = EditorTheme.baseAttributes(for: Block.paragraph())
        tv.textStorage?.setAttributedString(BlockBridge.attributedString(from: initialDoc))

        context.coordinator.textView = tv
        commands?.coordinator = context.coordinator

        let scroll = NSScrollView()
        scroll.documentView = tv
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.backgroundColor = NSColor.clear
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: bottomInset, right: 0)
        context.coordinator.lastFindToken = findToken

        DispatchQueue.main.async { [weak tv] in
            guard let tv else { return }
            tv.window?.makeFirstResponder(tv)
        }
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        commands?.coordinator = context.coordinator
        if nsView.contentInsets.bottom != bottomInset {
            nsView.contentInsets.bottom = bottomInset
        }
        // A change in findToken is the SwiftUI signal to open the find bar.
        if findToken != context.coordinator.lastFindToken {
            context.coordinator.lastFindToken = findToken
            context.coordinator.showFindBar()
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: BlockEditor
        weak var textView: BlockTextView?
        var isProgrammatic = false
        var lastFindToken = 0
        let slash = SlashMenuController()

        /// Reveal the native find bar (drives "Find in Note").
        func showFindBar() {
            guard let tv = textView else { return }
            let item = NSMenuItem()
            item.tag = NSTextFinder.Action.showFindInterface.rawValue
            tv.window?.makeFirstResponder(tv)
            tv.performTextFinderAction(item)
        }

        /// The empty last block, if any. An empty trailing block has zero
        /// characters in the attributed string, so its type lives only here
        /// (set on every structural render) — serialization and typing
        /// attributes consult it instead of misreading the previous block.
        private var trailingBlockMeta: Block?

        /// The trailing empty block, when it's a list item — so the text view can
        /// draw its bullet/number/checkbox on the otherwise-invisible last line
        /// (`byParagraphs` never visits the empty line after a final newline).
        var trailingListDecoration: (type: BlockType, checked: Bool)? {
            guard let m = trailingBlockMeta,
                  m.type == .bullet || m.type == .numbered || m.type == .todo else { return nil }
            return (m.type, m.checked ?? false)
        }
        var trailingBlockID: String? { trailingBlockMeta?.id }

        init(_ parent: BlockEditor) { self.parent = parent }

        // MARK: Change pipeline

        func textDidChange(_ notification: Notification) {
            guard !isProgrammatic, let tv = textView else { return }
            // Block-level markdown triggers (# , - , [] , > , ``` , --- , 1. )
            if applyBlockMarkdown(in: tv) { return }   // render() already saved
            // Inline markdown (**b** *i* `c` ~~s~~)
            applyInlineMarkdown(in: tv)
            if slash.isActive { updateSlashQuery(tv) }
            tv.needsDisplay = true
            save()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isProgrammatic, let tv = textView else { return }
            syncTypingAttributes(tv)
            if slash.isActive { updateSlashQuery(tv) }
            publishSelection(tv)
            // Deliberately NOT `tv.needsDisplay = true`. The gutter decorations
            // are drawn from block attributes and the trailing-block meta —
            // nothing there depends on where the caret or the selection is. This
            // line invalidated the entire view on every selection change, which
            // means once per mouse-move for the whole of a drag-select, and each
            // redraw walks every paragraph and asks the layout manager for its
            // rects. On a long note that is what made selecting text feel like
            // it was fighting you. AppKit already invalidates the selection's
            // own region.
        }

        /// Publish the current selection so a SwiftUI format bar can sit over
        /// it. Rect is in the clip view's coordinates, which are flipped and
        /// therefore share an origin with the SwiftUI frame around us.
        private func publishSelection(_ tv: BlockTextView) {
            guard let commands = parent.commands else { return }
            let next: EditorSelection? = {
                let sel = tv.selectedRange()
                guard sel.length > 0,
                      let lm = tv.layoutManager, let tc = tv.textContainer,
                      let clip = tv.enclosingScrollView?.contentView else { return nil }
                let glyphs = lm.glyphRange(forCharacterRange: sel, actualCharacterRange: nil)
                var rect = lm.boundingRect(forGlyphRange: glyphs, in: tc)
                rect.origin.x += tv.textContainerOrigin.x
                rect.origin.y += tv.textContainerOrigin.y
                return EditorSelection(rect: tv.convert(rect, to: clip),
                                       marks: marks(in: sel, of: tv))
            }()
            // The delegate callback is on the main thread but not annotated as
            // such, which the concurrency checker cannot know.
            MainActor.assumeIsolated {
                if commands.selection != next { commands.selection = next }
            }
        }

        /// Which marks the WHOLE selection carries — a partly-bold selection is
        /// not bold, so the button reads unset and one press makes all of it bold.
        private func marks(in range: NSRange, of tv: BlockTextView) -> Set<Mark> {
            guard let storage = tv.textStorage else { return [] }
            var out: Set<Mark> = []
            for mark in [Mark.bold, .italic, .strike, .code] {
                var all = true
                storage.enumerateAttributes(in: range, options: []) { at, _, _ in
                    if !hasMark(mark, at) { all = false }
                }
                if all { out.insert(mark) }
            }
            return out
        }

        /// Push every change up immediately. The network push is already
        /// debounced in AppState, and an editor-side debounce loses the last
        /// keystrokes on close / tab switch / quit.
        private func save() {
            parent.onChange(docFromStorage())
        }

        /// Serialize the storage, giving the invisible empty trailing block its
        /// real identity back (e.g. the empty bullet Enter just created).
        func docFromStorage() -> BlockDoc {
            guard let storage = textView?.textStorage else { return BlockDoc() }
            var doc = BlockBridge.blockDoc(from: storage)
            if let meta = trailingBlockMeta, storage.string.hasSuffix("\n"),
               let last = doc.blocks.last, last.type == .paragraph, last.plainText.isEmpty {
                doc.blocks[doc.blocks.count - 1] = Block(id: meta.id, type: meta.type, spans: [],
                                                         checked: meta.checked, level: meta.level,
                                                         language: meta.language)
            }
            return doc
        }

        private func rememberTrailing(_ doc: BlockDoc) {
            // Attachments are never the trailing "empty block": an image's
            // plainText is empty too, so it qualified — and the rebuild then
            // recreated it from the remembered meta *without* its `src`,
            // leaving a blank grey box in the note where the photo had been.
            if let last = doc.blocks.last, last.type != .divider,
               !last.isAttachment, last.plainText.isEmpty {
                trailingBlockMeta = last
            } else {
                trailingBlockMeta = nil
            }
        }

        /// Make a structural edit undoable, instead of destroying the history.
        ///
        /// This used to be `removeAllActions()`. The reasoning went as far as it
        /// went — a programmatic `setAttributedString` leaves the text view's own
        /// typing records pointing at ranges that no longer exist — but the cure
        /// meant no structural edit was ever undoable AND every one of them wiped
        /// the typing history before it. Delete an image and ⌘Z could not bring
        /// it back; press Return and ⌘Z could no longer reach the sentence typed
        /// before it.
        ///
        /// A full-document snapshot fixes both. Each action restores the entire
        /// storage, so after an undo the content is exactly what the older typing
        /// records were made against and the stack stays coherent. Registering
        /// the inverse from inside the undo gives redo.
        private func registerUndo(restoring doc: BlockDoc, caret: Int) {
            guard let um = textView?.undoManager else { return }
            um.registerUndo(withTarget: self) { target in
                target.restoreForUndo(doc, caret: caret)
            }
        }

        private func restoreForUndo(_ doc: BlockDoc, caret: Int) {
            guard let tv = textView, let storage = tv.textStorage else { return }
            let inverse = currentDoc()
            let inverseCaret = tv.selectedRange().location
            isProgrammatic = true
            storage.setAttributedString(BlockBridge.attributedString(from: doc))
            tv.setSelectedRange(NSRange(location: min(caret, storage.length), length: 0))
            isProgrammatic = false
            rememberTrailing(doc)
            registerUndo(restoring: inverse, caret: inverseCaret)
            syncTypingAttributes(tv)
            tv.needsDisplay = true
            save()
        }

        /// The document as it stands, for the undo stack.
        private func snapshotForUndo() -> (doc: BlockDoc, caret: Int)? {
            guard let tv = textView else { return nil }
            return (currentDoc(), tv.selectedRange().location)
        }

        // MARK: Typing attributes (carry block style forward as the caret moves)

        func syncTypingAttributes(_ tv: BlockTextView) {
            guard let storage = tv.textStorage else { return }
            let ns = storage.string as NSString
            let loc = min(tv.selectedRange().location, ns.length)
            let para = ns.paragraphRange(for: NSRange(location: loc, length: 0))
            // Caret on the empty trailing line: no character carries its
            // attributes, and the char before the caret is the PREVIOUS block's
            // newline — use the remembered trailing block instead.
            if para.length == 0, para.location == ns.length, ns.length > 0 {
                tv.typingAttributes = EditorTheme.baseAttributes(for: trailingBlockMeta ?? Block.paragraph())
                return
            }
            // block type of current paragraph
            var block = Block.paragraph()
            let readAt = para.length > 0 ? para.location : max(0, min(para.location, storage.length - 1))
            if storage.length > 0, readAt < storage.length {
                let at = storage.attributes(at: readAt, effectiveRange: nil)
                block = blockMeta(from: at)
            }
            // Never type "into" an attachment. `blockMeta` reads the block from
            // the character at the caret, so at offset 0 of an image paragraph it
            // handed typed text `blockType == "image"` with no source — and the
            // paragraph then serialized as an image block with a nil src,
            // destroying both the typed word and the photo.
            if block.isAttachment { block = Block.paragraph() }
            var attrs = EditorTheme.baseAttributes(for: block)
            // Inherit inline marks from the char just before the caret (same paragraph).
            if loc > para.location, loc - 1 < storage.length,
               ns.character(at: loc - 1) != 10 {
                var inherited = storage.attributes(at: loc - 1, effectiveRange: nil)
                inherited[.paragraphStyle] = attrs[.paragraphStyle]
                inherited[.blockType] = attrs[.blockType]
                inherited[.blockID] = attrs[.blockID]
                inherited[.headingLevel] = attrs[.headingLevel]
                inherited[.todoChecked] = attrs[.todoChecked]
                inherited[.codeLanguage] = attrs[.codeLanguage]
                // And the media keys. Inheriting every attribute from the
                // preceding character carried `.attachment`, `.blockImageSrc`
                // and `.blockLinkURL` into freshly typed text.
                inherited[.attachment] = nil
                inherited[.blockImageSrc] = nil
                inherited[.blockLinkURL] = nil
                attrs = inherited
            }
            tv.typingAttributes = attrs
        }

        private func blockMeta(from at: [NSAttributedString.Key: Any]) -> Block {
            let type = BlockType(rawValue: at[.blockType] as? String ?? "paragraph") ?? .paragraph
            return Block(id: at[.blockID] as? String ?? Block.newID(), type: type,
                         checked: at[.todoChecked] as? Bool,
                         level: at[.headingLevel] as? Int,
                         language: at[.codeLanguage] as? String)
        }

        // MARK: Structural edits (round-trip through BlockDoc)

        /// Re-render `doc` and place the caret at (blockIndex, within).
        func render(_ doc: BlockDoc, caretBlock: Int, caretWithin: Int) {
            guard let tv = textView, let storage = tv.textStorage else { return }
            let before = snapshotForUndo()
            isProgrammatic = true
            let attr = BlockBridge.attributedString(from: doc)
            storage.setAttributedString(attr)
            let caret = offset(block: caretBlock, within: caretWithin, in: doc)
            tv.setSelectedRange(NSRange(location: min(caret, storage.length), length: 0))
            isProgrammatic = false
            rememberTrailing(doc)
            if let before { registerUndo(restoring: before.doc, caret: before.caret) }
            syncTypingAttributes(tv)
            tv.needsDisplay = true
            save()
        }

        func currentDoc() -> BlockDoc { docFromStorage() }

        func handleReturn() -> Bool {
            guard let tv = textView else { return false }
            if slash.isActive { commitSlash(); return true }
            let doc = currentDoc()
            let (bi, w) = locate(tv.selectedRange().location, in: doc)
            var blocks = doc.blocks
            let cur = blocks[bi]

            // Empty list item → exit the list.
            if (cur.type == .bullet || cur.type == .numbered || cur.type == .todo), cur.plainText.isEmpty {
                blocks[bi] = Block(id: cur.id, type: .paragraph)
                render(BlockDoc(blocks: blocks), caretBlock: bi, caretWithin: 0)
                return true
            }

            let (left, right) = splitSpans(cur.spans, at: w)
            let continues = (cur.type == .bullet || cur.type == .numbered || cur.type == .todo)
            let newType: BlockType = continues ? cur.type : .paragraph
            var leftBlock = cur; leftBlock.spans = left
            let newBlock = Block(type: newType, spans: right,
                                 checked: newType == .todo ? false : nil,
                                 level: nil)
            blocks[bi] = leftBlock
            blocks.insert(newBlock, at: bi + 1)
            render(BlockDoc(blocks: blocks), caretBlock: bi + 1, caretWithin: 0)
            return true
        }

        /// Forward delete, with the same refusal as backspace.
        ///
        /// At the end of a block, fn-Delete pulls the NEXT block up into this
        /// one. If either side is an attachment that merge is destructive — the
        /// serializer takes a paragraph's identity from its first character, so
        /// a mixed `text + image` paragraph is saved as one or the other and the
        /// rest is discarded on the same keystroke.
        func handleForwardDelete() -> Bool {
            guard let tv = textView else { return false }
            guard tv.selectedRange().length == 0 else { return false }
            let doc = currentDoc()
            let caret = tv.selectedRange().location
            let (bi, w) = locate(caret, in: doc)
            guard bi < doc.blocks.count else { return false }
            let atEnd = w == (doc.blocks[bi].plainText as NSString).length
            guard atEnd, bi + 1 < doc.blocks.count else { return false }
            // Deleting forward INTO or OUT OF an attachment: refuse, exactly as
            // backspace does. The image stays removable with the caret on it.
            if doc.blocks[bi].isAttachment || doc.blocks[bi + 1].isAttachment { return true }
            return false
        }

        func handleBackspace() -> Bool {
            guard let tv = textView else { return false }
            if slash.isActive, slash.query.isEmpty { dismissSlash() }
            guard tv.selectedRange().length == 0 else { return false }  // let selection-delete pass
            let doc = currentDoc()
            let caret = tv.selectedRange().location
            let (bi, w) = locate(caret, in: doc)
            // A media block (image / link card) is a single attachment — backspace at
            // or just after it removes the whole thing, never a stray empty shell.
            if doc.blocks[bi].isAttachment {
                var blocks = doc.blocks
                blocks.remove(at: bi)
                if blocks.isEmpty { blocks = [Block.paragraph()] }
                let target = max(0, bi - 1)
                let within = blocks[target].isAttachment ? 1 : (blocks[target].plainText as NSString).length
                render(BlockDoc(blocks: blocks), caretBlock: target, caretWithin: within)
                return true
            }
            guard w == 0 else { return false }  // mid-line delete → default

            var blocks = doc.blocks
            let cur = blocks[bi]
            // Backspace at start of a styled block resets it to a plain paragraph first.
            if cur.type != .paragraph {
                blocks[bi] = Block(id: cur.id, type: .paragraph, spans: cur.type == .divider ? [] : cur.spans)
                render(BlockDoc(blocks: blocks), caretBlock: bi, caretWithin: 0)
                return true
            }
            guard bi > 0 else { return true }  // first block, nothing before
            let prev = blocks[bi - 1]
            if prev.type == .divider {
                blocks.remove(at: bi - 1)
                render(BlockDoc(blocks: blocks), caretBlock: bi - 1, caretWithin: 0)
                return true
            }
            // Never merge into an attachment. An image or link card renders as a
            // single attachment character, so the merged spans are gone on the
            // very next render — backspacing at the start of the line under a
            // photo silently deleted that whole line of text, for good. The
            // image itself is still removable by putting the caret on it (the
            // branch above), so refusing here costs no affordance.
            if prev.isAttachment { return true }
            let joinAt = prev.plainText as NSString
            var merged = prev
            merged.spans = prev.spans + cur.spans
            blocks[bi - 1] = merged
            blocks.remove(at: bi)
            render(BlockDoc(blocks: blocks), caretBlock: bi - 1, caretWithin: joinAt.length)
            return true
        }

        func toggleChecked(blockID: String) {
            var doc = currentDoc()
            guard let i = doc.blocks.firstIndex(where: { $0.id == blockID }) else { return }
            doc.blocks[i].checked = !(doc.blocks[i].checked ?? false)
            let caret = textView?.selectedRange() ?? NSRange(location: 0, length: 0)
            guard let tv = textView, let storage = tv.textStorage else { return }
            let before = snapshotForUndo()
            isProgrammatic = true
            storage.setAttributedString(BlockBridge.attributedString(from: doc))
            tv.setSelectedRange(NSRange(location: min(caret.location, storage.length), length: 0))
            isProgrammatic = false
            rememberTrailing(doc)
            if let before { registerUndo(restoring: before.doc, caret: before.caret) }
            tv.needsDisplay = true
            save()
        }

        // MARK: Media (images + link cards)

        /// Open a file picker and embed the chosen image.
        func pickImage() {
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.image]
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            if panel.runModal() == .OK, let url = panel.url, let img = NSImage(contentsOf: url) {
                insertImage(img)
            }
        }

        func insertImage(_ image: NSImage) {
            Log.media.info("insertImage: picked \(Int(image.size.width))x\(Int(image.size.height))")
            guard let base64 = NoteImage.encode(image) else {
                Log.media.error("insertImage: NoteImage.encode returned nil — nothing inserted")
                return
            }
            var doc = currentDoc()
            let (bi, _) = locate(textView?.selectedRange().location ?? 0, in: doc)
            Log.media.info("insertImage: base64 \(base64.count) chars, into block \(bi) of \(doc.blocks.count)")
            insertMediaBlock(Block(type: .image, src: base64), after: bi, in: &doc)
            let after = currentDoc()
            let images = after.blocks.filter { $0.type == .image }.count
            Log.media.info("insertImage: after render, storage holds \(images) image block(s), \(after.blocks.count) block(s) total")
        }

        func insertLink(_ url: URL) {
            var doc = currentDoc()
            let (bi, _) = locate(textView?.selectedRange().location ?? 0, in: doc)
            let block = Block(type: .linkCard, url: url.absoluteString,
                              linkDomain: url.host?.replacingOccurrences(of: "www.", with: ""))
            insertMediaBlock(block, after: bi, in: &doc)
            // Fetch title + thumbnail off-thread, then fill the card in by URL.
            let target = url
            Task { [weak self] in
                guard let meta = await LinkMetadata.fetch(target) else { return }
                await MainActor.run { self?.updateLinkCard(url: target.absoluteString, meta: meta) }
            }
        }

        private func insertMediaBlock(_ block: Block, after bi: Int, in doc: inout BlockDoc) {
            var blocks = doc.blocks
            if blocks[bi].type == .paragraph && blocks[bi].plainText.isEmpty {
                blocks[bi] = block                       // replace an empty line
            } else {
                blocks.insert(block, at: bi + 1)
            }
            let mi = blocks.firstIndex(where: { $0.id == block.id }) ?? bi
            // Always leave an editable paragraph after the media so the caret has a home.
            if mi == blocks.count - 1 || blocks[mi + 1].isAttachment {
                blocks.insert(Block.paragraph(), at: mi + 1)
            }
            render(BlockDoc(blocks: blocks), caretBlock: min(mi + 1, blocks.count - 1), caretWithin: 0)
        }

        /// Fill a link card with its fetched title/thumbnail (matched by URL, since
        /// block ids are re-minted on every serialization).
        func updateLinkCard(url: String, meta: LinkMetadata.Result) {
            var doc = currentDoc()
            guard let i = doc.blocks.firstIndex(where: { $0.type == .linkCard && $0.url == url }) else { return }
            doc.blocks[i].linkTitle = meta.title
            if let t = meta.thumbBase64 { doc.blocks[i].linkThumb = t }
            if let d = meta.domain { doc.blocks[i].linkDomain = d }
            guard let tv = textView, let storage = tv.textStorage else { return }
            let before = snapshotForUndo()
            let caret = tv.selectedRange()
            isProgrammatic = true
            storage.setAttributedString(BlockBridge.attributedString(from: doc))
            tv.setSelectedRange(NSRange(location: min(caret.location, storage.length), length: 0))
            isProgrammatic = false
            rememberTrailing(doc)
            if let before { registerUndo(restoring: before.doc, caret: before.caret) }
            tv.needsDisplay = true
            save()
        }

        // MARK: Block markdown  (returns true if it transformed the current block)

        private func applyBlockMarkdown(in tv: BlockTextView) -> Bool {
            guard let storage = tv.textStorage else { return false }
            let ns = storage.string as NSString
            let loc = min(tv.selectedRange().location, ns.length)
            let para = ns.paragraphRange(for: NSRange(location: loc, length: 0))
            let text = ns.substring(with: para)
            let rules: [(String, (inout Block) -> Void)] = [
                ("# ",    { $0.type = .heading; $0.level = 1 }),
                ("## ",   { $0.type = .heading; $0.level = 2 }),
                ("### ",  { $0.type = .heading; $0.level = 3 }),
                ("- ",    { $0.type = .bullet }),
                ("* ",    { $0.type = .bullet }),
                ("[] ",   { $0.type = .todo; $0.checked = false }),
                ("[ ] ",  { $0.type = .todo; $0.checked = false }),
                ("> ",    { $0.type = .quote }),
                ("```",   { $0.type = .code }),
                ("1. ",   { $0.type = .numbered }),
            ]
            for (trigger, apply) in rules {
                // Only fire when the caret is right after the trigger at block start.
                guard text.hasPrefix(trigger), loc == para.location + (trigger as NSString).length else { continue }
                var doc = currentDoc()
                let (bi, _) = locate(para.location, in: doc)
                var block = doc.blocks[bi]
                // strip the trigger from the block's spans
                block.spans = stripPrefix((trigger as NSString).length, from: block.spans)
                apply(&block)
                if block.type == .code, block.plainText == "`" { block.spans = [] } // ``` edge
                doc.blocks[bi] = block
                render(doc, caretBlock: bi, caretWithin: 0)
                return true
            }
            // Divider: "---" or "***" on its own line
            if text == "---" || text == "***" {
                var doc = currentDoc()
                let (bi, _) = locate(para.location, in: doc)
                doc.blocks[bi] = Block(type: .divider)
                doc.blocks.insert(Block.paragraph(), at: bi + 1)
                render(doc, caretBlock: bi + 1, caretWithin: 0)
                return true
            }
            return false
        }

        // MARK: Inline markdown  (**bold** *italic* `code` ~~strike~~)

        private func applyInlineMarkdown(in tv: BlockTextView) {
            guard let storage = tv.textStorage else { return }
            let ns = storage.string as NSString
            let caret = tv.selectedRange().location
            guard caret > 0, caret <= ns.length else { return }
            let para = ns.paragraphRange(for: NSRange(location: caret, length: 0))
            let lastChar = ns.substring(with: NSRange(location: caret - 1, length: 1))

            let patterns: [(marker: String, mark: Mark)] = [
                ("**", .bold), ("`", .code), ("*", .italic), ("~~", .strike),
            ]
            for p in patterns {
                let mk = p.marker as NSString
                guard lastChar == mk.substring(from: mk.length - 1) else { continue }
                let closeStart = caret - mk.length
                guard closeStart >= para.location else { continue }
                guard ns.substring(with: NSRange(location: closeStart, length: mk.length)) == p.marker else { continue }
                // find opening marker before closeStart within the paragraph
                let searchRange = NSRange(location: para.location, length: closeStart - para.location)
                let openRange = ns.range(of: p.marker, options: .backwards, range: searchRange)
                guard openRange.location != NSNotFound else { continue }
                // A '*' that is part of '**' is not an italic marker — otherwise
                // typing **bold** fires italic mid-way and eats the markers.
                if p.mark == .italic {
                    if closeStart > para.location,
                       ns.substring(with: NSRange(location: closeStart - 1, length: 1)) == "*" { continue }
                    if openRange.location > para.location,
                       ns.substring(with: NSRange(location: openRange.location - 1, length: 1)) == "*" { continue }
                }
                let contentStart = openRange.location + mk.length
                let contentEnd = closeStart
                guard contentEnd > contentStart else { continue }
                let contentRange = NSRange(location: contentStart, length: contentEnd - contentStart)
                // Skip if content is only the marker chars (e.g. typing "***")
                let content = ns.substring(with: contentRange)
                if content.allSatisfy({ String($0) == mk.substring(from: mk.length - 1) }) { continue }

                isProgrammatic = true
                storage.beginEditing()
                // remove closing then opening (back to front)
                storage.replaceCharacters(in: NSRange(location: closeStart, length: mk.length), with: "")
                storage.replaceCharacters(in: openRange, with: "")
                let markedRange = NSRange(location: contentStart - mk.length, length: contentRange.length)
                applyMarkAttributes(p.mark, over: markedRange, in: storage)
                storage.endEditing()
                let newCaret = markedRange.location + markedRange.length
                tv.setSelectedRange(NSRange(location: newCaret, length: 0))
                isProgrammatic = false
                // Nothing to invalidate: this edits the existing storage in
                // place rather than replacing it, so the text view's own records
                // stay valid and ⌘Z already walks back through them.
                // reset typing so text after the marked run is unmarked
                syncTypingAttributes(tv)
                clearMarkForTyping(p.mark, tv)
                return
            }
        }

        private func applyMarkAttributes(_ mark: Mark, over range: NSRange, in storage: NSTextStorage) {
            storage.enumerateAttributes(in: range, options: []) { at, r, _ in
                var new = at
                let base = blockMeta(from: at)
                let size = EditorTheme.baseSize(base); let weight = EditorTheme.baseWeight(base)
                var bold = false, italic = false, code = base.type == .code
                if let f = at[.font] as? NSFont {
                    bold = f.fontDescriptor.symbolicTraits.contains(.bold)
                    italic = f.fontDescriptor.symbolicTraits.contains(.italic)
                }
                if at[.inlineCode] as? Bool == true { code = true }
                switch mark {
                case .bold: bold = true
                case .italic: italic = true
                case .code: code = true; new[.inlineCode] = true; new[.foregroundColor] = NSColor(Palette.information)
                case .strike: new[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                case .link: break
                }
                new[.font] = EditorTheme.font(size: size, weight: weight, bold: bold, italic: italic, mono: code)
                storage.setAttributes(new, range: r)
            }
        }

        private func clearMarkForTyping(_ mark: Mark, _ tv: BlockTextView) {
            var a = tv.typingAttributes
            let base = blockMeta(from: a)
            a[.inlineCode] = nil
            a[.strikethroughStyle] = nil
            a[.foregroundColor] = EditorTheme.baseColor(base)
            a[.font] = EditorTheme.font(size: EditorTheme.baseSize(base), weight: EditorTheme.baseWeight(base),
                                        bold: false, italic: false, mono: base.type == .code)
            tv.typingAttributes = a
        }

        // MARK: Inline mark shortcuts (Cmd-B / I / E)

        func toggleMark(_ mark: Mark) {
            guard let tv = textView, let storage = tv.textStorage else { return }
            let sel = tv.selectedRange()
            if sel.length == 0 {
                // toggle for subsequent typing
                var a = tv.typingAttributes
                let base = blockMeta(from: a)
                var bold = false, italic = false, code = base.type == .code, strike = false
                if let f = a[.font] as? NSFont {
                    bold = f.fontDescriptor.symbolicTraits.contains(.bold)
                    italic = f.fontDescriptor.symbolicTraits.contains(.italic)
                }
                if a[.inlineCode] as? Bool == true { code = true }
                if a[.strikethroughStyle] != nil { strike = true }
                switch mark {
                case .bold: bold.toggle()
                case .italic: italic.toggle()
                case .code: code.toggle(); a[.inlineCode] = code ? true : nil
                    a[.foregroundColor] = code ? NSColor(Palette.information) : EditorTheme.baseColor(base)
                case .strike: strike.toggle(); a[.strikethroughStyle] = strike ? NSUnderlineStyle.single.rawValue : nil
                case .link: break
                }
                a[.font] = EditorTheme.font(size: EditorTheme.baseSize(base), weight: EditorTheme.baseWeight(base),
                                            bold: bold, italic: italic, mono: code)
                tv.typingAttributes = a
                return
            }
            // Determine whether the whole selection already has the mark → then remove.
            var allHave = true
            storage.enumerateAttributes(in: sel, options: []) { at, _, _ in
                if !hasMark(mark, at) { allHave = false }
            }
            isProgrammatic = true
            storage.beginEditing()
            storage.enumerateAttributes(in: sel, options: []) { at, r, _ in
                var new = at
                let base = blockMeta(from: at)
                var bold = false, italic = false, code = base.type == .code
                if let f = at[.font] as? NSFont {
                    bold = f.fontDescriptor.symbolicTraits.contains(.bold)
                    italic = f.fontDescriptor.symbolicTraits.contains(.italic)
                }
                if at[.inlineCode] as? Bool == true { code = true }
                let want = !allHave
                switch mark {
                case .bold: bold = want
                case .italic: italic = want
                case .code: code = want; new[.inlineCode] = want ? true : nil
                    new[.foregroundColor] = want ? NSColor(Palette.information) : EditorTheme.baseColor(base)
                case .strike: new[.strikethroughStyle] = want ? NSUnderlineStyle.single.rawValue : nil
                case .link: break
                }
                new[.font] = EditorTheme.font(size: EditorTheme.baseSize(base), weight: EditorTheme.baseWeight(base),
                                              bold: bold, italic: italic, mono: code)
                storage.setAttributes(new, range: r)
            }
            storage.endEditing()
            isProgrammatic = false
            tv.needsDisplay = true
            save()
        }

        // MARK: Slash menu

        func slashTyped() {
            guard let tv = textView else { return }
            slash.begin(anchor: tv.caretRectOnScreen(), host: tv) { [weak self] cmd in
                self?.applySlash(cmd)
            }
        }
        private func updateSlashQuery(_ tv: BlockTextView) {
            guard let storage = tv.textStorage else { return }
            let ns = storage.string as NSString
            let caret = tv.selectedRange().location
            guard let start = slash.triggerLocation, caret >= start, start <= ns.length else { dismissSlash(); return }
            let q = ns.substring(with: NSRange(location: start, length: min(caret, ns.length) - start))
            if q.contains(" ") || q.contains("\n") { dismissSlash(); return }
            slash.updateQuery(q, anchor: tv.caretRectOnScreen())
        }
        func moveSlash(_ delta: Int) { slash.move(delta) }
        func commitSlash() { slash.commitSelection() }
        func dismissSlash() { slash.dismiss() }

        private func applySlash(_ cmd: SlashCommand) {
            guard let tv = textView, let storage = tv.textStorage, let start = slash.triggerLocation else { return }
            let caret = tv.selectedRange().location
            // remove the "/query" text
            let removeLen = max(0, min(caret, storage.length) - (start - 1))
            let removeRange = NSRange(location: max(0, start - 1), length: removeLen)
            isProgrammatic = true
            storage.replaceCharacters(in: removeRange, with: "")
            tv.setSelectedRange(NSRange(location: removeRange.location, length: 0))
            isProgrammatic = false

            // Image is not a text transform — it opens a picker and embeds media.
            if cmd.type == .image {
                dismissSlash()
                save()
                pickImage()
                return
            }

            var doc = currentDoc()
            let (bi, _) = locate(tv.selectedRange().location, in: doc)
            if cmd.type == .divider {
                doc.blocks[bi] = Block(type: .divider)
                doc.blocks.insert(Block.paragraph(), at: bi + 1)
                render(doc, caretBlock: bi + 1, caretWithin: 0)
            } else {
                var b = doc.blocks[bi]
                b.type = cmd.type
                b.level = cmd.level
                b.checked = cmd.type == .todo ? false : nil
                doc.blocks[bi] = b
                render(doc, caretBlock: bi, caretWithin: (b.plainText as NSString).length)
            }
            dismissSlash()
        }

        // MARK: - char-offset helpers

        /// A block's length in the attributed string: dividers are invisible (0),
        /// media blocks are a single attachment char (1), text blocks their UTF-16 length.
        private func blockLen(_ b: Block) -> Int {
            if b.type == .divider { return 0 }
            if b.isAttachment { return 1 }
            return (b.plainText as NSString).length
        }

        func locate(_ caret: Int, in doc: BlockDoc) -> (Int, Int) {
            var off = 0
            for (i, b) in doc.blocks.enumerated() {
                let len = blockLen(b)
                if caret <= off + len { return (i, caret - off) }
                off += len + 1
            }
            let last = max(0, doc.blocks.count - 1)
            return (last, blockLen(doc.blocks[last]))
        }
        func offset(block bi: Int, within w: Int, in doc: BlockDoc) -> Int {
            var off = 0
            for i in 0..<max(0, min(bi, doc.blocks.count)) {
                off += blockLen(doc.blocks[i]) + 1
            }
            return off + w
        }
    }
}

// MARK: - free helpers

private func hasMark(_ mark: Mark, _ at: [NSAttributedString.Key: Any]) -> Bool {
    switch mark {
    case .bold: return (at[.font] as? NSFont)?.fontDescriptor.symbolicTraits.contains(.bold) ?? false
    case .italic: return (at[.font] as? NSFont)?.fontDescriptor.symbolicTraits.contains(.italic) ?? false
    case .code: return at[.inlineCode] as? Bool ?? false
    case .strike: return at[.strikethroughStyle] != nil
    case .link: return at[.link] != nil
    }
}

/// Split a span list at UTF-16 offset `w`.
private func splitSpans(_ spans: [TextSpan], at w: Int) -> ([TextSpan], [TextSpan]) {
    var left: [TextSpan] = [], right: [TextSpan] = []
    var consumed = 0
    for span in spans {
        let len = (span.text as NSString).length
        if consumed + len <= w {
            left.append(span); consumed += len
        } else if consumed >= w {
            right.append(span)
        } else {
            let cut = w - consumed
            let ns = span.text as NSString
            left.append(TextSpan(text: ns.substring(to: cut), marks: span.marks))
            right.append(TextSpan(text: ns.substring(from: cut), marks: span.marks))
            consumed += len
        }
    }
    return (left, right)
}

/// Remove the first `n` UTF-16 chars from a span list.
private func stripPrefix(_ n: Int, from spans: [TextSpan]) -> [TextSpan] {
    var remaining = n
    var out: [TextSpan] = []
    for span in spans {
        if remaining <= 0 { out.append(span); continue }
        let ns = span.text as NSString
        if ns.length <= remaining { remaining -= ns.length; continue }
        out.append(TextSpan(text: ns.substring(from: remaining), marks: span.marks))
        remaining = 0
    }
    return out
}
