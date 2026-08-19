import XCTest
@testable import MyOS

/// What "Share → MyOS" accepts. The share sheet is a much noisier input than
/// the paste field, so `sharedLink` is deliberately stricter than `videoID`.
final class ShareLinkTests: XCTestCase {

    // MARK: The shapes YouTube actually sends

    func testAcceptsEveryYouTubeLinkShape() {
        let cases: [(String, String)] = [
            ("https://www.youtube.com/watch?v=dQw4w9WgXcQ", "dQw4w9WgXcQ"),
            ("https://youtu.be/dQw4w9WgXcQ", "dQw4w9WgXcQ"),
            ("https://youtube.com/shorts/dQw4w9WgXcQ", "dQw4w9WgXcQ"),
            ("https://m.youtube.com/watch?v=dQw4w9WgXcQ", "dQw4w9WgXcQ"),
            ("https://www.youtube.com/embed/dQw4w9WgXcQ", "dQw4w9WgXcQ"),
            ("https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ", "dQw4w9WgXcQ")
        ]
        for (link, id) in cases {
            XCTAssertEqual(YouTube.sharedLink(in: link)?.id, id, link)
        }
    }

    /// The iOS share sheet hands over "title, newline, link" more often than a
    /// bare URL — the link has to be picked out of the text.
    func testPullsTheLinkOutOfSharedText() {
        let shared = "Never Gonna Give You Up\nhttps://youtu.be/dQw4w9WgXcQ"
        let found = YouTube.sharedLink(in: shared)
        XCTAssertEqual(found?.id, "dQw4w9WgXcQ")
        XCTAssertEqual(found?.url, "https://youtu.be/dQw4w9WgXcQ", "the link alone is stored, not the blurb")
    }

    func testKeepsTrackingParamsOutOfTheId() {
        XCTAssertEqual(YouTube.sharedLink(in: "https://youtu.be/dQw4w9WgXcQ?si=abc123&t=42")?.id,
                       "dQw4w9WgXcQ")
    }

    func testTrimsSurroundingWhitespace() {
        XCTAssertEqual(YouTube.sharedLink(in: "  https://youtu.be/dQw4w9WgXcQ \n")?.id, "dQw4w9WgXcQ")
    }

    // MARK: What it must refuse

    /// The whole reason this is separate from `videoID`: that one takes a bare
    /// id, so any twelve-letter word shared as text would become a "video".
    func testRefusesBareIdsAndLooseText() {
        XCTAssertNil(YouTube.sharedLink(in: "dQw4w9WgXcQ"))
        XCTAssertNil(YouTube.sharedLink(in: "grocerylist"))
        XCTAssertNil(YouTube.sharedLink(in: ""))
        XCTAssertNotNil(YouTube.videoID(from: "dQw4w9WgXcQ"),
                        "the paste-field parser still accepts a bare id — that's the difference")
    }

    func testRefusesOtherSites() {
        XCTAssertNil(YouTube.sharedLink(in: "https://vimeo.com/dQw4w9WgXcQ"))
        XCTAssertNil(YouTube.sharedLink(in: "https://example.com/watch?v=dQw4w9WgXcQ"))
    }

    /// A host merely *containing* "youtube.com" isn't YouTube — the match is on
    /// the domain, not a substring.
    func testRefusesLookalikeHosts() {
        XCTAssertNil(YouTube.sharedLink(in: "https://youtube.com.evil.example/watch?v=dQw4w9WgXcQ"))
        XCTAssertNil(YouTube.sharedLink(in: "https://notyoutube.com/watch?v=dQw4w9WgXcQ"))
    }

    // MARK: The queue the extension writes to

    func testInboxItemSurvivesTheHandOff() throws {
        let item = ShareInbox.Item(videoId: "dQw4w9WgXcQ",
                                   url: "https://youtu.be/dQw4w9WgXcQ",
                                   sharedAt: "2026-08-19T21:15:00")
        let back = try JSONDecoder().decode(ShareInbox.Item.self,
                                            from: try JSONEncoder().encode(item))
        XCTAssertEqual(back, item)
    }

    /// Without the App Group entitlement there's no container, so every call has
    /// to no-op rather than trap — that's the Mac build, and any device where
    /// the entitlement didn't make it.
    func testInboxIsInertWithoutTheAppGroup() {
        XCTAssertEqual(ShareInbox.pending(), [])
        XCTAssertEqual(ShareInbox.drain(), [])
        XCTAssertFalse(ShareInbox.add(videoId: "dQw4w9WgXcQ", url: "https://youtu.be/dQw4w9WgXcQ"))
    }
}
