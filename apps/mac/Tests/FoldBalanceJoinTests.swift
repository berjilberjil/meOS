import XCTest
@testable import meOS

/// Fold splits an account across two routes: `bank_accounts` carries the identity
/// (uuid, masked number, fip name) with **no** money on it, and
/// `bank_accounts/balances` carries the money. Neither response alone is a bank —
/// they have to be joined on the account id.
final class FoldBalanceJoinTests: XCTestCase {
    private let identities: [String: Any] = [
        "data": ["added": [
            ["uuid": "u1", "masked_account_number": "XXXXXX8362",
             "fi_type": "DEPOSIT", "fip": ["name": "HDFC Bank"]],
            ["uuid": "u2", "masked_account_number": "XXXXXX7065",
             "fi_type": "DEPOSIT", "fip": ["name": "State Bank of India"]]
        ], "subscribed": []]
    ]

    func testIdentityAndBalanceJoinOnAccountID() {
        let balances: [String: Any] = ["data": [
            ["account_id": "u1", "current_balance": 19_539.13],
            ["account_id": "u2", "current_balance": 111.56]
        ]]
        let out = FoldSnapshotBuilder.outcome(blobs: [identities, balances],
                                              transactions: [], previous: nil)
        XCTAssertTrue(out.extracted)
        XCTAssertEqual(out.data.banks.count, 2)
        let hdfc = out.data.banks.first { $0.name == "HDFC Bank" }
        XCTAssertEqual(hdfc?.balance, 19_539.13)
        XCTAssertEqual(hdfc?.last4, "8362")
        XCTAssertEqual(out.data.liquid, 19_650.69, accuracy: 0.001)
    }

    func testJoinAlsoWorksWhenTheBalanceKeysTheAccountByUUID() {
        let balances: [String: Any] = ["data": ["balances": [
            ["uuid": "u1", "balance": ["amount": 19_539.13, "currency": "INR"]]
        ]]]
        let out = FoldSnapshotBuilder.outcome(blobs: [identities, balances],
                                              transactions: [], previous: nil)
        XCTAssertEqual(out.data.banks.first?.name, "HDFC Bank")
        XCTAssertEqual(out.data.banks.first?.balance, 19_539.13)
    }

    /// Identities with no balance anywhere are not banks — three named accounts
    /// showing ₹0 would read as "your money vanished".
    func testIdentitiesAloneDoNotBecomeZeroBalanceBanks() {
        let out = FoldSnapshotBuilder.outcome(blobs: [identities], transactions: [], previous: nil)
        XCTAssertTrue(out.data.banks.isEmpty)
        XCTAssertFalse(out.extracted)
    }

    func testABalanceWithNoMatchingIdentityStillCounts() {
        let balances: [String: Any] = ["data": [["account_id": "u9", "current_balance": 500.0]]]
        let out = FoldSnapshotBuilder.outcome(blobs: [balances], transactions: [], previous: nil)
        XCTAssertEqual(out.data.banks.first?.balance, 500)
        XCTAssertEqual(out.data.banks.first?.name, "Bank")
    }

    /// `/v2/users/me` is full of uuid-bearing objects (fip, plan, settings).
    /// None of them may turn into an account.
    func testUnrelatedUUIDObjectsAreNotBanks() {
        let me: [String: Any] = ["data": [
            "plan": ["uuid": "p1", "name": "Fold Plus",
                     "feature_limits": ["max_connected_emails": 5]],
            "user": ["uuid": "x1", "name": "Berjil"]
        ]]
        let out = FoldSnapshotBuilder.outcome(blobs: [me], transactions: [], previous: nil)
        XCTAssertTrue(out.data.banks.isEmpty)
    }

    func testDuplicateAccountsAcrossResponsesAreNotCountedTwice() {
        let balances: [String: Any] = ["data": [["account_id": "u1", "current_balance": 19_539.13]]]
        let out = FoldSnapshotBuilder.outcome(blobs: [identities, balances, balances],
                                              transactions: [], previous: nil)
        XCTAssertEqual(out.data.banks.count, 1)
        XCTAssertEqual(out.data.liquid, 19_539.13)
    }
}
