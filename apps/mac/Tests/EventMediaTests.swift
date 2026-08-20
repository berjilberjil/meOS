import XCTest
@testable import MyOS

/// Event media moved out of the `myos.events` blob into R2. Both shapes — old
/// rows with inline base64, new rows with R2 keys — must survive a round trip,
/// because a device on an older build keeps writing the old shape.
final class EventMediaCodingTests: XCTestCase {
    private func decode(_ json: String) throws -> EventMedia {
        try JSONDecoder().decode(EventMedia.self, from: Data(json.utf8))
    }

    func testLegacyInlineRowDecodes() throws {
        let m = try decode(#"{"id":"a","kind":"image","data":"QUJD"}"#)
        XCTAssertEqual(m.data, "QUJD")
        XCTAssertNil(m.r2Key)
        XCTAssertTrue(m.needsMigration)
    }

    func testMigratedRowDecodes() throws {
        let m = try decode(#"{"id":"a","kind":"image","data":"","r2Key":"abc-123"}"#)
        XCTAssertEqual(m.r2Key, "abc-123")
        XCTAssertTrue(m.data.isEmpty)
        XCTAssertFalse(m.needsMigration)
    }

    func testVideoPosterNeedsMigrationOnItsOwn() throws {
        // Main asset already moved, thumbnail did not.
        let m = try decode(#"{"id":"a","kind":"video","data":"","r2Key":"k","poster":"QUJD"}"#)
        XCTAssertTrue(m.needsMigration)
    }

    func testFullyMigratedVideoIsDone() throws {
        let m = try decode(#"{"id":"a","kind":"video","data":"","r2Key":"k","posterKey":"p"}"#)
        XCTAssertFalse(m.needsMigration)
    }

    func testMissingKindFallsBackToImage() throws {
        XCTAssertEqual(try decode(#"{"id":"a"}"#).kind, .image)
    }

    func testRoundTripPreservesKeys() throws {
        let original = EventMedia(kind: .video, r2Key: "k1", posterKey: "k2")
        let data = try JSONEncoder().encode(original)
        let back = try JSONDecoder().decode(EventMedia.self, from: data)
        XCTAssertEqual(back.r2Key, "k1")
        XCTAssertEqual(back.posterKey, "k2")
        XCTAssertEqual(back.kind, .video)
        XCTAssertFalse(back.needsMigration)
    }

    /// An empty item must not loop forever in the backfill.
    func testEmptyMediaNeedsNothing() throws {
        XCTAssertFalse(EventMedia(kind: .image).needsMigration)
    }
}
