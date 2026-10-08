import XCTest
@testable import meOS

/// Fold's access token dies after ~15 minutes (200 at 13:59, 401 at 14:04 on the
/// same session). Renewal lives at `/v2/auth/tokens/refresh` — the v1 path the app
/// used to call 404s, so every session went stale one pull after sign-in.
final class FoldRenewalTests: XCTestCase {
    private let old = FoldSession.Tokens(access: "old-access", refresh: "old-refresh", userID: "u1")

    func testNewPairReplacesTheOldOne() {
        let json: [String: Any] = ["data": ["access_token": "new-access", "refresh_token": "new-refresh"]]
        let next = FoldClient.tokens(from: json, keeping: old)
        XCTAssertEqual(next?.access, "new-access")
        XCTAssertEqual(next?.refresh, "new-refresh")
        XCTAssertEqual(next?.userID, "u1")     // identity carries over
    }

    /// Some responses rotate only the access token — dropping the refresh token
    /// would strand the session at the next expiry.
    func testARotatedAccessTokenKeepsTheExistingRefreshToken() {
        let next = FoldClient.tokens(from: ["data": ["access_token": "new-access"]], keeping: old)
        XCTAssertEqual(next?.access, "new-access")
        XCTAssertEqual(next?.refresh, "old-refresh")
    }

    func testUnwrappedResponseWorksToo() {
        let next = FoldClient.tokens(from: ["access_token": "flat"], keeping: old)
        XCTAssertEqual(next?.access, "flat")
    }

    func testNoAccessTokenIsNotASession() {
        XCTAssertNil(FoldClient.tokens(from: ["data": ["refresh_token": "only-refresh"]], keeping: old))
        XCTAssertNil(FoldClient.tokens(from: [:], keeping: old))
    }

    func testAFirstLoginNeedsNoPreviousTokens() {
        let next = FoldClient.tokens(from: ["data": ["access_token": "a", "refresh_token": "r",
                                                     "user_id": "u9"]], keeping: nil)
        XCTAssertEqual(next?.access, "a")
        XCTAssertEqual(next?.userID, "u9")
    }

    // MARK: - When to renew

    func testAFreshTokenIsNotRenewed() {
        let fresh = FoldSession.Tokens(access: "a", refresh: "r", userID: "u",
                                       expiresAt: Date().addingTimeInterval(900))
        XCTAssertFalse(fresh.needsRenewal())
    }

    func testATokenAboutToExpireIsRenewed() {
        let stale = FoldSession.Tokens(access: "a", refresh: "r", userID: "u",
                                       expiresAt: Date().addingTimeInterval(30))
        XCTAssertTrue(stale.needsRenewal())
    }

    func testAnExpiredTokenIsRenewed() {
        let dead = FoldSession.Tokens(access: "a", refresh: "r", userID: "u",
                                      expiresAt: Date().addingTimeInterval(-10))
        XCTAssertTrue(dead.needsRenewal())
    }

    func testATokenWithNoKnownExpiryIsRenewed() {
        XCTAssertTrue(FoldSession.Tokens(access: "a", refresh: "r").needsRenewal())
    }

    // MARK: - expires_at arrives in several shapes

    func testExpiryFromEpochSeconds() throws {
        let d = try XCTUnwrap(FoldClient.expiry(1_785_000_000.0))
        XCTAssertEqual(d.timeIntervalSince1970, 1_785_000_000, accuracy: 1)
    }

    func testExpiryFromEpochMilliseconds() throws {
        let d = try XCTUnwrap(FoldClient.expiry(1_785_000_000_000.0))
        XCTAssertEqual(d.timeIntervalSince1970, 1_785_000_000, accuracy: 1)
    }

    func testExpiryFromRFC3339String() {
        let iso = ISO8601DateFormatter()
        let expected = iso.date(from: "2026-08-16T14:30:00Z")
        XCTAssertEqual(FoldClient.expiry("2026-08-16T14:30:00Z"), expected)
    }

    /// A small number is a duration (`expires_in`), not a 1970 timestamp.
    func testExpiryFromDurationSeconds() {
        let d = FoldClient.expiry(900.0)
        XCTAssertEqual(d?.timeIntervalSinceNow ?? 0, 900, accuracy: 5)
    }

    func testExpiryFromNonsenseIsUnknown() {
        XCTAssertNil(FoldClient.expiry(nil))
        XCTAssertNil(FoldClient.expiry("not a date"))
    }

    func testVerifyResponseCarriesItsExpiry() throws {
        let next = FoldClient.tokens(from: ["data": ["access_token": "a",
                                                     "expires_at": 1_785_000_000.0]], keeping: nil)
        let expiry = try XCTUnwrap(next?.expiresAt)
        XCTAssertEqual(expiry.timeIntervalSince1970, 1_785_000_000, accuracy: 1)
    }

    /// The user id can arrive nested under `user_meta` on the OTP verify response.
    func testUserIDFromUserMeta() {
        let next = FoldClient.tokens(from: ["data": ["access_token": "a",
                                                     "user_meta": ["uuid": "u7"]]], keeping: nil)
        XCTAssertEqual(next?.userID, "u7")
    }
}
