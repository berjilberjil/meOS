import Foundation

// Food + workout data, mirrored from fitOS (shapes only — no emoji icons; MyOS
// styles categories with SF Symbols). Two synced docs: `myos.nutrition` (foods +
// daily log + weekly meal plan) and `myos.training` (exercises + weekly plan + log).

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

/// A day's eating — meal key → items.
struct MealLog: Codable, Hashable {
    var meals: [String: [PlanItem]] = [:]
    init() {}
    enum CodingKeys: String, CodingKey { case meals }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        meals = try c.decodeIfPresent([String: [PlanItem]].self, forKey: .meals) ?? [:]
    }
    func items(_ meal: MealKey) -> [PlanItem] { meals[meal.rawValue] ?? [] }
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

    init(id: String = UUID().uuidString.lowercased(), name: String, category: WorkoutCategory,
         equipment: String, primary: String, muscles: [String] = [], gifId: String? = nil,
         weighted: Bool = true, isDefault: Bool = false) {
        self.id = id; self.name = name; self.category = category; self.equipment = equipment
        self.primary = primary; self.muscles = muscles; self.gifId = gifId
        self.weighted = weighted; self.isDefault = isDefault
    }

    enum CodingKeys: String, CodingKey { case id, name, category, equipment, primary, muscles, gifId, weighted, isDefault }
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
    init(rest: Bool = false, items: [PlanExercise] = []) { self.rest = rest; self.items = items }
    enum CodingKeys: String, CodingKey { case rest, items }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rest  = try c.decodeIfPresent(Bool.self, forKey: .rest) ?? false
        items = try c.decodeIfPresent([PlanExercise].self, forKey: .items) ?? []
    }
}

struct TrainingState: Codable, Hashable {
    var customExercises: [Exercise] = []
    var weekPlan: [String: WorkoutDayPlan] = [:]           // weekday "0".."6" → plan
    init() {}
    enum CodingKeys: String, CodingKey { case customExercises, weekPlan }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        customExercises = try c.decodeIfPresent([Exercise].self, forKey: .customExercises) ?? []
        weekPlan        = try c.decodeIfPresent([String: WorkoutDayPlan].self, forKey: .weekPlan) ?? [:]
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
