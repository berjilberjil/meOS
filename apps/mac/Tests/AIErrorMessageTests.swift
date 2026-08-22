import XCTest
@testable import MyOS

/// The AI keys screen used to print "The data couldn't be read because it isn't
/// in the correct format." into the middle of its setup flow — Foundation's
/// description of a `DecodingError`. It describes our JSON parser, gives the
/// reader nothing to act on, and reads like a crash. These pin the rule that
/// framework prose never reaches the UI.
@MainActor
final class AIErrorMessageTests: XCTestCase {

    private struct Decoding: Error {}

    /// The exact failure that shipped.
    private var decodingFailure: Error {
        DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "unexpected"))
    }

    func testDecodingFailureNeverLeaksFrameworkProse() {
        for doing: AISettingsStore.Doing in [.loading, .checking, .saving] {
            let msg = AISettingsStore.msg(decodingFailure, doing)
            XCTAssertFalse(msg.contains("couldn't be read"), "leaked Foundation prose: \(msg)")
            XCTAssertFalse(msg.contains("correct format"), "leaked Foundation prose: \(msg)")
            XCTAssertFalse(msg.isEmpty)
        }
    }

    func testMessageSaysWhatYouWereDoing() {
        XCTAssertEqual(AISettingsStore.msg(decodingFailure, .checking),
                       "Couldn't validate this key. Check the key and try again.")
        XCTAssertEqual(AISettingsStore.msg(decodingFailure, .loading),
                       "Couldn't load your AI settings. Try again.")
        XCTAssertEqual(AISettingsStore.msg(decodingFailure, .saving),
                       "That didn't save. Try again.")
    }

    /// The server writes its messages for people, so they win.
    func testServerMessageIsPreferred() {
        let api = APIError(status: 400, message: "That key was rejected by Gemini.")
        XCTAssertEqual(AISettingsStore.msg(api, .checking), "That key was rejected by Gemini.")
    }

    func testEmptyServerMessageFallsBackRatherThanShowingNothing() {
        let api = APIError(status: 500, message: "")
        XCTAssertEqual(AISettingsStore.msg(api, .checking),
                       "Couldn't validate this key. Check the key and try again.")
    }

    func testConnectionFailuresSaySo() {
        XCTAssertEqual(AISettingsStore.msg(URLError(.notConnectedToInternet), .loading),
                       "No internet connection.")
        XCTAssertEqual(AISettingsStore.msg(URLError(.timedOut), .loading),
                       "The server didn't respond. Try again.")
        XCTAssertEqual(AISettingsStore.msg(URLError(.cannotFindHost), .loading),
                       "Couldn't reach MyOS. Check your connection.")
    }

    /// Anything we have not thought of still has to produce a usable sentence.
    func testUnknownErrorsStillReadAsEnglish() {
        let msg = AISettingsStore.msg(Decoding(), .saving)
        XCTAssertEqual(msg, "That didn't save. Try again.")
    }
}
