import XCTest
@testable import meOS

/// Fold answers `bank_accounts` with 200 and 1531 bytes of accounts nested under
/// `data.added` / `data.subscribed`, and the old flat `{name, balance}` matcher
/// dropped every one of them — a "successful" pull that extracted nothing.
final class FoldBankParsingTests: XCTestCase {
    private func pull(_ blob: [String: Any]) -> FoldSnapshotBuilder.Outcome {
        FoldSnapshotBuilder.outcome(blobs: [blob], transactions: [], previous: nil)
    }

    func testAccountsNestedUnderDataAdded() {
        let out = pull([
            "data": ["added": [
                ["account_id": "a1",
                 "masked_account_number": "XXXXXX8362",
                 "current_balance": 19_539.13,
                 "fip": ["name": "HDFC Bank"]]
            ]]
        ])
        XCTAssertTrue(out.extracted)
        XCTAssertEqual(out.data.banks.count, 1)
        XCTAssertEqual(out.data.banks.first?.name, "HDFC Bank")
        XCTAssertEqual(out.data.banks.first?.last4, "8362")
        XCTAssertEqual(out.data.banks.first?.balance, 19_539.13)
        XCTAssertEqual(out.data.liquid, 19_539.13)
    }

    func testSubscribedAccountsCountToo() {
        let out = pull([
            "data": [
                "added": [["account_id": "a1", "account_number": "1111118362",
                           "balance": 100.0, "bank_name": "HDFC Bank"]],
                "subscribed": [["account_id": "a2", "account_number": "2222227065",
                                "balance": 11.5, "bank_name": "State Bank of India"]]
            ]
        ])
        XCTAssertEqual(out.data.banks.count, 2)
        XCTAssertEqual(out.data.liquid, 111.5)
    }

    func testBalanceArrivingAsAString() {
        let out = pull(["data": ["accounts": [
            ["account_id": "a1", "masked_account_number": "XX4377",
             "current_balance": "21.20", "name": "AU Small Finance Bank"]
        ]]])
        XCTAssertEqual(out.data.banks.first?.balance, 21.2)
    }

    func testBalanceWrappedInAnAmountObject() {
        let out = pull(["data": ["added": [
            ["account_id": "a1", "masked_account_number": "XX8362",
             "balance": ["amount": 19_539.13, "currency": "INR"],
             "financial_information_provider": ["name": "HDFC Bank"]]
        ]]])
        XCTAssertEqual(out.data.banks.first?.balance, 19_539.13)
        XCTAssertEqual(out.data.banks.first?.name, "HDFC Bank")
    }

    /// A plan/settings object with a name and a number must not become a bank.
    func testNonAccountObjectsAreNotBanks() {
        let out = pull(["data": [
            "plan": ["name": "Fold Plus", "amount": 499.0],
            "settings": ["name": "default", "balance": 0.0]
        ]])
        XCTAssertTrue(out.data.banks.isEmpty)
        XCTAssertFalse(out.extracted)
    }

    func testAccountWithNoNameStillKeepsItsMoney() {
        let out = pull(["data": ["added": [
            ["account_id": "a1", "masked_account_number": "XX9999", "current_balance": 500.0]
        ]]])
        XCTAssertEqual(out.data.banks.first?.balance, 500)
        XCTAssertEqual(out.data.banks.first?.last4, "9999")
    }

    // MARK: - The shape log must never carry a value

    func testSkeletonRecordsTypesNotValues() {
        let shape = FoldTrace.skeleton([
            "data": ["added": [["current_balance": 19_539.13, "fip": ["name": "HDFC Bank"]]]]
        ])
        XCTAssertTrue(shape.contains("current_balance"))
        XCTAssertTrue(shape.contains("number"))
        XCTAssertTrue(shape.contains("fip"))
        XCTAssertFalse(shape.contains("19539"))
        XCTAssertFalse(shape.contains("HDFC"))
    }

    func testSkeletonCollapsesArraysToOneElement() {
        let shape = FoldTrace.skeleton(["xs": [["alpha": 1], ["beta": 2], ["gamma": 3]]])
        XCTAssertTrue(shape.contains("alpha"))
        XCTAssertFalse(shape.contains("beta"))
        XCTAssertTrue(shape.contains("×3"))   // the count survives, the elements don't
    }
}
