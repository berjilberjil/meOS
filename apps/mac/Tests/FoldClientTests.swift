import XCTest
@testable import MyOS

final class FoldClientTests: XCTestCase {
    func testDeviceTypeIsAcceptedByFold() {
        XCTAssertEqual(FoldClient.deviceType, "Android")
        XCTAssertNotEqual(FoldClient.deviceType, "macOS")
    }

    func testNormalizePhoneAddsPlusIndiaCode() {
        XCTAssertEqual(FoldClient.normalizePhone("9876543210"), "+919876543210")
        XCTAssertEqual(FoldClient.normalizePhone("+91 98765 43210"), "+919876543210")
        XCTAssertEqual(FoldClient.normalizePhone("919876543210"), "+919876543210")
        XCTAssertEqual(FoldClient.normalizePhone("918300337987"), "+918300337987")
    }

    func testFoldAPIMessageReadsNestedError() {
        let body = Data("""
        {"meta":{"uri":"/api/v1/auth/otp"},"data":null,"error":{"code":2008,"message":"invalid phone"}}
        """.utf8)
        XCTAssertEqual(FoldClient.apiMessage(from: body, code: 422), "invalid phone")
    }

    func testSnapshotBuilderSumsDebitsAndBanks() {
        let txns: [[String: Any]] = [
            [
                "type": "DEBIT", "amount": 100.0, "category": "Food",
                "txn_timestamp": "2026-08-16T10:00:00Z",
                "current_balance": 5000.0,
                "account_id": "acc1",
                "financial_information_provider": ["name": "HDFC Bank"]
            ],
            [
                "type": "DEBIT", "amount": 50.0, "category": "Food",
                "txn_timestamp": "2026-08-16T11:00:00Z",
                "current_balance": 4950.0,
                "account_id": "acc1",
                "financial_information_provider": ["name": "HDFC Bank"]
            ],
            [
                "type": "CREDIT", "amount": 200.0, "category": "Salary",
                "txn_timestamp": "2026-08-16T12:00:00Z",
                "current_balance": 5150.0,
                "account_id": "acc1",
                "financial_information_provider": ["name": "HDFC Bank"]
            ]
        ]
        let blob: [String: Any] = ["net_worth": 67000.0, "liquid": 19600.0]
        let snap = FoldSnapshotBuilder.build(blobs: [blob], transactions: txns, previous: nil)
        XCTAssertEqual(snap.netWorth, 67000)
        XCTAssertEqual(snap.liquid, 19600)
        XCTAssertEqual(snap.spentThisMonth, 150)
        XCTAssertEqual(snap.topSpends.first?.category, "Food")
        XCTAssertEqual(snap.banks.first?.name, "HDFC Bank")
        XCTAssertFalse(snap.asOf.isEmpty)
    }

    func testEndpointURLKeepsPathSlashes() {
        XCTAssertEqual(
            FoldClient.endpointURL("/v1/auth/otp/verify").absoluteString,
            "https://api.fold.money/api/v1/auth/otp/verify"
        )
        XCTAssertEqual(
            FoldClient.endpointURL("/v1/auth/otp/verify", root: "https://api.fold.money").absoluteString,
            "https://api.fold.money/v1/auth/otp/verify"
        )
        XCTAssertEqual(
            FoldClient.endpointURL("/v2/users/me").absoluteString,
            "https://api.fold.money/api/v2/users/me"
        )
        let tx = FoldClient.endpointURL(
            "/v1/users/abc/transactions",
            query: ["filter": "all", "after": "a+b/c="]
        )
        XCTAssertTrue(tx.absoluteString.hasPrefix("https://api.fold.money/api/v1/users/abc/transactions?"))
        XCTAssertFalse(tx.absoluteString.contains("%2Fusers%2F"))
        XCTAssertTrue(tx.absoluteString.contains("after="))
        XCTAssertFalse(tx.absoluteString.contains("after=a+b/c="), "query values must be encoded")
    }

    func testTransactionCursorIsDecodableCountAndTimestamp() {
        let till = ISO8601DateFormatter().date(from: "2026-08-16T12:00:00Z")!
        let cursor = FoldClient.transactionAfterCursor(till: till)
        let raw = String(data: Data(base64Encoded: cursor) ?? Data(), encoding: .utf8) ?? ""
        let parts = raw.split(separator: ",", maxSplits: 1).map(String.init)
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts[0].count, 8)
        XCTAssertTrue(parts[1].contains("2026-08-16"))
    }

    func testSnapshotReplacesPreviousAsOfEvenWhenNumbersStay() {
        var prev = FoldData()
        prev.asOf = "14 Aug 2026, 9:14 pm"
        prev.netWorth = 67217
        prev.liquid = 19671
        let snap = FoldSnapshotBuilder.build(
            blobs: [["liquid": 19671.0, "net_worth": 67217.0]],
            transactions: [],
            previous: prev
        )
        XCTAssertNotEqual(snap.asOf, "14 Aug 2026, 9:14 pm")
        XCTAssertEqual(snap.netWorth, 67217)
        XCTAssertEqual(snap.liquid, 19671)
    }

    func testEmptyLivePullDoesNotWipePreviousSnapshot() {
        var prev = FoldData()
        prev.asOf = "14 Aug 2026, 9:14 pm"
        prev.netWorth = 67217.29
        prev.liquid = 19671.89
        prev.banks = [FoldData.Bank(name: "HDFC Bank", last4: "8362", balance: 19539.13)]
        let snap = FoldSnapshotBuilder.build(blobs: [], transactions: [], previous: prev)
        XCTAssertEqual(snap.netWorth, 67217.29)
        XCTAssertEqual(snap.liquid, 19671.89)
        XCTAssertEqual(snap.banks.first?.name, "HDFC Bank")
        XCTAssertEqual(snap.asOf, "14 Aug 2026, 9:14 pm")
        XCTAssertTrue(FoldSnapshotBuilder.isBare(FoldData()))
        XCTAssertFalse(FoldSnapshotBuilder.isBare(prev))
    }

    func testStaleDiskIsNotReloadedAfterFailedLivePull() {
        XCTAssertFalse(FoldRefresh.shouldReloadStaleSnapshot(linked: true, liveSucceeded: false))
        XCTAssertTrue(FoldRefresh.shouldReloadStaleSnapshot(linked: false, liveSucceeded: false))
        XCTAssertFalse(FoldRefresh.shouldReloadStaleSnapshot(linked: true, liveSucceeded: true))
    }

    func testResolvedPrefersRichThenDiskThenRecovery() {
        var rich = FoldData()
        rich.netWorth = 67217
        rich.liquid = 19671
        var zeros = FoldData()
        zeros.asOf = "16 Aug 2026, 6:11 pm"
        let rec = FoldData.recoverySnapshot()
        XCTAssertEqual(FoldSnapshotBuilder.resolved(current: rich, disk: nil, recovery: rec).netWorth, 67217)
        XCTAssertEqual(FoldSnapshotBuilder.resolved(current: zeros, disk: rich, recovery: rec).netWorth, 67217)
        XCTAssertEqual(FoldSnapshotBuilder.resolved(current: zeros, disk: zeros, recovery: rec).netWorth, rec.netWorth)
        XCTAssertFalse(FoldSnapshotBuilder.isBare(rec))
    }

    func testBareLocalStillPullsSyncAfterFailedLive() {
        XCTAssertTrue(FoldRefresh.shouldPullSync(linked: true, liveSucceeded: false, localBare: true))
        XCTAssertFalse(FoldRefresh.shouldPullSync(linked: true, liveSucceeded: false, localBare: false))
        XCTAssertTrue(FoldRefresh.shouldPullSync(linked: false, liveSucceeded: false, localBare: false))
        XCTAssertFalse(FoldRefresh.shouldPullSync(linked: true, liveSucceeded: true, localBare: true))
    }

    func testCaptionDoesNotCallStaleSnapshotLive() {
        XCTAssertEqual(
            FoldCaption.line(asOf: "14 Aug 2026, 9:14 pm", linked: false, error: nil),
            "Last snapshot · 14 Aug 2026, 9:14 pm · Connect to refresh"
        )
        XCTAssertEqual(
            FoldCaption.line(asOf: "16 Aug 2026, 4:00 pm", linked: true, error: nil),
            "Live Fold · 16 Aug 2026, 4:00 pm"
        )
        XCTAssertEqual(
            FoldCaption.line(asOf: "16 Aug 2026, 4:00 pm", linked: true, error: "Fold 401"),
            "Last snapshot · 16 Aug 2026, 4:00 pm"
        )
    }
}
