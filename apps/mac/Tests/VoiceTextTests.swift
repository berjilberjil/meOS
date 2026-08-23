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
        XCTAssertEqual(VoiceText.sentences("Two things:\n- rest\n- eat"), ["Two things: rest eat"])
    }

    // MARK: - Markdown must never be spoken

    /// The reported bug: she read "star star Clear Skcript Deliverables star star"
    /// out loud, because the model answered in markdown and Aura says what it is given.
    func testStripsBoldMarkers() {
        XCTAssertEqual(VoiceText.plain("**Clear Skcript Deliverables:** wrap it up"),
                       "Clear Skcript Deliverables: wrap it up")
    }

    func testStripsItalicAndCode() {
        XCTAssertEqual(VoiceText.plain("that is *really* the `main` thing"),
                       "that is really the main thing")
    }

    func testStripsNumberedAndBulletMarkers() {
        XCTAssertEqual(VoiceText.plain("1. lock the plan\n2. cut the video"),
                       "lock the plan cut the video")
        XCTAssertEqual(VoiceText.plain("- rest\n• eat"), "rest eat")
    }

    func testStripsHeadings() {
        XCTAssertEqual(VoiceText.plain("## Focus\ntrain legs"), "Focus train legs")
    }

    func testKeepsLinkTextAndDropsTheUrl() {
        XCTAssertEqual(VoiceText.plain("see [the plan](https://x.com/y) tonight"),
                       "see the plan tonight")
    }

    /// A decimal is not a list marker — "82.5" must survive.
    func testDoesNotMistakeADecimalForAListMarker() {
        XCTAssertEqual(VoiceText.plain("you lifted 82.5 kg"), "you lifted 82.5 kg")
    }

    func testAsterisksNeverReachTheSpokenOutput() {
        let out = VoiceText.sentences("**One.** Two *things* here.").joined(separator: " ")
        XCTAssertFalse(out.contains("*"), "an asterisk in TTS input is read aloud as a word")
    }
}
