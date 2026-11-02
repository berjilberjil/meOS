import Foundation

// MARK: - 60-Day Six-Pack Challenge
//
// One synced module (`meos.sixPack`), the same shape as every other MeOS
// module: a Codable value held on `AppState`, pushed debounced through
// `push(_:_:)`, and merged on live pull. Daily records are keyed by
// `yyyy-MM-dd`, so a day can only ever have one record — re-opening the app
// cannot create a duplicate, and a missed day is simply an absent key rather
// than anything that resets the challenge.
//
// Day maths is pure and string-based (`yyyy-MM-dd`), so it is timezone-stable
// and can be reasoned about without a clock.

// MARK: Configuration

struct SixPackConfig: Codable, Hashable {
    /// First day of the challenge, `yyyy-MM-dd`.
    var startDateKey: String
    var durationDays: Int
    var startWeightKg: Double
    /// The accepted daily range, inclusive.
    var calorieMin: Int
    var calorieMax: Int
    var proteinMin: Int
    var proteinMax: Int
    /// 24-hour clock. 12...20 is the 12 PM – 8 PM eating window.
    var fastingStartHour: Int
    var fastingEndHour: Int

    static let `default` = SixPackConfig(
        startDateKey: "2026-11-01",
        durationDays: 60,
        startWeightKg: 88,
        calorieMin: 2_200,
        calorieMax: 2_400,
        proteinMin: 130,
        proteinMax: 160,
        fastingStartHour: 12,
        fastingEndHour: 20
    )

    var fastingWindowLabel: String {
        func clock(_ h: Int) -> String {
            let hour = ((h % 24) + 24) % 24
            let suffix = hour < 12 ? "AM" : "PM"
            let twelve = hour % 12 == 0 ? 12 : hour % 12
            return "\(twelve) \(suffix)"
        }
        return "\(clock(fastingStartHour))–\(clock(fastingEndHour))"
    }

    enum CodingKeys: String, CodingKey {
        case startDateKey, durationDays, startWeightKg
        case calorieMin, calorieMax, proteinMin, proteinMax
        case fastingStartHour, fastingEndHour
    }

    init(startDateKey: String, durationDays: Int, startWeightKg: Double,
         calorieMin: Int, calorieMax: Int, proteinMin: Int, proteinMax: Int,
         fastingStartHour: Int, fastingEndHour: Int) {
        self.startDateKey = startDateKey
        self.durationDays = max(1, durationDays)
        self.startWeightKg = startWeightKg
        self.calorieMin = calorieMin
        self.calorieMax = calorieMax
        self.proteinMin = proteinMin
        self.proteinMax = proteinMax
        self.fastingStartHour = fastingStartHour
        self.fastingEndHour = fastingEndHour
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SixPackConfig.default
        startDateKey = try c.decodeIfPresent(String.self, forKey: .startDateKey) ?? d.startDateKey
        durationDays = max(1, try c.decodeIfPresent(Int.self, forKey: .durationDays) ?? d.durationDays)
        startWeightKg = try c.decodeIfPresent(Double.self, forKey: .startWeightKg) ?? d.startWeightKg
        calorieMin = try c.decodeIfPresent(Int.self, forKey: .calorieMin) ?? d.calorieMin
        calorieMax = try c.decodeIfPresent(Int.self, forKey: .calorieMax) ?? d.calorieMax
        proteinMin = try c.decodeIfPresent(Int.self, forKey: .proteinMin) ?? d.proteinMin
        proteinMax = try c.decodeIfPresent(Int.self, forKey: .proteinMax) ?? d.proteinMax
        fastingStartHour = try c.decodeIfPresent(Int.self, forKey: .fastingStartHour) ?? d.fastingStartHour
        fastingEndHour = try c.decodeIfPresent(Int.self, forKey: .fastingEndHour) ?? d.fastingEndHour
    }
}

// MARK: Checklist

/// The five daily non-negotiables. Stored as five explicit booleans (plus
/// sleep hours) rather than a free-form dictionary, so a record can never
/// silently lose a row when the checklist changes.
enum SixPackItem: String, CaseIterable, Identifiable, Hashable {
    case protein, calories, workout, fasting, sleep

    var id: String { rawValue }

    var title: String {
        switch self {
        case .protein:  return "Hit protein target"
        case .calories: return "Stayed within calories"
        case .workout:  return "Workout or recovery"
        case .fasting:  return "Kept the eating window"
        case .sleep:    return "Slept 7–9 hours"
        }
    }

    var detail: String {
        switch self {
        case .protein:  return "130–160 g"
        case .calories: return "2,200–2,400 kcal"
        case .workout:  return "As scheduled"
        case .fasting:  return "12 PM–8 PM"
        case .sleep:    return "Last night"
        }
    }

    var symbol: String {
        switch self {
        case .protein:  return "fork.knife"
        case .calories: return "flame"
        case .workout:  return "dumbbell"
        case .fasting:  return "sunset"
        case .sleep:    return "bed.double"
        }
    }
}

// MARK: Daily record

struct SixPackDayRecord: Codable, Identifiable, Hashable {
    var id: String
    var dateKey: String
    var proteinHit: Bool
    var caloriesWithinTarget: Bool
    var workoutCompleted: Bool
    var fastingFollowed: Bool
    var sleepHours: Double?

    var isComplete: Bool {
        proteinHit && caloriesWithinTarget && workoutCompleted && fastingFollowed && sleepIsWithinTarget
    }

    var sleepIsWithinTarget: Bool {
        guard let h = sleepHours else { return false }
        return h >= 7 && h <= 9
    }

    /// How many of the five rows are ticked — what the widget's "3 of 5" reads.
    var completedCount: Int {
        [proteinHit, caloriesWithinTarget, workoutCompleted, fastingFollowed, sleepIsWithinTarget]
            .filter { $0 }.count
    }

    init(dateKey: String, id: String = UUID().uuidString.lowercased()) {
        self.id = id
        self.dateKey = dateKey
        self.proteinHit = false
        self.caloriesWithinTarget = false
        self.workoutCompleted = false
        self.fastingFollowed = false
        self.sleepHours = nil
    }

    enum CodingKeys: String, CodingKey {
        case id, dateKey, proteinHit, caloriesWithinTarget
        case workoutCompleted, fastingFollowed, sleepHours
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString.lowercased()
        dateKey = try c.decodeIfPresent(String.self, forKey: .dateKey) ?? ""
        proteinHit = try c.decodeIfPresent(Bool.self, forKey: .proteinHit) ?? false
        caloriesWithinTarget = try c.decodeIfPresent(Bool.self, forKey: .caloriesWithinTarget) ?? false
        workoutCompleted = try c.decodeIfPresent(Bool.self, forKey: .workoutCompleted) ?? false
        fastingFollowed = try c.decodeIfPresent(Bool.self, forKey: .fastingFollowed) ?? false
        sleepHours = try c.decodeIfPresent(Double.self, forKey: .sleepHours)
    }

    func isOn(_ item: SixPackItem) -> Bool {
        switch item {
        case .protein:  return proteinHit
        case .calories: return caloriesWithinTarget
        case .workout:  return workoutCompleted
        case .fasting:  return fastingFollowed
        case .sleep:    return sleepIsWithinTarget
        }
    }

    mutating func toggle(_ item: SixPackItem) {
        switch item {
        case .protein:  proteinHit.toggle()
        case .calories: caloriesWithinTarget.toggle()
        case .workout:  workoutCompleted.toggle()
        case .fasting:  fastingFollowed.toggle()
        case .sleep:
            // No sleep number yet → 8 h (inside the window). Tapping past the
            // top wraps back to 7, so the row is one control, not a form.
            if let h = sleepHours {
                sleepHours = h >= 9 ? 7 : min(9, h + 1)
            } else {
                sleepHours = 8
            }
        }
    }
}

// MARK: Weigh-in

struct SixPackWeighIn: Codable, Identifiable, Hashable {
    var id: String
    var dateKey: String
    var kg: Double

    init(dateKey: String, kg: Double, id: String = UUID().uuidString.lowercased()) {
        self.id = id
        self.dateKey = dateKey
        self.kg = kg
    }

    enum CodingKeys: String, CodingKey { case id, dateKey, kg }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString.lowercased()
        dateKey = try c.decodeIfPresent(String.self, forKey: .dateKey) ?? ""
        kg = try c.decodeIfPresent(Double.self, forKey: .kg) ?? 0
    }
}

// MARK: The module

struct SixPackState: Codable, Hashable {
    var config: SixPackConfig
    /// Newest last. One entry per day — a second update on the same day replaces it.
    var weighIns: [SixPackWeighIn]
    /// `yyyy-MM-dd` → that day's record. The key IS the uniqueness guarantee.
    var records: [String: SixPackDayRecord]

    init(config: SixPackConfig = .default) {
        self.config = config
        self.weighIns = []
        self.records = [:]
    }

    enum CodingKeys: String, CodingKey { case config, weighIns, records }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        config = try c.decodeIfPresent(SixPackConfig.self, forKey: .config) ?? .default
        weighIns = try c.decodeIfPresent([SixPackWeighIn].self, forKey: .weighIns) ?? []
        records = try c.decodeIfPresent([String: SixPackDayRecord].self, forKey: .records) ?? [:]
    }

    // MARK: Weight

    var currentWeightKg: Double {
        sortedWeighIns.last?.kg ?? config.startWeightKg
    }

    var sortedWeighIns: [SixPackWeighIn] {
        weighIns.sorted { $0.dateKey < $1.dateKey }
    }

    var weightDeltaKg: Double { currentWeightKg - config.startWeightKg }

    /// Upsert a weigh-in for the day. Keeps history one-per-day, so tapping
    /// Save twice corrects today rather than appending a second entry.
    mutating func setWeight(_ kg: Double, on dateKey: String) {
        guard kg.isFinite, kg > 0, kg <= 1_000 else { return }
        if let i = weighIns.firstIndex(where: { $0.dateKey == dateKey }) {
            weighIns[i].kg = kg
        } else {
            weighIns.append(SixPackWeighIn(dateKey: dateKey, kg: kg))
        }
    }

    // MARK: Records

    func record(on dateKey: String) -> SixPackDayRecord {
        records[dateKey] ?? SixPackDayRecord(dateKey: dateKey)
    }

    /// Mutate today's record, creating it on first touch. One key, so no duplicates.
    mutating func updateRecord(on dateKey: String, _ transform: (inout SixPackDayRecord) -> Void) {
        var r = records[dateKey] ?? SixPackDayRecord(dateKey: dateKey)
        transform(&r)
        records[dateKey] = r
    }

    mutating func toggle(_ item: SixPackItem, on dateKey: String) {
        updateRecord(on: dateKey) { $0.toggle(item) }
    }

    // MARK: Progress

    func dayNumber(on today: String) -> Int {
        guard let delta = SixPackDayMath.daysBetween(config.startDateKey, and: today) else { return 1 }
        return min(max(delta + 1, 1), config.durationDays)
    }

    func progress(on today: String) -> Double {
        Double(dayNumber(on: today)) / Double(max(1, config.durationDays))
    }

    /// Days left after today. `0` on the final day, which the UI says out loud.
    func daysRemaining(on today: String) -> Int {
        max(0, config.durationDays - dayNumber(on: today))
    }

    func endDateKey() -> String {
        SixPackDayMath.addDays(config.durationDays - 1, to: config.startDateKey)
    }

    /// Consecutive complete days ending today (or yesterday, while today is
    /// still open). A missed day ends the run — it never resets the challenge.
    func streak(on today: String) -> Int {
        var key = record(on: today).isComplete ? today : SixPackDayMath.addDays(-1, to: today)
        var run = 0
        while run < config.durationDays, records[key]?.isComplete == true {
            run += 1
            key = SixPackDayMath.addDays(-1, to: key)
        }
        return run
    }

    var completedDays: Int {
        records.values.filter(\.isComplete).count
    }

    /// A day's state for the history grid.
    enum DayMark { case complete, partial, missed, today, future, before }

    func mark(for dateKey: String, today: String) -> DayMark {
        if dateKey > today { return .future }
        if dateKey < config.startDateKey { return .before }
        let r = records[dateKey]
        if dateKey == today {
            return (r?.isComplete == true) ? .complete : .today
        }
        if r?.isComplete == true { return .complete }
        return (r?.completedCount ?? 0) > 0 ? .partial : .missed
    }
}

// MARK: Day maths

enum SixPackDayMath {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func date(from key: String) -> Date? {
        formatter.date(from: String(key.prefix(10)))
    }

    static func key(_ date: Date) -> String {
        formatter.string(from: date)
    }

    static func addDays(_ n: Int, to key: String) -> String {
        guard let d = date(from: key),
              let moved = Calendar(identifier: .gregorian).date(byAdding: .day, value: n, to: d)
        else { return key }
        return self.key(moved)
    }

    /// Whole days from `start` to `end` (positive when `end` is later).
    static func daysBetween(_ start: String, and end: String) -> Int? {
        guard let a = date(from: start), let b = date(from: end) else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: a), to: cal.startOfDay(for: b)).day
        return days
    }
}

// MARK: - AppState integration

extension AppState {
    /// Today's record for the challenge (never nil — an untouched day reads as
    /// an empty record, which is what the checklist shows).
    var sixPackToday: SixPackDayRecord {
        sixPack.record(on: todayKey)
    }

    /// One push for the whole module, after the local value has changed.
    func updateSixPack(_ transform: (inout SixPackState) -> Void) {
        var next = sixPack
        transform(&next)
        guard next != sixPack else { return }
        sixPack = next
        push(StateKey.sixPack, next)
    }

    func toggleSixPackItem(_ item: SixPackItem) {
        updateSixPack { $0.toggle(item, on: todayKey) }
    }

    func logSixPackWeight(_ kg: Double) {
        updateSixPack { $0.setWeight(kg, on: todayKey) }
    }
}
