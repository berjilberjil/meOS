import XCTest
import CryptoKit
@testable import MyOS

/// The Mac app is ad-hoc signed, so every data-protection Keychain write returns
/// -34018 and the Fold tokens vanished the moment the login sheet closed — which
/// is why Refresh never called Fold at all. Tokens now sit beside the state cache,
/// sealed with the vault DEK.
final class FoldSessionTests: XCTestCase {
    private let key = SymmetricKey(size: .bits256)
    private var url: URL!

    override func setUp() {
        super.setUp()
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("fold.session.\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: url)
        super.tearDown()
    }

    func testTokensSurviveASaveAndReload() {
        let tokens = FoldSession.Tokens(access: "acc-123", refresh: "ref-456", userID: "u-1")
        XCTAssertTrue(FoldSession.write(tokens, to: url, key: key))
        XCTAssertEqual(FoldSession.read(from: url, key: key), tokens)
    }

    func testTokensAreNotWrittenInPlaintext() {
        XCTAssertTrue(FoldSession.write(.init(access: "acc-123"), to: url, key: key))
        let raw = String(data: (try? Data(contentsOf: url)) ?? Data(), encoding: .utf8) ?? ""
        XCTAssertFalse(raw.contains("acc-123"))
        XCTAssertTrue(raw.contains("\"ct\""))
    }

    func testAnotherKeyCannotReadTheSession() {
        XCTAssertTrue(FoldSession.write(.init(access: "acc-123"), to: url, key: key))
        XCTAssertNil(FoldSession.read(from: url, key: SymmetricKey(size: .bits256)))
    }

    func testLockedVaultReadsNothingAndWritesNothing() {
        XCTAssertFalse(FoldSession.write(.init(access: "acc-123"), to: url, key: nil))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertNil(FoldSession.read(from: url, key: nil))
    }

    func testMissingFileIsNotLinked() {
        XCTAssertNil(FoldSession.read(from: url, key: key))
    }

    func testEmptyAccessTokenIsNotASession() {
        XCTAssertTrue(FoldSession.write(.init(access: ""), to: url, key: key))
        XCTAssertNil(FoldSession.read(from: url, key: key))
    }

    func testClearRemovesTheSession() {
        XCTAssertTrue(FoldSession.write(.init(access: "acc-123"), to: url, key: key))
        FoldSession.remove(at: url)
        XCTAssertNil(FoldSession.read(from: url, key: key))
    }

    /// A rewritten session must not leave the old token behind.
    func testSavingAgainReplacesTheOldToken() {
        XCTAssertTrue(FoldSession.write(.init(access: "old"), to: url, key: key))
        XCTAssertTrue(FoldSession.write(.init(access: "new", refresh: "r"), to: url, key: key))
        XCTAssertEqual(FoldSession.read(from: url, key: key)?.access, "new")
        XCTAssertEqual(FoldSession.read(from: url, key: key)?.refresh, "r")
    }
}
