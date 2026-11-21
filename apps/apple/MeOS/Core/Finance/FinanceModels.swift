import Foundation

// MARK: - Finance domain
//
// Money is always integer paise (Int64). Dates are always `yyyy-MM-dd` keys in
// Asia/Kolkata. Every entity carries a stable string ID and, where it refers to
// another entity, the actual ID rather than a copy of its data.
//
// The synced `meos.finance` document is the source of truth for the native
// client. It is deliberately made of separate, keyed collections (accounts,
// transactions, budgets, …) with stable IDs and no opaque settings blob; the
// model survives the move to year shards without changing identifiers.
// Derived numbers are never stored as fact — `FinanceEngine` calculates them
// from these records. See `docs/finance-foundation.md`.

enum FinanceSchema {
    static let version = 1
    static let currency = "INR"
    static let locale = "en_IN"
    static let timeZoneID = "Asia/Kolkata"
}

enum FinID {
    static func new() -> String { UUID().uuidString.lowercased() }

    /// Deterministic ID for seed data. The same category gets the same ID on
    /// every device, so two devices seeding before their first sync cannot
    /// create duplicates.
    static func stable(_ key: String) -> String {
        var h1: UInt64 = 0xcbf29ce484222325
        for b in key.utf8 { h1 = (h1 ^ UInt64(b)) &* 0x100000001b3 }
        var h2: UInt64 = 0x84222325cbf29ce4
        for b in key.utf8.reversed() { h2 = (h2 ^ UInt64(b)) &* 0x100000001b3 }
        let hex = String(format: "%016llx%016llx", h1, h2).lowercased()
        let a = hex.prefix(8)
        let b = hex.dropFirst(8).prefix(4)
        let c = hex.dropFirst(12).prefix(4)
        let d = hex.dropFirst(16).prefix(4)
        let e = hex.dropFirst(20).prefix(12)
        return "\(a)-\(b)-\(c)-\(d)-\(e)"
    }
}

enum FinNow {
    static func stamp() -> String {
        let f = ISO8601DateFormatter()
        f.timeZone = FinanceCal.zone
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: Date())
    }
}

// MARK: - Calendar

enum FinanceCal {
    static let zone = TimeZone(identifier: FinanceSchema.timeZoneID) ?? .current

    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = zone
        c.locale = Locale(identifier: "en_US_POSIX")
        c.firstWeekday = 2
        return c
    }

    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = zone
        f.dateFormat = format
        return f
    }

    static func key(_ date: Date) -> String { formatter("yyyy-MM-dd").string(from: date) }

    static func date(_ key: String) -> Date? {
        guard key.count >= 10 else { return nil }
        return formatter("yyyy-MM-dd").date(from: String(key.prefix(10)))
    }

    static func today() -> String { key(Date()) }

    static func nowYear() -> Int {
        calendar.component(.year, from: Date())
    }

    static func addDays(_ n: Int, to key: String) -> String {
        guard let d = date(key), let moved = calendar.date(byAdding: .day, value: n, to: d) else { return key }
        return self.key(moved)
    }

    static func addMonths(_ n: Int, to key: String) -> String {
        guard let d = date(key), let moved = calendar.date(byAdding: .month, value: n, to: d) else { return key }
        return self.key(moved)
    }

    static func addYears(_ n: Int, to key: String) -> String {
        guard let d = date(key), let moved = calendar.date(byAdding: .year, value: n, to: d) else { return key }
        return self.key(moved)
    }

    /// First day of the month containing `key`.
    static func monthStart(_ key: String) -> String {
        guard let d = date(key) else { return key }
        var c = calendar.dateComponents([.year, .month], from: d)
        c.day = 1
        guard let start = calendar.date(from: c) else { return key }
        return self.key(start)
    }

    /// Last day of the month containing `key`.
    static func monthEnd(_ key: String) -> String {
        guard let d = date(key) else { return key }
        guard let range = calendar.range(of: .day, in: .month, for: d) else { return key }
        var c = calendar.dateComponents([.year, .month], from: d)
        c.day = range.count
        guard let end = calendar.date(from: c) else { return key }
        return self.key(end)
    }

    static func yearStart(_ key: String) -> String {
        String(key.prefix(4)) + "-01-01"
    }

    static func yearEnd(_ key: String) -> String {
        String(key.prefix(4)) + "-12-31"
    }

    static func monthKey(_ key: String) -> String { String(key.prefix(7)) }

    static func months(from start: String, through end: String) -> [String] {
        var out: [String] = []
        var cursor = monthStart(start)
        let stop = monthStart(end)
        var guardCount = 0
        while cursor <= stop && guardCount < 1200 {
            out.append(cursor)
            cursor = addMonths(1, to: cursor)
            guardCount += 1
        }
        return out
    }

    static func monthsBack(_ n: Int, from key: String = today()) -> [String] {
        let start = addMonths(-max(0, n - 1), to: monthStart(key))
        return months(from: start, through: key).map(monthEnd)
    }

    /// Indian financial year: 1 April – 31 March. Returns (start, end) keys.
    static func financialYear(containing key: String) -> (start: String, end: String) {
        let year = Int(key.prefix(4)) ?? nowYear()
        let month = Int(key.dropFirst(5).prefix(2)) ?? 1
        if month >= 4 {
            return ("\(year)-04-01", "\(year + 1)-03-31")
        }
        return ("\(year - 1)-04-01", "\(year)-03-31")
    }

    static func day(_ key: String) -> Int { Int(key.suffix(2)) ?? 1 }

    static func daysBetween(_ a: String, _ b: String) -> Int {
        guard let da = date(a), let db = date(b) else { return 0 }
        return calendar.dateComponents([.day], from: da, to: db).day ?? 0
    }

    static func monthLabel(_ key: String) -> String {
        guard let d = date(key) else { return key }
        return formatter("MMM yyyy").string(from: d)
    }

    static func shortMonth(_ key: String) -> String {
        guard let d = date(key) else { return key }
        return formatter("MMM").string(from: d)
    }

    /// The app-wide display format: DD MMM YYYY.
    static func display(_ key: String) -> String {
        guard let d = date(key) else { return key }
        return formatter("dd MMM yyyy").string(from: d)
    }

    static func weekday(_ key: String) -> String {
        guard let d = date(key) else { return "" }
        return formatter("EEE").string(from: d)
    }

    static func age(on key: String, born: String?) -> Int? {
        guard let born, let b = date(born), let d = date(key) else { return nil }
        return calendar.dateComponents([.year], from: b, to: d).year
    }
}

// MARK: - Formatting and money parsing

enum FinanceFormat {
    private static let grouped: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: FinanceSchema.locale)
        f.maximumFractionDigits = 0
        f.minimumFractionDigits = 0
        return f
    }()

    private static let grouped2: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: FinanceSchema.locale)
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 2
        return f
    }()

    /// `₹1,24,500` — no decimals for paise values by default.
    static func inr(_ paise: Int64, showSign: Bool = false, decimals: Bool = false) -> String {
        let negative = paise < 0
        let magnitude = paise.magnitude
        let rupees = Decimal(magnitude) / 100
        let number = NSDecimalNumber(decimal: rupees)
        let body = (decimals ? grouped2.string(from: number) : grouped.string(from: number)) ?? "0"
        let sign = negative ? "−" : (showSign && paise > 0 ? "+" : "")
        return "\(sign)₹\(body)"
    }

    /// Compact money for dense charts and chips: ₹1.2L / ₹3.4Cr.
    static func compact(_ paise: Int64) -> String {
        let negative = paise < 0
        let rupees = Double(paise.magnitude) / 100
        let text: String
        switch rupees {
        case 10_000_000...: text = String(format: "%.2fCr", rupees / 10_000_000)
        case 100_000...:    text = String(format: "%.1fL", rupees / 100_000)
        case 1_000...:      text = String(format: "%.0fK", rupees / 1_000)
        default:            text = String(format: "%.0f", rupees)
        }
        return "\(negative ? "−" : "")₹\(text)"
    }

    static func percent(_ value: Double, decimals: Int = 1) -> String {
        String(format: "%.\(decimals)f%%", value)
    }

    static func signedPercent(_ value: Double) -> String {
        (value > 0 ? "+" : value < 0 ? "−" : "") + String(format: "%.1f%%", abs(value))
    }

    /// Parse a user-entered rupee amount into exact paise.
    static func parsePaise(_ text: String) -> Int64? {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        t = t.replacingOccurrences(of: "₹", with: "")
        t = t.replacingOccurrences(of: ",", with: "")
        t = t.replacingOccurrences(of: " ", with: "")
        guard !t.isEmpty else { return nil }
        let negative = t.hasPrefix("-")
        if negative { t.removeFirst() }
        guard let decimal = Decimal(string: t, locale: Locale(identifier: "en_US_POSIX")),
              decimal.isFinite else { return nil }
        var value = decimal * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 0, .plain)
        let number = NSDecimalNumber(decimal: rounded)
        guard number != .notANumber else { return nil }
        let raw = number.int64Value
        return negative ? -raw : raw
    }

    /// Indian short date: 20 Nov 2026.
    static func date(_ key: String) -> String { FinanceCal.display(key) }

    static func dayMonth(_ key: String) -> String {
        guard let d = FinanceCal.date(key) else { return key }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_IN")
        f.timeZone = FinanceCal.zone
        f.dateFormat = "dd MMM"
        return f.string(from: d)
    }
}

// MARK: - Enums

enum FinAccountType: String, Codable, CaseIterable, Identifiable {
    case savings, current, salary, cash, creditCard, wallet
    case fixedDeposit, recurringDeposit, brokerage, investment, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .savings: "Savings"
        case .current: "Current"
        case .salary: "Salary"
        case .cash: "Cash"
        case .creditCard: "Credit card"
        case .wallet: "Wallet"
        case .fixedDeposit: "Fixed deposit"
        case .recurringDeposit: "Recurring deposit"
        case .brokerage: "Brokerage"
        case .investment: "Investment"
        case .other: "Other"
        }
    }

    var icon: String {
        switch self {
        case .savings: "banknote"
        case .current: "building.columns"
        case .salary: "briefcase"
        case .cash: "wallet.pass"
        case .creditCard: "creditcard"
        case .wallet: "iphone.gen3"
        case .fixedDeposit: "lock.square"
        case .recurringDeposit: "calendar.badge.clock"
        case .brokerage: "chart.line.uptrend.xyaxis"
        case .investment: "chart.pie"
        case .other: "square.stack"
        }
    }

    var isLiability: Bool { self == .creditCard }
    var isInvestment: Bool { self == .brokerage || self == .investment }
    var isCashLike: Bool {
        switch self {
        case .savings, .current, .salary, .cash, .wallet: true
        default: false
        }
    }
    var isDeposit: Bool { self == .fixedDeposit || self == .recurringDeposit }
}

enum FinAccountStatus: String, Codable, CaseIterable, Identifiable {
    case active, archived, closed
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum FinCategoryKind: String, Codable, CaseIterable, Identifiable {
    case income, expense
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum FinTxnType: String, Codable, CaseIterable, Identifiable {
    case income, expense, transfer, refund
    case investmentPurchase, investmentSale
    case loanDisbursement, loanRepayment
    case interest, dividend, fee, tax, adjustment

    var id: String { rawValue }

    var label: String {
        switch self {
        case .income: "Income"
        case .expense: "Expense"
        case .transfer: "Transfer"
        case .refund: "Refund"
        case .investmentPurchase: "Investment purchase"
        case .investmentSale: "Investment sale"
        case .loanDisbursement: "Loan disbursement"
        case .loanRepayment: "Loan repayment"
        case .interest: "Interest"
        case .dividend: "Dividend"
        case .fee: "Fee"
        case .tax: "Tax"
        case .adjustment: "Adjustment"
        }
    }

    var shortLabel: String {
        switch self {
        case .investmentPurchase: "Invested"
        case .investmentSale: "Redemption"
        case .loanDisbursement: "Loan received"
        case .loanRepayment: "Loan payment"
        default: label
        }
    }

    var icon: String {
        switch self {
        case .income: "arrow.down.left"
        case .expense: "arrow.up.right"
        case .transfer: "arrow.left.arrow.right"
        case .refund: "arrow.uturn.left"
        case .investmentPurchase: "chart.line.uptrend.xyaxis"
        case .investmentSale: "chart.line.downtrend.xyaxis"
        case .loanDisbursement: "banknote"
        case .loanRepayment: "calendar.badge.minus"
        case .interest: "percent"
        case .dividend: "gift"
        case .fee: "exclamationmark.circle"
        case .tax: "doc.text"
        case .adjustment: "slider.horizontal.3"
        }
    }

    var isTransferLike: Bool { self == .transfer }
    var isInvestmentFlow: Bool { self == .investmentPurchase || self == .investmentSale }
    var isDebtFlow: Bool { self == .loanDisbursement || self == .loanRepayment }
}

enum FinDirection: String, Codable, CaseIterable, Identifiable {
    case inflow, outflow
    var id: String { rawValue }
    var label: String { self == .inflow ? "Money in" : "Money out" }
    var sign: Int { self == .inflow ? 1 : -1 }
}

enum FinSource: String, Codable, CaseIterable, Identifiable {
    case manual, imported, recurring, demo, adjustment, migration
    var id: String { rawValue }
    var label: String {
        switch self {
        case .manual: "Manual"
        case .imported: "Imported"
        case .recurring: "Recurring"
        case .demo: "Demo"
        case .adjustment: "Adjustment"
        case .migration: "Migrated"
        }
    }
}

enum FinVerification: String, Codable, CaseIterable, Identifiable {
    case unverified, needsReview, verified, reconciled
    var id: String { rawValue }
    var label: String {
        switch self {
        case .unverified: "Unverified"
        case .needsReview: "Needs review"
        case .verified: "Verified"
        case .reconciled: "Reconciled"
        }
    }
    var isTrusted: Bool { self == .verified || self == .reconciled }
}

enum FinPaymentMethod: String, Codable, CaseIterable, Identifiable {
    case upi, card, netBanking, cash, autoDebit, cheque, bankTransfer, other
    var id: String { rawValue }
    var label: String {
        switch self {
        case .upi: "UPI"
        case .card: "Card"
        case .netBanking: "Net banking"
        case .cash: "Cash"
        case .autoDebit: "Auto debit"
        case .cheque: "Cheque"
        case .bankTransfer: "Bank transfer"
        case .other: "Other"
        }
    }
}

/// What we actually know about a number. Used everywhere a balance, valuation
/// or historical point could be measured, derived, carried forward or absent.
enum FinCertainty: String, Codable, CaseIterable, Identifiable {
    case verified, calculated, estimated, unknown
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .verified: "checkmark.seal.fill"
        case .calculated: "function"
        case .estimated: "waveform.path.ecg"
        case .unknown: "questionmark.circle"
        }
    }
    var rank: Int {
        switch self {
        case .verified: 3
        case .calculated: 2
        case .estimated: 1
        case .unknown: 0
        }
    }
    static func worst(_ values: [FinCertainty]) -> FinCertainty {
        values.min { $0.rank < $1.rank } ?? .unknown
    }
}

enum FinAssetClass: String, Codable, CaseIterable, Identifiable {
    case equity, mutualFund, etf, gold, silver, fixedDeposit, recurringDeposit, bond, other
    var id: String { rawValue }
    var label: String {
        switch self {
        case .equity: "Equity shares"
        case .mutualFund: "Mutual funds"
        case .etf: "ETFs"
        case .gold: "Gold"
        case .silver: "Silver"
        case .fixedDeposit: "Fixed deposits"
        case .recurringDeposit: "Recurring deposits"
        case .bond: "Bonds"
        case .other: "Other assets"
        }
    }
    var shortLabel: String {
        switch self {
        case .equity: "Equity"
        case .mutualFund: "Mutual funds"
        case .etf: "ETFs"
        case .gold: "Gold"
        case .silver: "Silver"
        case .fixedDeposit: "FD"
        case .recurringDeposit: "RD"
        case .bond: "Bonds"
        case .other: "Other"
        }
    }
    var icon: String {
        switch self {
        case .equity: "chart.bar.xaxis"
        case .mutualFund: "chart.pie"
        case .etf: "square.stack.3d.up"
        case .gold: "circle.hexagongrid"
        case .silver: "circle.hexagongrid.fill"
        case .fixedDeposit: "lock.square"
        case .recurringDeposit: "calendar.badge.clock"
        case .bond: "doc.text"
        case .other: "shippingbox"
        }
    }
}

enum FinValuationSource: String, Codable, CaseIterable, Identifiable {
    case manual, statement, provider
    var id: String { rawValue }
    var label: String {
        switch self {
        case .manual: "Manual valuation"
        case .statement: "Statement valuation"
        case .provider: "Market provider"
        }
    }
}

enum FinLiabilityKind: String, Codable, CaseIterable, Identifiable {
    case creditCard, personalLoan, educationLoan, homeLoan, goldLoan, vehicleLoan, informal, other
    var id: String { rawValue }
    var label: String {
        switch self {
        case .creditCard: "Credit card"
        case .personalLoan: "Personal loan"
        case .educationLoan: "Education loan"
        case .homeLoan: "Home loan"
        case .goldLoan: "Gold loan"
        case .vehicleLoan: "Vehicle loan"
        case .informal: "Informal loan"
        case .other: "Other liability"
        }
    }
    var icon: String {
        switch self {
        case .creditCard: "creditcard"
        case .personalLoan: "person.text.rectangle"
        case .educationLoan: "graduationcap"
        case .homeLoan: "house"
        case .goldLoan: "seal"
        case .vehicleLoan: "car"
        case .informal: "person.2"
        case .other: "doc.text"
        }
    }
}

enum FinOwnership: String, Codable, CaseIterable, Identifiable {
    case personal, household, shared
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum FinBudgetPeriod: String, Codable, CaseIterable, Identifiable {
    case monthly, quarterly, annual, custom
    var id: String { rawValue }
    var label: String {
        switch self {
        case .monthly: "Monthly"
        case .quarterly: "Quarterly"
        case .annual: "Annual"
        case .custom: "Custom"
        }
    }
}

enum FinGoalKind: String, Codable, CaseIterable, Identifiable {
    case emergencyFund, investment, savings, purchase, debtPayoff, custom
    var id: String { rawValue }
    var label: String {
        switch self {
        case .emergencyFund: "Emergency fund"
        case .investment: "Investment target"
        case .savings: "Savings target"
        case .purchase: "Major purchase"
        case .debtPayoff: "Debt repayment"
        case .custom: "Custom goal"
        }
    }
    var icon: String {
        switch self {
        case .emergencyFund: "shield.lefthalf.filled"
        case .investment: "chart.line.uptrend.xyaxis"
        case .savings: "banknote"
        case .purchase: "bag"
        case .debtPayoff: "creditcard.and.123"
        case .custom: "target"
        }
    }
}

enum FinRecurringKind: String, Codable, CaseIterable, Identifiable {
    case subscription, rent, emi, insurance, bill, sip, recurringDeposit, other
    var id: String { rawValue }
    var label: String {
        switch self {
        case .subscription: "Subscription"
        case .rent: "Rent"
        case .emi: "EMI"
        case .insurance: "Insurance"
        case .bill: "Bill"
        case .sip: "SIP"
        case .recurringDeposit: "Recurring deposit"
        case .other: "Other"
        }
    }
    var icon: String {
        switch self {
        case .subscription: "repeat"
        case .rent: "house"
        case .emi: "calendar.badge.clock"
        case .insurance: "shield"
        case .bill: "bolt"
        case .sip: "chart.line.uptrend.xyaxis"
        case .recurringDeposit: "lock.square"
        case .other: "clock.arrow.circlepath"
        }
    }
}

enum FinRecurringCadence: String, Codable, CaseIterable, Identifiable {
    case weekly, monthly, quarterly, halfYearly, yearly, custom
    var id: String { rawValue }
    var label: String {
        switch self {
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        case .quarterly: "Quarterly"
        case .halfYearly: "Half-yearly"
        case .yearly: "Yearly"
        case .custom: "Custom"
        }
    }
    /// How many times this cadence charges in a year, for annual commitments.
    var annualMultiplier: Double {
        switch self {
        case .weekly: 52
        case .monthly: 12
        case .quarterly: 4
        case .halfYearly: 2
        case .yearly: 1
        case .custom: 12
        }
    }
}

enum FinStatementStatus: String, Codable, CaseIterable, Identifiable {
    case awaitingParser, parsed, failed, archived
    var id: String { rawValue }
    var label: String {
        switch self {
        case .awaitingParser: "Awaiting parser"
        case .parsed: "Parsed"
        case .failed: "Failed"
        case .archived: "Archived"
        }
    }
}

enum FinImportStatus: String, Codable, CaseIterable, Identifiable {
    case draft, review, confirmed, failed
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum FinImportRowStatus: String, Codable, CaseIterable, Identifiable {
    case pending, ready, skipped, imported, error
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum FinReconciliationStatus: String, Codable, CaseIterable, Identifiable {
    case pending, matched, mismatch
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum FinMilestoneKind: String, Codable, CaseIterable, Identifiable {
    case firstAccount, firstIncome, firstFreelance, firstSalary, firstInvestment
    case majorPurchase, debt, savings, netWorth, custom
    var id: String { rawValue }
    var label: String {
        switch self {
        case .firstAccount: "First account"
        case .firstIncome: "First income"
        case .firstFreelance: "First freelance payment"
        case .firstSalary: "First salary"
        case .firstInvestment: "First investment"
        case .majorPurchase: "Major purchase"
        case .debt: "Debt"
        case .savings: "Savings"
        case .netWorth: "Net worth"
        case .custom: "Milestone"
        }
    }
    var icon: String {
        switch self {
        case .firstAccount: "building.columns"
        case .firstIncome: "arrow.down.left"
        case .firstFreelance: "laptopcomputer"
        case .firstSalary: "briefcase"
        case .firstInvestment: "chart.line.uptrend.xyaxis"
        case .majorPurchase: "bag"
        case .debt: "creditcard"
        case .savings: "banknote"
        case .netWorth: "chart.xyaxis.line"
        case .custom: "star"
        }
    }
}

enum FinAuditAction: String, Codable, CaseIterable, Identifiable {
    case created, updated, deleted, imported, matched, reconciled, restored, bulkUpdated
    var id: String { rawValue }
    var label: String {
        switch self {
        case .created: "Created"
        case .updated: "Corrected"
        case .deleted: "Deleted"
        case .imported: "Imported"
        case .matched: "Matched"
        case .reconciled: "Reconciled"
        case .restored: "Restored"
        case .bulkUpdated: "Bulk update"
        }
    }
}

// MARK: - Entities

struct FinAccount: Codable, Identifiable, Hashable {
    var id: String = FinID.new()
    var name: String
    var institution: String = ""
    var type: FinAccountType = .savings
    var currency: String = FinanceSchema.currency
    var openingDate: String = FinanceCal.today()
    var openingBalancePaise: Int64 = 0
    /// Latest known balance from a statement or manual check. When present it is
    /// the anchor; transactions after `statementBalanceOn` are added on top.
    var statementBalancePaise: Int64? = nil
    var statementBalanceOn: String? = nil
    var statementBalanceSource: FinCertainty = .verified
    var creditLimitPaise: Int64? = nil
    var status: FinAccountStatus = .active
    var notes: String = ""
    var lastReconciledOn: String? = nil
    var isDemo: Bool = false
    var createdAt: String = FinNow.stamp()
    var updatedAt: String = FinNow.stamp()

    var anchorDate: String { statementBalanceOn ?? openingDate }
    var anchorBalancePaise: Int64 { statementBalancePaise ?? openingBalancePaise }
}

struct FinCategory: Codable, Identifiable, Hashable {
    var id: String = FinID.new()
    var name: String
    var kind: FinCategoryKind
    var group: String = "Other"
    var icon: String = "circle"
    var parentID: String? = nil
    var isSystem: Bool = false
    var archived: Bool = false
    var isDemo: Bool = false
    var createdAt: String = FinNow.stamp()

    var displayName: String {
        group.isEmpty || group == "Other" ? name : "\(group) · \(name)"
    }
}

struct FinTransaction: Codable, Identifiable, Hashable {
    var id: String = FinID.new()
    var date: String = FinanceCal.today()
    var postedDate: String? = nil
    var amountPaise: Int64 = 0
    var currency: String = FinanceSchema.currency
    var direction: FinDirection = .outflow
    var type: FinTxnType = .expense
    var accountID: String = ""
    var transferAccountID: String? = nil
    var categoryID: String? = nil
    var subcategoryID: String? = nil
    var merchant: String = ""
    var paymentMethod: FinPaymentMethod = .other
    var note: String = ""
    var reference: String = ""
    var tags: [String] = []
    var source: FinSource = .manual
    var statementID: String? = nil
    var importBatchID: String? = nil
    var verification: FinVerification = .unverified
    var transferID: String? = nil
    var linkedTransactionID: String? = nil
    var investmentID: String? = nil
    var liabilityID: String? = nil
    /// For loan repayments: the part that reduces principal vs the part that is
    /// interest expense. Both are in paise; principal + interest should equal
    /// the cash amount where known.
    var principalPaise: Int64? = nil
    var interestPaise: Int64? = nil
    /// For an investment sale: what the sold units originally cost, and the
    /// resulting realised gain. Kept on the transaction so a sale can be
    /// audited and taxed without reconstructing history from valuations.
    var costBasisPaise: Int64? = nil
    var realisedGainPaise: Int64? = nil
    var isDemo: Bool = false
    var createdAt: String = FinNow.stamp()
    var updatedAt: String = FinNow.stamp()

    var signedPaise: Int64 { direction == .inflow ? amountPaise : -amountPaise }

    var title: String {
        if !merchant.isEmpty { return merchant }
        if !note.isEmpty { return note }
        return type.label
    }
}

struct FinTransfer: Codable, Identifiable, Hashable {
    var id: String = FinID.new()
    var fromAccountID: String
    var toAccountID: String
    var amountPaise: Int64
    var date: String
    var feePaise: Int64 = 0
    var reference: String = ""
    var note: String = ""
    var fromTransactionID: String? = nil
    var toTransactionID: String? = nil
    var feeTransactionID: String? = nil
    var reconciled: Bool = false
    var isDemo: Bool = false
    var createdAt: String = FinNow.stamp()
}

struct FinBudget: Codable, Identifiable, Hashable {
    var id: String = FinID.new()
    var name: String = ""
    var categoryID: String? = nil
    var period: FinBudgetPeriod = .monthly
    var startDate: String = FinanceCal.monthStart(FinanceCal.today())
    var endDate: String? = nil
    var plannedPaise: Int64 = 0
    var note: String = ""
    var archived: Bool = false
    var isDemo: Bool = false
    var createdAt: String = FinNow.stamp()

    func range(containing key: String) -> (start: String, end: String) {
        switch period {
        case .monthly:
            return (FinanceCal.monthStart(key), FinanceCal.monthEnd(key))
        case .quarterly:
            let month = Int(key.dropFirst(5).prefix(2)) ?? 1
            let firstMonth = ((month - 1) / 3) * 3 + 1
            let start = "\(String(key.prefix(4)))-\(String(format: "%02d", firstMonth))-01"
            return (start, FinanceCal.monthEnd(FinanceCal.addMonths(2, to: start)))
        case .annual:
            return (FinanceCal.yearStart(key), FinanceCal.yearEnd(key))
        case .custom:
            return (startDate, endDate ?? FinanceCal.monthEnd(key))
        }
    }
}

struct FinValuation: Codable, Identifiable, Hashable {
    var id: String = FinID.new()
    var investmentID: String
    var date: String
    var valuePaise: Int64
    var source: FinValuationSource = .manual
    var note: String = ""
    var isDemo: Bool = false
    var createdAt: String = FinNow.stamp()
}

struct FinInvestment: Codable, Identifiable, Hashable {
    var id: String = FinID.new()
    var name: String
    var assetClass: FinAssetClass = .mutualFund
    var institution: String = ""
    var units: Double? = nil
    var purchaseDate: String? = nil
    var purchasePricePaise: Int64? = nil
    var investedPaise: Int64 = 0
    var currentValuePaise: Int64 = 0
    var currentValueOn: String = FinanceCal.today()
    var realisedGainPaise: Int64 = 0
    var dividendsPaise: Int64 = 0
    var interestPaise: Int64 = 0
    var notes: String = ""
    var accountID: String? = nil
    var archived: Bool = false
    var isDemo: Bool = false
    var createdAt: String = FinNow.stamp()
    var updatedAt: String = FinNow.stamp()
}

struct FinLiability: Codable, Identifiable, Hashable {
    var id: String = FinID.new()
    var name: String
    var kind: FinLiabilityKind = .personalLoan
    var lender: String = ""
    var ownership: FinOwnership = .personal
    var originalPrincipalPaise: Int64 = 0
    /// Outstanding as of `asOf`. Principal repayments after this date reduce it.
    var outstandingPaise: Int64 = 0
    var asOf: String = FinanceCal.today()
    var interestRateBps: Int = 0
    var emiPaise: Int64 = 0
    var dueDay: Int = 5
    var startDate: String = FinanceCal.today()
    var maturityDate: String? = nil
    var accountID: String? = nil
    var notes: String = ""
    var closed: Bool = false
    var isDemo: Bool = false
    var createdAt: String = FinNow.stamp()
    var updatedAt: String = FinNow.stamp()
}

struct FinDebtPayment: Codable, Identifiable, Hashable {
    var id: String = FinID.new()
    var liabilityID: String
    var transactionID: String? = nil
    var date: String
    var amountPaise: Int64
    var principalPaise: Int64
    var interestPaise: Int64
    var note: String = ""
    var isDemo: Bool = false
    var createdAt: String = FinNow.stamp()
}

struct FinGoal: Codable, Identifiable, Hashable {
    var id: String = FinID.new()
    var name: String
    var kind: FinGoalKind = .savings
    var targetPaise: Int64 = 0
    var currentPaise: Int64 = 0
    var deadline: String? = nil
    var monthlyContributionPaise: Int64 = 0
    var accountID: String? = nil
    var note: String = ""
    var achieved: Bool = false
    var isDemo: Bool = false
    var createdAt: String = FinNow.stamp()
    var updatedAt: String = FinNow.stamp()
}

struct FinRecurring: Codable, Identifiable, Hashable {
    var id: String = FinID.new()
    var name: String
    var kind: FinRecurringKind = .subscription
    var amountPaise: Int64 = 0
    var cadence: FinRecurringCadence = .monthly
    var intervalDays: Int? = nil
    var nextDate: String = FinanceCal.today()
    var accountID: String? = nil
    var categoryID: String? = nil
    var vendor: String = ""
    var note: String = ""
    var active: Bool = true
    var isDemo: Bool = false
    var createdAt: String = FinNow.stamp()
    var updatedAt: String = FinNow.stamp()
}

struct FinStatement: Codable, Identifiable, Hashable {
    var id: String = FinID.new()
    var accountID: String? = nil
    var institution: String = ""
    var fileName: String = ""
    var fileSize: Int = 0
    var fileType: String = ""
    var periodStart: String? = nil
    var periodEnd: String? = nil
    var uploadedAt: String = FinNow.stamp()
    var status: FinStatementStatus = .awaitingParser
    var checksum: String = ""
    var note: String = ""
    var isDemo: Bool = false
}

struct FinImportBatch: Codable, Identifiable, Hashable {
    var id: String = FinID.new()
    var statementID: String
    var createdAt: String = FinNow.stamp()
    var status: FinImportStatus = .draft
    var rowCount: Int = 0
    var importedCount: Int = 0
    var duplicateCount: Int = 0
    var errorCount: Int = 0
    var confirmedAt: String? = nil
    var note: String = ""
}

struct FinImportRow: Codable, Identifiable, Hashable {
    var id: String = FinID.new()
    var batchID: String
    var date: String
    var description: String
    var amountPaise: Int64
    var direction: FinDirection
    var reference: String = ""
    var balancePaise: Int64? = nil
    var suggestedCategoryID: String? = nil
    var duplicateOfID: String? = nil
    var transferCandidateID: String? = nil
    var status: FinImportRowStatus = .pending
    var error: String? = nil
}

struct FinReconciliation: Codable, Identifiable, Hashable {
    var id: String = FinID.new()
    var accountID: String
    var statementID: String? = nil
    var periodStart: String
    var periodEnd: String
    var openingPaise: Int64 = 0
    /// What the ledger said the opening should be at the time this was
    /// recorded. Kept so an opening mismatch is a real, reviewable delta
    /// rather than a later recalculation.
    var expectedOpeningPaise: Int64? = nil
    var closingPaise: Int64 = 0
    var computedClosingPaise: Int64 = 0
    var status: FinReconciliationStatus = .pending
    var note: String = ""
    var isDemo: Bool = false
    var createdAt: String = FinNow.stamp()
}

struct FinAuditEntry: Codable, Identifiable, Hashable {
    var id: String = FinID.new()
    var entityType: String
    var entityID: String
    var action: FinAuditAction
    var field: String? = nil
    var oldValue: String? = nil
    var newValue: String? = nil
    var reason: String = ""
    var actor: String = "You"
    var at: String = FinNow.stamp()
    var sourceTransactionID: String? = nil
    var isDemo: Bool = false
}

struct FinSnapshot: Codable, Identifiable, Hashable {
    var id: String = FinID.new()
    var date: String
    var netWorthPaise: Int64
    var assetsPaise: Int64
    var liabilitiesPaise: Int64
    var certainty: FinCertainty = .calculated
    var note: String = ""
    var isDemo: Bool = false
}

struct FinMilestone: Codable, Identifiable, Hashable {
    var id: String = FinID.new()
    var date: String
    var title: String
    var detail: String = ""
    var kind: FinMilestoneKind = .custom
    var certainty: FinCertainty = .verified
    var linkedTransactionID: String? = nil
    var isDemo: Bool = false
    var createdAt: String = FinNow.stamp()
}

struct FinSettings: Codable, Hashable {
    var trackingStartDate: String = FinanceCal.today()
    var birthDate: String? = nil
    var currency: String = FinanceSchema.currency
    var locale: String = FinanceSchema.locale
    var includeHouseholdInNetWorth: Bool = false
    var emergencyFundMonths: Int = 6
    var hideBalances: Bool = false
    var demoMode: Bool = false
    var demoSeededAt: String? = nil
}

struct FinanceDocument: Codable, Hashable {
    var schemaVersion: Int = FinanceSchema.version
    var updatedAt: String = FinNow.stamp()
    var settings: FinSettings = FinSettings()
    var accounts: [FinAccount] = []
    var categories: [FinCategory] = []
    var transactions: [FinTransaction] = []
    var transfers: [FinTransfer] = []
    var budgets: [FinBudget] = []
    var investments: [FinInvestment] = []
    var valuations: [FinValuation] = []
    var liabilities: [FinLiability] = []
    var debtPayments: [FinDebtPayment] = []
    var goals: [FinGoal] = []
    var recurring: [FinRecurring] = []
    var statements: [FinStatement] = []
    var importBatches: [FinImportBatch] = []
    var importRows: [FinImportRow] = []
    var reconciliations: [FinReconciliation] = []
    var audit: [FinAuditEntry] = []
    var snapshots: [FinSnapshot] = []
    var milestones: [FinMilestone] = []

    var isEmpty: Bool {
        accounts.isEmpty && transactions.isEmpty && investments.isEmpty
            && liabilities.isEmpty && budgets.isEmpty && goals.isEmpty
            && recurring.isEmpty
    }

    var hasDemoRecords: Bool {
        settings.demoMode || accounts.contains(where: \.isDemo)
            || transactions.contains(where: \.isDemo)
            || investments.contains(where: \.isDemo)
            || liabilities.contains(where: \.isDemo)
    }

    func account(_ id: String?) -> FinAccount? {
        guard let id else { return nil }
        return accounts.first { $0.id == id }
    }

    func category(_ id: String?) -> FinCategory? {
        guard let id else { return nil }
        return categories.first { $0.id == id }
    }

    func transaction(_ id: String?) -> FinTransaction? {
        guard let id else { return nil }
        return transactions.first { $0.id == id }
    }

    func investment(_ id: String?) -> FinInvestment? {
        guard let id else { return nil }
        return investments.first { $0.id == id }
    }

    func liability(_ id: String?) -> FinLiability? {
        guard let id else { return nil }
        return liabilities.first { $0.id == id }
    }

    var sortedTransactions: [FinTransaction] {
        transactions.sorted {
            if $0.date != $1.date { return $0.date > $1.date }
            return $0.createdAt > $1.createdAt
        }
    }
}

// MARK: - Default taxonomy

enum FinanceTaxonomy {
    struct Seed {
        let key: String
        let name: String
        let kind: FinCategoryKind
        let group: String
        let icon: String
    }

    /// The starting structure. Every category can be renamed, extended with
    /// subcategories, or archived; these are seed rows, not hard-coded logic.
    static let seeds: [Seed] = [
        // Income
        .init(key: "income.salary", name: "Salary", kind: .income, group: "Employment", icon: "briefcase"),
        .init(key: "income.freelance", name: "Freelancing", kind: .income, group: "Independent work", icon: "laptopcomputer"),
        .init(key: "income.consulting", name: "Consulting", kind: .income, group: "Independent work", icon: "person.2"),
        .init(key: "income.creator", name: "Creator revenue", kind: .income, group: "Creator", icon: "play.rectangle"),
        .init(key: "income.youtube", name: "YouTube revenue", kind: .income, group: "Creator", icon: "play.square.stack"),
        .init(key: "income.sponsorship", name: "Sponsorships", kind: .income, group: "Creator", icon: "megaphone"),
        .init(key: "income.affiliate", name: "Affiliate income", kind: .income, group: "Creator", icon: "link"),
        .init(key: "income.business", name: "Business income", kind: .income, group: "Business", icon: "building.2"),
        .init(key: "income.interest", name: "Interest", kind: .income, group: "Investments", icon: "percent"),
        .init(key: "income.dividend", name: "Dividends", kind: .income, group: "Investments", icon: "gift"),
        .init(key: "income.gift", name: "Gifts", kind: .income, group: "Other income", icon: "gift.fill"),
        .init(key: "income.refund", name: "Refunds", kind: .income, group: "Other income", icon: "arrow.uturn.left"),
        .init(key: "income.other", name: "Other income", kind: .income, group: "Other income", icon: "plus.circle"),

        // Living
        .init(key: "expense.rent", name: "Rent", kind: .expense, group: "Living", icon: "house"),
        .init(key: "expense.utilities", name: "Utilities", kind: .expense, group: "Living", icon: "bolt"),
        .init(key: "expense.groceries", name: "Groceries", kind: .expense, group: "Living", icon: "cart"),
        .init(key: "expense.food", name: "Food", kind: .expense, group: "Living", icon: "fork.knife"),
        .init(key: "expense.transport", name: "Transportation", kind: .expense, group: "Living", icon: "car"),
        .init(key: "expense.household", name: "Household", kind: .expense, group: "Living", icon: "sofa"),

        // Lifestyle
        .init(key: "expense.shopping", name: "Shopping", kind: .expense, group: "Lifestyle", icon: "bag"),
        .init(key: "expense.entertainment", name: "Entertainment", kind: .expense, group: "Lifestyle", icon: "ticket"),
        .init(key: "expense.travel", name: "Travel", kind: .expense, group: "Lifestyle", icon: "airplane"),
        .init(key: "expense.social", name: "Social spending", kind: .expense, group: "Lifestyle", icon: "person.3"),
        .init(key: "expense.personalCare", name: "Personal care", kind: .expense, group: "Lifestyle", icon: "sparkles"),
        .init(key: "expense.subscriptions", name: "Subscriptions", kind: .expense, group: "Lifestyle", icon: "repeat"),

        // Financial
        .init(key: "expense.investment", name: "Investment", kind: .expense, group: "Financial", icon: "chart.line.uptrend.xyaxis"),
        .init(key: "expense.insurance", name: "Insurance", kind: .expense, group: "Financial", icon: "shield"),
        .init(key: "expense.bankCharges", name: "Bank charges", kind: .expense, group: "Financial", icon: "building.columns"),
        .init(key: "expense.interest", name: "Interest", kind: .expense, group: "Financial", icon: "percent"),
        .init(key: "expense.tax", name: "Tax", kind: .expense, group: "Financial", icon: "doc.text"),
        .init(key: "expense.debt", name: "Debt repayment", kind: .expense, group: "Financial", icon: "creditcard"),

        // Business
        .init(key: "expense.equipment", name: "Equipment", kind: .expense, group: "Business", icon: "camera"),
        .init(key: "expense.software", name: "Software", kind: .expense, group: "Business", icon: "app"),
        .init(key: "expense.production", name: "Production", kind: .expense, group: "Business", icon: "film"),
        .init(key: "expense.marketing", name: "Marketing", kind: .expense, group: "Business", icon: "megaphone"),
        .init(key: "expense.businessTravel", name: "Business travel", kind: .expense, group: "Business", icon: "airplane.departure"),
        .init(key: "expense.freelance", name: "Freelance expenses", kind: .expense, group: "Business", icon: "person.crop.rectangle"),
        .init(key: "expense.other", name: "Uncategorised", kind: .expense, group: "Other", icon: "questionmark.circle"),
    ]

    static func defaultCategories() -> [FinCategory] {
        seeds.map { s in
            FinCategory(id: FinID.stable("finance.category." + s.key), name: s.name,
                        kind: s.kind, group: s.group, icon: s.icon, isSystem: true)
        }
    }

    static func categoryID(_ key: String) -> String {
        FinID.stable("finance.category." + key)
    }

    static func defaultExpenseCategoryID() -> String { categoryID("expense.other") }
    static func defaultIncomeCategoryID() -> String { categoryID("income.other") }
}

enum FinAudit {
    static func record(_ doc: inout FinanceDocument,
                       entityType: String,
                       entityID: String,
                       action: FinAuditAction,
                       field: String? = nil,
                       oldValue: String? = nil,
                       newValue: String? = nil,
                       reason: String = "",
                       sourceTransactionID: String? = nil,
                       isDemo: Bool = false) {
        doc.audit.append(FinAuditEntry(entityType: entityType, entityID: entityID,
                                       action: action, field: field,
                                       oldValue: oldValue, newValue: newValue,
                                       reason: reason, actor: "You",
                                       sourceTransactionID: sourceTransactionID,
                                       isDemo: isDemo))
    }
}

