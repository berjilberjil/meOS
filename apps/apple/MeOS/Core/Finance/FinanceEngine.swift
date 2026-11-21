import Foundation

// MARK: - Finance calculation engine
//
// Every number the interface shows comes from here. Nothing in this file
// mutates a document, writes a derived value back, or invents a figure to fill
// a chart. Where a value is carried forward rather than observed, the result
// says so through `FinCertainty`.

// MARK: Result types

struct FinAmount: Hashable {
    var paise: Int64
    var certainty: FinCertainty

    static let zero = FinAmount(paise: 0, certainty: .calculated)

    var isPositive: Bool { paise > 0 }
    var isNegative: Bool { paise < 0 }
}

struct FinPeriodTotals: Hashable {
    var incomePaise: Int64 = 0
    var expensePaise: Int64 = 0
    var refundPaise: Int64 = 0
    var investmentPaise: Int64 = 0
    var debtPrincipalPaise: Int64 = 0
    var debtInterestPaise: Int64 = 0
    var transferPaise: Int64 = 0
    var transactionCount: Int = 0

    /// Ordinary income minus ordinary expenditure. Investing and principal
    /// repayment move money between buckets; they are not spending.
    var netSavingsPaise: Int64 { incomePaise - expensePaise }
    var savingsRate: Double? {
        guard incomePaise > 0 else { return nil }
        return Double(netSavingsPaise) / Double(incomePaise) * 100
    }
}

struct FinMonthPoint: Identifiable, Hashable {
    var id: String { month }
    var month: String          // yyyy-MM-dd, first of month
    var incomePaise: Int64
    var expensePaise: Int64
    var netPaise: Int64
    var certainty: FinCertainty
}

struct FinNetWorthPoint: Identifiable, Hashable {
    var id: String { date }
    var date: String
    var assetsPaise: Int64
    var liabilitiesPaise: Int64
    var netPaise: Int64
    var certainty: FinCertainty
}

struct FinCategorySlice: Identifiable, Hashable {
    var id: String { categoryID }
    var categoryID: String
    var name: String
    var group: String
    var icon: String
    var paise: Int64
    var count: Int
    var share: Double
}

struct FinMerchantSlice: Identifiable, Hashable {
    var id: String { merchant }
    var merchant: String
    var paise: Int64
    var count: Int
}

struct FinAllocationSlice: Identifiable, Hashable {
    var id: String { assetClass.rawValue }
    var assetClass: FinAssetClass
    var paise: Int64
    var share: Double
}

struct FinAccountSummary: Identifiable, Hashable {
    var id: String { account.id }
    var account: FinAccount
    var balance: FinAmount
    var availablePaise: Int64?
    var transactionCount: Int
    var lastActivity: String?
}

struct FinInvestmentSummary: Identifiable, Hashable {
    var id: String { investment.id }
    var investment: FinInvestment
    var valuePaise: Int64
    var investedPaise: Int64
    var unrealisedPaise: Int64
    var returnPercent: Double?
    var certainty: FinCertainty
    var holdingAgeDays: Int?
}

struct FinLiabilitySummary: Identifiable, Hashable {
    var id: String { liability.id }
    var liability: FinLiability
    var outstandingPaise: Int64
    var paidPrincipalPaise: Int64
    var paidInterestPaise: Int64
    var progress: Double
    var tenureMonthsLeft: Int?
}

struct FinBudgetStatus: Identifiable, Hashable {
    var id: String { budget.id }
    var budget: FinBudget
    var actualPaise: Int64
    var remainingPaise: Int64
    var progress: Double
    var variancePaise: Int64
    var categoryName: String
    var range: (start: String, end: String)

    static func == (a: FinBudgetStatus, b: FinBudgetStatus) -> Bool {
        a.budget == b.budget && a.actualPaise == b.actualPaise
            && a.range.start == b.range.start && a.range.end == b.range.end
    }
    func hash(into h: inout Hasher) {
        h.combine(budget); h.combine(actualPaise); h.combine(range.start); h.combine(range.end)
    }
}

struct FinGoalStatus: Identifiable, Hashable {
    var id: String { goal.id }
    var goal: FinGoal
    var progress: Double
    var remainingPaise: Int64
    var monthsLeft: Int?
    var requiredMonthlyPaise: Int64?
    var onTrack: Bool?
}

struct FinUpcomingPayment: Identifiable, Hashable {
    var id: String
    var title: String
    var date: String
    var amountPaise: Int64
    var kind: FinRecurringKind
    var accountID: String?
    var sourceID: String?
    var certainty: FinCertainty

    var daysAway: Int { FinanceCal.daysBetween(FinanceCal.today(), date) }
}

enum FinInsightTone: String, Hashable {
    case positive, negative, neutral, information
}

struct FinInsight: Identifiable, Hashable {
    var id: String
    var title: String
    var detail: String
    var tone: FinInsightTone
    var symbol: String
}

enum FinIntegrityKind: String, CaseIterable, Identifiable, Hashable {
    case duplicate, uncategorised, unmatchedTransfer, unreconciled
    case openingMismatch, closingMismatch, missingReference, invalidDate
    case suspiciousAmount, correction, unverified

    var id: String { rawValue }
    var label: String {
        switch self {
        case .duplicate: "Duplicate candidates"
        case .uncategorised: "Uncategorised entries"
        case .unmatchedTransfer: "Unmatched transfers"
        case .unreconciled: "Unreconciled statements"
        case .openingMismatch: "Opening balance mismatches"
        case .closingMismatch: "Closing balance mismatches"
        case .missingReference: "Missing references"
        case .invalidDate: "Invalid dates"
        case .suspiciousAmount: "Suspicious amount changes"
        case .correction: "Manual corrections"
        case .unverified: "Unverified transactions"
        }
    }
    var symbol: String {
        switch self {
        case .duplicate: "doc.on.doc"
        case .uncategorised: "tag.slash"
        case .unmatchedTransfer: "arrow.left.arrow.right"
        case .unreconciled: "checklist.unchecked"
        case .openingMismatch: "equal.circle"
        case .closingMismatch: "exclamationmark.triangle"
        case .missingReference: "number"
        case .invalidDate: "calendar.badge.exclamationmark"
        case .suspiciousAmount: "magnifyingglass"
        case .correction: "pencil.and.list.clipboard"
        case .unverified: "questionmark.circle"
        }
    }
}

struct FinIntegrityIssue: Identifiable, Hashable {
    var id: String
    var kind: FinIntegrityKind
    var title: String
    var detail: String
    var severity: Int          // 0 = info, 1 = review, 2 = broken
    var transactionIDs: [String] = []
    var accountID: String?
}

struct FinDuplicateGroup: Identifiable, Hashable {
    var id: String { transactions.map(\.id).joined(separator: "-") }
    var transactions: [FinTransaction]
    var reason: String
}

struct FinTransferCandidate: Identifiable, Hashable {
    var id: String { from.id + "|" + to.id }
    var from: FinTransaction
    var to: FinTransaction
    var dayGap: Int
}

struct FinTimelineEntry: Identifiable, Hashable {
    var id: String
    var date: String
    var title: String
    var detail: String
    var kind: FinMilestoneKind
    var certainty: FinCertainty
    var amountPaise: Int64?
    var isAutomatic: Bool
    var transactionID: String?
}

struct FinTaxSummary: Hashable {
    var fyLabel: String
    var start: String
    var end: String
    var salaryPaise: Int64
    var freelancePaise: Int64
    var businessPaise: Int64
    var interestPaise: Int64
    var dividendPaise: Int64
    var otherIncomePaise: Int64
    var taxPaidPaise: Int64
    var taxExpensesPaise: Int64
    var capitalGainsPaise: Int64
    var recordedSaleProceedsPaise: Int64

    var totalIncomePaise: Int64 {
        salaryPaise + freelancePaise + businessPaise + interestPaise + dividendPaise + otherIncomePaise
    }
}

enum FinRangePreset: String, CaseIterable, Identifiable {
    case m1 = "1M", m3 = "3M", m6 = "6M", y1 = "1Y", y3 = "3Y", y5 = "5Y", all = "ALL", custom = "Custom"
    var id: String { rawValue }
    var label: String { rawValue }
    var months: Int? {
        switch self {
        case .m1: 1
        case .m3: 3
        case .m6: 6
        case .y1: 12
        case .y3: 36
        case .y5: 60
        case .all, .custom: nil
        }
    }
}

// MARK: Engine

enum FinanceEngine {

    // MARK: Scope and primitives

    static func transactions(_ doc: FinanceDocument,
                             from start: String? = nil,
                             through end: String? = nil,
                             accountID: String? = nil) -> [FinTransaction] {
        doc.transactions.filter { t in
            if let start, t.date < start { return false }
            if let end, t.date > end { return false }
            if let accountID {
                let touches = t.accountID == accountID || t.transferAccountID == accountID
                if !touches { return false }
            }
            return true
        }
    }

    static func isIncome(_ t: FinTransaction) -> Bool {
        guard t.direction == .inflow else { return false }
        switch t.type {
        case .income, .interest, .dividend: return true
        default: return false
        }
    }

    static func isExpense(_ t: FinTransaction) -> Bool {
        switch t.type {
        case .expense, .fee, .tax:
            return true
        case .interest:
            return t.direction == .outflow
        case .loanRepayment:
            return (t.interestPaise ?? 0) > 0
        default:
            return false
        }
    }

    /// The part of a transaction that belongs to ordinary expenditure.
    static func expenseAmount(_ t: FinTransaction) -> Int64 {
        guard isExpense(t) else { return 0 }
        if t.type == .loanRepayment { return t.interestPaise ?? 0 }
        return t.amountPaise
    }

    static func isRefund(_ t: FinTransaction) -> Bool { t.type == .refund }

    /// An internal transfer is neither income nor expenditure.
    static func isInternalTransfer(_ t: FinTransaction) -> Bool {
        t.type == .transfer || t.transferID != nil
    }

    static func isInvestmentFlow(_ t: FinTransaction) -> Bool {
        t.type == .investmentPurchase || t.type == .investmentSale
    }

    static func isDebtFlow(_ t: FinTransaction) -> Bool {
        t.type == .loanDisbursement || t.type == .loanRepayment
    }

    static func accountTransactions(_ doc: FinanceDocument, accountID: String) -> [FinTransaction] {
        doc.transactions
            .filter { $0.accountID == accountID || $0.transferAccountID == accountID }
            .sorted { $0.date > $1.date }
    }

    // MARK: Account balances

    /// The signed balance: assets positive, credit-card debt negative. The
    /// anchor is the latest statement balance (or the opening balance), so a
    /// transaction is counted exactly once.
    static func accountBalance(_ doc: FinanceDocument,
                               account: FinAccount,
                               asOf: String = FinanceCal.today()) -> FinAmount {
        if asOf < account.openingDate {
            return FinAmount(paise: 0, certainty: .calculated)
        }
        let anchorDate = account.anchorDate
        let asOfIsBeforeAnchor = asOf < anchorDate
        let baseDate = asOfIsBeforeAnchor ? account.openingDate : anchorDate
        let basePaise = asOfIsBeforeAnchor ? account.openingBalancePaise : account.anchorBalancePaise
        var flow: Int64 = 0
        var sawImported = false
        for t in doc.transactions where t.date > baseDate && t.date <= asOf {
            if t.accountID == account.id {
                // A credit card is a liability: an outflow increases what is
                // owed, so the sign of the movement is reversed for its debt.
                flow += account.type.isLiability ? -t.signedPaise : t.signedPaise
                if t.source == .imported { sawImported = true }
            } else if t.transferID == nil, t.transferAccountID == account.id {
                // Legacy single-row transfer: the destination is named on the
                // same row. Paired transfers carry `transferID` and already
                // have their own destination row, so counting this branch too
                // would double the movement.
                flow += account.type.isLiability ? -t.amountPaise : t.amountPaise
                if t.source == .imported { sawImported = true }
            }
        }
        let raw = basePaise + flow
        let signed = account.type.isLiability ? -raw : raw
        let certainty: FinCertainty
        if account.statementBalanceOn != nil && flow == 0 {
            certainty = .verified
        } else if sawImported {
            certainty = .calculated
        } else if doc.transactions.contains(where: { $0.accountID == account.id || $0.transferAccountID == account.id }) {
            certainty = .calculated
        } else {
            certainty = .calculated
        }
        return FinAmount(paise: signed, certainty: certainty)
    }

    static func accountSummaries(_ doc: FinanceDocument, asOf: String = FinanceCal.today()) -> [FinAccountSummary] {
        doc.accounts
            .filter { $0.status != .closed }
            .map { a in
                let txns = accountTransactions(doc, accountID: a.id)
                var available: Int64? = nil
                if let limit = a.creditLimitPaise {
                    let debt = max(0, -accountBalance(doc, account: a, asOf: asOf).paise)
                    available = max(0, limit - debt)
                }
                return FinAccountSummary(account: a,
                                         balance: accountBalance(doc, account: a, asOf: asOf),
                                         availablePaise: available,
                                         transactionCount: txns.count,
                                         lastActivity: txns.first?.date)
            }
            .sorted {
                if $0.account.status != $1.account.status { return $0.account.status == .active }
                if $0.account.type != $1.account.type { return $0.account.type.rawValue < $1.account.type.rawValue }
                return abs($0.balance.paise) > abs($1.balance.paise)
            }
    }

    /// A statement-facing balance: debt is positive for a credit card.
    static func statementBalance(_ doc: FinanceDocument, account: FinAccount, asOf: String) -> Int64 {
        let balance = accountBalance(doc, account: account, asOf: asOf).paise
        return account.type.isLiability ? abs(balance) : balance
    }

    /// The closing implied by a stated opening and the transactions between
    /// the period boundaries. This is what reconciliation compares with the
    /// bank's number.
    static func statementClosing(_ doc: FinanceDocument,
                                 account: FinAccount,
                                 periodStart: String,
                                 periodEnd: String,
                                 openingPaise: Int64) -> Int64 {
        var signedFlow: Int64 = 0
        for t in doc.transactions where t.date > periodStart && t.date <= periodEnd {
            if t.accountID == account.id {
                signedFlow += t.signedPaise
            } else if t.transferID == nil, t.transferAccountID == account.id {
                signedFlow += t.amountPaise
            }
        }
        let delta = account.type.isLiability ? -signedFlow : signedFlow
        return openingPaise + delta
    }

    static func openingMismatch(_ recon: FinReconciliation) -> Int64? {
        guard let expected = recon.expectedOpeningPaise else { return nil }
        let delta = recon.openingPaise - expected
        return delta == 0 ? nil : delta
    }

    // MARK: Period totals

    static func totals(_ doc: FinanceDocument, from start: String, through end: String,
                       accountID: String? = nil) -> FinPeriodTotals {
        var out = FinPeriodTotals()
        for t in doc.transactions where t.date >= start && t.date <= end {
            if let accountID, t.accountID != accountID && t.transferAccountID != accountID { continue }
            out.transactionCount += 1
            if isIncome(t) {
                out.incomePaise += t.amountPaise
                continue
            }
            if isRefund(t) {
                out.refundPaise += t.amountPaise
                continue
            }
            if isInternalTransfer(t) {
                out.transferPaise += t.amountPaise
                continue
            }
            if isInvestmentFlow(t) {
                if t.direction == .outflow { out.investmentPaise += t.amountPaise }
                continue
            }
            if t.type == .loanRepayment {
                let principal = t.principalPaise ?? max(0, t.amountPaise - (t.interestPaise ?? 0))
                let interest = t.interestPaise ?? 0
                out.debtPrincipalPaise += principal
                out.debtInterestPaise += interest
                // Only the interest portion is ordinary expenditure. The
                // principal reduces a liability and is not spending.
                out.expensePaise += interest
                continue
            }
            if t.type == .loanDisbursement { continue }
            if isExpense(t) {
                out.expensePaise += expenseAmount(t)
            }
        }
        out.expensePaise = max(0, out.expensePaise - out.refundPaise)
        return out
    }

    static func monthTotals(_ doc: FinanceDocument, monthContaining key: String) -> FinPeriodTotals {
        let start = FinanceCal.monthStart(key)
        let end = FinanceCal.monthEnd(key)
        return totals(doc, from: start, through: end)
    }

    static func yearTotals(_ doc: FinanceDocument, year: Int) -> FinPeriodTotals {
        totals(doc, from: "\(year)-01-01", through: "\(year)-12-31")
    }

    static func previousMonthKey(_ key: String = FinanceCal.today()) -> String {
        FinanceCal.monthStart(FinanceCal.addMonths(-1, to: key))
    }

    static func comparison(_ current: Int64, _ previous: Int64) -> Double? {
        guard previous != 0 else { return nil }
        return Double(current - previous) / Double(abs(previous)) * 100
    }

    /// The three comparisons the overview asks for.
    static func periodComparisons(_ doc: FinanceDocument, asOf: String = FinanceCal.today())
        -> (month: FinPeriodTotals, prevMonth: FinPeriodTotals, prevQuarter: FinPeriodTotals, prevYear: FinPeriodTotals) {
        let cur = monthTotals(doc, monthContaining: asOf)
        let prevM = monthTotals(doc, monthContaining: previousMonthKey(asOf))
        let qStart = FinanceCal.addMonths(-3, to: FinanceCal.monthStart(asOf))
        let prevQ = totals(doc, from: qStart, through: FinanceCal.addDays(-1, to: FinanceCal.monthStart(asOf)))
        let prevYStart = FinanceCal.addYears(-1, to: FinanceCal.monthStart(asOf))
        let prevY = totals(doc, from: prevYStart, through: FinanceCal.addDays(-1, to: FinanceCal.monthStart(asOf)))
        return (cur, prevM, prevQ, prevY)
    }

    // MARK: Categories and merchants

    static func expenseByCategory(_ doc: FinanceDocument, from start: String, through end: String) -> [FinCategorySlice] {
        var sums: [String: Int64] = [:]
        var counts: [String: Int] = [:]
        var refunds: [String: Int64] = [:]

        for t in doc.transactions where t.date >= start && t.date <= end {
            if isExpense(t) {
                let id = t.categoryID ?? FinanceTaxonomy.defaultExpenseCategoryID()
                sums[id, default: 0] += expenseAmount(t)
                counts[id, default: 0] += 1
            } else if isRefund(t) {
                if let id = t.categoryID { refunds[id, default: 0] += t.amountPaise }
            }
        }
        for (id, value) in refunds {
            sums[id] = max(0, (sums[id] ?? 0) - value)
        }
        let total = sums.values.reduce(0, +)
        return sums.map { id, value in
            let cat = doc.category(id)
            return FinCategorySlice(categoryID: id,
                                    name: cat?.name ?? "Uncategorised",
                                    group: cat?.group ?? "Other",
                                    icon: cat?.icon ?? "questionmark.circle",
                                    paise: value,
                                    count: counts[id] ?? 0,
                                    share: total > 0 ? Double(value) / Double(total) * 100 : 0)
        }
        .filter { $0.paise > 0 }
        .sorted { $0.paise > $1.paise }
    }

    static func incomeByCategory(_ doc: FinanceDocument, from start: String, through end: String) -> [FinCategorySlice] {
        var sums: [String: Int64] = [:]
        var counts: [String: Int] = [:]
        for t in doc.transactions where t.date >= start && t.date <= end && isIncome(t) {
            let id = t.categoryID ?? FinanceTaxonomy.defaultIncomeCategoryID()
            sums[id, default: 0] += t.amountPaise
            counts[id, default: 0] += 1
        }
        let total = sums.values.reduce(0, +)
        return sums.map { id, value in
            let cat = doc.category(id)
            return FinCategorySlice(categoryID: id,
                                    name: cat?.name ?? "Other income",
                                    group: cat?.group ?? "Other",
                                    icon: cat?.icon ?? "plus.circle",
                                    paise: value,
                                    count: counts[id] ?? 0,
                                    share: total > 0 ? Double(value) / Double(total) * 100 : 0)
        }
        .sorted { $0.paise > $1.paise }
    }

    static func merchantBreakdown(_ doc: FinanceDocument, from start: String, through end: String) -> [FinMerchantSlice] {
        var sums: [String: Int64] = [:]
        var counts: [String: Int] = [:]
        for t in doc.transactions where t.date >= start && t.date <= end && isExpense(t) {
            let name = t.merchant.isEmpty ? (doc.category(t.categoryID)?.name ?? "Unknown merchant") : t.merchant
            sums[name, default: 0] += expenseAmount(t)
            counts[name, default: 0] += 1
        }
        return sums.map { FinMerchantSlice(merchant: $0.key, paise: $0.value, count: counts[$0.key] ?? 0) }
            .sorted { $0.paise > $1.paise }
    }

    static func monthlyCashflow(_ doc: FinanceDocument, months: [String]) -> [FinMonthPoint] {
        months.map { end in
            let start = FinanceCal.monthStart(end)
            let totals = totals(doc, from: start, through: FinanceCal.monthEnd(end))
            let certainty: FinCertainty = doc.transactions.contains(where: { $0.date >= start && $0.date <= FinanceCal.monthEnd(end) }) ? .calculated : .unknown
            return FinMonthPoint(month: start,
                                 incomePaise: totals.incomePaise,
                                 expensePaise: totals.expensePaise,
                                 netPaise: totals.netSavingsPaise,
                                 certainty: certainty)
        }
    }

    // MARK: Investments

    static func latestValuation(_ doc: FinanceDocument, investmentID: String, onOrBefore date: String) -> FinValuation? {
        doc.valuations
            .filter { $0.investmentID == investmentID && $0.date <= date }
            .max { $0.date < $1.date }
    }

    /// Current portfolio value. A valuation recorded on the date is verified;
    /// one carried forward is explicitly estimated.
    static func investmentValue(_ doc: FinanceDocument, investment: FinInvestment, asOf: String = FinanceCal.today()) -> FinAmount {
        if let v = latestValuation(doc, investmentID: investment.id, onOrBefore: asOf) {
            let certainty: FinCertainty = v.date == asOf ? .verified : .estimated
            return FinAmount(paise: v.valuePaise, certainty: certainty)
        }
        guard investment.purchaseDate == nil || investment.purchaseDate! <= asOf else {
            return FinAmount(paise: 0, certainty: .verified)
        }
        // A value observed after `asOf` cannot be used in the past. Fall back
        // to the recorded cost basis and label it estimated, rather than
        // pretending a later market value existed earlier.
        if investment.currentValueOn > asOf {
            return FinAmount(paise: investment.investedPaise, certainty: .estimated)
        }
        let stale = FinanceCal.daysBetween(investment.currentValueOn, asOf) > 45
        return FinAmount(paise: investment.currentValuePaise, certainty: stale ? .estimated : .calculated)
    }

    static func investmentSummaries(_ doc: FinanceDocument, asOf: String = FinanceCal.today()) -> [FinInvestmentSummary] {
        doc.investments
            .filter { !$0.archived }
            .map { inv in
                let value = investmentValue(doc, investment: inv, asOf: asOf)
                let invested = max(0, inv.investedPaise)
                let gain = value.paise - invested
                let pct = invested > 0 ? Double(gain) / Double(invested) * 100 : nil
                let since = inv.purchaseDate ?? String(inv.createdAt.prefix(10))
                return FinInvestmentSummary(investment: inv,
                                            valuePaise: value.paise,
                                            investedPaise: invested,
                                            unrealisedPaise: gain,
                                            returnPercent: pct,
                                            certainty: value.certainty,
                                            holdingAgeDays: FinanceCal.daysBetween(since, asOf))
            }
            .sorted { $0.valuePaise > $1.valuePaise }
    }

    static func portfolio(_ doc: FinanceDocument, asOf: String = FinanceCal.today())
        -> (value: Int64, invested: Int64, unrealised: Int64, certainty: FinCertainty, allocation: [FinAllocationSlice]) {
        let summaries = investmentSummaries(doc, asOf: asOf)
        let value = summaries.reduce(0) { $0 + $1.valuePaise }
        let invested = summaries.reduce(0) { $0 + $1.investedPaise }
        let certainty = summaries.isEmpty ? FinCertainty.unknown : FinCertainty.worst(summaries.map(\.certainty))
        var byClass: [FinAssetClass: Int64] = [:]
        for s in summaries { byClass[s.investment.assetClass, default: 0] += s.valuePaise }
        let allocation = byClass.map { FinAllocationSlice(assetClass: $0.key, paise: $0.value,
                                                          share: value > 0 ? Double($0.value) / Double(value) * 100 : 0) }
            .sorted { $0.paise > $1.paise }
        return (value, invested, value - invested, certainty, allocation)
    }

    static func portfolioHistory(_ doc: FinanceDocument, monthEnds: [String]) -> [FinNetWorthPoint] {
        monthEnds.map { end in
            var value: Int64 = 0
            var certainties: [FinCertainty] = []
            for inv in doc.investments where !inv.archived {
                if let bought = inv.purchaseDate, bought > end { continue }
                let amount = investmentValue(doc, investment: inv, asOf: end)
                value += amount.paise
                certainties.append(amount.certainty)
            }
            let certainty = certainties.isEmpty ? .unknown : FinCertainty.worst(certainties)
            return FinNetWorthPoint(date: end, assetsPaise: value, liabilitiesPaise: 0,
                                    netPaise: value, certainty: certainty)
        }
    }

    // MARK: Liabilities

    static func liabilityOutstanding(_ doc: FinanceDocument, liability: FinLiability, asOf: String = FinanceCal.today()) -> Int64 {
        if liability.kind == .creditCard, let account = doc.account(liability.accountID) {
            return max(0, -accountBalance(doc, account: account, asOf: asOf).paise)
        }
        let payments = doc.debtPayments
            .filter { $0.liabilityID == liability.id && $0.date > liability.asOf && $0.date <= asOf }
        var principalPaid = payments.reduce(Int64(0)) { $0 + $1.principalPaise }
        // Imported or manually entered repayments may exist without a
        // debt_payment row. Count those principal portions too, but never the
        // ones already represented by a payment record.
        let recorded = Set(payments.compactMap(\.transactionID))
        let derived = doc.transactions.filter {
            $0.liabilityID == liability.id
                && $0.type == .loanRepayment
                && $0.date > liability.asOf
                && $0.date <= asOf
                && !recorded.contains($0.id)
        }
        principalPaid += derived.reduce(Int64(0)) { $0 + ($1.principalPaise ?? max(0, $1.amountPaise - ($1.interestPaise ?? 0))) }
        return max(0, liability.outstandingPaise - principalPaid)
    }

    static func liabilitySummaries(_ doc: FinanceDocument, asOf: String = FinanceCal.today()) -> [FinLiabilitySummary] {
        doc.liabilities.map { l in
            let payments = doc.debtPayments.filter { $0.liabilityID == l.id && $0.date <= asOf }
            let principalPaid = payments.reduce(0) { $0 + $1.principalPaise }
            let interestPaid = payments.reduce(0) { $0 + $1.interestPaise }
            let outstanding = liabilityOutstanding(doc, liability: l, asOf: asOf)
            let effectivePaid = max(principalPaid, max(0, l.originalPrincipalPaise - outstanding))
            let progress = l.originalPrincipalPaise > 0
                ? min(1, max(0, Double(effectivePaid) / Double(l.originalPrincipalPaise))) : 0
            let tenure: Int?
            if l.emiPaise > 0, outstanding > 0 {
                tenure = Int((Double(outstanding) / Double(l.emiPaise)).rounded(.up))
            } else if let maturity = l.maturityDate {
                tenure = max(0, FinanceCal.daysBetween(asOf, maturity) / 30)
            } else {
                tenure = nil
            }
            return FinLiabilitySummary(liability: l,
                                       outstandingPaise: outstanding,
                                       paidPrincipalPaise: principalPaid,
                                       paidInterestPaise: interestPaid,
                                       progress: progress,
                                       tenureMonthsLeft: tenure)
        }
        .sorted { $0.outstandingPaise > $1.outstandingPaise }
    }

    static func totalLiabilities(_ doc: FinanceDocument, asOf: String = FinanceCal.today()) -> Int64 {
        let summaries = liabilitySummaries(doc, asOf: asOf)
        return summaries.reduce(0) { total, s in
            if s.liability.ownership == .personal { return total + s.outstandingPaise }
            if s.liability.ownership == .household && doc.settings.includeHouseholdInNetWorth {
                return total + s.outstandingPaise
            }
            return total
        }
    }

    static func totalAssets(_ doc: FinanceDocument, asOf: String = FinanceCal.today()) -> FinAmount {
        var out: Int64 = 0
        var certainties: [FinCertainty] = []
        for account in doc.accounts where account.status != .closed {
            guard !account.type.isLiability else { continue }
            let balance = accountBalance(doc, account: account, asOf: asOf)
            out += balance.paise
            certainties.append(balance.certainty)
        }
        for summary in investmentSummaries(doc, asOf: asOf) {
            out += summary.valuePaise
            certainties.append(summary.certainty)
        }
        return FinAmount(paise: out, certainty: certainties.isEmpty ? .unknown : FinCertainty.worst(certainties))
    }

    static func netWorth(_ doc: FinanceDocument, asOf: String = FinanceCal.today()) -> FinAmount {
        let assets = totalAssets(doc, asOf: asOf)
        let liabilities = totalLiabilities(doc, asOf: asOf)
        return FinAmount(paise: assets.paise - liabilities, certainty: assets.certainty)
    }

    /// Liquid money for a runway calculation: cash-like account balances.
    static func liquidAssets(_ doc: FinanceDocument, asOf: String = FinanceCal.today()) -> Int64 {
        doc.accounts
            .filter { $0.type.isCashLike && $0.status == .active }
            .reduce(0) { $0 + accountBalance(doc, account: $1, asOf: asOf).paise }
    }

    static func averageMonthlyExpense(_ doc: FinanceDocument, monthsBack: Int = 6) -> Int64? {
        let ends = FinanceCal.monthsBack(monthsBack)
        var values: [Int64] = []
        for end in ends {
            let totals = monthTotals(doc, monthContaining: end)
            if totals.transactionCount > 0 { values.append(totals.expensePaise) }
        }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Int64(values.count)
    }

    static func runwayMonths(_ doc: FinanceDocument, asOf: String = FinanceCal.today()) -> Double? {
        guard let burn = averageMonthlyExpense(doc), burn > 0 else { return nil }
        return Double(liquidAssets(doc, asOf: asOf)) / Double(burn)
    }

    // MARK: Net worth history

    /// Month-end net worth built from dated records. Account balances are
    /// calculated from transactions; investment and liability values are
    /// carried forward only from a recorded date and are labelled estimated.
    /// A month with no records at all is skipped, not interpolated.
    static func netWorthHistory(_ doc: FinanceDocument,
                                from start: String,
                                through end: String,
                                includeOpening: Bool = true) -> [FinNetWorthPoint] {
        let monthEnds = FinanceCal.months(from: start, through: end).map { FinanceCal.monthEnd($0) }
        var points: [FinNetWorthPoint] = []
        let verifiedSnapshots = doc.snapshots

        for monthEnd in monthEnds {
            if monthEnd > end { continue }
            if let snapshot = verifiedSnapshots.first(where: { $0.date == monthEnd }) {
                points.append(FinNetWorthPoint(date: monthEnd,
                                               assetsPaise: snapshot.assetsPaise,
                                               liabilitiesPaise: snapshot.liabilitiesPaise,
                                               netPaise: snapshot.netWorthPaise,
                                               certainty: snapshot.certainty))
                continue
            }

            // Did anything exist by this month?
            let hasAccount = doc.accounts.contains { $0.openingDate <= monthEnd }
            let hasTxn = doc.transactions.contains { $0.date <= monthEnd }
            let hasInvestment = doc.investments.contains {
                ($0.purchaseDate ?? String($0.createdAt.prefix(10))) <= monthEnd && !$0.archived
            }
            let hasLiability = doc.liabilities.contains { $0.startDate <= monthEnd }
            guard hasAccount || hasTxn || hasInvestment || hasLiability else { continue }

            var assets: Int64 = 0
            var certainties: [FinCertainty] = []
            for account in doc.accounts where !account.type.isLiability && account.status != .closed {
                if account.openingDate > monthEnd { continue }
                let b = accountBalance(doc, account: account, asOf: monthEnd)
                assets += b.paise
                certainties.append(b.certainty)
            }
            for inv in doc.investments where !inv.archived {
                let bought = inv.purchaseDate ?? String(inv.createdAt.prefix(10))
                guard bought <= monthEnd else { continue }
                let v = investmentValue(doc, investment: inv, asOf: monthEnd)
                assets += v.paise
                certainties.append(v.certainty)
            }
            let liabilities = totalLiabilities(doc, asOf: monthEnd)
            if liabilities > 0 { certainties.append(.calculated) }
            points.append(FinNetWorthPoint(date: monthEnd,
                                           assetsPaise: assets,
                                           liabilitiesPaise: liabilities,
                                           netPaise: assets - liabilities,
                                           certainty: certainties.isEmpty ? .unknown : FinCertainty.worst(certainties)))
        }

        if includeOpening, points.isEmpty,
           let first = doc.transactions.map(\.date).min() {
            let assets = doc.accounts.reduce(0) { $0 + accountBalance(doc, account: $1, asOf: first).paise }
            points.append(FinNetWorthPoint(date: first, assetsPaise: assets, liabilitiesPaise: 0,
                                           netPaise: assets, certainty: .calculated))
        }

        // A verified snapshot is a real dated observation, even mid-month.
        // Add it rather than waiting for a month-end to carry it.
        let knownDates = Set(points.map(\.date))
        for s in doc.snapshots
        where s.date >= start && s.date <= end && !knownDates.contains(s.date) {
            points.append(FinNetWorthPoint(date: s.date, assetsPaise: s.assetsPaise,
                                           liabilitiesPaise: s.liabilitiesPaise,
                                           netPaise: s.netWorthPaise, certainty: s.certainty))
        }
        return points.sorted { $0.date < $1.date }
    }

    static func earliestRecordDate(_ doc: FinanceDocument) -> String? {
        var dates: [String] = [doc.settings.trackingStartDate]
        dates.append(contentsOf: doc.accounts.map(\.openingDate))
        dates.append(contentsOf: doc.transactions.map(\.date))
        dates.append(contentsOf: doc.investments.compactMap(\.purchaseDate))
        dates.append(contentsOf: doc.liabilities.map(\.startDate))
        return dates.min()
    }

    static func rangeStart(_ preset: FinRangePreset, doc: FinanceDocument, asOf: String = FinanceCal.today(), customStart: String? = nil) -> String? {
        switch preset {
        case .custom: return customStart ?? FinanceCal.addMonths(-12, to: asOf)
        case .all: return earliestRecordDate(doc)
        default:
            guard let months = preset.months else { return nil }
            return FinanceCal.addMonths(-months, to: asOf)
        }
    }

    // MARK: Budgets and goals

    static func budgetStatuses(_ doc: FinanceDocument, on key: String = FinanceCal.today()) -> [FinBudgetStatus] {
        doc.budgets.filter { !$0.archived }.map { budget in
            let range = budget.range(containing: key)
            var actual: Int64 = 0
            for t in doc.transactions where t.date >= range.start && t.date <= range.end {
                guard let categoryID = budget.categoryID else {
                    // A whole-spend budget, not tied to one category.
                    if isExpense(t) { actual += expenseAmount(t) }
                    else if isRefund(t) { actual -= t.amountPaise }
                    continue
                }
                if isExpense(t) && t.categoryID == categoryID { actual += expenseAmount(t) }
                if isRefund(t) && t.categoryID == categoryID { actual -= t.amountPaise }
            }
            actual = max(0, actual)
            let remaining = budget.plannedPaise - actual
            let progress = budget.plannedPaise > 0 ? Double(actual) / Double(budget.plannedPaise) : 0
            return FinBudgetStatus(budget: budget,
                                   actualPaise: actual,
                                   remainingPaise: remaining,
                                   progress: progress,
                                   variancePaise: remaining,
                                   categoryName: doc.category(budget.categoryID)?.name ?? "All spending",
                                   range: range)
        }
        .sorted { $0.progress > $1.progress }
    }

    static func goalStatuses(_ doc: FinanceDocument, asOf: String = FinanceCal.today()) -> [FinGoalStatus] {
        doc.goals.map { goal in
            let progress = goal.targetPaise > 0 ? min(1, Double(goal.currentPaise) / Double(goal.targetPaise)) : 0
            let remaining = max(0, goal.targetPaise - goal.currentPaise)
            let months: Int?
            if let deadline = goal.deadline {
                months = max(0, FinanceCal.daysBetween(asOf, deadline) / 30)
            } else { months = nil }
            let required = months.flatMap { m in m > 0 ? remaining / Int64(m) : remaining }
            let onTrack: Bool?
            if let required, goal.monthlyContributionPaise > 0 {
                onTrack = goal.monthlyContributionPaise >= required
            } else { onTrack = nil }
            return FinGoalStatus(goal: goal, progress: progress, remainingPaise: remaining,
                                 monthsLeft: months, requiredMonthlyPaise: required, onTrack: onTrack)
        }
        .sorted { $0.progress > $1.progress }
    }

    // MARK: Recurring and upcoming

    static func annualRecurringCommitment(_ doc: FinanceDocument) -> Int64 {
        doc.recurring
            .filter(\.active)
            .reduce(0) { $0 + Int64(Double($1.amountPaise) * $1.cadence.annualMultiplier) }
    }

    static func monthlyRecurringCommitment(_ doc: FinanceDocument) -> Int64 {
        annualRecurringCommitment(doc) / 12
    }

    static func upcomingPayments(_ doc: FinanceDocument, days: Int = 45, asOf: String = FinanceCal.today()) -> [FinUpcomingPayment] {
        let horizon = FinanceCal.addDays(days, to: asOf)
        var out: [FinUpcomingPayment] = []

        for item in doc.recurring where item.active {
            if item.nextDate >= asOf && item.nextDate <= horizon {
                out.append(FinUpcomingPayment(id: item.id, title: item.name, date: item.nextDate,
                                              amountPaise: item.amountPaise, kind: item.kind,
                                              accountID: item.accountID, sourceID: item.id,
                                              certainty: .calculated))
            }
        }

        for summary in liabilitySummaries(doc, asOf: asOf) where !summary.liability.closed && summary.outstandingPaise > 0 {
            let isCard = summary.liability.kind == .creditCard
            guard summary.liability.emiPaise > 0 || isCard else { continue }
            let next = nextMonthlyDay(summary.liability.dueDay, asOf: asOf)
            guard next <= horizon else { continue }
            out.append(FinUpcomingPayment(id: "liability-" + summary.liability.id,
                                          title: isCard ? "\(summary.liability.name) bill" : summary.liability.name,
                                          date: next,
                                          amountPaise: summary.liability.emiPaise > 0 ? summary.liability.emiPaise : summary.outstandingPaise,
                                          kind: isCard ? .bill : .emi,
                                          accountID: summary.liability.accountID,
                                          sourceID: summary.liability.id,
                                          certainty: .calculated))
        }
        return out.sorted { $0.date < $1.date }
    }

    static func nextMonthlyDay(_ day: Int, asOf: String = FinanceCal.today()) -> String {
        let clamped = max(1, min(28, day))
        let thisMonth = FinanceCal.monthStart(asOf)
        let candidate = FinanceCal.addDays(clamped - 1, to: thisMonth)
        if candidate >= asOf { return candidate }
        return FinanceCal.addDays(clamped - 1, to: FinanceCal.addMonths(1, to: thisMonth))
    }

    // MARK: Insights

    /// Only facts the records support. If a comparison has no baseline, the
    /// insight is simply not shown.
    static func insights(_ doc: FinanceDocument, asOf: String = FinanceCal.today()) -> [FinInsight] {
        var out: [FinInsight] = []
        let current = monthTotals(doc, monthContaining: asOf)
        let previous = monthTotals(doc, monthContaining: previousMonthKey(asOf))
        let cats = expenseByCategory(doc, from: FinanceCal.monthStart(asOf), through: FinanceCal.monthEnd(asOf))

        if let rate = current.savingsRate, current.incomePaise > 0 {
            out.append(FinInsight(id: "savings-rate",
                                  title: "Savings rate this month",
                                  detail: "\(FinanceFormat.percent(rate)) of \(FinanceFormat.inr(current.incomePaise)) income kept after ordinary spending.",
                                  tone: rate >= 20 ? .positive : .negative,
                                  symbol: "percent"))
        }

        if let top = cats.first, top.paise > 0 {
            out.append(FinInsight(id: "top-category",
                                  title: "Biggest category",
                                  detail: "\(top.name) — \(FinanceFormat.inr(top.paise)) across \(top.count) transaction\(top.count == 1 ? "" : "s").",
                                  tone: .neutral,
                                  symbol: top.icon))
        }

        if let change = comparison(current.expensePaise, previous.expensePaise), previous.expensePaise > 0 {
            out.append(FinInsight(id: "spend-change",
                                  title: change > 0 ? "Spending is up" : "Spending is down",
                                  detail: "\(FinanceFormat.signedPercent(change)) versus last month (\(FinanceFormat.inr(previous.expensePaise)) → \(FinanceFormat.inr(current.expensePaise))).",
                                  tone: change > 0 ? .negative : .positive,
                                  symbol: change > 0 ? "arrow.up.right" : "arrow.down.right"))
        }

        let recurring = annualRecurringCommitment(doc)
        if recurring > 0 {
            out.append(FinInsight(id: "recurring",
                                  title: "Recurring commitments",
                                  detail: "\(FinanceFormat.inr(recurring)) a year, about \(FinanceFormat.inr(recurring / 12)) a month.",
                                  tone: .information,
                                  symbol: "repeat"))
        }

        let history = netWorthHistory(doc, from: FinanceCal.addMonths(-3, to: asOf), through: asOf)
        if history.count >= 2, let last = history.last, let prev = history.dropLast().last {
            let delta = last.netPaise - prev.netPaise
            out.append(FinInsight(id: "net-worth-change",
                                  title: delta >= 0 ? "Net worth grew" : "Net worth fell",
                                  detail: "\(FinanceFormat.inr(abs(delta))) since \(FinanceCal.monthLabel(prev.date)). \(last.certainty.label).",
                                  tone: delta >= 0 ? .positive : .negative,
                                  symbol: delta >= 0 ? "chart.line.uptrend.xyaxis" : "chart.line.downtrend.xyaxis"))
        }

        if let runway = runwayMonths(doc, asOf: asOf), runway < 12 {
            out.append(FinInsight(id: "runway",
                                  title: "Financial runway",
                                  detail: "About \(String(format: "%.1f", runway)) months of average spending is covered by cash. No emergency fund is assumed.",
                                  tone: runway >= 6 ? .positive : .negative,
                                  symbol: "timer"))
        }

        // An unusual charge is only claimed when there is a real baseline.
        let recentExpenses = doc.transactions.filter {
            FinanceEngine.isExpense($0) && $0.date >= FinanceCal.addDays(-90, to: asOf) && $0.date <= asOf
        }
        if recentExpenses.count >= 20 {
            let amounts = recentExpenses.map { $0.amountPaise }.sorted()
            let median = amounts[amounts.count / 2]
            if let largest = recentExpenses.max(by: { $0.amountPaise < $1.amountPaise }),
               median > 0, largest.amountPaise > median * 4, largest.amountPaise > 1_000_000 {
                out.append(FinInsight(id: "unusual-expense",
                                      title: "Unusually large expense",
                                      detail: "\(largest.title) at \(FinanceFormat.inr(largest.amountPaise)) is more than four times the \(FinanceFormat.inr(median)) median of the last 90 days.",
                                      tone: .information,
                                      symbol: "exclamationmark.magnifyingglass"))
            }
        }

        let unreviewed = doc.transactions.filter { $0.verification == .needsReview || $0.verification == .unverified }.count
        if unreviewed > 0 {
            out.append(FinInsight(id: "review",
                                  title: "\(unreviewed) entries need review",
                                  detail: "Unverified records are included in totals but are not treated as reconciled.",
                                  tone: .information,
                                  symbol: "checklist"))
        }
        return out
    }

    // MARK: Integrity

    static func duplicateGroups(_ doc: FinanceDocument) -> [FinDuplicateGroup] {
        var buckets: [String: [FinTransaction]] = [:]
        for t in doc.transactions where t.type != .transfer {
            let merchant = t.merchant.lowercased().trimmingCharacters(in: .whitespaces)
            let key = "\(t.accountID)|\(t.date)|\(t.amountPaise)|\(t.direction.rawValue)|\(merchant)"
            buckets[key, default: []].append(t)
        }
        return buckets.values
            .filter { $0.count > 1 }
            .map { FinDuplicateGroup(transactions: $0.sorted { $0.createdAt < $1.createdAt },
                                     reason: "Same account, date, amount, direction and payee") }
            .sorted { $0.transactions.first?.date ?? "" > $1.transactions.first?.date ?? "" }
    }

    static func transferCandidates(_ doc: FinanceDocument) -> [FinTransferCandidate] {
        let open = doc.transactions.filter {
            $0.transferID == nil && !isInternalTransfer($0)
                && ($0.type == .expense || $0.type == .income || $0.type == .loanRepayment)
        }
        var out: [FinTransferCandidate] = []
        var used = Set<String>()
        for a in open {
            guard !used.contains(a.id) else { continue }
            for b in open where b.id != a.id && !used.contains(b.id) {
                guard a.accountID != b.accountID else { continue }
                guard a.amountPaise == b.amountPaise else { continue }
                guard a.direction != b.direction else { continue }
                let gap = abs(FinanceCal.daysBetween(a.date, b.date))
                guard gap <= 3 else { continue }
                // Only pair where it plausibly reads as a movement, not two
                // unrelated purchases that happen to match.
                let minDate = a.date < b.date ? a : b
                out.append(FinTransferCandidate(from: minDate, to: minDate.id == a.id ? b : a, dayGap: gap))
                used.insert(a.id); used.insert(b.id)
                break
            }
        }
        return out
    }

    static func integrityIssues(_ doc: FinanceDocument, asOf: String = FinanceCal.today()) -> [FinIntegrityIssue] {
        var out: [FinIntegrityIssue] = []

        let duplicates = duplicateGroups(doc)
        if !duplicates.isEmpty {
            out.append(FinIntegrityIssue(id: "duplicates", kind: .duplicate,
                                         title: "Duplicate candidates",
                                         detail: "\(duplicates.count) group\(duplicates.count == 1 ? "" : "s") share account, date and amount.",
                                         severity: 1,
                                         transactionIDs: duplicates.flatMap { $0.transactions.map(\.id) }))
        }

        let uncategorised = doc.transactions.filter {
            isExpense($0) && ($0.categoryID == nil || $0.categoryID == FinanceTaxonomy.defaultExpenseCategoryID())
        }
        if !uncategorised.isEmpty {
            out.append(FinIntegrityIssue(id: "uncategorised", kind: .uncategorised,
                                         title: "Uncategorised expenses",
                                         detail: "\(uncategorised.count) expense\(uncategorised.count == 1 ? "" : "s") still sit in Uncategorised.",
                                         severity: 1,
                                         transactionIDs: uncategorised.map(\.id)))
        }

        let unmatched = doc.transactions.filter { $0.type == .transfer && $0.transferID == nil }
        if !unmatched.isEmpty {
            out.append(FinIntegrityIssue(id: "unmatched-transfers", kind: .unmatchedTransfer,
                                         title: "Unmatched transfers",
                                         detail: "\(unmatched.count) transfer entr\(unmatched.count == 1 ? "y is" : "ies are") not linked to a counterpart.",
                                         severity: 1,
                                         transactionIDs: unmatched.map(\.id)))
        }

        let unreconciled = doc.statements.filter { $0.status == .parsed }.filter { statement in
            !doc.reconciliations.contains { $0.statementID == statement.id && $0.status == .matched }
        }
        if !unreconciled.isEmpty {
            out.append(FinIntegrityIssue(id: "unreconciled", kind: .unreconciled,
                                         title: "Unreconciled statements",
                                         detail: "\(unreconciled.count) parsed statement\(unreconciled.count == 1 ? "" : "s") without a reconciled closing balance.",
                                         severity: 1))
        }

        for recon in doc.reconciliations where recon.status == .mismatch {
            out.append(FinIntegrityIssue(id: "closing-" + recon.id, kind: .closingMismatch,
                                         title: "Closing balance mismatch",
                                         detail: "\(doc.account(recon.accountID)?.name ?? "Account") · \(FinanceCal.display(recon.periodEnd)): counted \(FinanceFormat.inr(recon.computedClosingPaise)), statement says \(FinanceFormat.inr(recon.closingPaise)).",
                                         severity: 2, accountID: recon.accountID))
        }

        for recon in doc.reconciliations {
            if let delta = openingMismatch(recon) {
                out.append(FinIntegrityIssue(id: "opening-" + recon.id, kind: .openingMismatch,
                                             title: "Opening balance mismatch",
                                             detail: "\(doc.account(recon.accountID)?.name ?? "Account"): the stated opening differs from the ledger by \(FinanceFormat.inr(delta)) for the period ending \(FinanceCal.display(recon.periodEnd)).",
                                             severity: 1, accountID: recon.accountID))
            }
        }

        let importedNoRef = doc.transactions.filter { $0.source == .imported && $0.reference.isEmpty }
        if !importedNoRef.isEmpty {
            out.append(FinIntegrityIssue(id: "missing-ref", kind: .missingReference,
                                         title: "Missing references",
                                         detail: "\(importedNoRef.count) imported entries have no bank reference.",
                                         severity: 0, transactionIDs: importedNoRef.map(\.id)))
        }

        let invalidDates = doc.transactions.filter {
            FinanceCal.date($0.date) == nil || $0.date > FinanceCal.addDays(1, to: asOf)
        }
        if !invalidDates.isEmpty {
            out.append(FinIntegrityIssue(id: "invalid-dates", kind: .invalidDate,
                                         title: "Invalid dates",
                                         detail: "\(invalidDates.count) record\(invalidDates.count == 1 ? " has" : "s have") a malformed or future date.",
                                         severity: 2, transactionIDs: invalidDates.map(\.id)))
        }

        let amountEdits = doc.audit.filter { $0.action == .updated && $0.field == "amount" }
        let suspicious = amountEdits.filter { entry in
            guard let old = entry.oldValue.flatMap(FinanceFormat.parsePaise),
                  let new = entry.newValue.flatMap(FinanceFormat.parsePaise),
                  old != 0 else { return false }
            return abs(Double(new - old) / Double(old)) > 3.0
        }
        if !suspicious.isEmpty {
            out.append(FinIntegrityIssue(id: "suspicious-amounts", kind: .suspiciousAmount,
                                         title: "Large amount corrections",
                                         detail: "\(suspicious.count) recorded correction\(suspicious.count == 1 ? "" : "s") changed a transaction by more than 3×. Review the audit entry and source.",
                                         severity: 1,
                                         transactionIDs: suspicious.compactMap(\.sourceTransactionID)))
        }

        let corrections = doc.audit.filter { $0.action == .updated || $0.action == .deleted }
        if !corrections.isEmpty {
            out.append(FinIntegrityIssue(id: "corrections", kind: .correction,
                                         title: "Manual corrections",
                                         detail: "\(corrections.count) correction\(corrections.count == 1 ? "" : "s") recorded in the immutable audit log.",
                                         severity: 0))
        }

        let unverified = doc.transactions.filter { $0.source == .imported && !$0.verification.isTrusted }
        if !unverified.isEmpty {
            out.append(FinIntegrityIssue(id: "unverified", kind: .unverified,
                                         title: "Unverified imported rows",
                                         detail: "\(unverified.count) imported transaction\(unverified.count == 1 ? "" : "s") have not been verified or reconciled.",
                                         severity: 1, transactionIDs: unverified.map(\.id)))
        }

        return out.sorted { $0.severity > $1.severity }
    }

    // MARK: Timeline

    static func timeline(_ doc: FinanceDocument) -> [FinTimelineEntry] {
        var out: [FinTimelineEntry] = []

        for m in doc.milestones {
            out.append(FinTimelineEntry(id: "milestone-" + m.id, date: m.date, title: m.title,
                                        detail: m.detail, kind: m.kind, certainty: m.certainty,
                                        amountPaise: nil, isAutomatic: false,
                                        transactionID: m.linkedTransactionID))
        }

        if let firstAccount = doc.accounts.min(by: { $0.openingDate < $1.openingDate }) {
            out.append(FinTimelineEntry(id: "first-account", date: firstAccount.openingDate,
                                        title: "Opened \(firstAccount.name)",
                                        detail: firstAccount.institution.isEmpty ? firstAccount.type.label : "\(firstAccount.institution) · \(firstAccount.type.label)",
                                        kind: .firstAccount, certainty: .verified,
                                        amountPaise: firstAccount.openingBalancePaise,
                                        isAutomatic: true, transactionID: nil))
        }

        let incomes = doc.transactions.filter { isIncome($0) }.sorted { $0.date < $1.date }
        if let first = incomes.first {
            out.append(FinTimelineEntry(id: "first-income-" + first.id, date: first.date,
                                        title: "First recorded income",
                                        detail: first.title, kind: .firstIncome,
                                        certainty: first.verification.isTrusted ? .verified : .calculated,
                                        amountPaise: first.amountPaise, isAutomatic: true,
                                        transactionID: first.id))
        }
        if let firstSalary = incomes.first(where: { doc.category($0.categoryID)?.name.lowercased().contains("salary") == true }) {
            out.append(FinTimelineEntry(id: "first-salary-" + firstSalary.id, date: firstSalary.date,
                                        title: "First salary", detail: firstSalary.title,
                                        kind: .firstSalary, certainty: .calculated,
                                        amountPaise: firstSalary.amountPaise, isAutomatic: true,
                                        transactionID: firstSalary.id))
        }
        if let firstFreelance = incomes.first(where: { doc.category($0.categoryID)?.name.lowercased().contains("freelanc") == true }) {
            out.append(FinTimelineEntry(id: "first-freelance-" + firstFreelance.id, date: firstFreelance.date,
                                        title: "First freelance payment", detail: firstFreelance.title,
                                        kind: .firstFreelance, certainty: .calculated,
                                        amountPaise: firstFreelance.amountPaise, isAutomatic: true,
                                        transactionID: firstFreelance.id))
        }
        if let firstInvestment = doc.investments.min(by: { ($0.purchaseDate ?? "") < ($1.purchaseDate ?? "") }),
           let date = firstInvestment.purchaseDate {
            out.append(FinTimelineEntry(id: "first-investment-" + firstInvestment.id, date: date,
                                        title: "First investment",
                                        detail: "\(firstInvestment.name) · \(firstInvestment.assetClass.label)",
                                        kind: .firstInvestment, certainty: .verified,
                                        amountPaise: firstInvestment.investedPaise, isAutomatic: true,
                                        transactionID: nil))
        }
        if let firstLiability = doc.liabilities.min(by: { $0.startDate < $1.startDate }) {
            out.append(FinTimelineEntry(id: "first-liability-" + firstLiability.id, date: firstLiability.startDate,
                                        title: "Took on \(firstLiability.name)",
                                        detail: "\(firstLiability.kind.label) · \(firstLiability.lender)",
                                        kind: .debt, certainty: .verified,
                                        amountPaise: firstLiability.originalPrincipalPaise,
                                        isAutomatic: true, transactionID: nil))
        }

        // Annual net-worth marks, only where the records exist.
        let history = netWorthHistory(doc, from: earliestRecordDate(doc) ?? FinanceCal.today(),
                                      through: FinanceCal.today())
        let byYear = Dictionary(grouping: history) { String($0.date.prefix(4)) }
        for (year, points) in byYear.sorted(by: { $0.key < $1.key }) {
            guard let last = points.last else { continue }
            out.append(FinTimelineEntry(id: "networth-" + year, date: last.date,
                                        title: "Net worth at the end of \(year)",
                                        detail: "\(FinanceFormat.inr(last.netPaise)) · \(last.certainty.label)",
                                        kind: .netWorth, certainty: last.certainty,
                                        amountPaise: last.netPaise, isAutomatic: true, transactionID: nil))
        }

        return out.sorted { $0.date > $1.date }
    }

    // MARK: Tax

    static func taxSummary(_ doc: FinanceDocument, fyContaining key: String) -> FinTaxSummary {
        let fy = FinanceCal.financialYear(containing: key)
        var s = FinTaxSummary(fyLabel: "FY \(String(fy.start.prefix(4)))–\(String(fy.end.prefix(2)))",
                              start: fy.start, end: fy.end,
                              salaryPaise: 0, freelancePaise: 0, businessPaise: 0,
                              interestPaise: 0, dividendPaise: 0, otherIncomePaise: 0,
                              taxPaidPaise: 0, taxExpensesPaise: 0,
                              capitalGainsPaise: 0, recordedSaleProceedsPaise: 0)
        for t in doc.transactions where t.date >= fy.start && t.date <= fy.end {
            if isIncome(t) {
                let cat = doc.category(t.categoryID)?.name.lowercased() ?? ""
                if cat.contains("salary") { s.salaryPaise += t.amountPaise }
                else if cat.contains("freelanc") || cat.contains("consult") { s.freelancePaise += t.amountPaise }
                else if cat.contains("business") || cat.contains("youtube") || cat.contains("creator")
                            || cat.contains("sponsor") || cat.contains("affiliate") {
                    s.businessPaise += t.amountPaise
                } else if cat.contains("interest") || t.type == .interest { s.interestPaise += t.amountPaise }
                else if cat.contains("dividend") || t.type == .dividend { s.dividendPaise += t.amountPaise }
                else { s.otherIncomePaise += t.amountPaise }
            }
            if t.type == .tax || t.type == .fee {
                s.taxPaidPaise += t.amountPaise
            }
            if t.type == .investmentSale {
                s.recordedSaleProceedsPaise += t.amountPaise
                s.capitalGainsPaise += t.realisedGainPaise ?? 0
            }
        }
        return s
    }

    static func taxExpenses(_ doc: FinanceDocument, from start: String, through end: String) -> [FinCategorySlice] {
        let all = expenseByCategory(doc, from: start, through: end)
        let taxIDs = Set(doc.categories.filter { $0.name.lowercased().contains("tax") }.map(\.id))
        return all.filter { taxIDs.contains($0.categoryID) || $0.group == "Financial" }
    }

    // MARK: Exports

    static func transactionsCSV(_ transactions: [FinTransaction], doc: FinanceDocument) -> String {
        let headers = ["id", "date", "posted_date", "account", "type", "direction", "amount_inr",
                       "currency", "category", "merchant", "payment_method", "reference",
                       "description", "source", "verification", "transfer_id", "tags", "created_at"]
        var rows = [headers.joined(separator: ",")]
        for t in transactions.sorted(by: { $0.date < $1.date }) {
            let values: [String] = [
                t.id, t.date, t.postedDate ?? "",
                doc.account(t.accountID)?.name ?? "",
                t.type.rawValue, t.direction.rawValue,
                String(format: "%.2f", Double(t.amountPaise) / 100),
                t.currency,
                doc.category(t.categoryID)?.displayName ?? "",
                t.merchant, t.paymentMethod.rawValue, t.reference,
                t.note, t.source.rawValue, t.verification.rawValue,
                t.transferID ?? "", t.tags.joined(separator: ";"), t.createdAt
            ]
            rows.append(values.map(csvEscape).joined(separator: ","))
        }
        return rows.joined(separator: "\n")
    }

    static func accountsCSV(_ doc: FinanceDocument) -> String {
        var rows = ["id,name,institution,type,currency,opening_date,opening_balance_inr,balance_inr,status,last_reconciled"]
        for a in doc.accounts {
            let balance = FinanceEngine.accountBalance(doc, account: a)
            let values = [a.id, a.name, a.institution, a.type.rawValue, a.currency,
                          a.openingDate, String(format: "%.2f", Double(a.openingBalancePaise) / 100),
                          String(format: "%.2f", Double(balance.paise) / 100),
                          a.status.rawValue, a.lastReconciledOn ?? ""]
            rows.append(values.map(csvEscape).joined(separator: ","))
        }
        return rows.joined(separator: "\n")
    }

    private static func csvEscape(_ value: String) -> String {
        let clean = value.replacingOccurrences(of: "\"", with: "\"\"")
        if clean.contains(",") || clean.contains("\"") || clean.contains("\n") {
            return "\"\(clean)\""
        }
        return clean
    }

    // MARK: Definitions
    //
    // Shown next to reports so a metric can never be ambiguous.

    static let definitions: [(String, String)] = [
        ("Net worth", "Assets minus liabilities. Assets are cash-like account balances plus investment valuations. Credit-card debt and recorded loans are liabilities."),
        ("Income", "Inflows classified as income, interest or dividend. Transfers, refunds, loan disbursements and investment sales are never income."),
        ("Expenses", "Expense, fee, tax and loan-interest entries, minus refunds received in the same period. It excludes transfers, investment purchases and loan principal."),
        ("Net savings", "Income minus expenses. Money invested is still savings, just held in another asset."),
        ("Savings rate", "Net savings divided by income for the period."),
        ("Assets", "Cash-like and deposit account balances plus investment current value. A credit card is never an asset."),
        ("Liabilities", "Outstanding credit-card balances plus loan principal. Household debt is excluded from personal net worth unless explicitly included in Finance Settings."),
        ("Investment return", "Current value minus invested capital, divided by invested capital. Unrealised until a sale is recorded."),
        ("Runway", "Liquid cash divided by the average monthly expense of the last six months with records. It assumes spending stays flat."),
        ("Certainty", "Verified: a statement or explicit valuation. Calculated: derived from recorded transactions. Estimated: carried forward from an older valuation. Unknown: no supporting record."),
        ("Realised gain", "Proceeds of an investment sale minus the recorded cost basis. Only recorded sales contribute; nothing is inferred."),
    ]
}
