import Foundation

// Food + workout data, mirrored from fitOS (shapes only — no emoji icons; MeOS
// styles categories with SF Symbols). Two synced docs: `meos.nutrition` (foods +
// daily log + weekly meal plan) and `meos.training` (exercises + weekly plan + log).

// MARK: - Nutrition

/// The five tracked macros. `carbs` is total carb (fiber included); fiber shown
/// separately. Calories are stored as given, not recomputed.
struct Macros: Codable, Hashable {
    var calories: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fiber: Double = 0
    var fats: Double = 0

    init(calories: Double = 0, protein: Double = 0, carbs: Double = 0, fiber: Double = 0, fats: Double = 0) {
        self.calories = calories; self.protein = protein; self.carbs = carbs
        self.fiber = fiber; self.fats = fats
    }

    enum CodingKeys: String, CodingKey { case calories, protein, carbs, fiber, fats }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        calories = try c.decodeIfPresent(Double.self, forKey: .calories) ?? 0
        protein  = try c.decodeIfPresent(Double.self, forKey: .protein) ?? 0
        carbs    = try c.decodeIfPresent(Double.self, forKey: .carbs) ?? 0
        fiber    = try c.decodeIfPresent(Double.self, forKey: .fiber) ?? 0
        fats     = try c.decodeIfPresent(Double.self, forKey: .fats) ?? 0
    }

    static let zero = Macros()
    func scaled(_ q: Double) -> Macros {
        Macros(calories: calories * q, protein: protein * q, carbs: carbs * q, fiber: fiber * q, fats: fats * q)
    }
    static func + (a: Macros, b: Macros) -> Macros {
        Macros(calories: a.calories + b.calories, protein: a.protein + b.protein,
               carbs: a.carbs + b.carbs, fiber: a.fiber + b.fiber, fats: a.fats + b.fats)
    }
}

enum FoodCategory: String, Codable, CaseIterable, Hashable {
    case protein, carb, veg, dairy, fruit, drink, junk, other
    var label: String {
        switch self {
        case .protein: return "Protein"
        case .carb: return "Carb"
        case .veg: return "Veg"
        case .dairy: return "Dairy"
        case .fruit: return "Fruit"
        case .drink: return "Drink"
        case .junk: return "Junk"
        case .other: return "Other"
        }
    }
}

/// One food. `servingLabel` is a human label ("1 chapati", "100 g"); `perServing`
/// is the macros for exactly one of that serving. Quantities in logs multiply it.
struct Food: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var category: FoodCategory
    var servingLabel: String
    var perServing: Macros
    var vitamins: String?   // informational (e.g. "B12, Iron") — never summed into macros
    var isDefault: Bool

    init(id: String = UUID().uuidString.lowercased(), name: String, category: FoodCategory,
         servingLabel: String, perServing: Macros, vitamins: String? = nil, isDefault: Bool = false) {
        self.id = id; self.name = name; self.category = category
        self.servingLabel = servingLabel; self.perServing = perServing
        self.vitamins = vitamins; self.isDefault = isDefault
    }

    /// How two foods are judged to be the same thing when all you have is a
    /// name — which is all an importer or the MCP bridge ever has.
    static func matchKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    enum CodingKeys: String, CodingKey { case id, name, category, servingLabel, perServing, vitamins, isDefault }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id           = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString.lowercased()
        name         = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        category     = (try? c.decode(FoodCategory.self, forKey: .category)) ?? .other
        servingLabel = try c.decodeIfPresent(String.self, forKey: .servingLabel) ?? "1 serving"
        perServing   = try c.decodeIfPresent(Macros.self, forKey: .perServing) ?? .zero
        vitamins     = try c.decodeIfPresent(String.self, forKey: .vitamins)
        isDefault    = try c.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
    }
}

enum MealKey: String, Codable, CaseIterable, Hashable, Identifiable {
    case breakfast, lunch, dinner, snacks
    var id: String { rawValue }
    var label: String {
        switch self {
        case .breakfast: return "Breakfast"
        case .lunch: return "Lunch"
        case .dinner: return "Dinner"
        case .snacks: return "Snacks"
        }
    }
    var icon: String {
        switch self {
        case .breakfast: return "sunrise.fill"
        case .lunch: return "sun.max.fill"
        case .dinner: return "moon.stars.fill"
        case .snacks: return "takeoutbag.and.cup.and.straw.fill"
        }
    }
}

/// A logged/planned food line — a food id + how many servings.
struct PlanItem: Codable, Identifiable, Hashable {
    var id: String
    var foodId: String
    var quantity: Double
    init(id: String = UUID().uuidString.lowercased(), foodId: String, quantity: Double = 1) {
        self.id = id; self.foodId = foodId; self.quantity = quantity
    }
    enum CodingKeys: String, CodingKey { case id, foodId, quantity }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id       = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString.lowercased()
        foodId   = try c.decodeIfPresent(String.self, forKey: .foodId) ?? ""
        quantity = try c.decodeIfPresent(Double.self, forKey: .quantity) ?? 1
    }
}

/// A day's eating — meal key → items, plus the meals intentionally skipped that day.
struct MealLog: Codable, Hashable {
    var meals: [String: [PlanItem]] = [:]
    var skipped: [String] = []                       // meal raws skipped this date
    /// Meals the user has confirmed, whatever ended up in them.
    ///
    /// "Logged" used to be inferred from `meals` being non-empty, so removing the
    /// last item from a meal you had already logged made it unconfirmed again —
    /// and the tile went back to advertising the plan, as if you were about to
    /// eat it. Recording the confirmation separately keeps an emptied meal
    /// logged-and-empty, which is what actually happened.
    var confirmed: [String] = []
    init() {}
    enum CodingKeys: String, CodingKey { case meals, skipped, confirmed }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        meals   = try c.decodeIfPresent([String: [PlanItem]].self, forKey: .meals) ?? [:]
        skipped = try c.decodeIfPresent([String].self, forKey: .skipped) ?? []
        // Anything logged before this field existed is inferred the old way, so
        // a day recorded by an older build still reads correctly.
        confirmed = try c.decodeIfPresent([String].self, forKey: .confirmed)
            ?? meals.filter { !$0.value.isEmpty }.map(\.key)
    }
    func items(_ meal: MealKey) -> [PlanItem] { meals[meal.rawValue] ?? [] }
}

// MARK: - Plan → confirmed (pure derivation + mutation; unit-tested without AppState)

extension MealLog {
    enum MealState: Equatable, Hashable { case unconfirmed, logged, skipped }

    /// Logged (has items) wins over skipped wins over unconfirmed.
    func state(_ meal: MealKey) -> MealState {
        if !items(meal).isEmpty || confirmed.contains(meal.rawValue) { return .logged }
        if skipped.contains(meal.rawValue) { return .skipped }
        return .unconfirmed
    }
    /// Tick "ate it": copy the planned items into this meal (fresh ids), un-skip.
    /// No-op if nothing is planned.
    mutating func tick(_ meal: MealKey, planned: [PlanItem]) {
        guard !planned.isEmpty else { return }
        meals[meal.rawValue] = planned.map { PlanItem(foodId: $0.foodId, quantity: $0.quantity) }
        skipped.removeAll { $0 == meal.rawValue }
        if !confirmed.contains(meal.rawValue) { confirmed.append(meal.rawValue) }
    }
    /// Skip the meal: clear any logged items (so the state is unambiguous) and mark it.
    mutating func skip(_ meal: MealKey) {
        meals[meal.rawValue] = []
        confirmed.removeAll { $0 == meal.rawValue }
        if !skipped.contains(meal.rawValue) { skipped.append(meal.rawValue) }
    }
    mutating func unskip(_ meal: MealKey) { skipped.removeAll { $0 == meal.rawValue } }
    /// Replace a meal's logged items wholesale (editor Save); un-skips.
    mutating func setItems(_ meal: MealKey, _ items: [PlanItem]) {
        meals[meal.rawValue] = items
        skipped.removeAll { $0 == meal.rawValue }
        if !confirmed.contains(meal.rawValue) { confirmed.append(meal.rawValue) }
    }
}

/// Weekday key helpers ("0"=Sun … "6"=Sat) for copy-day.
enum WeekdayKeys {
    static let all: [String] = (0..<7).map(String.init)
    static func others(except day: String) -> [String] { all.filter { $0 != day } }
}

struct NutritionState: Codable, Hashable {
    var customFoods: [Food] = []
    var log: [String: MealLog] = [:]                       // date → meals
    var mealPlan: [String: [String: [PlanItem]]] = [:]     // weekday "0".."6" → meal → items
    init() {}
    enum CodingKeys: String, CodingKey { case customFoods, log, mealPlan }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        customFoods = try c.decodeIfPresent([Food].self, forKey: .customFoods) ?? []
        log         = try c.decodeIfPresent([String: MealLog].self, forKey: .log) ?? [:]
        mealPlan    = try c.decodeIfPresent([String: [String: [PlanItem]]].self, forKey: .mealPlan) ?? [:]
    }
}

// MARK: - Training

enum WorkoutCategory: String, Codable, CaseIterable, Hashable {
    case chest, back, shoulders, arms, legs, core, cardio, boxing
    var label: String {
        switch self {
        case .chest: return "Chest"
        case .back: return "Back"
        case .shoulders: return "Shoulders"
        case .arms: return "Arms"
        case .legs: return "Legs"
        case .core: return "Core"
        case .cardio: return "Cardio"
        case .boxing: return "Boxing"
        }
    }
}

/// One exercise. `muscles` are anatomy slugs (for the body-map highlight); `gifId`
/// is the ExerciseDB demo id (nil for custom → falls back to the category icon).
struct Exercise: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var category: WorkoutCategory
    var equipment: String
    var primary: String
    var muscles: [String]
    var gifId: String?
    var weighted: Bool
    var isDefault: Bool
    /// The muscle-group section this files under in a workout day. nil means
    /// "derive it" — see `Exercise.group`, which reads the anatomy slugs. Seed
    /// exercises leave it nil on purpose so one slug table stays the source.
    var muscleGroup: MuscleGroup?

    init(id: String = UUID().uuidString.lowercased(), name: String, category: WorkoutCategory,
         equipment: String, primary: String, muscles: [String] = [], gifId: String? = nil,
         weighted: Bool = true, isDefault: Bool = false, muscleGroup: MuscleGroup? = nil) {
        self.id = id; self.name = name; self.category = category; self.equipment = equipment
        self.primary = primary; self.muscles = muscles; self.gifId = gifId
        self.weighted = weighted; self.isDefault = isDefault; self.muscleGroup = muscleGroup
    }

    enum CodingKeys: String, CodingKey { case id, name, category, equipment, primary, muscles, gifId, weighted, isDefault, muscleGroup }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id        = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString.lowercased()
        name      = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        category  = (try? c.decode(WorkoutCategory.self, forKey: .category)) ?? .core
        equipment = try c.decodeIfPresent(String.self, forKey: .equipment) ?? "Bodyweight"
        primary   = try c.decodeIfPresent(String.self, forKey: .primary) ?? ""
        muscles   = try c.decodeIfPresent([String].self, forKey: .muscles) ?? []
        gifId     = try c.decodeIfPresent(String.self, forKey: .gifId)
        weighted  = try c.decodeIfPresent(Bool.self, forKey: .weighted) ?? true
        isDefault = try c.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
        muscleGroup = try? c.decodeIfPresent(MuscleGroup.self, forKey: .muscleGroup)
    }

    /// The remote demo GIF (ExerciseDB open mirror) — nil for custom exercises.
    var gifURL: URL? { gifId.flatMap { URL(string: "https://static.exercisedb.dev/media/\($0).gif") } }
}

/// A planned exercise slot — sets × reps.
struct PlanExercise: Codable, Identifiable, Hashable {
    var id: String
    var exerciseId: String
    var sets: Int
    var reps: Int
    init(id: String = UUID().uuidString.lowercased(), exerciseId: String, sets: Int = 3, reps: Int = 10) {
        self.id = id; self.exerciseId = exerciseId; self.sets = sets; self.reps = reps
    }
    enum CodingKeys: String, CodingKey { case id, exerciseId, sets, reps }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id         = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString.lowercased()
        exerciseId = try c.decodeIfPresent(String.self, forKey: .exerciseId) ?? ""
        sets       = try c.decodeIfPresent(Int.self, forKey: .sets) ?? 3
        reps       = try c.decodeIfPresent(Int.self, forKey: .reps) ?? 10
    }
}

struct WorkoutDayPlan: Codable, Hashable {
    var rest: Bool = false
    var items: [PlanExercise] = []

    /// A day with exercises is a training day, even if a stale `rest` flag
    /// lingered from an AI draft or an older save. The single source of truth
    /// for "is this a rest day" — never read `rest` directly for display.
    var isRestDay: Bool { rest && items.isEmpty }

    init(rest: Bool = false, items: [PlanExercise] = []) { self.rest = rest; self.items = items }
    enum CodingKeys: String, CodingKey { case rest, items }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rest  = try c.decodeIfPresent(Bool.self, forKey: .rest) ?? false
        items = try c.decodeIfPresent([PlanExercise].self, forKey: .items) ?? []
    }
}

/// A date's workout status. `nil` items = did it as planned; non-nil = an edited
/// actual. Mirrors the meal plan→confirmed model.
struct WorkoutDayLog: Codable, Hashable {
    var done: Bool = false
    var skipped: Bool = false
    var items: [PlanExercise]? = nil
    /// Which program day ran on this date. Set when you pick a different
    /// workout for today — the program's own schedule is never rewritten.
    var dayId: String? = nil
    var programId: String? = nil
    /// The day's name as it was when you trained it, so history survives a
    /// rename or a deleted program.
    var title: String? = nil
    /// What you actually lifted, set by set. nil = never started a session.
    var entries: [ExerciseLog]? = nil
    /// "Make today a rest day" — distinct from skipping a workout you owed.
    var restOverride: Bool = false

    init() {}
    enum CodingKeys: String, CodingKey {
        case done, skipped, items, dayId, programId, title, entries, restOverride
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        done    = try c.decodeIfPresent(Bool.self, forKey: .done) ?? false
        skipped = try c.decodeIfPresent(Bool.self, forKey: .skipped) ?? false
        items   = try c.decodeIfPresent([PlanExercise].self, forKey: .items)
        dayId       = try c.decodeIfPresent(String.self, forKey: .dayId)
        programId   = try c.decodeIfPresent(String.self, forKey: .programId)
        title       = try c.decodeIfPresent(String.self, forKey: .title)
        entries     = try c.decodeIfPresent([ExerciseLog].self, forKey: .entries)
        restOverride = try c.decodeIfPresent(Bool.self, forKey: .restOverride) ?? false
    }
}

extension WorkoutDayLog {
    enum DayState: Equatable, Hashable { case unconfirmed, done, skipped }
    var state: DayState { done ? .done : (skipped ? .skipped : .unconfirmed) }
    mutating func tick(items: [PlanExercise]?) { done = true; skipped = false; self.items = items }
    mutating func skip() { done = false; skipped = true; items = nil; entries = nil }
    mutating func unskip() { skipped = false }

    /// The exercises actually performed, if a session was logged.
    var loggedItems: [PlanExercise]? {
        guard let entries, !entries.isEmpty else { return items }
        return WorkoutSessionBuilder.planItems(from: entries)
    }
    /// A session exists the moment any set is ticked — that's what makes the
    /// day show up in History even if you never slid to finish.
    var hasSession: Bool { (entries?.contains { $0.sets.contains(where: \.done) }) ?? false }
}

struct TrainingState: Codable, Hashable {
    var customExercises: [Exercise] = []
    /// Legacy single weekday plan. Kept so old saves still decode and can be
    /// migrated once into `programs`; nothing writes it any more.
    var weekPlan: [String: WorkoutDayPlan] = [:]           // weekday "0".."6" → plan
    var dayLog: [String: WorkoutDayLog] = [:]              // date → per-day status
    /// Every program, independent of every other. Order is the user's.
    var programs: [WorkoutProgram] = []
    var activeProgramId: String? = nil
    /// Set once the legacy `weekPlan` has been folded into a program, so an
    /// emptied-out program is never "helpfully" refilled from the old plan.
    var migratedWeekPlan: Bool = false

    init() {}
    enum CodingKeys: String, CodingKey {
        case customExercises, weekPlan, dayLog, programs, activeProgramId, migratedWeekPlan
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        customExercises = try c.decodeIfPresent([Exercise].self, forKey: .customExercises) ?? []
        weekPlan        = try c.decodeIfPresent([String: WorkoutDayPlan].self, forKey: .weekPlan) ?? [:]
        dayLog          = try c.decodeIfPresent([String: WorkoutDayLog].self, forKey: .dayLog) ?? [:]
        programs        = try c.decodeIfPresent([WorkoutProgram].self, forKey: .programs) ?? []
        activeProgramId = try c.decodeIfPresent(String.self, forKey: .activeProgramId)
        migratedWeekPlan = try c.decodeIfPresent(Bool.self, forKey: .migratedWeekPlan) ?? false
    }

    var activeProgram: WorkoutProgram? {
        guard let id = activeProgramId else { return nil }
        return programs.first { $0.id == id }
    }
}

// MARK: - AI plan payloads (decodes POST /api/plan)

struct GeneratedPlan: Codable, Hashable {
    struct Day: Codable, Hashable {
        var weekday: Int
        var rest: Bool
        var exercises: [Ex]
    }
    struct Ex: Codable, Hashable {
        var name: String
        var sets: Int
        var reps: Int
    }
    struct MealDay: Codable, Hashable {
        var weekday: Int
        var breakfast: [String]
        var lunch: [String]
        var dinner: [String]
        var snacks: [String]
    }
    var summary: String = ""
    var workout: [Day] = []
    var meals: [MealDay] = []
}
