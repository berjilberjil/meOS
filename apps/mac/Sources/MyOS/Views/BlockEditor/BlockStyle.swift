import AppKit
import SwiftUI

// Bridges the pure BlockDoc model to a styled NSAttributedString (the live model
// the NSTextView edits) and back. Also owns the editor's dark visual language.

extension NSAttributedString.Key {
    static let blockType    = NSAttributedString.Key("myBlockType")     // BlockType.rawValue
    static let blockID      = NSAttributedString.Key("myBlockID")       // String
    static let headingLevel = NSAttributedString.Key("myHeadingLevel")  // Int
    static let todoChecked  = NSAttributedString.Key("myTodoChecked")   // Bool
    static let codeLanguage = NSAttributedString.Key("myCodeLanguage")  // String
    static let inlineCode   = NSAttributedString.Key("myInlineCode")    // Bool (code mark)
    // Rich-media metadata carried on the attachment character.
    static let blockImageSrc  = NSAttributedString.Key("myBlockImageSrc")  // String (base64)
    static let blockLinkURL   = NSAttributedString.Key("myBlockLinkURL")   // String
    static let blockLinkTitle = NSAttributedString.Key("myBlockLinkTitle") // String
    static let blockLinkThumb = NSAttributedString.Key("myBlockLinkThumb") // String (base64)
    static let blockLinkDomain = NSAttributedString.Key("myBlockLinkDomain")// String
}

enum EditorMetrics {
    static let listGutter: CGFloat  = 26   // bullet / number / checkbox indent
    static let quoteGutter: CGFloat = 18
    static let codeGutter: CGFloat  = 12
    static let checkboxSize: CGFloat = 16
}

enum EditorTheme {
    // Computed, not stored. `NSColor(_ color:)` snapshots whatever `Palette`
    // held at the moment it ran, so a `static let` here would pin the editor to
    // the colour the app launched with — and the whole point of the appearance
    // settings is that a new colour lands everywhere at once.
    static var text: NSColor     { NSColor(Palette.text) }
    static var muted: NSColor    { NSColor(Palette.muted) }
    static var faint: NSColor    { NSColor(Palette.faint) }
    static var brand: NSColor    { NSColor(Palette.action) }
    static var green: NSColor    { NSColor(Palette.green) }
    static var blue: NSColor     { NSColor(Palette.blue) }
    static var surface2: NSColor { NSColor(Palette.surfaceElevated) }
    static let border   = NSColor(white: 1, alpha: 0.09)

    // Base (block-level) size/weight/color before inline marks.
    static func baseSize(_ b: Block) -> CGFloat {
        switch b.type {
        case .heading: switch b.level ?? 1 { case 1: return 27; case 2: return 21; default: return 17 }
        case .code:    return 13.5
        case .quote:   return 16
        default:       return 15
        }
    }
    static func baseWeight(_ b: Block) -> NSFont.Weight {
        switch b.type {
        case .heading: return (b.level ?? 1) <= 2 ? .bold : .semibold
        default:       return .regular
        }
    }
    static func baseColor(_ b: Block) -> NSColor {
        switch b.type {
        case .quote: return muted
        default:     return text
        }
    }

    static func font(size: CGFloat, weight: NSFont.Weight, bold: Bool, italic: Bool, mono: Bool) -> NSFont {
        var f: NSFont
        if mono {
            f = NSFont.monospacedSystemFont(ofSize: size - 0.5, weight: bold ? .semibold : .regular)
        } else {
            f = NSFont.systemFont(ofSize: size, weight: bold ? .bold : weight)
        }
        if italic {
            let d = f.fontDescriptor.withSymbolicTraits(.italic)
            if let fi = NSFont(descriptor: d, size: size) { f = fi }
        }
        return f
    }

    static func paragraphStyle(for b: Block) -> NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = 3
        p.paragraphSpacing = 6
        switch b.type {
        case .heading:
            p.paragraphSpacingBefore = 10
            p.paragraphSpacing = 4
        case .bullet, .numbered, .todo:
            p.firstLineHeadIndent = EditorMetrics.listGutter
            p.headIndent = EditorMetrics.listGutter
            p.paragraphSpacing = 3
        case .quote:
            p.firstLineHeadIndent = EditorMetrics.quoteGutter
            p.headIndent = EditorMetrics.quoteGutter
        case .code:
            p.firstLineHeadIndent = EditorMetrics.codeGutter
            p.headIndent = EditorMetrics.codeGutter
            p.paragraphSpacing = 0
            p.lineSpacing = 2
        default: break
        }
        return p
    }

    /// Block-level attributes (paragraph style + block metadata + default char attrs).
    static func baseAttributes(for b: Block) -> [NSAttributedString.Key: Any] {
        var a: [NSAttributedString.Key: Any] = [
            .paragraphStyle: paragraphStyle(for: b),
            .font: font(size: baseSize(b), weight: baseWeight(b), bold: false, italic: false, mono: b.type == .code),
            .foregroundColor: baseColor(b),
            .blockType: b.type.rawValue,
            .blockID: b.id,
        ]
        if let l = b.level { a[.headingLevel] = l }
        if let c = b.checked { a[.todoChecked] = c }
        if let lang = b.language { a[.codeLanguage] = lang }
        return a
    }

    /// Full attributes for one inline span inside a block (base + marks).
    static func attributes(for span: TextSpan, in b: Block) -> [NSAttributedString.Key: Any] {
        var a = baseAttributes(for: b)
        var bold = false, italic = false, code = b.type == .code, strike = false
        var link: String? = nil
        for m in span.marks {
            switch m {
            case .bold: bold = true
            case .italic: italic = true
            case .code: code = true
            case .strike: strike = true
            case .link(let href): link = href
            }
        }
        a[.font] = font(size: baseSize(b), weight: baseWeight(b), bold: bold, italic: italic, mono: code)
        if code && b.type != .code {
            a[.inlineCode] = true
            a[.foregroundColor] = NSColor(Palette.information)
        }
        if strike { a[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        if let href = link {
            a[.foregroundColor] = blue
            a[.underlineStyle] = NSUnderlineStyle.single.rawValue
            if let url = URL(string: href) { a[.link] = url }
        }
        return a
    }
}

// MARK: - Conversion

enum BlockBridge {

    /// Build the editable attributed string for a document. One paragraph per block,
    /// joined by newlines; every char (incl. the trailing separator) carries block metadata.
    static func attributedString(from doc: BlockDoc) -> NSAttributedString {
        let out = NSMutableAttributedString()
        for (i, block) in doc.blocks.enumerated() {
            let base = EditorTheme.baseAttributes(for: block)
            let start = out.length
            if block.isAttachment {
                out.append(attachment(for: block))
            } else if block.type != .divider {
                if block.spans.isEmpty {
                    // empty paragraph — nothing to append; separator carries attrs
                } else {
                    for span in block.spans {
                        out.append(NSAttributedString(string: span.text,
                                                      attributes: EditorTheme.attributes(for: span, in: block)))
                    }
                }
            }
            // ensure block metadata spans the block text (inline attrs already include it)
            if out.length > start && !block.isAttachment {
                out.addAttributes([
                    .blockType: block.type.rawValue,
                    .blockID: block.id,
                ], range: NSRange(location: start, length: out.length - start))
            }
            if i < doc.blocks.count - 1 {
                out.append(NSAttributedString(string: "\n", attributes: base))
            }
        }
        if out.length == 0 {
            out.append(NSAttributedString(string: "", attributes: EditorTheme.baseAttributes(for: Block.paragraph())))
        }
        return out
    }

    /// One attachment character carrying a media block's data + a rendered image.
    static func attachment(for block: Block) -> NSAttributedString {
        let att = NSTextAttachment()
        switch block.type {
        case .image:
            if let s = block.src, let data = Data(base64Encoded: s), let img = NSImage(data: data) {
                att.image = img
                let maxW: CGFloat = 560
                let nat = img.size
                let w = nat.width > 0 ? min(nat.width, maxW) : maxW
                let h = nat.width > 0 ? w * nat.height / nat.width : 300
                att.bounds = NSRect(x: 0, y: 0, width: w, height: h)
            } else {
                att.bounds = NSRect(x: 0, y: 0, width: 320, height: 180)
            }
        case .linkCard:
            let img = LinkCardRenderer.render(block)
            att.image = img
            att.bounds = NSRect(origin: .zero, size: img.size)
        default:
            break
        }
        let s = NSMutableAttributedString(attachment: att)
        s.addAttributes(mediaAttrs(block), range: NSRange(location: 0, length: s.length))
        return s
    }

    private static func mediaAttrs(_ block: Block) -> [NSAttributedString.Key: Any] {
        var a: [NSAttributedString.Key: Any] = [
            .blockType: block.type.rawValue,
            .blockID: block.id,
            .paragraphStyle: EditorTheme.paragraphStyle(for: block),
        ]
        if let v = block.src { a[.blockImageSrc] = v }
        if let v = block.url { a[.blockLinkURL] = v }
        if let v = block.linkTitle { a[.blockLinkTitle] = v }
        if let v = block.linkThumb { a[.blockLinkThumb] = v }
        if let v = block.linkDomain { a[.blockLinkDomain] = v }
        return a
    }

    /// Serialize the edited attributed string back into a BlockDoc.
    static func blockDoc(from attr: NSAttributedString) -> BlockDoc {
        let ns = attr.string as NSString
        var blocks: [Block] = []
        var idx = 0
        let full = NSRange(location: 0, length: ns.length)
        ns.enumerateSubstrings(in: full, options: .byParagraphs) { _, subRange, _, _ in
            let readAt = subRange.length > 0 ? subRange.location : min(subRange.location, ns.length - 1)
            var at: [NSAttributedString.Key: Any] = [:]
            if readAt >= 0 && readAt < attr.length {
                at = attr.attributes(at: readAt, effectiveRange: nil)
            }
            let typeRaw = (at[.blockType] as? String) ?? BlockType.paragraph.rawValue
            let type = BlockType(rawValue: typeRaw) ?? .paragraph
            idx += 1
            if type == .divider {
                blocks.append(Block(type: .divider))
                return
            }
            if type == .image || type == .linkCard {
                blocks.append(Block(id: at[.blockID] as? String ?? Block.newID(), type: type,
                                    src: at[.blockImageSrc] as? String,
                                    url: at[.blockLinkURL] as? String,
                                    linkTitle: at[.blockLinkTitle] as? String,
                                    linkThumb: at[.blockLinkThumb] as? String,
                                    linkDomain: at[.blockLinkDomain] as? String))
                return
            }
            let level = at[.headingLevel] as? Int
            let checked = at[.todoChecked] as? Bool
            let language = at[.codeLanguage] as? String
            let spans = subRange.length > 0 ? Self.spans(in: attr, range: subRange) : []
            // Carry the id through, exactly as the media branch above does.
            // Minting a fresh one per serialization meant every block's identity
            // changed on every save — so `toggleChecked`, which looks the block
            // up by the id it read from the text storage, never found a match
            // and silently returned. Checkboxes in notes could not be ticked by
            // clicking at all.
            blocks.append(Block(id: at[.blockID] as? String ?? Block.newID(),
                                type: type, spans: spans,
                                checked: type == .todo ? (checked ?? false) : nil,
                                level: type == .heading ? (level ?? 1) : nil,
                                language: type == .code ? language : nil))
        }
        // A trailing newline means an empty last block that byParagraphs never
        // visits — restore it so trailing blank lines survive the round-trip
        // (and so Enter-at-end / caret math see the block the user is on).
        if ns.length > 0, ns.hasSuffix("\n") { blocks.append(Block.paragraph()) }
        if blocks.isEmpty { blocks = [Block.paragraph()] }
        return BlockDoc(blocks: blocks)
    }

    /// The spans in `range` that are not the attachment character itself.
    ///
    /// Rescues text that ended up sharing a paragraph with an image or a link
    /// card — something the block model cannot represent as a single block.
    private static func textOutsideAttachments(in attr: NSAttributedString,
                                               range: NSRange) -> [TextSpan] {
        guard range.length > 0 else { return [] }
        let ns = attr.string as NSString
        let object = unichar(0xFFFC)
        let kept = NSMutableAttributedString()
        for i in 0..<range.length {
            let at = range.location + i
            guard at < ns.length, ns.character(at: at) != object else { continue }
            kept.append(attr.attributedSubstring(from: NSRange(location: at, length: 1)))
        }
        guard kept.length > 0 else { return [] }
        return spans(in: kept, range: NSRange(location: 0, length: kept.length))
    }

    private static func spans(in attr: NSAttributedString, range: NSRange) -> [TextSpan] {
        var spans: [TextSpan] = []
        attr.enumerateAttributes(in: range, options: []) { at, r, _ in
            let text = (attr.string as NSString).substring(with: r)
            guard !text.isEmpty else { return }
            var marks: [Mark] = []
            if let f = at[.font] as? NSFont {
                let traits = f.fontDescriptor.symbolicTraits
                if traits.contains(.bold) { marks.append(.bold) }
                if traits.contains(.italic) { marks.append(.italic) }
            }
            if at[.inlineCode] as? Bool == true { marks.append(.code) }
            if at[.strikethroughStyle] != nil { marks.append(.strike) }
            if let url = at[.link] as? URL { marks.append(.link(url.absoluteString)) }
            // merge with previous span if identical marks
            if var last = spans.last, last.marks == marks {
                last.text += text
                spans[spans.count - 1] = last
            } else {
                spans.append(TextSpan(text: text, marks: marks))
            }
        }
        return spans
    }
}
