import Foundation

// Program CRUD, schedule resolution and workout logging.
//
// One rule runs through all of it: **the program is a template and the day log
// is history.** Nothing you do while training writes back into `programs`, and
// nothing you do while editing a program rewrites a day you already trained.

extension AppState {

    // MARK: - Exercise library, by muscle group

    /// Every exercise filed under a group, alphabetical.
    func exercises(in group: MuscleGroup) -> [Exercise] {
        allExercises.filter { $0.group == group }
    }

    /// The group an exercise id files under (unknown ids read as full body).
    func group(ofExercise id: String) -> MuscleGroup {
        exercise(id)?.group ?? .fullBody
    }

    // MARK: - Programs

    var programs: [WorkoutProgram] { training.programs }
    var activeProgram: WorkoutProgram? { training.activeProgram }
    func program(_ id: String) -> WorkoutProgram? { training.programs.first { $0.id == id } }

    /// Create a program. The first one you make becomes active — there is no
    /// value in a program nobody is running.
    @discardableResult
    func createProgram(name: String, notes: String? = nil, goal: String? = nil,
                       days: [ProgramDay] = []) -> WorkoutProgram {
        var p = WorkoutProgram(name: name.trimmingCharacters(in: .whitespaces),
                               notes: notes?.nilIfBlank, goal: goal?.nilIfBlank,
                               days: days, anchorDate: todayKey, createdAt: todayKey)
        if p.name.isEmpty { p.name = "New program" }
        training.programs.append(p)
        if training.activeProgramId == nil { training.activeProgramId = p.id }
        push(StateKey.training, training)
        return p
    }

    func updateProgram(_ id: String, name: String? = nil, notes: String?? = nil, goal: String?? = nil) {
        mutateProgram(id) { p in
            if let name, !name.trimmingCharacters(in: .whitespaces).isEmpty {
                p.name = name.trimmingCharacters(in: .whitespaces)
            }
            if let notes { p.notes = notes?.nilIfBlank }
            if let goal { p.goal = goal?.nilIfBlank }
        }
    }

    /// A copy with fresh ids all the way down, so editing the duplicate can
    /// never reach into the original.
    @discardableResult
    func duplicateProgram(_ id: String) -> WorkoutProgram? {
        guard let src = program(id) else { return nil }
        var copy = src
        copy.id = UUID().uuidString.lowercased()
        copy.name = Self.copyName(src.name, taken: training.programs.map(\.name))
        copy.createdAt = todayKey
        copy.anchorDate = todayKey
        copy.days = src.days.map(Self.freshIds)
        training.programs.append(copy)
        push(StateKey.training, training)
        return copy
    }

    func deleteProgram(_ id: String) {
        training.programs.removeAll { $0.id == id }
        if training.activeProgramId == id { training.activeProgramId = training.programs.first?.id }
        push(StateKey.training, training)
    }

    /// Switching programs only moves a pointer. Nothing else is touched — the
    /// program you were on keeps every day, block and exercise it had.
    func setActiveProgram(_ id: String?) {
        training.activeProgramId = id
        // Re-anchor a rotation so "Day 1" starts today rather than mid-cycle.
        if let id, let i = training.programs.firstIndex(where: { $0.id == id }),
           !training.programs[i].isWeekdayBound {
            training.programs[i].anchorDate = todayKey
        }
        push(StateKey.training, training)
    }

    func moveProgramDays(_ programId: String, from source: IndexSet, to destination: Int) {
        mutateProgram(programId) { $0.days.move(fromOffsets: source, toOffset: destination) }
    }

    // MARK: - Days

    @discardableResult
    func addDay(to programId: String, name: String? = nil, weekday: Int? = nil,
                rest: Bool = false) -> ProgramDay? {
        guard let p = program(programId) else { return nil }
        let label = name?.nilIfBlank ?? (rest ? "Rest" : Self.nextDayName(p))
        let day = ProgramDay(name: label, weekday: weekday, rest: rest)
        mutateProgram(programId) { $0.days.append(day) }
        return day
    }

    func renameDay(_ programId: String, _ dayId: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        mutateDay(programId, dayId) { $0.name = trimmed }
    }

    /// nil unbinds the day from the calendar and puts it back in the rotation.
    func setDayWeekday(_ programId: String, _ dayId: String, weekday: Int?) {
        mutateProgram(programId) { p in
            guard let i = p.days.firstIndex(where: { $0.id == dayId }) else { return }
            // A weekday can only belong to one day, or Today has no answer.
            if let weekday {
                for j in p.days.indices where j != i && p.days[j].weekday == weekday {
                    p.days[j].weekday = nil
                }
            }
            p.days[i].weekday = weekday
        }
    }

    /// Turning a training day into a rest day keeps its exercises, so turning
    /// it back doesn't mean rebuilding the day. (`isRestDay` reads the flag and
    /// the emptiness together, so a rest day with exercises still shows as rest.)
    func setDayRest(_ programId: String, _ dayId: String, _ rest: Bool) {
        mutateDay(programId, dayId) { d in
            d.rest = rest
            if rest && d.name.trimmingCharacters(in: .whitespaces).isEmpty { d.name = "Rest" }
        }
    }

    func duplicateDay(_ programId: String, _ dayId: String) {
        mutateProgram(programId) { p in
            guard let i = p.days.firstIndex(where: { $0.id == dayId }) else { return }
            var copy = Self.freshIds(p.days[i])
            copy.name = Self.copyName(copy.name, taken: p.days.map(\.name))
            copy.weekday = nil          // two days can't own the same weekday
            p.days.insert(copy, at: i + 1)
        }
    }

    func deleteDay(_ programId: String, _ dayId: String) {
        mutateProgram(programId) { $0.days.removeAll { $0.id == dayId } }
    }

    // MARK: - Muscle-group blocks

    @discardableResult
    func addBlock(_ programId: String, _ dayId: String, group: MuscleGroup) -> String? {
        var newId: String?
        mutateDay(programId, dayId) { d in
            if let existing = d.blocks.first(where: { $0.group == group }) {
                newId = existing.id          // adding a group twice just reveals the one there
                return
            }
            let b = ProgramMuscleBlock(group: group)
            d.blocks.append(b)
            d.rest = false
            newId = b.id
        }
        return newId
    }

    func removeBlock(_ programId: String, _ dayId: String, _ blockId: String) {
        mutateDay(programId, dayId) { $0.blocks.removeAll { $0.id == blockId } }
    }

    func moveBlocks(_ programId: String, _ dayId: String, from source: IndexSet, to destination: Int) {
        mutateDay(programId, dayId) { $0.blocks.move(fromOffsets: source, toOffset: destination) }
    }

    // MARK: - Exercises inside a block

    func addProgramExercise(_ programId: String, _ dayId: String, _ blockId: String,
                            exerciseId: String, sets: Int = 3, reps: Int = 10, restSec: Int = 90) {
        mutateBlock(programId, dayId, blockId) {
            $0.items.append(ProgramExercise(exerciseId: exerciseId, sets: sets, reps: reps, restSec: restSec))
        }
        mutateDay(programId, dayId) { $0.rest = false }
    }

    /// Swap the movement, keep the slot. Sets, reps, rest and notes survive —
    /// that is the whole point of "change exercise" being one tap.
    func replaceProgramExercise(_ programId: String, _ dayId: String, _ blockId: String,
                                itemId: String, with exerciseId: String) {
        mutateBlock(programId, dayId, blockId) {
            guard let i = $0.items.firstIndex(where: { $0.id == itemId }) else { return }
            $0.items[i].exerciseId = exerciseId
        }
    }

    func updateProgramExercise(_ programId: String, _ dayId: String, _ blockId: String,
                               itemId: String, _ f: @escaping (inout ProgramExercise) -> Void) {
        mutateBlock(programId, dayId, blockId) {
            guard let i = $0.items.firstIndex(where: { $0.id == itemId }) else { return }
            f(&$0.items[i])
            $0.items[i].sets = max(1, $0.items[i].sets)
            $0.items[i].reps = max(1, $0.items[i].reps)
            $0.items[i].restSec = max(0, $0.items[i].restSec)
        }
    }

    func duplicateProgramExercise(_ programId: String, _ dayId: String, _ blockId: String, itemId: String) {
        mutateBlock(programId, dayId, blockId) {
            guard let i = $0.items.firstIndex(where: { $0.id == itemId }) else { return }
            var copy = $0.items[i]
            copy.id = UUID().uuidString.lowercased()
            $0.items.insert(copy, at: i + 1)
        }
    }

    func removeProgramExercise(_ programId: String, _ dayId: String, _ blockId: String, itemId: String) {
        mutateBlock(programId, dayId, blockId) { $0.items.removeAll { $0.id == itemId } }
    }

    func moveProgramExercises(_ programId: String, _ dayId: String, _ blockId: String,
                              from source: IndexSet, to destination: Int) {
        mutateBlock(programId, dayId, blockId) { $0.items.move(fromOffsets: source, toOffset: destination) }
    }

    // MARK: - What am I training today?

    /// The day the *schedule* says runs on this date, ignoring any override.
    func scheduledDay(for date: String) -> (program: WorkoutProgram, day: ProgramDay)? {
        guard let p = activeProgram else { return nil }
        let weekday = Int(Self.weekdayKey(date)) ?? 0
        // Only a rotation needs the date arithmetic. This runs in the Today
        // card's body, and Today keeps three pages alive at once on iPhone.
        let offset = p.isWeekdayBound ? 0
                   : (Self.daysBetween(p.anchorDate ?? p.createdAt, and: date) ?? 0)
        guard let d = p.day(weekday: weekday, dayOffset: offset) else { return nil }
        return (p, d)
    }

    /// What actually runs today: an override you picked, else the schedule.
    /// Returns nil when there is no active program at all.
    func programDay(for date: String) -> (program: WorkoutProgram, day: ProgramDay)? {
        let log = workoutDayLog(date)
        if let overrideId = log.dayId,
           let p = program(log.programId ?? training.activeProgramId ?? ""),
           let d = p.days.first(where: { $0.id == overrideId }) {
            return (p, d)
        }
        return scheduledDay(for: date)
    }

    /// Run a different workout from the active program today. The program's own
    /// schedule is untouched — only this date moves.
    func setWorkoutOverride(date: String, dayId: String?) {
        mutateDayLog(date) {
            $0.dayId = dayId
            $0.programId = dayId == nil ? nil : self.training.activeProgramId
            $0.restOverride = false
        }
    }

    /// "Make today a rest day" — no workout owed, and not a skipped one either.
    func setRestOverride(date: String, _ rest: Bool) {
        mutateDayLog(date) {
            $0.restOverride = rest
            if rest { $0.dayId = nil; $0.skipped = false; $0.done = false }
        }
    }

    /// Is this date a rest day — by override, or because the schedule says so?
    func isRestDay(_ date: String) -> Bool {
        if workoutDayLog(date).restOverride { return true }
        guard let (_, day) = programDay(for: date) else { return false }
        return day.isRestDay
    }

    // MARK: - Logging a workout (history only)

    /// The heaviest weight logged for an exercise, most recent day first.
    /// Used to prefill a session so you don't retype the same load weekly.
    func lastWeight(exerciseId: String) -> Double? {
        for date in training.dayLog.keys.sorted(by: >) {
            guard let entries = training.dayLog[date]?.entries else { continue }
            if let hit = entries.first(where: { $0.exerciseId == exerciseId }), let w = hit.topWeight {
                return w
            }
        }
        return nil
    }

    /// Build today's session from the template (once). Idempotent — reopening
    /// a session in progress returns what's already there.
    func startSession(date: String) {
        guard workoutDayLog(date).entries == nil else { return }
        guard let (p, day) = programDay(for: date), !day.isRestDay else { return }
        let entries = WorkoutSessionBuilder.session(from: day) { [weak self] id in
            self?.lastWeight(exerciseId: id)
        }
        mutateDayLog(date) {
            $0.entries = entries
            $0.dayId = $0.dayId ?? day.id
            $0.programId = p.id
            $0.title = day.name
            $0.skipped = false
        }
    }

    /// Throw away the session and rebuild it from the program as it stands now.
    func resetSession(date: String) {
        mutateDayLog(date) { $0.entries = nil; $0.done = false }
        startSession(date: date)
    }

    func updateSet(date: String, entryId: String, setId: String, _ f: @escaping (inout SetLog) -> Void) {
        mutateSession(date) { entries in
            guard let i = entries.firstIndex(where: { $0.id == entryId }),
                  let j = entries[i].sets.firstIndex(where: { $0.id == setId }) else { return }
            f(&entries[i].sets[j])
            entries[i].sets[j].reps = max(0, entries[i].sets[j].reps)
            if let w = entries[i].sets[j].weightKg, w < 0 { entries[i].sets[j].weightKg = 0 }
        }
    }

    func addSet(date: String, entryId: String) {
        mutateSession(date) { entries in
            guard let i = entries.firstIndex(where: { $0.id == entryId }) else { return }
            let last = entries[i].sets.last
            entries[i].sets.append(SetLog(weightKg: last?.weightKg, reps: last?.reps ?? 10, done: false))
        }
    }

    func removeSet(date: String, entryId: String, setId: String) {
        mutateSession(date) { entries in
            guard let i = entries.firstIndex(where: { $0.id == entryId }) else { return }
            entries[i].sets.removeAll { $0.id == setId }
        }
    }

    /// Add an exercise to *today only* — the program keeps its shape.
    func addSessionExercise(date: String, exerciseId: String, sets: Int = 3, reps: Int = 10) {
        let g = group(ofExercise: exerciseId)
        let w = lastWeight(exerciseId: exerciseId)
        let entry = ExerciseLog(exerciseId: exerciseId, group: g,
                                sets: (0..<max(1, sets)).map { _ in SetLog(weightKg: w, reps: reps) })
        mutateDayLog(date) { $0.entries = ($0.entries ?? []) + [entry] }
    }

    func removeSessionExercise(date: String, entryId: String) {
        mutateSession(date) { $0.removeAll { $0.id == entryId } }
    }

    func setSessionNote(date: String, entryId: String, note: String?) {
        mutateSession(date) { entries in
            guard let i = entries.firstIndex(where: { $0.id == entryId }) else { return }
            entries[i].note = note?.nilIfBlank
        }
    }

    /// Finish the workout. Every untouched set is dropped rather than recorded
    /// as done — history should say what happened, not what was scheduled.
    ///
    /// Finishing with nothing ticked is not "did nothing": it's the old
    /// slide-to-log, meaning *did it as planned*. `items = nil` has always been
    /// how that is stored, so the day still reads back off the template.
    func finishSession(date: String) {
        mutateDayLog(date) { log in
            if var entries = log.entries {
                for i in entries.indices { entries[i].sets.removeAll { !$0.done } }
                entries.removeAll { $0.sets.isEmpty }
                if entries.isEmpty {
                    log.entries = nil
                    log.items = nil
                } else {
                    log.entries = entries
                    log.items = WorkoutSessionBuilder.planItems(from: entries)
                }
            }
            log.done = true
            log.skipped = false
        }
    }

    /// "I did it as planned" — no set-by-set log, just the tick. Keeps the
    /// three-second path that existed before sessions did.
    func markWorkoutDone(date: String) {
        if let (p, day) = programDay(for: date) {
            mutateDayLog(date) {
                $0.dayId = $0.dayId ?? day.id
                $0.programId = p.id
                $0.title = day.name
            }
        }
        mutateDayLog(date) { $0.tick(items: nil) }
    }

    private func mutateSession(_ date: String, _ f: @escaping (inout [ExerciseLog]) -> Void) {
        mutateDayLog(date) { log in
            var entries = log.entries ?? []
            f(&entries)
            log.entries = entries
        }
    }

    // MARK: - History

    /// Dates with a finished or in-progress workout, newest first.
    func workoutHistoryDates(limit: Int = 60) -> [String] {
        training.dayLog
            .filter { $0.value.done || $0.value.hasSession }
            .keys.sorted(by: >)
            .prefix(limit)
            .map { $0 }
    }

    /// Every logged set for an exercise, newest date first — the "last time"
    /// panel inside a session.
    func history(ofExercise id: String, limit: Int = 8) -> [(date: String, entry: ExerciseLog)] {
        var out: [(String, ExerciseLog)] = []
        for date in training.dayLog.keys.sorted(by: >) {
            guard let entries = training.dayLog[date]?.entries else { continue }
            for e in entries where e.exerciseId == id && e.doneSets > 0 {
                out.append((date, e))
                if out.count >= limit { return out }
            }
        }
        return out
    }

    // MARK: - Migration off the legacy weekday plan

    /// Fold an old `weekPlan` into a program, once.
    ///
    /// Only ever runs off a state pulled from the server (see the call sites in
    /// `AppState`), and only writes when there is genuinely something to carry
    /// over — a migration that pushes on every launch would happily overwrite a
    /// newer program with whatever this device had cached.
    func migrateTrainingIfNeeded() {
        guard !training.migratedWeekPlan, training.programs.isEmpty else { return }
        guard let p = ProgramMigration.program(
            from: training.weekPlan,
            group: { [weak self] id in self?.group(ofExercise: id) ?? .fullBody },
            createdAt: todayKey
        ) else { return }
        var prog = p
        prog.anchorDate = todayKey
        training.migratedWeekPlan = true
        training.programs = [prog]
        training.activeProgramId = prog.id
        push(StateKey.training, training)
    }

    // MARK: - Plumbing

    func mutateProgram(_ id: String, _ f: (inout WorkoutProgram) -> Void) {
        guard let i = training.programs.firstIndex(where: { $0.id == id }) else { return }
        f(&training.programs[i])
        push(StateKey.training, training)
    }

    private func mutateDay(_ programId: String, _ dayId: String, _ f: (inout ProgramDay) -> Void) {
        mutateProgram(programId) { p in
            guard let i = p.days.firstIndex(where: { $0.id == dayId }) else { return }
            f(&p.days[i])
        }
    }

    private func mutateBlock(_ programId: String, _ dayId: String, _ blockId: String,
                             _ f: (inout ProgramMuscleBlock) -> Void) {
        mutateDay(programId, dayId) { d in
            guard let i = d.blocks.firstIndex(where: { $0.id == blockId }) else { return }
            f(&d.blocks[i])
        }
    }

    /// Whole days between two `yyyy-MM-dd` keys. Negative when `date` is earlier.
    static func daysBetween(_ from: String, and date: String) -> Int? {
        guard let a = Self.date(fromKey: from), let b = Self.date(fromKey: date) else { return nil }
        return Self.dayCalendar.dateComponents([.day], from: a, to: b).day
    }

    /// The destination for a one-step "move up"/"move down".
    ///
    /// `Array.move(fromOffsets:toOffset:)` counts the row being lifted out, so a
    /// downward move needs +1 or it lands exactly where it started. Getting this
    /// wrong is silent — the row just doesn't move — so it lives here once
    /// instead of three times in the views.
    static func moveOffset(from index: Int, delta: Int, count: Int) -> Int? {
        let target = index + delta
        guard delta != 0, index >= 0, index < count, target >= 0, target < count else { return nil }
        return delta > 0 ? target + 1 : target
    }

    /// "Push A" → "Push A copy" → "Push A copy 2".
    static func copyName(_ name: String, taken: [String]) -> String {
        let base = "\(name) copy"
        if !taken.contains(base) { return base }
        var n = 2
        while taken.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }

    /// "Day 4" for the next day of a program that names its days that way.
    static func nextDayName(_ p: WorkoutProgram) -> String {
        "Day \(p.days.count + 1)"
    }

    /// Deep copy of a day with new ids at every level.
    static func freshIds(_ day: ProgramDay) -> ProgramDay {
        var d = day
        d.id = UUID().uuidString.lowercased()
        d.blocks = day.blocks.map { b in
            var nb = b
            nb.id = UUID().uuidString.lowercased()
            nb.items = b.items.map { i in
                var ni = i
                ni.id = UUID().uuidString.lowercased()
                return ni
            }
            return nb
        }
        return d
    }
}

extension String {
    /// Blank strings should be absent, not stored as "".
    var nilIfBlank: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
