import Foundation

// All MyOS data. Each top-level model maps to one `myos.*` JSON key in the
// backend's per-user state store. Add a module → add a model + a key here.

struct AuthUser: Codable, Hashable {
    let id: Int
    let username: String
}

// MARK: - Fitness  (key: myos.fitness — [date: FitnessDay])

struct FitnessDay: Codable, Hashable {
    var weightKg: Double?
    var calories: Double?
    var proteinG: Double?
    var waterMl: Double?
    var steps: Int?             // daily step count — the iPhone writes this from
                               // CMPedometer; the Mac can correct it by hand.
    var note: String?
    /// Which step goals have already been congratulated for this day — 1 for the
    /// mandatory goal, 2 for the stretch.
    ///
    /// It lives in synced state rather than on the device that noticed, because
    /// crossing 8,000 is one moment in your day and it should be celebrated
    /// once: not again when the Mac pulls the same number down, not again when
    /// the pedometer re-reports the day, and not again tomorrow morning.
    var hailed: [Int]?
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
    var stepsTarget: Int? = nil        // mandatory daily step goal (nil → 8,000)
    var stepsStretch: Int? = nil       // the optional second goal (nil → 10,000)

    init() {}

    enum CodingKeys: String, CodingKey {
        case goal, sex, activity, targetWeightKg, calorieTargetKcal, proteinTargetG, waterTargetMl
        case stepsTarget, stepsStretch
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
        stepsStretch      = try c.decodeIfPresent(Int.self, forKey: .stepsStretch)
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
        static let wins      = ["Posted content", "Hit the gym", "Ate a clean meal", "Deep work done", "Learned something", "Saved money"]
        static let mistakes  = ["Ate junk", "Skipped gym", "Slept late", "Wasted time on phone", "Overspent", "Procrastinated"]
        static let lessons   = ["Consistency beats intensity", "Show up daily", "Spend less than I earn", "Protect the mornings"]
        static let gratitude = ["Family", "Health", "The job", "Roof and food", "This journey", "Learning daily"]
    }

    enum CodingKeys: String, CodingKey { case morning, night, wins, mistakes, lessons, gratitude }

    // Lenient: a set saved before a section existed falls back to that seed.
    // Reword a few outdated starter chips so existing installs pick up the fix.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        morning   = try c.decodeIfPresent([String].self, forKey: .morning) ?? Seed.morning
        night     = try c.decodeIfPresent([String].self, forKey: .night) ?? Seed.night
        wins      = Self.rewritten(try c.decodeIfPresent([String].self, forKey: .wins) ?? Seed.wins)
        mistakes  = try c.decodeIfPresent([String].self, forKey: .mistakes) ?? Seed.mistakes
        lessons   = try c.decodeIfPresent([String].self, forKey: .lessons) ?? Seed.lessons
        gratitude = try c.decodeIfPresent([String].self, forKey: .gratitude) ?? Seed.gratitude
    }

    private static func rewritten(_ wins: [String]) -> [String] {
        wins.map { $0 == "Ate clean" || $0 == "ate" ? "Ate a clean meal" : $0 }
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

    /// Whether saving this title and body would actually change anything.
    ///
    /// Notes are saved on open, on close, on tab switch and on every keystroke,
    /// and the list is sorted by `updatedAt` and grouped into date sections. So
    /// a save that writes when nothing moved does not just waste a network push
    /// — it reorders the list under the cursor for the crime of *looking* at a
    /// note. Compare against `effectiveDoc` rather than `content` so a legacy
    /// plain-text note that round-trips identically is also left alone.
    /// Whether a plain-text save would actually alter this note.
    ///
    /// The iOS notes screen edits the plain-text mirror and saves from
    /// `onDisappear`, unconditionally — so without this, merely *opening* a note
    /// on the phone and going back rewrote `updatedAt`, which the list is sorted
    /// by, and rebuilt `content` from the flat body. A note written on the Mac
    /// with headings, checkboxes and images lost every one of them to being
    /// looked at.
    func wouldChange(title: String, body: String) -> Bool {
        title != self.title || body != self.body
    }

    func wouldChange(title: String, doc: BlockDoc) -> Bool {
        // By content, not by identity. A legacy note stores no `content`, so
        // `effectiveDoc` builds one from its body with fresh block ids every
        // call — comparing with `!=` would report a change on every open and
        // reinstate the very shuffle this guard removes.
        title != self.title || !effectiveDoc.sameContent(as: doc)
    }
}

/// Order notes for display, honouring a frozen order where one is supplied.
///
/// Pinned always wins — pinning is a deliberate act whose entire point is to
/// move the note. Beyond that, a frozen order keeps the list still while its
/// notes are being edited beside it; ids absent from the snapshot are new and
/// fall to the end, joining the list rather than reshuffling it.
func orderedNotes(_ notes: [Note], frozen: [String]?) -> [Note] {
    guard let frozen else {
        return notes.sorted { a, b in
            if a.pinned != b.pinned { return a.pinned }
            return a.updatedAt > b.updatedAt
        }
    }
    var rank: [String: Int] = [:]
    for (i, id) in frozen.enumerated() { rank[id] = i }
    return notes.sorted { a, b in
        if a.pinned != b.pinned { return a.pinned }
        let ra = rank[a.id], rb = rank[b.id]
        if (ra == nil) != (rb == nil) { return ra != nil }
        if let ra, let rb, ra != rb { return ra < rb }
        return a.updatedAt > b.updatedAt
    }
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

/// One saved conversation with the mentor — a titled thread of turns.
struct ChatThread: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var createdAt: String
    var updatedAt: String
    var messages: [ChatMessage]

    init(id: String, title: String = "New chat", createdAt: String = "",
         updatedAt: String = "", messages: [ChatMessage] = []) {
        self.id = id; self.title = title; self.createdAt = createdAt
        self.updatedAt = updatedAt; self.messages = messages
    }

    enum CodingKeys: String, CodingKey { case id, title, createdAt, updatedAt, messages }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id        = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString.lowercased()
        title     = try c.decodeIfPresent(String.self, forKey: .title) ?? "New chat"
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt) ?? ""
        messages  = try c.decodeIfPresent([ChatMessage].self, forKey: .messages) ?? []
    }
}

/// The mentor chat store — many threads plus which one is active. Migrates the old
/// single-conversation shape (`{messages:[…]}`) into one thread on first load.
struct ChatState: Codable, Hashable {
    var threads: [ChatThread] = []
    var activeID: String? = nil

    init() {}

    enum CodingKeys: String, CodingKey { case threads, activeID }
    private enum LegacyKeys: String, CodingKey { case messages }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let t = try? c.decodeIfPresent([ChatThread].self, forKey: .threads) { threads = t }
        if threads.isEmpty, let lc = try? decoder.container(keyedBy: LegacyKeys.self),
           let msgs = try? lc.decodeIfPresent([ChatMessage].self, forKey: .messages), !msgs.isEmpty {
            let title = msgs.first(where: { $0.role == "user" }).map { String($0.content.prefix(40)) } ?? "Chat"
            threads = [ChatThread(id: UUID().uuidString.lowercased(), title: title, messages: msgs)]
        }
        if let a = try? c.decodeIfPresent(String.self, forKey: .activeID) { activeID = a }
        if activeID == nil { activeID = threads.first?.id }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(threads, forKey: .threads)
        try c.encodeIfPresent(activeID, forKey: .activeID)
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

/// One Today to-do. Older clients stored these as plain strings in `focus`.
struct FocusItem: Codable, Identifiable, Hashable {
    var id: String
    var text: String
    var done: Bool
    /// Planned length of one focus block, in minutes. nil = use the default.
    var mins: Int?
    /// Seconds actually spent on it in focus sessions, across the day.
    var spent: Int

    init(id: String = UUID().uuidString.lowercased(), text: String, done: Bool = false,
         mins: Int? = nil, spent: Int = 0) {
        self.id = id; self.text = text; self.done = done; self.mins = mins; self.spent = spent
    }

    enum CodingKeys: String, CodingKey { case id, text, done, mins, spent }

    /// Hand-rolled so day plans written before the timer existed still decode.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        text = try c.decode(String.self, forKey: .text)
        done = try c.decodeIfPresent(Bool.self, forKey: .done) ?? false
        mins = try c.decodeIfPresent(Int.self, forKey: .mins)
        spent = try c.decodeIfPresent(Int.self, forKey: .spent) ?? 0
    }
}

struct DayPlan: Codable, Hashable {
    var todos: [FocusItem] = []
    var habits: [String: Bool] = [:]    // habit name → done

    init() {}

    enum CodingKeys: String, CodingKey { case focus, todos, habits }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        habits = try c.decodeIfPresent([String: Bool].self, forKey: .habits) ?? [:]
        if let items = try c.decodeIfPresent([FocusItem].self, forKey: .todos), !items.isEmpty {
            todos = items
        } else {
            let legacy = try c.decodeIfPresent([String].self, forKey: .focus) ?? []
            todos = legacy.map { FocusItem(text: $0) }
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(todos, forKey: .todos)
        try c.encode(todos.map(\.text), forKey: .focus)
        try c.encode(habits, forKey: .habits)
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
    /// Legacy inline base64. Empty once the item has moved to R2 — kept so a
    /// device on an older build can still read events it hasn't migrated.
    var data: String
    var poster: String?      // legacy inline base64 JPEG thumbnail (video only)
    /// R2 object ids for the sealed bytes. Set once migrated.
    var r2Key: String?
    var posterKey: String?

    init(id: String = UUID().uuidString.lowercased(), kind: Kind, data: String = "",
         poster: String? = nil, r2Key: String? = nil, posterKey: String? = nil) {
        self.id = id; self.kind = kind; self.data = data; self.poster = poster
        self.r2Key = r2Key; self.posterKey = posterKey
    }

    enum CodingKeys: String, CodingKey { case id, kind, data, poster, r2Key, posterKey }

    /// Lenient: rows written before R2 have no keys, rows written after have no
    /// inline data. Either shape must decode.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id        = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString.lowercased()
        kind      = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .image
        data      = try c.decodeIfPresent(String.self, forKey: .data) ?? ""
        poster    = try c.decodeIfPresent(String.self, forKey: .poster)
        r2Key     = try c.decodeIfPresent(String.self, forKey: .r2Key)
        posterKey = try c.decodeIfPresent(String.self, forKey: .posterKey)
    }

    /// True when the bytes are still inline and need moving to R2.
    var needsMigration: Bool {
        (r2Key == nil && !data.isEmpty) || (posterKey == nil && !(poster ?? "").isEmpty)
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

// MARK: - Full state payload (decodes GET /api/state)

struct AppStatePayload: Codable {
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
    var belongings: BelongingsState?
    var fold: FoldData?
    var memory: MemoryState?
    var scans: [ScanRecord]?
    var taskMode: TaskModeState?
    var weekly: [WeeklyReport]?
    var activity: ActivityDoc?
    var appearance: AppearanceSettings?

    init() {}

    enum CodingKeys: String, CodingKey {
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
        case belongings     = "myos.belongings"
        case fold           = "myos.fold"
        case memory         = "myos.memory"
        case scans          = "myos.scans"
        case taskMode       = "myos.taskMode"
        case weekly         = "myos.weekly"
        case activity       = "myos.activity"
        case appearance     = "myos.appearance"
    }

    // Decode each module independently: one unexpected key can no longer sink the
    // whole payload (which showed as "Couldn't load your data"). A key that fails
    // is left nil, so `apply` uses that module's default — same as an absent key.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
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
        belongings     = try? c.decodeIfPresent(BelongingsState.self, forKey: .belongings)
        fold           = try? c.decodeIfPresent(FoldData.self, forKey: .fold)
        memory         = try? c.decodeIfPresent(MemoryState.self, forKey: .memory)
        scans          = try? c.decodeIfPresent([ScanRecord].self, forKey: .scans)
        taskMode       = try? c.decodeIfPresent(TaskModeState.self, forKey: .taskMode)
        weekly         = try? c.decodeIfPresent([WeeklyReport].self, forKey: .weekly)
        activity       = try? c.decodeIfPresent(ActivityDoc.self, forKey: .activity)
        appearance     = try? c.decodeIfPresent(AppearanceSettings.self, forKey: .appearance)
    }
}

// MARK: - AI parse result (decodes POST /api/parse)

struct ParseResult: Codable {
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
    let fitness: Fit?
    let journal: Jrn?
    let notes: [Nte]
}

// MARK: - AI image parse result (decodes POST /api/parse-image)

struct ImageParseResult: Codable {
    let summary: String
    let kind: String?
    let foods: [FoodItem]?
    let object: Obj?
    let name: String?
    let category: String?
    let priceInr: Double?
    let lifeMonths: Int?

    struct FoodItem: Codable {
        let name: String
        let category: String
        let servingLabel: String
        let calories: Double
        let protein: Double
        let carbs: Double
        let fiber: Double
        let fats: Double
        let vitamins: String?
    }
    struct Obj: Codable {
        let name: String
        let needed: String
        let why: String
        let useful: String
    }
}

// Keys — single source of truth for the state store.
enum StateKey {
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
    static let belongings     = "myos.belongings"
    static let fold           = "myos.fold"
    static let memory         = "myos.memory"
    static let scans          = "myos.scans"
    static let taskMode       = "myos.taskMode"
    static let weekly         = "myos.weekly"
    static let activity       = "myos.activity"
    static let appearance     = "myos.appearance"
}
