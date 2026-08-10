import Foundation

// A note's rich content: an ordered list of typed blocks — the native answer to
// a Notion/TipTap document. This is the on-disk shape (JSON inside a note's
// `content`). It maps conceptually 1:1 to ProseMirror nodes so an embed path
// stays open later, but on disk we keep a flat, self-describing block list.

enum BlockType: String, Codable, Hashable {
    case paragraph, heading, bullet, numbered, todo, quote, code, divider
    // Rich media — rendered as a single NSTextAttachment in the editor.
    case image        // an embedded picture (base64 in `src`)
    case linkCard     // a pasted URL, shown as a preview card (thumbnail + title)
}

// Inline formatting applied to a run of text within a block.
enum Mark: Codable, Hashable {
    case bold, italic, code, strike
    case link(String)

    private enum CodingKeys: String, CodingKey { case t, href }
    private enum Kind: String, Codable { case bold, italic, code, strike, link }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .t) {
        case .bold:   self = .bold
        case .italic: self = .italic
        case .code:   self = .code
        case .strike: self = .strike
        case .link:   self = .link(try c.decodeIfPresent(String.self, forKey: .href) ?? "")
        }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .bold:            try c.encode(Kind.bold, forKey: .t)
        case .italic:          try c.encode(Kind.italic, forKey: .t)
        case .code:            try c.encode(Kind.code, forKey: .t)
        case .strike:          try c.encode(Kind.strike, forKey: .t)
        case .link(let href):  try c.encode(Kind.link, forKey: .t); try c.encode(href, forKey: .href)
        }
    }
}

// A run of text sharing the same set of marks.
struct TextSpan: Codable, Hashable {
    var text: String
    var marks: [Mark] = []
}

struct Block: Codable, Hashable, Identifiable {
    var id: String
    var type: BlockType
    var spans: [TextSpan] = []
    var checked: Bool? = nil     // todo
    var level: Int? = nil        // heading: 1...3
    var language: String? = nil  // code
    // Rich media
    var src: String? = nil       // image: base64 (no data: prefix)
    var url: String? = nil       // linkCard: the link
    var linkTitle: String? = nil // linkCard: fetched page/video title
    var linkThumb: String? = nil // linkCard: fetched thumbnail, base64
    var linkDomain: String? = nil// linkCard: host, for the card footer

    enum CodingKeys: String, CodingKey {
        case id, type, spans, checked, level, language, src, url, linkTitle, linkThumb, linkDomain
    }

    init(id: String = Block.newID(), type: BlockType, spans: [TextSpan] = [],
         checked: Bool? = nil, level: Int? = nil, language: String? = nil,
         src: String? = nil, url: String? = nil, linkTitle: String? = nil,
         linkThumb: String? = nil, linkDomain: String? = nil) {
        self.id = id; self.type = type; self.spans = spans
        self.checked = checked; self.level = level; self.language = language
        self.src = src; self.url = url; self.linkTitle = linkTitle
        self.linkThumb = linkThumb; self.linkDomain = linkDomain
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id         = try c.decodeIfPresent(String.self, forKey: .id) ?? Block.newID()
        type       = try c.decode(BlockType.self, forKey: .type)
        spans      = try c.decodeIfPresent([TextSpan].self, forKey: .spans) ?? []
        checked    = try c.decodeIfPresent(Bool.self, forKey: .checked)
        level      = try c.decodeIfPresent(Int.self, forKey: .level)
        language   = try c.decodeIfPresent(String.self, forKey: .language)
        src        = try c.decodeIfPresent(String.self, forKey: .src)
        url        = try c.decodeIfPresent(String.self, forKey: .url)
        linkTitle  = try c.decodeIfPresent(String.self, forKey: .linkTitle)
        linkThumb  = try c.decodeIfPresent(String.self, forKey: .linkThumb)
        linkDomain = try c.decodeIfPresent(String.self, forKey: .linkDomain)
    }

    /// Rendered as a single attachment character in the editor (occupies its own
    /// line, no editable text). The caret math treats these as length 1.
    var isAttachment: Bool { type == .image || type == .linkCard }

    var plainText: String {
        // Link cards mirror their URL into the plain-text body so search + previews
        // still find them; images contribute nothing.
        if type == .linkCard { return url ?? spans.map(\.text).joined() }
        return spans.map(\.text).joined()
    }
    var isEmpty: Bool { type != .divider && !isAttachment && plainText.isEmpty }

    static func newID() -> String { String(UUID().uuidString.prefix(8)).lowercased() }
    static func paragraph(_ text: String = "") -> Block {
        Block(type: .paragraph, spans: text.isEmpty ? [] : [TextSpan(text: text)])
    }
}

struct BlockDoc: Codable, Hashable {
    var blocks: [Block]

    init(blocks: [Block] = [Block.paragraph()]) {
        self.blocks = blocks.isEmpty ? [Block.paragraph()] : blocks
    }

    // Custom decode so a synced `{"blocks":[]}` (any client, any version) can
    // never reach the editor as an empty document — `locate()` indexes blocks[0].
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let decoded = try c.decodeIfPresent([Block].self, forKey: .blocks) ?? []
        blocks = decoded.isEmpty ? [Block.paragraph()] : decoded
    }

    /// Flattened plain text — the mirror used for search, list previews, and the
    /// AI quick-log. Dividers render as a rule glyph so previews read cleanly.
    var plainText: String {
        blocks.map { $0.type == .divider ? "———" : $0.plainText }
            .joined(separator: "\n")
    }

    var isEffectivelyEmpty: Bool {
        blocks.allSatisfy { $0.type == .paragraph && $0.plainText.isEmpty }
    }

    /// Migrate a legacy plain-text body into blocks: each line becomes a
    /// paragraph. Lossless and reversible via `plainText`.
    static func from(plainText text: String) -> BlockDoc {
        let trimmed = text.replacingOccurrences(of: "\r\n", with: "\n")
        guard !trimmed.isEmpty else { return BlockDoc() }
        let blocks = trimmed.components(separatedBy: "\n").map { Block.paragraph($0) }
        return BlockDoc(blocks: blocks)
    }
}
