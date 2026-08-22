import XCTest
@testable import MyOS

final class VoiceTextTests: XCTestCase {
    func testSplitsOnSentenceEnders() {
        XCTAssertEqual(VoiceText.sentences("You skipped legs. Fix that tomorrow."),
                       ["You skipped legs.", "Fix that tomorrow."])
    }

    func testKeepsQuestionAndExclamation() {
        XCTAssertEqual(VoiceText.sentences("Did you? Really!"), ["Did you?", "Really!"])
    }

    func testTextWithNoTerminatorIsOneChunk() {
        XCTAssertEqual(VoiceText.sentences("no full stop here"), ["no full stop here"])
    }

    func testEmptyAndWhitespaceYieldNothing() {
        XCTAssertEqual(VoiceText.sentences(""), [])
        XCTAssertEqual(VoiceText.sentences("   \n  "), [])
    }

    func testDoesNotSplitOnDecimals() {
        XCTAssertEqual(VoiceText.sentences("You lifted 82.5 kg today."), ["You lifted 82.5 kg today."])
    }

    func testDoesNotSplitOnCommonAbbreviations() {
        XCTAssertEqual(VoiceText.sentences("Dr. Rao called. Ring him back."),
                       ["Dr. Rao called.", "Ring him back."])
    }

    func testTreatsEllipsisAsOneBreak() {
        XCTAssertEqual(VoiceText.sentences("Hmm... maybe not."), ["Hmm...", "maybe not."])
    }

    func testSplitsAnOverlongSentenceOnAWordBoundary() {
        let long = String(repeating: "word ", count: 200).trimmingCharacters(in: .whitespaces)
        let parts = VoiceText.sentences(long, maxLength: 60)
        XCTAssertGreaterThan(parts.count, 1)
        XCTAssertTrue(parts.allSatisfy { $0.count <= 60 }, "every chunk must fit the server's cap")
        XCTAssertFalse(parts.contains { $0.hasPrefix(" ") || $0.hasSuffix(" ") })
        XCTAssertEqual(parts.joined(separator: " "), long)
    }

    func testCollapsesNewlinesInsideASentence() {
        XCTAssertEqual(VoiceText.sentences("Two things:\n- rest\n- eat"), ["Two things: - rest - eat"])
    }
}
