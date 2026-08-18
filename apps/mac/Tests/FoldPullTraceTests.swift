import XCTest
@testable import MyOS

/// A pull that reaches Fold and comes back with nothing used to report success and
/// quietly re-save last week's snapshot — the dashboard then said "Live Fold ·
/// 14 Aug" two days later. A pull must either bring new numbers or say what Fold
/// actually answered.
final class FoldPullTraceTests: XCTestCase {
    private func rich() -> FoldData {
        var f = FoldData()
        f.asOf = "14 Aug 2026, 9:14 pm"
        f.netWorth = 67_217
        f.liquid = 19_671
        f.banks = [FoldData.Bank(name: "HDFC Bank", last4: "8362", balance: 19_539)]
        return f
    }

    func testNothingFromFoldIsNotAnExtraction() {
        let out = FoldSnapshotBuilder.outcome(blobs: [], transactions: [], previous: rich())
        XCTAssertFalse(out.extracted)
        XCTAssertEqual(out.data.asOf, "14 Aug 2026, 9:14 pm")   // untouched, not restamped
    }

    func testBankAccountsCountAsAnExtraction() {
        let blobs: [[String: Any]] = [[
            "data": ["bank_accounts": [
                ["name": "HDFC Bank", "masked_account_number": "XXXX8362", "balance": 25_000.0]
            ]]
        ]]
        let out = FoldSnapshotBuilder.outcome(blobs: blobs, transactions: [], previous: rich())
        XCTAssertTrue(out.extracted)
        XCTAssertEqual(out.data.banks.first?.balance, 25_000)
        XCTAssertNotEqual(out.data.asOf, "14 Aug 2026, 9:14 pm")
    }

    func testBuildStillReturnsTheSnapshotOutcomeCarries() {
        let previous = rich()
        let built = FoldSnapshotBuilder.build(blobs: [], transactions: [], previous: previous)
        XCTAssertEqual(built, FoldSnapshotBuilder.outcome(blobs: [], transactions: [], previous: previous).data)
    }

    func testTraceLineNamesTheRouteAndStatus() {
        let line = FoldTrace.line(method: "GET", path: "/v1/users/me", code: 401, bytes: 120,
                                  keys: ["meta", "error"])
        XCTAssertTrue(line.contains("/v1/users/me"))
        XCTAssertTrue(line.contains("401"))
        XCTAssertTrue(line.contains("error"))
    }

    /// The log is for debugging routes, not for leaking balances.
    func testTraceLineCarriesKeyNamesNotValues() {
        let line = FoldTrace.line(method: "GET", path: "/v1/users/x/bank_accounts", code: 200,
                                  bytes: 812, keys: ["balance", "data"])
        XCTAssertTrue(line.contains("balance"))
        XCTAssertFalse(line.contains("19539"))
    }

    func testEmptyPullErrorRepeatsWhatFoldAnswered() {
        let err = FoldError.emptyPull("GET /v1/users/me → 401 (120 B)")
        XCTAssertTrue(err.errorDescription?.contains("401") ?? false)
    }

    /// The shape dump is hundreds of characters — it goes to the log file, never
    /// into the error line on the dashboard.
    func testSummaryLeavesTheShapeDumpToTheLog() {
        FoldTrace.reset()
        FoldTrace.record("GET /v1/users/me → 401 (278 B)")
        FoldTrace.recordShape(path: "/v1/users/me", data: Data(#"{"data":{"plan":{"tier":"x"}}}"#.utf8))
        XCTAssertEqual(FoldTrace.lines.count, 2)
        XCTAssertTrue(FoldTrace.summary.contains("401"))
        XCTAssertFalse(FoldTrace.summary.contains("shape"))
        XCTAssertFalse(FoldTrace.summary.contains("tier"))
    }

    func testTraceResetsBetweenPulls() {
        FoldTrace.reset()
        FoldTrace.record("GET /a → 200")
        XCTAssertEqual(FoldTrace.lines.count, 1)
        FoldTrace.reset()
        XCTAssertTrue(FoldTrace.lines.isEmpty)
        XCTAssertEqual(FoldTrace.summary, "")
    }
}
