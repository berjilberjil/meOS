import XCTest
@testable import meOS

final class BlockDocTests: XCTestCase {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func testEmptyBlocksNeverReachTheEditor() throws {
        let json = """
        {"blocks":[]}
        """
        let doc = try decoder.decode(BlockDoc.self, from: Data(json.utf8))
        XCTAssertEqual(doc.blocks.count, 1, "an empty blocks array must seed a paragraph")
        XCTAssertEqual(doc.blocks.first?.type, .paragraph)
        XCTAssertEqual(doc.blocks.first?.plainText, "")
    }

    func testMissingBlocksKeySeedsParagraph() throws {
        let doc = try decoder.decode(BlockDoc.self, from: Data("{}".utf8))
        XCTAssertEqual(doc.blocks.count, 1)
    }

    func testRoundTripPreservesBlocks() throws {
        let doc = BlockDoc(blocks: [
            Block(type: .heading, spans: [TextSpan(text: "My note")], level: 2),
            Block(type: .bullet, spans: [TextSpan(text: "First item")]),
            Block(type: .divider),
            Block(type: .paragraph),
        ])
        let data = try encoder.encode(doc)
        let decoded = try decoder.decode(BlockDoc.self, from: data)
        XCTAssertEqual(decoded, doc)
    }

    func testImageAndLinkBlocksRoundTrip() throws {
        let doc = BlockDoc(blocks: [
            Block(type: .paragraph, spans: [TextSpan(text: "before")]),
            Block(type: .image, src: "AAECAwQF"),
            Block(type: .linkCard, url: "https://youtu.be/8UX0j2ieqTo",
                  linkTitle: "A video", linkThumb: "Zm9vYmFy", linkDomain: "youtube.com"),
            Block(type: .paragraph, spans: [TextSpan(text: "after")]),
        ])
        let decoded = try decoder.decode(BlockDoc.self, from: try encoder.encode(doc))
        XCTAssertEqual(decoded, doc, "image + link blocks must survive a full round trip")
        XCTAssertEqual(decoded.blocks[1].src, "AAECAwQF")
        XCTAssertEqual(decoded.blocks[2].url, "https://youtu.be/8UX0j2ieqTo")
        XCTAssertEqual(decoded.blocks[2].linkThumb, "Zm9vYmFy")
        XCTAssertTrue(decoded.blocks[1].isAttachment)
        XCTAssertFalse(doc.isEffectivelyEmpty, "a note with only media is not empty")
    }

    func testBlockBridgeMediaRoundTrip() {
        // The editor's own attributed-string <-> BlockDoc path must preserve media
        // blocks and the text around them (this is where note data could be lost).
        let doc = BlockDoc(blocks: [
            Block(type: .paragraph, spans: [TextSpan(text: "before")]),
            Block(type: .image, src: "AAECAwQF"),
            Block(type: .linkCard, url: "https://youtu.be/abc123",
                  linkTitle: "A title", linkThumb: "Zm9v", linkDomain: "youtube.com"),
            Block(type: .paragraph, spans: [TextSpan(text: "after")]),
        ])
        let back = BlockBridge.blockDoc(from: BlockBridge.attributedString(from: doc))
        XCTAssertEqual(back.blocks.map(\.type), [.paragraph, .image, .linkCard, .paragraph])
        XCTAssertEqual(back.blocks[0].plainText, "before")
        XCTAssertEqual(back.blocks[1].src, "AAECAwQF")
        XCTAssertEqual(back.blocks[2].url, "https://youtu.be/abc123")
        XCTAssertEqual(back.blocks[2].linkTitle, "A title")
        XCTAssertEqual(back.blocks[2].linkThumb, "Zm9v")
        XCTAssertEqual(back.blocks[2].linkDomain, "youtube.com")
        XCTAssertEqual(back.blocks[3].plainText, "after")
    }

    func testYouTubeIDParsing() {
        func id(_ s: String) -> String? { LinkMetadata.youTubeID(URL(string: s)!) }
        XCTAssertEqual(id("https://www.youtube.com/watch?v=8UX0j2ieqTo"), "8UX0j2ieqTo")
        XCTAssertEqual(id("https://youtu.be/8UX0j2ieqTo"), "8UX0j2ieqTo")
        XCTAssertEqual(id("https://www.youtube.com/shorts/abc123"), "abc123")
        XCTAssertNil(id("https://example.com/watch?v=nope"))
    }

    func testMediaOnlyNoteIsNotEmpty() {
        XCTAssertFalse(BlockDoc(blocks: [Block(type: .image, src: "x")]).isEffectivelyEmpty)
        XCTAssertFalse(BlockDoc(blocks: [Block(type: .linkCard, url: "https://x.com")]).isEffectivelyEmpty)
    }

    func testPlainTextMirror() {
        let doc = BlockDoc(blocks: [
            Block(type: .paragraph, spans: [TextSpan(text: "Hello")]),
            Block(type: .divider),
            Block(type: .paragraph, spans: [TextSpan(text: "World")]),
        ])
        XCTAssertEqual(doc.plainText, "Hello\n———\nWorld")
    }
}
