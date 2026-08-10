import XCTest
@testable import MyOS

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

    func testPlainTextMirror() {
        let doc = BlockDoc(blocks: [
            Block(type: .paragraph, spans: [TextSpan(text: "Hello")]),
            Block(type: .divider),
            Block(type: .paragraph, spans: [TextSpan(text: "World")]),
        ])
        XCTAssertEqual(doc.plainText, "Hello\n———\nWorld")
    }
}
