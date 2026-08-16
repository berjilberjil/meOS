import XCTest
@testable import MyOS

final class FoldClientTests: XCTestCase {
    func testNormalizePhoneAddsIndiaCode() {
        XCTAssertEqual(FoldClient.normalizePhone("9876543210"), "919876543210")
        XCTAssertEqual(FoldClient.normalizePhone("+91 98765 43210"), "919876543210")
        XCTAssertEqual(FoldClient.normalizePhone("919876543210"), "919876543210")
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
}
