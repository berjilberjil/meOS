import XCTest
@testable import meOS

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

/// The iOS event editor used SwiftUI `PhotosPicker` inside a sheet that
/// observes `AppState`. A 1.5s live-sync tick remounted the picker, the
/// library reloaded, and whatever you had tapped vanished. Import kind is
/// the part we can pin in a test: photos AND videos, never a PDF.
final class EventMediaImportTests: XCTestCase {
    func testJPEGIsAnImage() {
        XCTAssertEqual(EventMediaImport.kind(typeIdentifier: "public.jpeg"), .image)
    }

    func testHEICIsAnImage() {
        XCTAssertEqual(EventMediaImport.kind(typeIdentifier: "public.heic"), .image)
    }

    func testPNGIsAnImage() {
        XCTAssertEqual(EventMediaImport.kind(typeIdentifier: "public.png"), .image)
    }

    func testMPEG4IsAVideo() {
        XCTAssertEqual(EventMediaImport.kind(typeIdentifier: "public.mpeg-4"), .video)
    }

    func testQuickTimeIsAVideo() {
        XCTAssertEqual(EventMediaImport.kind(typeIdentifier: "com.apple.quicktime-movie"), .video)
    }

    func testGenericMovieIsAVideo() {
        XCTAssertEqual(EventMediaImport.kind(typeIdentifier: "public.movie"), .video)
    }

    func testPDFIsRejected() {
        XCTAssertNil(EventMediaImport.kind(typeIdentifier: "com.adobe.pdf"))
    }

    func testGarbageTypeIsRejected() {
        XCTAssertNil(EventMediaImport.kind(typeIdentifier: "not.a.real.type"))
    }

    func testAtMostEightItems() {
        XCTAssertEqual(EventMediaImport.maxSelection, 8)
    }
}

/// Every API call goes through one URL join. `appendingPathComponent` treats the
/// whole string as a path component, so it percent-escapes a `?` — which silently
/// turned the one call that carries a query, `signEventMedia`, into a request for
/// a path that does not exist. The 404 blacklisted the media, and every event
/// photo that had moved to R2 rendered as a grey box on any device that had not
/// uploaded it itself.
final class APIURLJoinTests: XCTestCase {
    func testQueryStringSurvivesTheJoin() {
        let u = APIClient.url(for: "api/event-media?ids=abc-123,def-456")
        XCTAssertEqual(u.path, "/api/event-media")
        XCTAssertEqual(u.query, "ids=abc-123,def-456")
        XCTAssertFalse(u.absoluteString.contains("%3F"))
    }

    func testPlainPathIsUnchanged() {
        XCTAssertEqual(APIClient.url(for: "api/me").path, "/api/me")
        XCTAssertNil(APIClient.url(for: "api/me").query)
    }

    /// The caller already percent-encodes the value, so the join must not encode
    /// it a second time and turn `%20` into `%2520`.
    func testAlreadyEncodedQueryIsNotDoubleEncoded() {
        let u = APIClient.url(for: "api/event-media?ids=a%20b")
        XCTAssertEqual(u.query, "ids=a%20b")
    }

    /// A path component that itself needs escaping still gets it.
    func testPathComponentIsStillEscaped() {
        XCTAssertFalse(APIClient.url(for: "api/event-media/a b").absoluteString.contains(" "))
    }
}
