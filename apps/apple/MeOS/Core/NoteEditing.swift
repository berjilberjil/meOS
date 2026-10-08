import Foundation

/// The rules a note editor follows: what Return does, what a tick does, what
/// changing a line's type keeps and what it throws away.
///
/// Pure, and deliberately so. The phone's editor is a stack of text fields, and
/// a stack of text fields is very easy to make *look* like Apple Notes and very
/// hard to make *behave* like it — Return has to continue a checklist, an empty
/// item has to end one, a heading must not breed more headings. None of that is
/// visible in a screenshot, so all of it is pinned by tests here and the view is
/// left with nothing to decide.
///
/// The Mac has its own editor (`Views/BlockEditor`, AppKit/TextKit) which owns
/// these rules in its own terms. This is the phone's copy of the rules, over the
/// same `BlockDoc`, so a note edited on either device stays the same note.
enum NoteEditing {

    /// Types that continue themselves when you press Return.
    static func isList(_ type: BlockType) -> Bool {
        type == .bullet || type == .numbered || type == .todo
    }

    // MARK: - Return

    struct SplitResult {
        var blocks: [Block]
        /// Where the caret should land. nil when nothing happened.
        var focus: String?
    }

    /// Press Return with `head` before the caret and `tail` after it.
    static func split(_ blocks: [Block], at id: String, head: String, tail: String) -> SplitResult {
        guard let i = blocks.firstIndex(where: { $0.id == id }) else {
            return SplitResult(blocks: blocks, focus: nil)
        }
        var out = blocks
        let type = out[i].type

        // Return on an item with nothing in it ends the list rather than making
        // another one. Without this the only way out of a checklist is a menu,
        // which is why lists in lesser editors never end.
        if isList(type), head.isEmpty, tail.isEmpty {
            out[i] = retyped(out[i], to: .paragraph)
            return SplitResult(blocks: out, focus: out[i].id)
        }

        out = setText(head, in: out, id: id)

        // A list carries on; everything else drops to body text. Nobody has
        // ever wanted a second title under the first one.
        let nextType: BlockType = isList(type) ? type : .paragraph

        // The tail is split on every newline, not just the one that triggered
        // this. A single Return has no others and so makes exactly one line —
        // but a paste arrives as one insertion carrying all of them, and one
        // block holding four newlines is a run-on paragraph the moment the Mac
        // opens it.
        let lines = tail.components(separatedBy: "\n")
        let inserted: [Block] = lines.map { line in
            var b = Block(type: nextType)
            b.spans = line.isEmpty ? [] : [TextSpan(text: line)]
            if nextType == .todo { b.checked = false }   // a fresh item is not already done
            return b
        }

        out.insert(contentsOf: inserted, at: i + 1)
        return SplitResult(blocks: out, focus: inserted.last?.id)
    }

    // MARK: - Typing

    /// Replace a line's text, keeping the formatting it already carried.
    ///
    /// This is the whole reason the phone stopped destroying Mac notes. The old
    /// path wrote the body as plain text and rebuilt the document from it, so
    /// every heading, bullet and checkbox came back as a paragraph.
    static func setText(_ text: String, in blocks: [Block], id: String) -> [Block] {
        guard let i = blocks.firstIndex(where: { $0.id == id }) else { return blocks }
        var out = blocks
        let marks = out[i].spans.first?.marks ?? []
        // An empty line with no formatting holds no spans at all — but an empty
        // line you have just pressed Bold on has to keep that, or the mark is
        // gone before you have typed the word you wanted bold.
        out[i].spans = (text.isEmpty && marks.isEmpty) ? [] : [TextSpan(text: text, marks: marks)]
        return out
    }

    /// Turn a mark on or off across a whole line.
    ///
    /// A whole line, not a selection: SwiftUI's `TextField` does not hand out
    /// the caret's range, so per-run formatting is not something the phone can
    /// honestly offer. Line-level is what it can do, and it is a great deal more
    /// than the placeholder button that did nothing.
    static func toggleMark(_ blocks: [Block], id: String, mark: Mark) -> [Block] {
        guard let i = blocks.firstIndex(where: { $0.id == id }) else { return blocks }
        var out = blocks
        let text = out[i].spans.map(\.text).joined()
        var marks = out[i].spans.first?.marks ?? []
        if let at = marks.firstIndex(of: mark) { marks.remove(at: at) } else { marks.append(mark) }
        out[i].spans = [TextSpan(text: text, marks: marks)]
        return out
    }

    // MARK: - Ticking

    static func toggleChecked(_ blocks: [Block], id: String) -> [Block] {
        guard let i = blocks.firstIndex(where: { $0.id == id }), blocks[i].type == .todo else {
            return blocks
        }
        var out = blocks
        out[i].checked = !(out[i].checked ?? false)
        return out
    }

    // MARK: - Changing a line's type

    static func convert(_ blocks: [Block], id: String, to type: BlockType, level: Int? = nil) -> [Block] {
        guard let i = blocks.firstIndex(where: { $0.id == id }) else { return blocks }
        var out = blocks
        out[i] = retyped(out[i], to: type, level: level)
        return out
    }

    /// Change what a line *is* without touching what it says.
    private static func retyped(_ block: Block, to type: BlockType, level: Int? = nil) -> Block {
        var b = block
        b.type = type
        b.checked = type == .todo ? (block.checked ?? false) : nil
        b.level = type == .heading ? (level ?? block.level ?? 1) : nil
        return b
    }

    // MARK: - Numbering

    /// The number to draw beside each numbered line.
    ///
    /// Computed rather than stored, and restarted by anything that is not a
    /// numbered line — two lists with a sentence between them are two lists,
    /// not one that counts to five.
    static func ordinals(_ blocks: [Block]) -> [String: Int] {
        var out: [String: Int] = [:]
        var n = 0
        for b in blocks {
            if b.type == .numbered {
                n += 1
                out[b.id] = n
            } else {
                n = 0
            }
        }
        return out
    }

    // MARK: - Find

    /// Ids of the lines containing `query`, in document order. Blank queries
    /// match nothing — matching everything is not a search result, it is noise.
    static func matches(_ blocks: [Block], query: String) -> [String] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        return blocks.filter { $0.plainText.lowercased().contains(q) }.map(\.id)
    }

    // MARK: - Structure

    /// Put a block in after `id` (or at the end), leaving somewhere to keep
    /// typing when what went in cannot hold a caret.
    static func insert(_ block: Block, into blocks: [Block], after id: String?) -> [Block] {
        var out = blocks
        let at = id.flatMap { key in out.firstIndex { $0.id == key } }.map { $0 + 1 } ?? out.count
        out.insert(block, at: at)
        if block.isAttachment {
            out.insert(Block.paragraph(), at: at + 1)
        }
        return out
    }

    /// A document always has somewhere to type.
    ///
    /// An empty `blocks` array, or one holding only a photo, leaves the editor
    /// with no text field at all — a note you cannot write in.
    static func normalized(_ blocks: [Block]) -> [Block] {
        guard !blocks.isEmpty else { return [Block.paragraph()] }
        if blocks.allSatisfy(\.isAttachment) { return blocks + [Block.paragraph()] }
        return blocks
    }
}
