import Foundation

/// The two step goals, and everything that follows from them.
///
/// Two on purpose. One goal is a pass/fail line and the day is over the moment
/// you cross it; two turns the same walk into a floor and a ceiling — 8,000 is
/// the day's rent and 10,000 is the day you actually wanted. Missing the second
/// one is not a failure, which is the whole reason it exists.
struct StepGoals: Equatable, Hashable {
    /// The mandatory goal. This is the one the streak is counted on.
    var daily: Int
    /// The optional one, above it.
    var stretch: Int

    static let defaultDaily = 8_000
    static let defaultStretch = 10_000

    /// Built from whatever the profile holds, which may be nothing, or nonsense.
    ///
    /// The stretch is forced above the daily. A stretch goal that sits at or
    /// below the mandatory one is not a stretch — it would be reached in the
    /// same stride, fire both celebrations at once, and make the second arc on
    /// the ring draw backwards.
    init(daily: Int?, stretch: Int?) {
        let floor = max(1, daily ?? Self.defaultDaily)
        self.daily = floor
        let ceiling = stretch ?? Self.defaultStretch
        self.stretch = ceiling > floor ? ceiling : floor + 2_000
    }

    /// How many goals a count reaches: 0, 1 or 2.
    func reached(_ steps: Int) -> Int {
        if steps >= stretch { return 2 }
        if steps >= daily { return 1 }
        return 0
    }

    /// Which goals this count has reached that have not been celebrated yet.
    ///
    /// Pulled out of `AppState` so the rule that matters most here — that a goal
    /// is congratulated exactly once, however many times the day is re-read — is
    /// pinned by a test rather than by walking around with a phone.
    func fresh(steps: Int, alreadyHailed: [Int]?) -> [Int] {
        let level = reached(steps)
        guard level > 0 else { return [] }
        let already = Set(alreadyHailed ?? [])
        return (1...level).filter { !already.contains($0) }
    }

    /// The target for a given level, and the one after it.
    func target(_ level: Int) -> Int { level >= 2 ? stretch : daily }
    func next(after level: Int) -> Int? { level >= 2 ? nil : stretch }
}

/// How one day reads on a streak calendar.
enum StepDay: Equatable {
    /// Past the stretch.
    case stretch
    /// Past the mandatory goal.
    case hit
    /// Walked, but short of the goal.
    case short
    /// Today, still counting — not a miss until midnight.
    case pending
    /// Nothing recorded.
    case none
}

/// The streak, counted on steps.
///
/// Deliberately unforgiving: there is no freeze day. A single day under the
/// mandatory goal ends the run. Berjil chose this over the journal's
/// Duolingo-style freeze — on a cut, a day under 8,000 is a day under 8,000,
/// and a streak that survives it is telling you something that isn't true.
///
/// Today is the one exception, and it is not a kindness: a day that has not
/// finished cannot have been missed, so the run stays alive until midnight.
@MainActor
enum StepStreak {

    /// A run longer than this is a corrupt key walking backwards forever.
    private static let walkLimit = 3_650

    static func count(fitness: [String: FitnessDay], goals: StepGoals, today: String) -> Int {
        var key = today
        // Today not yet at goal is pending, not broken — start the walk on
        // yesterday and let the day finish.
        if steps(fitness, key) < goals.daily { key = AppState.addDays(-1, to: key) }

        var run = 0
        while run < walkLimit, steps(fitness, key) >= goals.daily {
            run += 1
            key = AppState.addDays(-1, to: key)
        }
        return run
    }

    /// What a single date is worth on the calendar.
    static func day(_ key: String, fitness: [String: FitnessDay],
                    goals: StepGoals, today: String) -> StepDay {
        let n = steps(fitness, key)
        if n >= goals.stretch { return .stretch }
        if n >= goals.daily { return .hit }
        if key == today { return .pending }
        return n > 0 ? .short : .none
    }

    private static func steps(_ fitness: [String: FitnessDay], _ key: String) -> Int {
        max(0, fitness[key]?.steps ?? 0)
    }
}

/// A goal, just crossed, and everything the celebration needs to say.
struct StepCelebration: Equatable, Identifiable {
    /// 1 for the mandatory goal, 2 for the stretch.
    var level: Int
    var steps: Int
    var target: Int
    /// The goal after this one, when there is one.
    var next: Int?
    /// The streak this day just extended, counting this day.
    var streak: Int
    var quote: String
    var id: String { "\(day).\(level)" }
    var day: String

    var remaining: Int? { next.map { max(0, $0 - steps) } }
}

/// Lines for the walk that has just been finished.
///
/// Local, not a model call — the same reasoning as the activity insights. This
/// has to land the instant the goal is crossed, offline, on a phone in a pocket,
/// and a confident wrong sentence is worse than a plain right one. Written for a
/// cut, because that is the goal these steps are in service of.
enum StepQuotes {

    /// Crossing the floor. The tone is "that was the job, and you did it".
    static let mandatory: [String] = [
        "The cut is won on the boring days. Today was one of them.",
        "Nothing dramatic happened. That's exactly why it worked.",
        "Discipline is just showing up when it isn't interesting.",
        "You didn't feel like it and you did it anyway. That's the whole skill.",
        "Fat loss is a slow argument you win by not quitting.",
        "The goal wasn't to feel motivated. The goal was to move. Done.",
        "Consistency beats intensity, and today you were consistent.",
        "Every day like this one makes the next one easier to start.",
    ]

    /// Past the stretch. The tone is "you went further than required".
    static let stretch: [String] = [
        "Past the line you set. That's where the change actually lives.",
        "You didn't have to do that. That's the point.",
        "The extra two thousand is the part nobody sees and everybody notices.",
        "This is what a good day looks like. Remember it on a bad one.",
        "You beat your own minimum. That's not luck, that's a habit forming.",
        "Ahead of the plan, not behind it. Keep the receipts.",
    ]

    /// A stable pick, so opening the app twice does not reshuffle the line and
    /// the same one does not land two days running. Swift's own `hashValue` is
    /// seeded per process and would do exactly that.
    static func line(day: String, level: Int) -> String {
        let pool = level >= 2 ? stretch : mandatory
        guard !pool.isEmpty else { return "" }
        var seed = level &* 31
        for scalar in day.unicodeScalars { seed = (seed &* 131 &+ Int(scalar.value)) % 1_000_003 }
        return pool[abs(seed) % pool.count]
    }
}
