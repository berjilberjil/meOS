import Foundation

// The training architecture: Program → Workout day → Muscle group → Exercise →
// sets/reps/rest. A program is a *template* you build once; what you actually
// did lives in `WorkoutDayLog` and never writes back to the template.
//
// Everything here is pure value types + pure functions so the scheduling and
// migration rules are unit-testable without an AppState.

// MARK: - Muscle groups

/// The category an exercise is filed under inside a workout day.
///
/// Finer than `WorkoutCategory` (which stays as-is for the exercise library's
/// icons and filters) because a Pull day needs "Back" and "Biceps" as separate
/// sections, and Leg day needs quads apart from hamstrings and calves. Every
/// seed exercise already carries anatomy slugs, so the mapping is derived —
/// no seed row had to be rewritten.
enum MuscleGroup: String, Codable, CaseIterable, Hashable, Identifiable {
    case chest, back, shoulders, biceps, triceps, forearms
    case quads, hamstrings, glutes, calves, abs, cardio, fullBody

    var id: String { rawValue }

    var label: String {
        switch self {
        case .chest: return "Chest"
        case .back: return "Back"
        case .shoulders: return "Shoulders"
        case .biceps: return "Biceps"
        case .triceps: return "Triceps"
        case .forearms: return "Forearms"
        case .quads: return "Quads"
        case .hamstrings: return "Hamstrings"
        case .glutes: return "Glutes"
        case .calves: return "Calves"
        case .abs: return "Core"
        case .cardio: return "Cardio"
        case .fullBody: return "Full body"
        }
    }

    /// Which library category this group lives in — lets the existing
    /// `ExerciseIcon` keep drawing the right glyph without a second icon set.
    var category: WorkoutCategory {
        switch self {
        case .chest: return .chest
        case .back: return .back
        case .shoulders: return .shoulders
        case .biceps, .triceps, .forearms: return .arms
        case .quads, .hamstrings, .glutes, .calves: return .legs
        case .abs: return .core
        case .cardio: return .cardio
        case .fullBody: return .core
        }
    }

    /// Anatomy slugs this group highlights on the body map.
    var slugs: [String] {
        switch self {
        case .chest: return ["chest"]
        case .back: return ["upper-back", "lower-back", "trapezius"]
        case .shoulders: return ["deltoids"]
        case .biceps: return ["biceps"]
        case .triceps: return ["triceps"]
        case .forearms: return ["forearm"]
        case .quads: return ["quadriceps"]
        case .hamstrings: return ["hamstring"]
        case .glutes: return ["gluteal"]
        case .calves: return ["calves"]
        case .abs: return ["abs", "obliques"]
        case .cardio, .fullBody: return []
        }
    }

    /// Push/pull/legs ordering — sections read top-to-bottom the way people
    /// train, big muscles before the small ones that assist them.
    var sortRank: Int {
        switch self {
        case .chest: return 0
        case .back: return 1
        case .shoulders: return 2
        case .biceps: return 3
        case .triceps: return 4
        case .forearms: return 5
        case .quads: return 6
        case .hamstrings: return 7
        case .glutes: return 8
        case .calves: return 9
        case .abs: return 10
        case .cardio: return 11
        case .fullBody: return 12
        }
    }

    /// The anatomy slug → group mapping used to file the seed library.
    static func fromSlug(_ slug: String) -> MuscleGroup? {
        switch slug {
        case "chest": return .chest
        case "upper-back", "lower-back", "trapezius": return .back
        case "deltoids": return .shoulders
        case "biceps": return .biceps
        case "triceps": return .triceps
        case "forearm": return .forearms
        case "quadriceps": return .quads
        case "hamstring": return .hamstrings
        case "gluteal": return .glutes
        case "calves": return .calves
        case "abs", "obliques": return .abs
        default: return nil
        }
    }

    /// Last-resort mapping for a custom exercise with neither an explicit group
    /// nor anatomy slugs.
    static func fromCategory(_ c: WorkoutCategory) -> MuscleGroup {
        switch c {
        case .chest: return .chest
        case .back: return .back
        case .shoulders: return .shoulders
        case .arms: return .biceps
        case .legs: return .quads
        case .core: return .abs
        case .cardio, .boxing: return .cardio
        }
    }
}

extension Exercise {
    /// Where this exercise files itself: the author's explicit choice, else its
    /// primary anatomy slug, else its library category.
    var group: MuscleGroup {
        if let g = muscleGroup { return g }
        for slug in muscles { if let g = MuscleGroup.fromSlug(slug) { return g } }
        return MuscleGroup.fromCategory(category)
    }
}

// MARK: - Program template

/// One exercise slot inside a muscle-group block. Sets, reps and rest are the
/// *plan*; what you lifted is a `SetLog` in the day's history.
struct ProgramExercise: Codable, Identifiable, Hashable {
    var id: String
    var exerciseId: String
    var sets: Int
    var reps: Int
    /// Rest between sets, in seconds. 0 = unset (nothing shown).
    var restSec: Int
    var note: String?

    init(id: String = UUID().uuidString.lowercased(), exerciseId: String,
         sets: Int = 3, reps: Int = 10, restSec: Int = 90, note: String? = nil) {
        self.id = id; self.exerciseId = exerciseId
        self.sets = sets; self.reps = reps; self.restSec = restSec; self.note = note
    }

    enum CodingKeys: String, CodingKey { case id, exerciseId, sets, reps, restSec, note }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id         = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString.lowercased()
        exerciseId = try c.decodeIfPresent(String.self, forKey: .exerciseId) ?? ""
        sets       = try c.decodeIfPresent(Int.self, forKey: .sets) ?? 3
        reps       = try c.decodeIfPresent(Int.self, forKey: .reps) ?? 10
        restSec    = try c.decodeIfPresent(Int.self, forKey: .restSec) ?? 90
        note       = try c.decodeIfPresent(String.self, forKey: .note)
    }
}

/// A muscle group inside a day, and the exercise variations chosen for it.
/// The same group can appear on several days with completely different
/// exercises — that is the whole point of the block sitting between the day
/// and the exercise.
struct ProgramMuscleBlock: Codable, Identifiable, Hashable {
    var id: String
    var group: MuscleGroup
    var items: [ProgramExercise]

    init(id: String = UUID().uuidString.lowercased(), group: MuscleGroup, items: [ProgramExercise] = []) {
        self.id = id; self.group = group; self.items = items
    }

    enum CodingKeys: String, CodingKey { case id, group, items }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id    = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString.lowercased()
        group = (try? c.decode(MuscleGroup.self, forKey: .group)) ?? .fullBody
        items = try c.decodeIfPresent([ProgramExercise].self, forKey: .items) ?? []
    }
}

/// One day of a program. `name` is free text ("Push A", "Day 1", "Leg day").
/// `weekday` binds it to a calendar day (0 = Sunday); nil means the day takes
/// its turn in a rotation instead.
struct ProgramDay: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var weekday: Int?
    var rest: Bool
    var blocks: [ProgramMuscleBlock]

    init(id: String = UUID().uuidString.lowercased(), name: String, weekday: Int? = nil,
         rest: Bool = false, blocks: [ProgramMuscleBlock] = []) {
        self.id = id; self.name = name; self.weekday = weekday
        self.rest = rest; self.blocks = blocks
    }

    enum CodingKeys: String, CodingKey { case id, name, weekday, rest, blocks }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id      = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString.lowercased()
        name    = try c.decodeIfPresent(String.self, forKey: .name) ?? "Day"
        weekday = try c.decodeIfPresent(Int.self, forKey: .weekday)
        rest    = try c.decodeIfPresent(Bool.self, forKey: .rest) ?? false
        blocks  = try c.decodeIfPresent([ProgramMuscleBlock].self, forKey: .blocks) ?? []
    }

    /// Rest is an explicit choice, and it keeps whatever is planned on the day
    /// so turning it back on doesn't mean rebuilding it. There's no ambiguity to
    /// guard against the way `WorkoutDayPlan` had: adding a muscle group or an
    /// exercise clears the flag, so a day can never be "resting" and scheduled.
    var isRestDay: Bool { rest }
    var exerciseCount: Int { blocks.reduce(0) { $0 + $1.items.count } }
    var groups: [MuscleGroup] { blocks.filter { !$0.items.isEmpty }.map(\.group) }
    /// "Chest · Shoulders · Triceps" — what the day trains, for the schedule list.
    var groupSummary: String {
        let names = groups.map(\.label)
        return names.isEmpty ? "" : names.joined(separator: " · ")
    }
    var allItems: [ProgramExercise] { blocks.flatMap(\.items) }
}

/// A complete training program. Independent of every other program — switching
/// the active one only changes `TrainingState.activeProgramId`.
struct WorkoutProgram: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var notes: String?
    /// Free-text goal/type ("Cut", "Strength", "Hypertrophy") — never a fixed list.
    var goal: String?
    var days: [ProgramDay]
    /// Day 0 of the rotation, for programs whose days aren't bound to weekdays.
    var anchorDate: String?
    var createdAt: String

    init(id: String = UUID().uuidString.lowercased(), name: String, notes: String? = nil,
         goal: String? = nil, days: [ProgramDay] = [], anchorDate: String? = nil,
         createdAt: String = "") {
        self.id = id; self.name = name; self.notes = notes; self.goal = goal
        self.days = days; self.anchorDate = anchorDate; self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey { case id, name, notes, goal, days, anchorDate, createdAt }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id         = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString.lowercased()
        name       = try c.decodeIfPresent(String.self, forKey: .name) ?? "Program"
        notes      = try c.decodeIfPresent(String.self, forKey: .notes)
        goal       = try c.decodeIfPresent(String.self, forKey: .goal)
        days       = try c.decodeIfPresent([ProgramDay].self, forKey: .days) ?? []
        anchorDate = try c.decodeIfPresent(String.self, forKey: .anchorDate)
        createdAt  = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
    }

    /// Days that actually train (rest days don't count towards "6 workout days").
    var trainingDayCount: Int { days.filter { !$0.isRestDay }.count }

    /// A program is weekday-bound the moment any one of its days claims a
    /// weekday. Mixed programs resolve by weekday and fall back to rest, which
    /// is what "Thursday — Rest" means without needing a Rest row for it.
    var isWeekdayBound: Bool { days.contains { $0.weekday != nil } }

    /// The day that runs on a given date.
    ///
    /// - `weekday`: 0 = Sunday … 6 = Saturday, for weekday-bound programs.
    /// - `dayOffset`: whole days since `anchorDate`, for rotation programs.
    ///
    /// Pure on purpose — the caller does the calendar maths so this stays testable.
    func day(weekday: Int, dayOffset: Int) -> ProgramDay? {
        guard !days.isEmpty else { return nil }
        if isWeekdayBound { return days.first { $0.weekday == weekday } }
        let n = days.count
        return days[((dayOffset % n) + n) % n]
    }
}

// MARK: - What actually happened (history, never the template)

/// One set as performed. `reps` starts at the planned target and is edited to
/// what you really got; `weightKg` is nil for bodyweight work.
struct SetLog: Codable, Identifiable, Hashable {
    var id: String
    var weightKg: Double?
    var reps: Int
    var done: Bool

    init(id: String = UUID().uuidString.lowercased(), weightKg: Double? = nil,
         reps: Int = 0, done: Bool = false) {
        self.id = id; self.weightKg = weightKg; self.reps = reps; self.done = done
    }

    enum CodingKeys: String, CodingKey { case id, weightKg, reps, done }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id       = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString.lowercased()
        weightKg = try c.decodeIfPresent(Double.self, forKey: .weightKg)
        reps     = try c.decodeIfPresent(Int.self, forKey: .reps) ?? 0
        done     = try c.decodeIfPresent(Bool.self, forKey: .done) ?? false
    }

    /// "60 kg × 6", or "× 12" when there's no load.
    var summary: String {
        let r = "\(reps)"
        guard let w = weightKg, w > 0 else { return "× \(r)" }
        return "\(Fmt.trimKg(w)) kg × \(r)"
    }
}

/// One exercise as performed, with the muscle group snapshotted so history
/// still reads correctly after the program is edited or deleted.
struct ExerciseLog: Codable, Identifiable, Hashable {
    var id: String
    var exerciseId: String
    var group: MuscleGroup
    var sets: [SetLog]
    var note: String?

    init(id: String = UUID().uuidString.lowercased(), exerciseId: String,
         group: MuscleGroup = .fullBody, sets: [SetLog] = [], note: String? = nil) {
        self.id = id; self.exerciseId = exerciseId; self.group = group
        self.sets = sets; self.note = note
    }

    enum CodingKeys: String, CodingKey { case id, exerciseId, group, sets, note }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id         = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString.lowercased()
        exerciseId = try c.decodeIfPresent(String.self, forKey: .exerciseId) ?? ""
        group      = (try? c.decode(MuscleGroup.self, forKey: .group)) ?? .fullBody
        sets       = try c.decodeIfPresent([SetLog].self, forKey: .sets) ?? []
        note       = try c.decodeIfPresent(String.self, forKey: .note)
    }

    var doneSets: Int { sets.filter(\.done).count }
    /// Heaviest completed set — what a "last time" hint should show.
    var topWeight: Double? { sets.filter(\.done).compactMap(\.weightKg).max() }
    var volumeKg: Double { sets.filter(\.done).reduce(0) { $0 + ($1.weightKg ?? 0) * Double($1.reps) } }
}

// MARK: - Building a session from a template

enum WorkoutSessionBuilder {
    /// Expand a day's template into blank per-set rows to fill in.
    ///
    /// `lastWeight` prefills the load from the last time that exercise was
    /// logged, because typing 60 kg again every Monday is the single most
    /// repeated action in a training log.
    static func session(from day: ProgramDay,
                        lastWeight: (String) -> Double? = { _ in nil }) -> [ExerciseLog] {
        day.blocks.flatMap { block in
            block.items.map { item in
                let w = lastWeight(item.exerciseId)
                return ExerciseLog(
                    exerciseId: item.exerciseId,
                    group: block.group,
                    sets: (0..<max(1, item.sets)).map { _ in
                        SetLog(weightKg: w, reps: max(0, item.reps), done: false)
                    },
                    note: item.note)
            }
        }
    }

    /// History → the flat `[PlanExercise]` the older Today/Day cards still read.
    /// Reps report the most common logged value so a drop set doesn't rewrite
    /// the headline number.
    static func planItems(from entries: [ExerciseLog]) -> [PlanExercise] {
        entries.map { e in
            var counts: [Int: Int] = [:]
            for s in e.sets { counts[s.reps, default: 0] += 1 }
            let reps = counts.max { a, b in a.value == b.value ? a.key < b.key : a.value < b.value }?.key
            return PlanExercise(exerciseId: e.exerciseId, sets: max(1, e.sets.count), reps: reps ?? 0)
        }
    }
}

// MARK: - Migration off the old weekday plan

enum ProgramMigration {
    static let weekdayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    /// Fold a legacy `weekPlan` ("0".."6" → exercises) into one weekday-bound
    /// program, grouping each day's exercises by muscle group while keeping the
    /// order they were added in. Returns nil when there is nothing to carry over.
    static func program(from weekPlan: [String: WorkoutDayPlan],
                        name: String = "My program",
                        group: (String) -> MuscleGroup,
                        createdAt: String = "") -> WorkoutProgram? {
        let hasWork = weekPlan.values.contains { !$0.items.isEmpty }
        guard hasWork else { return nil }

        var days: [ProgramDay] = []
        for wd in 0..<7 {
            let plan = weekPlan[String(wd)] ?? WorkoutDayPlan()
            let dayName = weekdayNames[wd]
            guard !plan.items.isEmpty else {
                days.append(ProgramDay(name: "Rest", weekday: wd, rest: true))
                continue
            }
            var blocks: [ProgramMuscleBlock] = []
            for item in plan.items {
                let g = group(item.exerciseId)
                let pe = ProgramExercise(exerciseId: item.exerciseId, sets: item.sets, reps: item.reps)
                if let i = blocks.firstIndex(where: { $0.group == g }) {
                    blocks[i].items.append(pe)
                } else {
                    blocks.append(ProgramMuscleBlock(group: g, items: [pe]))
                }
            }
            days.append(ProgramDay(name: dayName, weekday: wd, rest: false, blocks: blocks))
        }
        return WorkoutProgram(name: name, notes: "Carried over from your weekly plan.",
                              days: days, createdAt: createdAt)
    }
}
