import Foundation

// All MyOS data. Each top-level model maps to one `myos.*` JSON key in the
// backend's per-user state store. Add a module → add a model + a key here.

struct AuthUser: Codable, Hashable {
    let id: Int
    let username: String
}

// MARK: - Finance  (key: myos.finance)

enum TxnKind: String, Codable, Hashable {
    case income, expense
}

/// How worthwhile a spend was — the "useless / useful / best investment" read
/// the user asked for. Set by the AI (or by hand); nil until judged. Income has none.
enum TxnQuality: String, Codable, Hashable, CaseIterable {
    case useless        // impulse / avoidable / a want he could skip
    case useful         // a genuine need — rent, groceries, bills, transport
    case investment     // builds future wealth, skills, health or income
}

/// Where a transaction came from — a small trust signal on the row.
enum TxnSource: String, Codable, Hashable {
    case manual         // typed into the form
    case screenshot     // read from a UPI screenshot
    case statement      // read from a bank statement
    case ai             // parsed from the command bar
}

struct Transaction: Codable, Identifiable, Hashable {
    var id: String
    var date: String            // yyyy-MM-dd
    var kind: TxnKind
    var amountInr: Double
    var category: String
    var quality: TxnQuality?    // useless / useful / investment
    var merchant: String?       // payee or sender (from a screenshot)
    var account: String?        // bank / app the money moved through
    var note: String?
    var source: TxnSource?

    init(id: String, date: String, kind: TxnKind, amountInr: Double, category: String,
         quality: TxnQuality? = nil, merchant: String? = nil, account: String? = nil,
         note: String? = nil, source: TxnSource? = nil) {
        self.id = id; self.date = date; self.kind = kind
        self.amountInr = amountInr; self.category = category
        self.quality = quality; self.merchant = merchant; self.account = account
        self.note = note; self.source = source
    }

    enum CodingKeys: String, CodingKey {
        case id, date, kind, amountInr, category, quality, merchant, account, note, source
    }

    // Lenient: a row missing any field decodes instead of failing the whole load.
    // Fields added later (quality/merchant/account/source) default to nil on old rows.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id        = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString.lowercased()
        date      = try c.decodeIfPresent(String.self, forKey: .date) ?? ""
        kind      = (try? c.decode(TxnKind.self, forKey: .kind)) ?? .expense
        amountInr = try c.decodeIfPresent(Double.self, forKey: .amountInr) ?? 0
        category  = try c.decodeIfPresent(String.self, forKey: .category) ?? "other"
        quality   = try? c.decode(TxnQuality.self, forKey: .quality)
        merchant  = try c.decodeIfPresent(String.self, forKey: .merchant)
        account   = try c.decodeIfPresent(String.self, forKey: .account)
        note      = try c.decodeIfPresent(String.self, forKey: .note)
        source    = try? c.decode(TxnSource.self, forKey: .source)
    }
}

/// The canonical category vocabulary. Mirrors apps/web/src/lib/finance.ts — keep
/// the two lists in sync. Visual styling (icon + colour) lives in Theme.swift.
enum Categories {
    static let all = [
        "food", "groceries", "transport", "travel", "shopping", "gadgets",
        "health", "fitness", "bills", "rent", "subscriptions", "entertainment",
        "education", "editor", "family", "loan", "investment",
        "salary", "freelance", "refund", "misc"
    ]
    /// Categories that read as income (used to default the kind toggle).
    static let income = ["salary", "freelance", "refund"]
}

struct FinanceMeta: Codable, Hashable {
    // Neutral defaults — a fresh account starts empty. Real values live in the
    // user's synced DB record and load on hydrate; nothing personal is seeded here.
    var goldLoanStartInr: Double = 0
    var goldLoanOutstandingInr: Double = 0
    var goldLoanRatePct: Double = 0
    var emergencyTargetInr: Double = 0
    var emergencyCurrentInr: Double = 0
    var monthlyIncomeInr: Double = 0
    var termInsuranceBought: Bool = false
    var healthInsuranceBought: Bool = false

    init() {}

    enum CodingKeys: String, CodingKey {
        case goldLoanStartInr, goldLoanOutstandingInr, goldLoanRatePct
        case emergencyTargetInr, emergencyCurrentInr, monthlyIncomeInr
        case termInsuranceBought, healthInsuranceBought
    }

    // Lenient: fields added in later versions default instead of throwing, so an
    // older stored meta still loads (this was the hydrate-breaking bug).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = FinanceMeta()
        goldLoanStartInr       = try c.decodeIfPresent(Double.self, forKey: .goldLoanStartInr) ?? d.goldLoanStartInr
        goldLoanOutstandingInr = try c.decodeIfPresent(Double.self, forKey: .goldLoanOutstandingInr) ?? d.goldLoanOutstandingInr
        goldLoanRatePct        = try c.decodeIfPresent(Double.self, forKey: .goldLoanRatePct) ?? d.goldLoanRatePct
        emergencyTargetInr     = try c.decodeIfPresent(Double.self, forKey: .emergencyTargetInr) ?? d.emergencyTargetInr
        emergencyCurrentInr    = try c.decodeIfPresent(Double.self, forKey: .emergencyCurrentInr) ?? d.emergencyCurrentInr
        monthlyIncomeInr       = try c.decodeIfPresent(Double.self, forKey: .monthlyIncomeInr) ?? d.monthlyIncomeInr
        termInsuranceBought    = try c.decodeIfPresent(Bool.self, forKey: .termInsuranceBought) ?? d.termInsuranceBought
        healthInsuranceBought  = try c.decodeIfPresent(Bool.self, forKey: .healthInsuranceBought) ?? d.healthInsuranceBought
    }
}

struct FinanceState: Codable, Hashable {
    var txns: [Transaction] = []
    var meta: FinanceMeta = FinanceMeta()

    init() {}

    enum CodingKeys: String, CodingKey { case txns, meta }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        txns = try c.decodeIfPresent([Transaction].self, forKey: .txns) ?? []
        meta = try c.decodeIfPresent(FinanceMeta.self, forKey: .meta) ?? FinanceMeta()
    }
}

// MARK: - Portfolio  (key: myos.portfolio)

enum HoldingType: String, Codable, Hashable, CaseIterable {
    case stock, mutualFund, etf, gold, crypto, other
    var label: String {
        switch self {
        case .stock: return "Stock"
        case .mutualFund: return "Mutual fund"
        case .etf: return "ETF"
        case .gold: return "Gold"
        case .crypto: return "Crypto"
        case .other: return "Other"
        }
    }
}

/// One position read from a portfolio screenshot.
struct Holding: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var type: HoldingType
    var investedInr: Double
    var currentInr: Double
    var units: Double?
    var note: String?
    var symbol: String?     // Groww exchange symbol (e.g. "NSE_ITC") for live prices

    init(id: String = UUID().uuidString.lowercased(), name: String, type: HoldingType,
         investedInr: Double, currentInr: Double, units: Double? = nil, note: String? = nil,
         symbol: String? = nil) {
        self.id = id; self.name = name; self.type = type
        self.investedInr = investedInr; self.currentInr = currentInr
        self.units = units; self.note = note; self.symbol = symbol
    }

    enum CodingKeys: String, CodingKey { case id, name, type, investedInr, currentInr, units, note, symbol }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id          = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString.lowercased()
        name        = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        type        = (try? c.decode(HoldingType.self, forKey: .type)) ?? .other
        investedInr = try c.decodeIfPresent(Double.self, forKey: .investedInr) ?? 0
        currentInr  = try c.decodeIfPresent(Double.self, forKey: .currentInr) ?? 0
        units       = try c.decodeIfPresent(Double.self, forKey: .units)
        note        = try c.decodeIfPresent(String.self, forKey: .note)
        symbol      = try c.decodeIfPresent(String.self, forKey: .symbol)
    }

    var pnl: Double { currentInr - investedInr }
    var returnPct: Double { investedInr > 0 ? pnl / investedInr : 0 }
}

/// A weekly snapshot of the whole portfolio — the unit the user re-uploads to track change.
struct PortfolioSnapshot: Codable, Identifiable, Hashable {
    var id: String
    var date: String            // yyyy-MM-dd
    var holdings: [Holding]
    var note: String?

    init(id: String = UUID().uuidString.lowercased(), date: String, holdings: [Holding], note: String? = nil) {
        self.id = id; self.date = date; self.holdings = holdings; self.note = note
    }

    enum CodingKeys: String, CodingKey { case id, date, holdings, note }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id       = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString.lowercased()
        date     = try c.decodeIfPresent(String.self, forKey: .date) ?? ""
        holdings = try c.decodeIfPresent([Holding].self, forKey: .holdings) ?? []
        note     = try c.decodeIfPresent(String.self, forKey: .note)
    }

    var totalInvested: Double { holdings.reduce(0) { $0 + $1.investedInr } }
    var totalCurrent: Double { holdings.reduce(0) { $0 + $1.currentInr } }
    var pnl: Double { totalCurrent - totalInvested }
    var returnPct: Double { totalInvested > 0 ? pnl / totalInvested : 0 }
}

/// The AI's weekly read on the portfolio — grounded in the finance principles.
struct PortfolioAdvice: Codable, Hashable {
    var date: String = ""       // stamped client-side after the call
    var verdict: String = ""
    var allocation: String = ""
    var diversification: String = ""
    var actions: [String] = []
    var ideas: [String] = []
    var summary: String = ""

    init() {}

    enum CodingKeys: String, CodingKey {
        case date, verdict, allocation, diversification, actions, ideas, summary
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date            = try c.decodeIfPresent(String.self, forKey: .date) ?? ""
        verdict         = try c.decodeIfPresent(String.self, forKey: .verdict) ?? ""
        allocation      = try c.decodeIfPresent(String.self, forKey: .allocation) ?? ""
        diversification = try c.decodeIfPresent(String.self, forKey: .diversification) ?? ""
        actions         = try c.decodeIfPresent([String].self, forKey: .actions) ?? []
        ideas           = try c.decodeIfPresent([String].self, forKey: .ideas) ?? []
        summary         = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
    }
}

struct PortfolioState: Codable, Hashable {
    var snapshots: [PortfolioSnapshot] = []     // newest first
    var advice: PortfolioAdvice? = nil

    init() {}

    enum CodingKeys: String, CodingKey { case snapshots, advice }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        snapshots = try c.decodeIfPresent([PortfolioSnapshot].self, forKey: .snapshots) ?? []
        advice    = try? c.decode(PortfolioAdvice.self, forKey: .advice)
    }

    var latest: PortfolioSnapshot? { snapshots.first }
    var previous: PortfolioSnapshot? { snapshots.count > 1 ? snapshots[1] : nil }
}

// MARK: - Fitness  (key: myos.fitness — [date: FitnessDay])

struct FitnessDay: Codable, Hashable {
    var weightKg: Double?
    var calories: Double?
    var proteinG: Double?
    var waterMl: Double?
    var steps: Int?             // daily step count — manual for now; the iPhone client
                               // (next month) writes this from HealthKit into the same key.
    var note: String?
}

// MARK: - Fitness profile  (key: myos.fitnessProfile)

/// The user's training intent — cut / maintain / bulk.
enum FitnessGoal: String, Codable, Hashable, CaseIterable {
    case cut, maintain, bulk
    var label: String {
        switch self {
        case .cut: return "Cut"
        case .maintain: return "Maintain"
        case .bulk: return "Bulk"
        }
    }
    /// Calorie offset from maintenance for this goal (kcal/day).
    var calorieOffset: Double {
        switch self {
        case .cut: return -500
        case .maintain: return 0
        case .bulk: return 300
        }
    }
}

/// Biological sex — needed for the Mifflin-St Jeor BMR term only.
enum Sex: String, Codable, Hashable, CaseIterable {
    case male, female
    var label: String { self == .male ? "Male" : "Female" }
}

/// Activity level → the TDEE multiplier over BMR (standard Mifflin factors).
enum ActivityLevel: String, Codable, Hashable, CaseIterable {
    case sedentary, light, moderate, active, athlete
    var multiplier: Double {
        switch self {
        case .sedentary: return 1.2
        case .light:     return 1.375
        case .moderate:  return 1.55
        case .active:    return 1.725
        case .athlete:   return 1.9
        }
    }
    var label: String {
        switch self {
        case .sedentary: return "Sedentary"
        case .light:     return "Light"
        case .moderate:  return "Moderate"
        case .active:    return "Active"
        case .athlete:   return "Athlete"
        }
    }
    var hint: String {
        switch self {
        case .sedentary: return "Desk, little exercise"
        case .light:     return "1–3 days/week"
        case .moderate:  return "3–5 days/week"
        case .active:    return "6–7 days/week"
        case .athlete:   return "Hard daily / physical job"
        }
    }
}

/// The fitness *profile* — goal + targets that stand apart from the daily log.
/// Height is deliberately NOT stored here: it lives on `Profile.heightCm` and
/// both the Fitness tab and Settings edit that one field, so they never drift.
struct FitnessProfile: Codable, Hashable {
    var goal: FitnessGoal = .maintain
    var sex: Sex = .male
    var activity: ActivityLevel = .moderate
    var targetWeightKg: Double? = nil
    var calorieTargetKcal: Double? = nil
    var proteinTargetG: Double? = nil
    var waterTargetMl: Double? = nil
    var stepsTarget: Int? = nil        // daily step goal (nil → the 8,000 default the UI shows)

    init() {}

    enum CodingKeys: String, CodingKey {
        case goal, sex, activity, targetWeightKg, calorieTargetKcal, proteinTargetG, waterTargetMl, stepsTarget
    }

    // Lenient: a profile saved before a field existed still loads.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        goal              = (try? c.decode(FitnessGoal.self, forKey: .goal)) ?? .maintain
        sex               = (try? c.decode(Sex.self, forKey: .sex)) ?? .male
        activity          = (try? c.decode(ActivityLevel.self, forKey: .activity)) ?? .moderate
        targetWeightKg    = try c.decodeIfPresent(Double.self, forKey: .targetWeightKg)
        calorieTargetKcal = try c.decodeIfPresent(Double.self, forKey: .calorieTargetKcal)
        proteinTargetG    = try c.decodeIfPresent(Double.self, forKey: .proteinTargetG)
        waterTargetMl     = try c.decodeIfPresent(Double.self, forKey: .waterTargetMl)
        stepsTarget       = try c.decodeIfPresent(Int.self, forKey: .stepsTarget)
    }
}

// MARK: - Journal  (key: myos.journal — [date: JournalEntry])

struct JournalEntry: Codable, Hashable {
    var morning: String = ""
    var night: String = ""
    var wins: [String] = []
    var mistakes: [String] = []
    var lessons: [String] = []
    var gratitude: [String] = []
    var mood: Int? = nil        // 1...5

    init() {}

    enum CodingKeys: String, CodingKey {
        case morning, night, wins, mistakes, lessons, gratitude, mood
    }

    // Lenient: older entries missing newer fields (e.g. gratitude) still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        morning   = try c.decodeIfPresent(String.self, forKey: .morning) ?? ""
        night     = try c.decodeIfPresent(String.self, forKey: .night) ?? ""
        wins      = try c.decodeIfPresent([String].self, forKey: .wins) ?? []
        mistakes  = try c.decodeIfPresent([String].self, forKey: .mistakes) ?? []
        lessons   = try c.decodeIfPresent([String].self, forKey: .lessons) ?? []
        gratitude = try c.decodeIfPresent([String].self, forKey: .gratitude) ?? []
        mood      = try c.decodeIfPresent(Int.self, forKey: .mood)
    }
}

// MARK: - Journal presets  (key: myos.journalPresets)

/// Tappable quick-add chips for the journal, editable in Settings. Lists (wins /
/// mistakes / lessons / gratitude) append a chip; reflections insert its text.
struct JournalPresets: Codable, Hashable {
    var morning: [String]
    var night: [String]
    var wins: [String]
    var mistakes: [String]
    var lessons: [String]
    var gratitude: [String]

    init(morning: [String] = Seed.morning, night: [String] = Seed.night,
         wins: [String] = Seed.wins, mistakes: [String] = Seed.mistakes,
         lessons: [String] = Seed.lessons, gratitude: [String] = Seed.gratitude) {
        self.morning = morning; self.night = night
        self.wins = wins; self.mistakes = mistakes
        self.lessons = lessons; self.gratitude = gratitude
    }

    /// Starter chips — generic, disciplined defaults. No emojis.
    enum Seed {
        static let morning   = ["Feeling grateful", "Locked in", "Slept well", "Bit tired but going"]
        static let night     = ["Productive day", "Stayed disciplined", "Could've done better", "Wasted some time"]
        static let wins      = ["Posted content", "Hit the gym", "Ate clean", "Deep work done", "Learned something", "Saved money"]
        static let mistakes  = ["Ate junk", "Skipped gym", "Slept late", "Wasted time on phone", "Overspent", "Procrastinated"]
        static let lessons   = ["Consistency beats intensity", "Show up daily", "Spend less than I earn", "Protect the mornings"]
        static let gratitude = ["Family", "Health", "The job", "Roof and food", "This journey", "Learning daily"]
    }

    enum CodingKeys: String, CodingKey { case morning, night, wins, mistakes, lessons, gratitude }

    // Lenient: a set saved before a section existed falls back to that seed.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        morning   = try c.decodeIfPresent([String].self, forKey: .morning) ?? Seed.morning
        night     = try c.decodeIfPresent([String].self, forKey: .night) ?? Seed.night
        wins      = try c.decodeIfPresent([String].self, forKey: .wins) ?? Seed.wins
        mistakes  = try c.decodeIfPresent([String].self, forKey: .mistakes) ?? Seed.mistakes
        lessons   = try c.decodeIfPresent([String].self, forKey: .lessons) ?? Seed.lessons
        gratitude = try c.decodeIfPresent([String].self, forKey: .gratitude) ?? Seed.gratitude
    }
}

// MARK: - Notes  (key: myos.notes — [Note])

struct Note: Codable, Identifiable, Hashable {
    var id: String
    var createdAt: String
    var updatedAt: String
    var title: String
    var body: String                 // plain-text mirror of `content` (search / previews / AI)
    var pinned: Bool = false
    var locked: Bool = false          // hides preview + gates the editor behind an unlock
    var content: BlockDoc? = nil      // rich block content (source of truth once edited)

    enum CodingKeys: String, CodingKey { case id, createdAt, updatedAt, title, body, pinned, locked, content }

    init(id: String, createdAt: String, updatedAt: String, title: String, body: String,
         pinned: Bool = false, locked: Bool = false, content: BlockDoc? = nil) {
        self.id = id; self.createdAt = createdAt; self.updatedAt = updatedAt
        self.title = title; self.body = body; self.pinned = pinned
        self.locked = locked; self.content = content
    }

    // Custom decode so notes saved before `pinned`/`locked`/`content` existed still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id        = try c.decode(String.self, forKey: .id)
        createdAt = try c.decode(String.self, forKey: .createdAt)
        updatedAt = try c.decode(String.self, forKey: .updatedAt)
        title     = try c.decode(String.self, forKey: .title)
        body      = try c.decode(String.self, forKey: .body)
        pinned    = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        locked    = try c.decodeIfPresent(Bool.self, forKey: .locked) ?? false
        content   = try c.decodeIfPresent(BlockDoc.self, forKey: .content)
    }

    /// The block document to edit — real `content` if present, otherwise migrated
    /// from the legacy plain-text body so old notes open as blocks with nothing lost.
    var effectiveDoc: BlockDoc { content ?? BlockDoc.from(plainText: body) }
}

// MARK: - Chat  (key: myos.chat)

/// One turn in the mentor chat. `role` is "user" or "assistant" (matches the API).
struct ChatMessage: Codable, Identifiable, Hashable {
    var id: String
    var role: String
    var content: String
    var at: String

    init(id: String = UUID().uuidString.lowercased(), role: String, content: String, at: String = "") {
        self.id = id; self.role = role; self.content = content; self.at = at
    }

    enum CodingKeys: String, CodingKey { case id, role, content, at }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id      = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString.lowercased()
        role    = try c.decodeIfPresent(String.self, forKey: .role) ?? "assistant"
        content = try c.decodeIfPresent(String.self, forKey: .content) ?? ""
        at      = try c.decodeIfPresent(String.self, forKey: .at) ?? ""
    }
}

struct ChatState: Codable, Hashable {
    var messages: [ChatMessage] = []
    init() {}
    enum CodingKeys: String, CodingKey { case messages }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        messages = try c.decodeIfPresent([ChatMessage].self, forKey: .messages) ?? []
    }
}

/// Recent tech + finance news for Today (decodes POST /api/news). Not persisted.
struct NewsResult: Codable, Hashable {
    struct Item: Codable, Hashable, Identifiable {
        var id = UUID().uuidString.lowercased()
        var title: String
        var category: String
        var summary: String
        var detail: String?          // 2-3 sentence deeper explanation (shown on expand)
        var source: String?
        var url: String?             // link to the source (opens in browser)
        var time: String?            // when it happened — human date/time
        enum CodingKeys: String, CodingKey { case title, category, summary, detail, source, url, time }
    }
    var items: [Item] = []
}

/// The Today mentor nudge (decodes POST /api/suggest). Not persisted.
struct SuggestResult: Codable, Hashable {
    struct Item: Codable, Hashable, Identifiable {
        var id = UUID().uuidString.lowercased()
        var area: String
        var title: String
        var why: String
        var impact: String
        enum CodingKeys: String, CodingKey { case area, title, why, impact }
    }
    var headline: String = ""
    var suggestions: [Item] = []
}

// MARK: - Day spine  (key: myos.days — [date: DayPlan])

struct DayPlan: Codable, Hashable {
    var focus: [String] = []            // 1–3 priorities for the day
    var habits: [String: Bool] = [:]    // habit name → done

    init() {}

    enum CodingKeys: String, CodingKey { case focus, habits }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        focus  = try c.decodeIfPresent([String].self, forKey: .focus) ?? []
        habits = try c.decodeIfPresent([String: Bool].self, forKey: .habits) ?? [:]
    }
}

// MARK: - Profile  (key: myos.profile)

/// One life milestone / achievement on the profile timeline.
struct Milestone: Codable, Identifiable, Hashable {
    var id: String
    var year: String        // "2026" or "2026-06" — display string
    var title: String
    var note: String = ""

    init(id: String = UUID().uuidString.lowercased(), year: String, title: String, note: String = "") {
        self.id = id; self.year = year; self.title = title; self.note = note
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id    = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString.lowercased()
        year  = try c.decodeIfPresent(String.self, forKey: .year) ?? ""
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        note  = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
    }
}

/// The whole person, end to end — identity, body, career, goals, achievements,
/// health. Ships EMPTY — no personal data is seeded in code. Each user fills these
/// in the app and they persist to their own synced DB record. `about` is a free-
/// text brief the AI mentor reads to know them; it too lives in the DB, not here.
struct Profile: Codable, Hashable {
    // Identity
    var name: String = ""
    var dob: String = ""                    // yyyy-MM-dd once known
    var age: Int? = nil
    var bloodGroup: String = ""
    var relationship: String = ""
    var phone: String = ""
    var email: String = ""
    var city: String = ""
    var hometown: String = ""
    var education: String = ""

    // Body
    var heightCm: Double? = nil

    // Photo — base64-encoded JPEG/PNG the user picks; empty = show initials.
    var photoBase64: String = ""

    // Career
    var role: String = ""
    var work: String = ""

    // Links
    var website: String = ""
    var instagram: String = ""
    var github: String = ""

    // Goals
    var goalsShort: [String] = []
    var goalsMid: [String] = []
    var goalsLong: [String] = []

    // Achievements
    var achievements: [Milestone] = []

    // Health
    var healthNotes: String = ""

    // Free-text brief for the AI mentor — "anything your assistant should know
    // about you" (story, family, positioning, goals). Stored in the DB, editable.
    var about: String = ""

    // Daily habit list (used by Today) — generic starter examples, not personal.
    var habits: [String] = ["Gym", "Read", "No junk", "Sleep"]

    // Fixed pick-lists for profile fields that must be one of a set (no free text).
    static let bloodGroupOptions = ["O+", "O-", "A+", "A-", "B+", "B-", "AB+", "AB-"]
    static let relationshipOptions = ["Single", "Married", "In a relationship",
                                      "Engaged", "Divorced", "Widowed"]

    enum CodingKeys: String, CodingKey {
        case name, dob, age, bloodGroup, relationship, phone, email, city, hometown, education
        case heightCm, photoBase64, role, work, website, instagram, github
        case goalsShort, goalsMid, goalsLong, achievements, healthNotes, about, habits
    }

    init() {}

    // Custom decode so profiles saved before these fields existed still load —
    // anything missing falls back to the seeded defaults above.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Profile()
        name         = try c.decodeIfPresent(String.self, forKey: .name) ?? d.name
        dob          = try c.decodeIfPresent(String.self, forKey: .dob) ?? d.dob
        age          = try c.decodeIfPresent(Int.self, forKey: .age) ?? d.age
        bloodGroup   = try c.decodeIfPresent(String.self, forKey: .bloodGroup) ?? d.bloodGroup
        relationship = try c.decodeIfPresent(String.self, forKey: .relationship) ?? d.relationship
        phone        = try c.decodeIfPresent(String.self, forKey: .phone) ?? d.phone
        email        = try c.decodeIfPresent(String.self, forKey: .email) ?? d.email
        city         = try c.decodeIfPresent(String.self, forKey: .city) ?? d.city
        hometown     = try c.decodeIfPresent(String.self, forKey: .hometown) ?? d.hometown
        education    = try c.decodeIfPresent(String.self, forKey: .education) ?? d.education
        heightCm     = try c.decodeIfPresent(Double.self, forKey: .heightCm) ?? d.heightCm
        photoBase64  = try c.decodeIfPresent(String.self, forKey: .photoBase64) ?? d.photoBase64
        role         = try c.decodeIfPresent(String.self, forKey: .role) ?? d.role
        work         = try c.decodeIfPresent(String.self, forKey: .work) ?? d.work
        website      = try c.decodeIfPresent(String.self, forKey: .website) ?? d.website
        instagram    = try c.decodeIfPresent(String.self, forKey: .instagram) ?? d.instagram
        github       = try c.decodeIfPresent(String.self, forKey: .github) ?? d.github
        goalsShort   = try c.decodeIfPresent([String].self, forKey: .goalsShort) ?? d.goalsShort
        goalsMid     = try c.decodeIfPresent([String].self, forKey: .goalsMid) ?? d.goalsMid
        goalsLong    = try c.decodeIfPresent([String].self, forKey: .goalsLong) ?? d.goalsLong
        achievements = try c.decodeIfPresent([Milestone].self, forKey: .achievements) ?? d.achievements
        healthNotes  = try c.decodeIfPresent(String.self, forKey: .healthNotes) ?? d.healthNotes
        about        = try c.decodeIfPresent(String.self, forKey: .about) ?? d.about
        habits       = try c.decodeIfPresent([String].self, forKey: .habits) ?? d.habits
    }
}

// MARK: - Profile pure logic (unit-tested)

extension Profile {
    /// Initials shown in the avatar circle when no photo is set.
    var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first.map(String.init) }.joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }

    /// Body mass index in kg/m² — nil unless both height and weight are valid (> 0).
    static func bmi(heightCm: Double, weightKg: Double) -> Double? {
        guard heightCm > 0, weightKg > 0 else { return nil }
        let m = heightCm / 100
        return weightKg / (m * m)
    }

    /// WHO-style label for a computed BMI.
    static func bmiCategory(_ bmi: Double) -> String {
        switch bmi {
        case ..<18.5: return "underweight"
        case ..<25:   return "normal range"
        case ..<30:   return "overweight"
        default:      return "obese range"
        }
    }
}

// MARK: - Events  (key: myos.events — [EventItem])

/// What kind of upcoming event this is — drives the chip colour + glyph.
enum EventCategory: String, Codable, Hashable, CaseIterable {
    case travel, family, work, personal, milestone, reminder, other
    var label: String {
        switch self {
        case .travel:    return "Travel"
        case .family:    return "Family"
        case .work:      return "Work"
        case .personal:  return "Personal"
        case .milestone: return "Milestone"
        case .reminder:  return "Reminder"
        case .other:     return "Other"
        }
    }
}

/// A user-defined event tag — name + SF Symbol + colour. The built-in seven (below) are
/// editable but not deletable; custom tags are fully removable. Ids of the built-ins are
/// the old `EventCategory` raw values so pre-tag events migrate straight onto them.
struct EventTag: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var symbol: String       // SF Symbol name
    var colorHex: String     // 6-digit RRGGBB (no leading #)
    var builtIn: Bool

    init(id: String = UUID().uuidString.lowercased(), name: String, symbol: String,
         colorHex: String, builtIn: Bool = false) {
        self.id = id; self.name = name; self.symbol = symbol
        self.colorHex = colorHex; self.builtIn = builtIn
    }

    /// The seven defaults, seeded when a user has no tags yet.
    static var seedDefaults: [EventTag] {
        [
            EventTag(id: "personal",  name: "Personal",  symbol: "person.fill",    colorHex: "58CC02", builtIn: true),
            EventTag(id: "travel",    name: "Travel",    symbol: "airplane",       colorHex: "1CB0F6", builtIn: true),
            EventTag(id: "family",    name: "Family",    symbol: "house.fill",     colorHex: "FF9600", builtIn: true),
            EventTag(id: "work",      name: "Work",      symbol: "briefcase.fill", colorHex: "FFC800", builtIn: true),
            EventTag(id: "milestone", name: "Milestone", symbol: "flag.fill",      colorHex: "CE82FF", builtIn: true),
            EventTag(id: "reminder",  name: "Reminder",  symbol: "bell.fill",      colorHex: "84D8FF", builtIn: true),
            EventTag(id: "other",     name: "Other",     symbol: "calendar",       colorHex: "9A9A9A", builtIn: true),
        ]
    }
}

/// A photo or short video attached to an event — stored inline as base64 so it rides the
/// same encrypted sync as everything else. Video is transcoded + capped (see `VideoMedia`).
struct EventMedia: Codable, Identifiable, Hashable {
    enum Kind: String, Codable, Hashable { case image, video }
    var id: String
    var kind: Kind
    var data: String         // base64, no data: prefix. image → JPEG · video → mp4
    var poster: String?      // video only: base64 JPEG first-frame thumbnail

    init(id: String = UUID().uuidString.lowercased(), kind: Kind, data: String, poster: String? = nil) {
        self.id = id; self.kind = kind; self.data = data; self.poster = poster
    }
}

/// One logged life event — a memory. Past, present, or future. Carries multiple tags and
/// photo/video media. Sorted by `date`.
struct EventItem: Codable, Identifiable, Hashable {
    var id: String
    var date: String            // yyyy-MM-dd
    var title: String
    var tagIDs: [String]        // references EventTag.id (0..n)
    var note: String
    var media: [EventMedia]
    var special: Bool           // the big ones (a wedding, a lifetime trip) — highlighted
    // Legacy fields — kept so pre-tag events still decode and migrate. Not used by new UI.
    var category: EventCategory
    var done: Bool

    init(id: String = UUID().uuidString.lowercased(), date: String, title: String,
         tagIDs: [String] = [], note: String = "", media: [EventMedia] = [],
         special: Bool = false, category: EventCategory = .personal, done: Bool = false) {
        self.id = id; self.date = date; self.title = title
        self.tagIDs = tagIDs; self.note = note; self.media = media
        self.special = special; self.category = category; self.done = done
    }

    enum CodingKeys: String, CodingKey { case id, date, title, tagIDs, note, media, special, category, done }

    // Lenient + migrating: an event saved before a field existed still loads, and a
    // pre-tag event (no `tagIDs`, has `category`) maps its category → the built-in tag id.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id       = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString.lowercased()
        date     = try c.decodeIfPresent(String.self, forKey: .date) ?? ""
        title    = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        note     = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        media    = (try? c.decodeIfPresent([EventMedia].self, forKey: .media)) ?? []
        special  = try c.decodeIfPresent(Bool.self, forKey: .special) ?? false
        category = (try? c.decode(EventCategory.self, forKey: .category)) ?? .personal
        done     = try c.decodeIfPresent(Bool.self, forKey: .done) ?? false
        if c.contains(.tagIDs), let t = try? c.decode([String].self, forKey: .tagIDs) {
            tagIDs = t
        } else if c.contains(.category) {
            tagIDs = [category.rawValue]      // migrate old single category → one tag
        } else {
            tagIDs = []
        }
    }
}

// MARK: - Productivity / watch log  (key: myos.watch — [WatchItem])

/// The learning bucket a video belongs to — aligned to the content pillars.
enum WatchCategory: String, Codable, Hashable, CaseIterable {
    case finance, business, investing, economy, content, mindset, tech, other
    var label: String {
        switch self {
        case .finance:   return "Finance"
        case .business:  return "Business"
        case .investing: return "Investing"
        case .economy:   return "Economy"
        case .content:   return "Content"
        case .mindset:   return "Mindset"
        case .tech:      return "Tech"
        case .other:     return "Other"
        }
    }
}

/// One YouTube video in the watch log — metadata is fetched from YouTube's public
/// oEmbed endpoint (no API key) when the link is pasted; `takeaway` is the user's
/// "what I learned" note that feeds the Teach-Everything habit.
struct WatchItem: Codable, Identifiable, Hashable {
    var id: String
    var url: String
    var videoId: String
    var title: String
    var channel: String
    var thumbUrl: String
    var addedAt: String         // ISO stamp
    var category: WatchCategory
    var takeaway: String
    var watched: Bool

    init(id: String = UUID().uuidString.lowercased(), url: String, videoId: String,
         title: String = "", channel: String = "", thumbUrl: String = "", addedAt: String = "",
         category: WatchCategory = .other, takeaway: String = "", watched: Bool = false) {
        self.id = id; self.url = url; self.videoId = videoId; self.title = title
        self.channel = channel; self.thumbUrl = thumbUrl; self.addedAt = addedAt
        self.category = category; self.takeaway = takeaway; self.watched = watched
    }

    enum CodingKeys: String, CodingKey {
        case id, url, videoId, title, channel, thumbUrl, addedAt, category, takeaway, watched
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id       = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString.lowercased()
        url      = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
        videoId  = try c.decodeIfPresent(String.self, forKey: .videoId) ?? ""
        title    = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        channel  = try c.decodeIfPresent(String.self, forKey: .channel) ?? ""
        thumbUrl = try c.decodeIfPresent(String.self, forKey: .thumbUrl) ?? ""
        addedAt  = try c.decodeIfPresent(String.self, forKey: .addedAt) ?? ""
        category = (try? c.decode(WatchCategory.self, forKey: .category)) ?? .other
        takeaway = try c.decodeIfPresent(String.self, forKey: .takeaway) ?? ""
        watched  = try c.decodeIfPresent(Bool.self, forKey: .watched) ?? false
    }
}

// MARK: - Net worth  (key: myos.networth)

/// One manually-entered asset or liability line (bank cash, mom's gold, other loan).
/// Tracked pieces — portfolio value, emergency fund, gold loan — are pulled live and
/// never stored here, so they can't drift or double-count.
struct NetWorthLine: Codable, Identifiable, Hashable {
    var id: String
    var label: String
    var amountInr: Double

    init(id: String = UUID().uuidString.lowercased(), label: String, amountInr: Double) {
        self.id = id; self.label = label; self.amountInr = amountInr
    }

    enum CodingKeys: String, CodingKey { case id, label, amountInr }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id        = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString.lowercased()
        label     = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        amountInr = try c.decodeIfPresent(Double.self, forKey: .amountInr) ?? 0
    }
}

struct NetWorthState: Codable, Hashable {
    var assets: [NetWorthLine] = []
    var liabilities: [NetWorthLine] = []

    init() {}

    enum CodingKeys: String, CodingKey { case assets, liabilities }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        assets      = try c.decodeIfPresent([NetWorthLine].self, forKey: .assets) ?? []
        liabilities = try c.decodeIfPresent([NetWorthLine].self, forKey: .liabilities) ?? []
    }
}

// MARK: - Full state payload (decodes GET /api/state)

struct AppStatePayload: Codable {
    var finance: FinanceState?
    var portfolio: PortfolioState?
    var fitness: [String: FitnessDay]?
    var fitnessProfile: FitnessProfile?
    var journal: [String: JournalEntry]?
    var journalPresets: JournalPresets?
    var notes: [Note]?
    var days: [String: DayPlan]?
    var profile: Profile?
    var chat: ChatState?
    var nutrition: NutritionState?
    var training: TrainingState?
    var events: [EventItem]?
    var eventTags: [EventTag]?
    var watch: [WatchItem]?
    var networth: NetWorthState?

    init() {}

    enum CodingKeys: String, CodingKey {
        case finance        = "myos.finance"
        case portfolio      = "myos.portfolio"
        case fitness        = "myos.fitness"
        case fitnessProfile = "myos.fitnessProfile"
        case journal        = "myos.journal"
        case journalPresets = "myos.journalPresets"
        case notes          = "myos.notes"
        case days           = "myos.days"
        case profile        = "myos.profile"
        case chat           = "myos.chat"
        case nutrition      = "myos.nutrition"
        case training       = "myos.training"
        case events         = "myos.events"
        case eventTags      = "myos.eventTags"
        case watch          = "myos.watch"
        case networth       = "myos.networth"
    }

    // Decode each module independently: one unexpected key can no longer sink the
    // whole payload (which showed as "Couldn't load your data"). A key that fails
    // is left nil, so `apply` uses that module's default — same as an absent key.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        finance        = try? c.decodeIfPresent(FinanceState.self, forKey: .finance)
        portfolio      = try? c.decodeIfPresent(PortfolioState.self, forKey: .portfolio)
        fitness        = try? c.decodeIfPresent([String: FitnessDay].self, forKey: .fitness)
        fitnessProfile = try? c.decodeIfPresent(FitnessProfile.self, forKey: .fitnessProfile)
        journal        = try? c.decodeIfPresent([String: JournalEntry].self, forKey: .journal)
        journalPresets = try? c.decodeIfPresent(JournalPresets.self, forKey: .journalPresets)
        notes          = try? c.decodeIfPresent([Note].self, forKey: .notes)
        days           = try? c.decodeIfPresent([String: DayPlan].self, forKey: .days)
        profile        = try? c.decodeIfPresent(Profile.self, forKey: .profile)
        chat           = try? c.decodeIfPresent(ChatState.self, forKey: .chat)
        nutrition      = try? c.decodeIfPresent(NutritionState.self, forKey: .nutrition)
        training       = try? c.decodeIfPresent(TrainingState.self, forKey: .training)
        events         = try? c.decodeIfPresent([EventItem].self, forKey: .events)
        eventTags      = try? c.decodeIfPresent([EventTag].self, forKey: .eventTags)
        watch          = try? c.decodeIfPresent([WatchItem].self, forKey: .watch)
        networth       = try? c.decodeIfPresent(NetWorthState.self, forKey: .networth)
    }
}

// MARK: - AI parse result (decodes POST /api/parse)

struct ParseResult: Codable {
    struct Fin: Codable {
        let spoken: String
        let kind: TxnKind
        let amountInr: Double
        let category: String
        let quality: String?
        let merchant: String?
        let note: String?
    }
    struct Fit: Codable {
        let weightKg: Double?
        let calories: Double?
        let proteinG: Double?
        let waterMl: Double?
        let note: String?
    }
    struct Jrn: Codable {
        let note: String?
        let mood: Int?
        let wins: [String]
        let mistakes: [String]
        let lessons: [String]
        let gratitude: [String]
    }
    struct Nte: Codable {
        let title: String
        let body: String
    }
    let summary: String
    let finance: [Fin]
    let fitness: Fit?
    let journal: Jrn?
    let notes: [Nte]
}

// MARK: - AI image parse result (decodes POST /api/parse-image)

struct ImageParseResult: Codable {
    let summary: String
    let transactions: [TxnItem]?
    let holdings: [HoldingItem]?

    struct TxnItem: Codable {
        let kind: TxnKind
        let amountInr: Double
        let category: String
        let quality: String?
        let merchant: String?
        let account: String?
        let note: String?
        let date: String?
    }
    struct HoldingItem: Codable {
        let name: String
        let type: String
        let investedInr: Double?
        let currentInr: Double
        let units: Double?
        let note: String?
    }
}

// MARK: - Draft rows for the review-then-save sheets

/// An extracted transaction awaiting the user's confirmation. Editable; `include`
/// drives whether it gets saved.
struct DraftTxn: Identifiable, Hashable {
    var id = UUID().uuidString.lowercased()
    var include = true
    var kind: TxnKind
    var amountInr: Double
    var category: String
    var quality: TxnQuality?
    var merchant: String?
    var account: String?
    var note: String?
    var date: String
}

/// An extracted holding awaiting confirmation before it becomes a snapshot.
struct DraftHolding: Identifiable, Hashable {
    var id = UUID().uuidString.lowercased()
    var include = true
    var name: String
    var type: HoldingType
    var investedInr: Double
    var currentInr: Double
    var units: Double?
    var note: String?
    var symbol: String?
}

// MARK: - Advice request (encodes POST /api/advise)

struct AdviceRequest: Encodable {
    struct H: Encodable {
        let name: String
        let type: String
        let investedInr: Double
        let currentInr: Double
        let units: Double?
    }
    struct Ctx: Encodable {
        let monthlyIncomeInr: Double
        let monthExpenseInr: Double
        let goldLoanOutstandingInr: Double
        let goldLoanRatePct: Double
        let emergencyCurrentInr: Double
        let emergencyTargetInr: Double
        let termInsuranceBought: Bool
        let healthInsuranceBought: Bool
    }
    struct Prev: Encodable {
        let date: String
        let totalCurrent: Double
    }
    let holdings: [H]
    let context: Ctx
    let prev: Prev?
}

// Keys — single source of truth for the state store.
enum StateKey {
    static let finance        = "myos.finance"
    static let portfolio      = "myos.portfolio"
    static let fitness        = "myos.fitness"
    static let fitnessProfile = "myos.fitnessProfile"
    static let journal        = "myos.journal"
    static let journalPresets = "myos.journalPresets"
    static let notes          = "myos.notes"
    static let days           = "myos.days"
    static let profile        = "myos.profile"
    static let chat           = "myos.chat"
    static let nutrition      = "myos.nutrition"
    static let training       = "myos.training"
    static let events         = "myos.events"
    static let eventTags      = "myos.eventTags"
    static let watch          = "myos.watch"
    static let networth       = "myos.networth"
}
