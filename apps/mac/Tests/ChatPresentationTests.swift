import XCTest
@testable import MyOS

/// The chat widget shows the panel or the voice call — never both, and never
/// via two stacked presentations.
///
/// This exists because the first cut of voice chained a SECOND
/// `.fullScreenCover` onto the view that already presents the chat. SwiftUI
/// honours one cover per view, and the button that triggered the second lived
/// *inside* the first — so tapping "Talk" did nothing at all. Same shape as the
/// `.fileImporter` bug in Events. The rule is pinned here as logic so it cannot
/// silently come back as ordinary-looking SwiftUI.
final class ChatPresentationTests: XCTestCase {

    func testClosedByDefault() {
        let p = ChatPresentation()
        XCTAssertFalse(p.open)
        XCTAssertEqual(p.screen, .panel)
    }

    func testOpeningShowsThePanelNotACall() {
        var p = ChatPresentation()
        p.openChat()
        XCTAssertTrue(p.open)
        XCTAssertEqual(p.screen, .panel, "opening chat must never land in a call")
    }

    func testStartingACallSwapsTheContentOfTheSameCover() {
        var p = ChatPresentation()
        p.openChat()
        p.startCall()
        XCTAssertEqual(p.screen, .call)
        XCTAssertTrue(p.open, "the call replaces the panel INSIDE the open cover — it is not a second presentation")
    }

    func testEndingACallReturnsToThePanel() {
        var p = ChatPresentation()
        p.openChat()
        p.startCall()
        p.endCall()
        XCTAssertEqual(p.screen, .panel)
        XCTAssertTrue(p.open, "ending a call must drop back to the chat, not close it")
    }

    /// The second bug: leaving the widget mid-call used to leave the call armed,
    /// so the next time he opened chat he was thrown straight into a call.
    func testClosingTheWidgetMidCallDisarmsTheCall() {
        var p = ChatPresentation()
        p.openChat()
        p.startCall()
        p.close()
        XCTAssertFalse(p.open)
        XCTAssertEqual(p.screen, .panel)

        p.openChat()
        XCTAssertEqual(p.screen, .panel, "reopening chat must not resume the old call")
    }

    func testACallCannotBeStartedWhileTheWidgetIsClosed() {
        var p = ChatPresentation()
        p.startCall()
        XCTAssertFalse(p.open)
        XCTAssertEqual(p.screen, .panel, "nothing to present a call over")
    }
}
