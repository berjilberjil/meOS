import XCTest
@testable import FinanceCore

final class FinanceCoreTests: XCTestCase {

    private let today = "2026-11-20"
    private let cat = FinanceTaxonomy.categoryID

    // MARK: Fixtures

    private func account(_ name: String, type: FinAccountType = .savings,
                         opening: Int64 = 0, openingDate: String = "2020-01-01",
                         id: String = FinID.new()) -> FinAccount {
        FinAccount(id: id, name: name, institution: "Test Bank", type: type,
                   openingDate: openingDate, openingBalancePaise: opening)
    }

    private func txn(_ amount: Int64, _ type: FinTxnType, _ direction: FinDirection,
                     account: FinAccount, date: String = "2026-11-10",
                     category: String? = nil, merchant: String = "",
                     source: FinSource = .manual,
                     transferID: String? = nil,
                     principal: Int64? = nil, interest: Int64? = nil,
                     investmentID: String? = nil) -> FinTransaction {
        FinTransaction(date: date, amountPaise: amount, direction: direction,
                       type: type, accountID: account.id,
                       categoryID: category, merchant: merchant,
                       source: source, transferID: transferID,
                       investmentID: investmentID,
                       principalPaise: principal, interestPaise: interest)
    }

    private func emptyDoc(_ accounts: [FinAccount]) -> FinanceDocument {
        var doc = FinanceDocument()
        doc.settings.trackingStartDate = "2020-01-01"
        doc.accounts = accounts
        doc.categories = FinanceTaxonomy.defaultCategories()
        return doc
    }

    // MARK: Money

    func testMoneyParsingIsExactToPaise() {
        XCTAssertEqual(FinanceFormat.parsePaise("1,234.56"), 123_456)
        XCTAssertEqual(FinanceFormat.parsePaise("₹0.01"), 1)
        XCTAssertEqual(FinanceFormat.parsePaise("-0.01"), -1)
        XCTAssertEqual(FinanceFormat.parsePaise("1.999"), 200)
        XCTAssertNil(FinanceFormat.parsePaise(""))
        XCTAssertNil(FinanceFormat.parsePaise("not money"))
    }

    func testMoneyFormattingUsesIndianGroupingAndSign() {
        XCTAssertEqual(FinanceFormat.inr(12_450_000), "₹1,24,500")
        XCTAssertEqual(FinanceFormat.inr(-100, showSign: true), "−₹1")
    }

    // MARK: Classification

    func testInternalTransferIsNeitherIncomeNorExpense() {
        let a = account("A", opening: 1_000_00)
        let b = account("B")
        var doc = emptyDoc([a, b])
        let tid = "transfer-1"
        doc.transactions = [
            txn(400_00, .transfer, .outflow, account: a, transferID: tid),
            txn(400_00, .transfer, .inflow, account: b, transferID: tid),
        ]
        let totals = FinanceEngine.totals(doc, from: "2026-11-01", through: "2026-11-30")
        XCTAssertEqual(totals.incomePaise, 0)
        XCTAssertEqual(totals.expensePaise, 0)
        XCTAssertEqual(totals.transferPaise, 800_00)
    }

    func testCreditCardPurchaseCountsOnceAndPaymentIsNotExpense() {
        let bank = account("Bank", opening: 1_000_00)
        let card = account("Card", type: .creditCard)
        var doc = emptyDoc([bank, card])
        doc.transactions = [
            txn(500_00, .expense, .outflow, account: card, category: cat("expense.food")),
        ]
        var totals = FinanceEngine.totals(doc, from: "2026-11-01", through: "2026-11-30")
        XCTAssertEqual(totals.expensePaise, 500_00)
        XCTAssertEqual(FinanceEngine.accountBalance(doc, account: card).paise, -500_00)

        let tid = "card-payment"
        doc.transactions.append(txn(500_00, .transfer, .outflow, account: bank, transferID: tid))
        doc.transactions.append(txn(500_00, .transfer, .inflow, account: card, transferID: tid))
        totals = FinanceEngine.totals(doc, from: "2026-11-01", through: "2026-11-30")
        XCTAssertEqual(totals.expensePaise, 500_00, "Paying the card must not create a second expense")
        XCTAssertEqual(FinanceEngine.accountBalance(doc, account: bank).paise, 500_00)
        XCTAssertEqual(FinanceEngine.accountBalance(doc, account: card).paise, 0)
        XCTAssertEqual(FinanceEngine.totalLiabilities(doc), 0)
    }

    func testRefundReducesExpenseAndIsNeverIncome() {
        let a = account("Bank", opening: 2_000_00)
        var doc = emptyDoc([a])
        doc.transactions = [
            txn(1_000_00, .expense, .outflow, account: a, category: cat("expense.shopping")),
            txn(300_00, .refund, .inflow, account: a, category: cat("expense.shopping")),
        ]
        let totals = FinanceEngine.totals(doc, from: "2026-11-01", through: "2026-11-30")
        XCTAssertEqual(totals.incomePaise, 0)
        XCTAssertEqual(totals.expensePaise, 700_00)
        XCTAssertEqual(totals.refundPaise, 300_00)
    }

    func testLoanPrincipalIsNotExpenseButInterestIs() {
        let bank = account("Bank", opening: 2_000_00)
        var doc = emptyDoc([bank])
        let loan = FinLiability(name: "Education loan", kind: .educationLoan,
                                originalPrincipalPaise: 1_000_00,
                                outstandingPaise: 1_000_00, asOf: "2026-11-01")
        doc.liabilities = [loan]
        doc.transactions = [
            FinTransaction(date: "2026-11-07", amountPaise: 150_00, direction: .outflow,
                           type: .loanRepayment, accountID: bank.id,
                           categoryID: cat("expense.interest"), merchant: "EMI",
                           verification: .verified, liabilityID: loan.id,
                           principalPaise: 120_00, interestPaise: 30_00),
        ]
        let totals = FinanceEngine.totals(doc, from: "2026-11-01", through: "2026-11-30")
        XCTAssertEqual(totals.expensePaise, 30_00)
        XCTAssertEqual(totals.debtPrincipalPaise, 120_00)
        XCTAssertEqual(totals.debtInterestPaise, 30_00)
        XCTAssertEqual(FinanceEngine.liabilityOutstanding(doc, liability: loan, asOf: "2026-11-30"), 880_00)
    }

    func testInvestmentPurchaseIsCapitalNotSpendingAndAddsAnAsset() {
        let bank = account("Bank", opening: 500_00)
        var doc = emptyDoc([bank])
        let inv = FinInvestment(name: "Index fund", assetClass: .mutualFund,
                                investedPaise: 100_00, currentValuePaise: 120_00,
                                currentValueOn: "2026-11-01")
        doc.investments = [inv]
        doc.valuations = [FinValuation(investmentID: inv.id, date: "2026-11-01", valuePaise: 120_00)]
        doc.transactions = [
            txn(100_00, .investmentPurchase, .outflow, account: bank, investmentID: inv.id),
        ]
        let totals = FinanceEngine.totals(doc, from: "2026-11-01", through: "2026-11-30")
        XCTAssertEqual(totals.expensePaise, 0)
        XCTAssertEqual(totals.investmentPaise, 100_00)
        XCTAssertEqual(FinanceEngine.accountBalance(doc, account: bank).paise, 400_00)
        XCTAssertEqual(FinanceEngine.totalAssets(doc).paise, 520_00)
    }

    func testInternalTransferKeepsNetWorthUnchanged() {
        let a = account("A", opening: 1_000_00)
        let b = account("B")
        var doc = emptyDoc([a, b])
        let tid = "t1"
        doc.transactions = [
            txn(400_00, .transfer, .outflow, account: a, transferID: tid),
            txn(400_00, .transfer, .inflow, account: b, transferID: tid),
        ]
        XCTAssertEqual(FinanceEngine.netWorth(doc).paise, 1_000_00)
    }

    // MARK: Balances

    func testStatementAnchorCountsOnlyLaterTransactions() {
        var a = account("Bank", opening: 100_00, openingDate: "2026-01-01")
        a.statementBalancePaise = 500_00
        a.statementBalanceOn = "2026-10-31"
        var doc = emptyDoc([a])
        doc.transactions = [
            txn(999_00, .income, .inflow, account: a, date: "2026-09-01"),
            txn(50_00, .income, .inflow, account: a, date: "2026-11-05"),
            txn(20_00, .expense, .outflow, account: a, date: "2026-11-06"),
        ]
        XCTAssertEqual(FinanceEngine.accountBalance(doc, account: a, asOf: "2026-11-30").paise, 530_00)
        XCTAssertEqual(FinanceEngine.accountBalance(doc, account: a, asOf: "2026-11-30").certainty, .calculated)
    }

    func testHistoricalBalanceBeforeAnchorUsesOpeningPosition() {
        var a = account("Bank", opening: 100_00, openingDate: "2026-01-01")
        a.statementBalancePaise = 500_00
        a.statementBalanceOn = "2026-10-31"
        var doc = emptyDoc([a])
        doc.transactions = [
            txn(50_00, .income, .inflow, account: a, date: "2026-05-01"),
        ]
        XCTAssertEqual(FinanceEngine.accountBalance(doc, account: a, asOf: "2026-06-30").paise, 150_00)
    }

    func testInvestmentValueDoesNotLeakFutureValuationBackwards() {
        let inv = FinInvestment(name: "Fund", assetClass: .mutualFund,
                                purchaseDate: "2025-01-01",
                                investedPaise: 100_00, currentValuePaise: 200_00,
                                currentValueOn: "2026-11-01")
        var doc = emptyDoc([])
        doc.investments = [inv]
        let value = FinanceEngine.investmentValue(doc, investment: inv, asOf: "2025-06-01")
        XCTAssertEqual(value.paise, 100_00)
        XCTAssertEqual(value.certainty, .estimated)
    }

    func testCarriedForwardValuationIsMarkedEstimated() {
        let inv = FinInvestment(name: "Fund", assetClass: .mutualFund,
                                purchaseDate: "2025-01-01",
                                investedPaise: 100_00, currentValuePaise: 100_00,
                                currentValueOn: "2025-01-01")
        var doc = emptyDoc([])
        doc.investments = [inv]
        doc.valuations = [FinValuation(investmentID: inv.id, date: "2025-01-01", valuePaise: 120_00)]
        let value = FinanceEngine.investmentValue(doc, investment: inv, asOf: "2026-01-31")
        XCTAssertEqual(value.paise, 120_00)
        XCTAssertEqual(value.certainty, .estimated)
    }

    func testReconciliationUsesTheStatedOpeningAndFlagsAMismatch() {
        let a = account("Bank", opening: 1_000_00, openingDate: "2026-10-01")
        var doc = emptyDoc([a])
        doc.transactions = [
            txn(500_00, .income, .inflow, account: a, date: "2026-10-10"),
        ]
        let computed = FinanceEngine.statementClosing(doc, account: a,
                                                      periodStart: "2026-10-01",
                                                      periodEnd: "2026-10-31",
                                                      openingPaise: 1_000_00)
        XCTAssertEqual(computed, 1_500_00)

        let recon = FinReconciliation(accountID: a.id, periodStart: "2026-10-01",
                                      periodEnd: "2026-10-31",
                                      openingPaise: 900_00,
                                      expectedOpeningPaise: 1_000_00,
                                      closingPaise: 1_500_00,
                                      computedClosingPaise: computed,
                                      status: .mismatch)
        doc.reconciliations = [recon]
        XCTAssertEqual(FinanceEngine.openingMismatch(recon), -100_00)
        XCTAssertTrue(FinanceEngine.integrityIssues(doc, asOf: today).contains { $0.kind == .openingMismatch })
    }

    func testCreditCardStatementClosingIsPositiveDebt() {
        let card = account("Card", type: .creditCard)
        var doc = emptyDoc([card])
        doc.transactions = [
            txn(500_00, .expense, .outflow, account: card, date: "2026-10-05"),
            txn(100_00, .transfer, .inflow, account: card, date: "2026-10-20", transferID: "pay"),
        ]
        let closing = FinanceEngine.statementClosing(doc, account: card,
                                                     periodStart: "2026-10-01",
                                                     periodEnd: "2026-10-31",
                                                     openingPaise: 200_00)
        XCTAssertEqual(closing, 600_00)
    }

    // MARK: Budgets and goals

    func testBudgetActualIsNetOfRefundsAndExcludesTransfers() {
        let a = account("Bank", opening: 10_000_00)
        var doc = emptyDoc([a])
        let food = cat("expense.food")
        doc.budgets = [FinBudget(name: "Food", categoryID: food, startDate: "2026-11-01",
                                 plannedPaise: 1_000_00)]
        doc.transactions = [
            txn(800_00, .expense, .outflow, account: a, date: "2026-11-05", category: food),
            txn(200_00, .refund, .inflow, account: a, date: "2026-11-07", category: food),
            txn(300_00, .transfer, .outflow, account: a, date: "2026-11-08"),
        ]
        let status = FinanceEngine.budgetStatuses(doc, on: "2026-11-20").first
        XCTAssertEqual(status?.actualPaise, 600_00)
        XCTAssertEqual(status?.remainingPaise, 400_00)
        XCTAssertEqual(status?.progress ?? 0, 0.6, accuracy: 0.0001)
    }

    // MARK: Integrity

    func testDuplicateDetectionGroupsSameAccountDateAmountAndPayee() {
        let a = account("Bank", opening: 10_000_00)
        var doc = emptyDoc([a])
        doc.transactions = [
            txn(500_00, .expense, .outflow, account: a, merchant: "Cafe"),
            txn(500_00, .expense, .outflow, account: a, merchant: "Cafe"),
            txn(500_00, .expense, .outflow, account: a, merchant: "Shop"),
        ]
        let groups = FinanceEngine.duplicateGroups(doc)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.transactions.count, 2)
    }

    func testTransferCandidatesPairOppositeEqualMovements() {
        let a = account("A", opening: 1_000_00)
        let b = account("B")
        var doc = emptyDoc([a, b])
        doc.transactions = [
            txn(250_00, .expense, .outflow, account: a, date: "2026-11-01", merchant: "Transfer"),
            txn(250_00, .income, .inflow, account: b, date: "2026-11-02", merchant: "Transfer"),
        ]
        let candidates = FinanceEngine.transferCandidates(doc)
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.dayGap, 1)
    }

    func testIntegrityFlagsUncategorisedAndInvalidDate() {
        let a = account("Bank", opening: 1_000_00)
        var doc = emptyDoc([a])
        doc.transactions = [
            txn(100_00, .expense, .outflow, account: a, category: nil),
            txn(200_00, .income, .inflow, account: a, date: "2027-12-01"),
        ]
        let issues = FinanceEngine.integrityIssues(doc, asOf: today)
        XCTAssertTrue(issues.contains { $0.kind == .uncategorised })
        XCTAssertTrue(issues.contains { $0.kind == .invalidDate })
    }

    // MARK: Net worth and liabilities

    func testNetWorthHistorySkipsEmptyMonthsAndLabelsCertainty() {
        let a = account("Bank", opening: 100_00, openingDate: "2026-01-01")
        var doc = emptyDoc([a])
        doc.transactions = [
            txn(50_00, .income, .inflow, account: a, date: "2026-08-01", category: cat("income.salary")),
        ]
        let history = FinanceEngine.netWorthHistory(doc, from: "2026-01-01", through: "2026-11-30")
        XCTAssertFalse(history.isEmpty)
        XCTAssertLessThanOrEqual(history.count, 11)
        XCTAssertTrue(history.allSatisfy { ["verified", "calculated", "estimated", "unknown"].contains($0.certainty.rawValue) })
    }

    func testHouseholdDebtIsExcludedUnlessOptedIn() {
        let a = account("Bank", opening: 5_000_00)
        var doc = emptyDoc([a])
        doc.liabilities = [
            FinLiability(name: "Personal", kind: .personalLoan, ownership: .personal,
                         originalPrincipalPaise: 1_000_00, outstandingPaise: 1_000_00, asOf: "2026-01-01"),
            FinLiability(name: "Family", kind: .homeLoan, ownership: .household,
                         originalPrincipalPaise: 9_000_00, outstandingPaise: 9_000_00, asOf: "2026-01-01"),
        ]
        XCTAssertEqual(FinanceEngine.totalLiabilities(doc), 1_000_00)
        doc.settings.includeHouseholdInNetWorth = true
        XCTAssertEqual(FinanceEngine.totalLiabilities(doc), 10_000_00)
    }

    func testVerifiedSnapshotBecomesADatedNetWorthPoint() {
        let a = account("Bank", opening: 1_000_00, openingDate: "2026-01-01")
        var doc = emptyDoc([a])
        doc.transactions = [txn(100_00, .income, .inflow, account: a, date: "2026-05-01", category: cat("income.salary"))]
        doc.snapshots = [FinSnapshot(date: "2026-05-15", netWorthPaise: 1_100_00,
                                     assetsPaise: 1_100_00, liabilitiesPaise: 0,
                                     certainty: .verified, note: "Checked against the bank")]
        let history = FinanceEngine.netWorthHistory(doc, from: "2026-01-01", through: "2026-06-30")
        XCTAssertTrue(history.contains { $0.date == "2026-05-15" && $0.certainty == .verified && $0.netPaise == 1_100_00 })
    }

    func testSavingsRateIsNilWhenThereIsNoIncome() {
        let a = account("Bank", opening: 1_000_00)
        var doc = emptyDoc([a])
        doc.transactions = [txn(100_00, .expense, .outflow, account: a)]
        let totals = FinanceEngine.totals(doc, from: "2026-11-01", through: "2026-11-30")
        XCTAssertNil(totals.savingsRate)
    }

    // MARK: Tax and exports

    func testFinancialYearRunsAprilToMarch() {
        let fy = FinanceCal.financialYear(containing: "2026-05-15")
        XCTAssertEqual(fy.start, "2026-04-01")
        XCTAssertEqual(fy.end, "2027-03-31")
        let earlier = FinanceCal.financialYear(containing: "2026-02-15")
        XCTAssertEqual(earlier.start, "2025-04-01")
        XCTAssertEqual(earlier.end, "2026-03-31")
    }

    func testTaxSummarySplitsSalaryAndRecordedCapitalGains() {
        let a = account("Bank", opening: 0)
        var doc = emptyDoc([a])
        doc.transactions = [
            txn(10_000_00, .income, .inflow, account: a, date: "2026-05-01", category: cat("income.salary")),
            txn(500_00, .income, .inflow, account: a, date: "2026-06-01", category: cat("income.dividend")),
            FinTransaction(date: "2026-07-01", amountPaise: 2_000_00, direction: .inflow,
                           type: .investmentSale, accountID: a.id,
                           costBasisPaise: 1_500_00, realisedGainPaise: 500_00),
        ]
        let tax = FinanceEngine.taxSummary(doc, fyContaining: "2026-05-15")
        XCTAssertEqual(tax.salaryPaise, 10_000_00)
        XCTAssertEqual(tax.dividendPaise, 500_00)
        XCTAssertEqual(tax.capitalGainsPaise, 500_00)
        XCTAssertEqual(tax.recordedSaleProceedsPaise, 2_000_00)
    }

    func testCSVExportEscapesCommasAndQuotes() {
        let a = account("Bank")
        var doc = emptyDoc([a])
        doc.transactions = [
            txn(100_00, .expense, .outflow, account: a, merchant: "Shop, \"Main\""),
        ]
        let csv = FinanceEngine.transactionsCSV(doc.transactions, doc: doc)
        XCTAssertTrue(csv.contains("\"Shop, \"\"Main\"\"\""))
    }

    // MARK: Demo data

    func testDemoDataIsClearlyFlaggedAndHasRealHistory() {
        let doc = FinanceDemo.build(today: today)
        XCTAssertTrue(doc.settings.demoMode)
        XCTAssertFalse(doc.accounts.isEmpty)
        XCTAssertTrue(doc.accounts.allSatisfy(\.isDemo))
        XCTAssertTrue(doc.transactions.allSatisfy(\.isDemo))
        XCTAssertGreaterThan(doc.transactions.count, 100)
        XCTAssertFalse(doc.investments.isEmpty)
        XCTAssertTrue(doc.investments.allSatisfy(\.isDemo))
        XCTAssertGreaterThan(FinanceEngine.netWorth(doc, asOf: today).paise, 0)
        XCTAssertGreaterThan(FinanceEngine.totalLiabilities(doc, asOf: today), 0)
        XCTAssertGreaterThan(FinanceEngine.totals(doc, from: "2025-04-01", through: today).incomePaise, 0)
        XCTAssertTrue(doc.transfers.allSatisfy(\.isDemo))
    }

    func testDemoIncludesCreditCardPurchasesAndSettlementTransfers() {
        let doc = FinanceDemo.build(today: today)
        XCTAssertTrue(doc.transactions.contains { $0.type == .expense && $0.accountID == FinID.stable("demo.account.card") })
        XCTAssertTrue(doc.transactions.contains { $0.type == .transfer && $0.transferAccountID == FinID.stable("demo.account.card") })
        let card = doc.accounts.first { $0.id == FinID.stable("demo.account.card") }!
        let balance = FinanceEngine.accountBalance(doc, account: card, asOf: today).paise
        XCTAssertLessThanOrEqual(balance, 0, "A credit card balance is signed as debt")
    }

    func testDemoDocumentRoundTripsAndFitsTheStateLimit() throws {
        let doc = FinanceDemo.build(today: today)
        let data = try JSONEncoder().encode(doc)
        print("FINANCE_DOCUMENT_BYTES", data.count)
        XCTAssertLessThan(data.count, 1_900_000, "The synced module must stay under D1/API's 1.9 MB ceiling")
        let decoded = try JSONDecoder().decode(FinanceDocument.self, from: data)
        XCTAssertEqual(decoded.accounts.count, doc.accounts.count)
        XCTAssertEqual(decoded.transactions.count, doc.transactions.count)
        XCTAssertEqual(decoded.audit.count, doc.audit.count)
        XCTAssertTrue(decoded.settings.demoMode)
    }

    func testDemoNetWorthHistoryHasCertaintyLabels() {
        let doc = FinanceDemo.build(today: today)
        let history = FinanceEngine.netWorthHistory(doc, from: "2025-01-01", through: today)
        XCTAssertGreaterThan(history.count, 6)
        XCTAssertTrue(history.contains { $0.certainty == .verified || $0.certainty == .calculated || $0.certainty == .estimated })
    }
}
