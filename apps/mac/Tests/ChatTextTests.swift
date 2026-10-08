import XCTest
@testable import meOS

final class ChatTextTests: XCTestCase {
    func testPlainTextPassesThrough() {
        XCTAssertEqual(ChatText.unwrap("Just drink water."), "Just drink water.")
    }

    func testPeelsAReplyObject() {
        XCTAssertEqual(ChatText.unwrap("{\"reply\":\"Drink water.\"}"), "Drink water.")
    }

    func testPeelsNestedReplyObjects() {
        let raw = "{\"reply\":\"{\\\"reply\\\":\\\"Drink water.\\\"}\"}"
        XCTAssertEqual(ChatText.unwrap(raw), "Drink water.")
    }

    func testPeelsPartialStreamPrefix() {
        XCTAssertEqual(ChatText.unwrap("{\"reply\":\"Drink wa"), "Drink wa")
    }

    func testStripsJsonFence() {
        XCTAssertEqual(ChatText.unwrap("```json\n{\"reply\":\"Hi\"}\n```"), "Hi")
    }
}
