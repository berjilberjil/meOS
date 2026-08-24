import XCTest
@testable import MyOS

// The program layer's rules, tested without an AppState: which muscle group an
// exercise files under, which day runs on a date, what a session expands to,
// and what the old weekday plan becomes.

final class MuscleGroupTests: XCTestCase {
    func testSlugsMapToTheFinerGroups() {
        XCTAssertEqual(MuscleGroup.fromSlug("chest"), .chest)
        XCTAssertEqual(MuscleGroup.fromSlug("upper-back"), .back)
        XCTAssertEqual(MuscleGroup.fromSlug("trapezius"), .back)
        XCTAssertEqual(MuscleGroup.fromSlug("deltoids"), .shoulders)
        XCTAssertEqual(MuscleGroup.fromSlug("quadriceps"), .quads)
        XCTAssertEqual(MuscleGroup.fromSlug("hamstring"), .hamstrings)
        XCTAssertEqual(MuscleGroup.fromSlug("obliques"), .abs)
        XCTAssertNil(MuscleGroup.fromSlug("nonsense"))
    }

    /// Arms is one library category but two training sections — this split is
    /// the reason MuscleGroup exists alongside WorkoutCategory.
    func testBicepsAndTricepsAreSeparateGroupsInOneCategory() {
        XCTAssertNotEqual(MuscleGroup.biceps, MuscleGroup.triceps)
        XCTAssertEqual(MuscleGroup.biceps.category, .arms)
        XCTAssertEqual(MuscleGroup.triceps.category, .arms)
    }

    func testExplicitGroupWinsOverSlugs() {
        let ex = Exercise(name: "Rope pushdown", category: .arms, equipment: "Cable",
                          primary: "Triceps", muscles: ["biceps"], muscleGroup: .triceps)
        XCTAssertEqual(ex.group, .triceps)
    }

    func testFallsBackToTheFirstAnatomySlug() {
        let ex = Exercise(name: "Barbell bench press", category: .chest, equipment: "Barbell",
                          primary: "Mid chest", muscles: ["chest", "triceps", "deltoids"])
        XCTAssertEqual(ex.group, .chest)
    }

    func testFallsBackToCategoryWhenNothingElseIsKnown() {
        let ex = Exercise(name: "Mystery machine", category: .legs, equipment: "Machine", primary: "")
        XCTAssertEqual(ex.group, .quads)
    }

    /// Every seed exercise must land in a real group — an unfiled exercise is
    /// invisible when you add exercises by muscle.
    func testEverySeedExerciseResolvesToAGroup() {
        for ex in ExerciseSeed.all {
            XCTAssertFalse(ex.group == .fullBody, "\(ex.name) fell through to Full body")
        }
    }

    /// Reading the slugs literally filed a treadmill run under Quads and a jab
    /// under Shoulders, and left Cardio with nothing in it.
    func testCardioAndBoxingFileUnderCardio() {
        for ex in ExerciseSeed.all where ex.category == .cardio || ex.category == .boxing {
            XCTAssertEqual(ex.group, .cardio, "\(ex.name) filed under \(ex.group.label)")
        }
    }

    /// A muscle group you can pick with nothing behind it is a dead end. Full
    /// body is the one exception: it exists as the decode fallback and as a
    /// home for custom circuit work.
    func testEveryPickableGroupHasSeedExercises() {
        let filled = Set(ExerciseSeed.all.map(\.group))
        for g in MuscleGroup.allCases where g != .fullBody {
            XCTAssertTrue(filled.contains(g), "no seed exercise for \(g.label)")
        }
    }
}

final class ProgramScheduleTests: XCTestCase {
    private func day(_ name: String, weekday: Int? = nil, rest: Bool = false,
                     exercises: Int = 1) -> ProgramDay {
        let items = (0..<exercises).map { _ in ProgramExercise(exerciseId: "seed-ex-1") }
        return ProgramDay(name: name, weekday: weekday, rest: rest,
                          blocks: items.isEmpty ? [] : [ProgramMuscleBlock(group: .chest, items: items)])
    }

    func testWeekdayBoundProgramPicksTheDayForThatWeekday() {
        let p = WorkoutProgram(name: "PPL", days: [
            day("Push A", weekday: 1), day("Pull A", weekday: 2), day("Rest", weekday: 3, rest: true, exercises: 0)
        ])
        XCTAssertTrue(p.isWeekdayBound)
        XCTAssertEqual(p.day(weekday: 1, dayOffset: 0)?.name, "Push A")
        XCTAssertEqual(p.day(weekday: 2, dayOffset: 99)?.name, "Pull A")
        XCTAssertEqual(p.day(weekday: 3, dayOffset: 0)?.name, "Rest")
    }

    /// A weekday nobody claimed is a rest day by omission — you shouldn't have
    /// to add a Rest row for every day off.
    func testUnclaimedWeekdayResolvesToNothing() {
        let p = WorkoutProgram(name: "PPL", days: [day("Push A", weekday: 1)])
        XCTAssertNil(p.day(weekday: 5, dayOffset: 0))
    }

    func testRotationProgramCyclesByOffset() {
        let p = WorkoutProgram(name: "3-day", days: [day("Day 1"), day("Day 2"), day("Day 3")])
        XCTAssertFalse(p.isWeekdayBound)
        XCTAssertEqual(p.day(weekday: 0, dayOffset: 0)?.name, "Day 1")
        XCTAssertEqual(p.day(weekday: 3, dayOffset: 2)?.name, "Day 3")
        XCTAssertEqual(p.day(weekday: 6, dayOffset: 4)?.name, "Day 2")
    }

    /// Looking back before the anchor must not crash or land off the end.
    func testRotationHandlesNegativeOffsets() {
        let p = WorkoutProgram(name: "3-day", days: [day("Day 1"), day("Day 2"), day("Day 3")])
        XCTAssertEqual(p.day(weekday: 0, dayOffset: -1)?.name, "Day 3")
        XCTAssertEqual(p.day(weekday: 0, dayOffset: -3)?.name, "Day 1")
    }

    func testEmptyProgramResolvesToNothing() {
        XCTAssertNil(WorkoutProgram(name: "Empty").day(weekday: 2, dayOffset: 0))
    }

    /// One day carrying a weekday makes the whole program weekday-bound, so a
    /// half-migrated program can't silently rotate.
    func testAnySingleBindingMakesTheProgramWeekdayBound() {
        let p = WorkoutProgram(name: "Mixed", days: [day("Free"), day("Monday", weekday: 1)])
        XCTAssertTrue(p.isWeekdayBound)
        XCTAssertEqual(p.day(weekday: 1, dayOffset: 7)?.name, "Monday")
    }

    /// Converting a day to rest must keep its exercises — otherwise "make it a
    /// rest day this week" costs you the day you built.
    func testRestIsExplicitAndKeepsWhatIsPlanned() {
        XCTAssertTrue(ProgramDay(name: "Rest", rest: true).isRestDay)
        let resting = day("Push", rest: true)
        XCTAssertTrue(resting.isRestDay)
        XCTAssertEqual(resting.exerciseCount, 1, "the plan survives the rest flag")
        XCTAssertFalse(ProgramDay(name: "Push").isRestDay)
    }

    func testTrainingDayCountIgnoresRestDays() {
        let p = WorkoutProgram(name: "PPL", days: [
            day("Push", weekday: 1), day("Rest", weekday: 2, rest: true, exercises: 0),
            day("Pull", weekday: 3)
        ])
        XCTAssertEqual(p.trainingDayCount, 2)
        XCTAssertEqual(p.days.count, 3)
    }

    func testGroupSummaryListsTheMusclesTrained() {
        let d = ProgramDay(name: "Push A", blocks: [
            ProgramMuscleBlock(group: .chest, items: [ProgramExercise(exerciseId: "a")]),
            ProgramMuscleBlock(group: .shoulders, items: [ProgramExercise(exerciseId: "b")]),
            ProgramMuscleBlock(group: .triceps, items: [])       // empty block stays out of the summary
        ])
        XCTAssertEqual(d.groupSummary, "Chest · Shoulders")
        XCTAssertEqual(d.exerciseCount, 2)
    }
}

final class WorkoutSessionBuilderTests: XCTestCase {
    private let day = ProgramDay(name: "Push A", blocks: [
        ProgramMuscleBlock(group: .chest, items: [
            ProgramExercise(exerciseId: "bench", sets: 4, reps: 6),
            ProgramExercise(exerciseId: "incline", sets: 3, reps: 8)
        ]),
        ProgramMuscleBlock(group: .triceps, items: [
            ProgramExercise(exerciseId: "pushdown", sets: 3, reps: 12)
        ])
    ])

    func testExpandsEveryPlannedSetIntoItsOwnRow() {
        let s = WorkoutSessionBuilder.session(from: day)
        XCTAssertEqual(s.count, 3)
        XCTAssertEqual(s.map(\.sets.count), [4, 3, 3])
        XCTAssertEqual(s.map(\.group), [.chest, .chest, .triceps])
        XCTAssertEqual(s[0].sets.first?.reps, 6)
        XCTAssertTrue(s.allSatisfy { $0.sets.allSatisfy { !$0.done } })
    }

    func testPrefillsTheWeightYouUsedLastTime() {
        let s = WorkoutSessionBuilder.session(from: day) { $0 == "bench" ? 60 : nil }
        XCTAssertEqual(s[0].sets.first?.weightKg, 60)
        XCTAssertNil(s[2].sets.first?.weightKg)
    }

    func testAtLeastOneSetEvenIfThePlanSaysZero() {
        let d = ProgramDay(name: "X", blocks: [
            ProgramMuscleBlock(group: .abs, items: [ProgramExercise(exerciseId: "plank", sets: 0, reps: 0)])
        ])
        XCTAssertEqual(WorkoutSessionBuilder.session(from: d).first?.sets.count, 1)
    }

    /// A drop set shouldn't rewrite the headline number on the Today card.
    func testPlanItemsReportTheMostCommonRepCount() {
        let entry = ExerciseLog(exerciseId: "bench", group: .chest, sets: [
            SetLog(weightKg: 60, reps: 6, done: true),
            SetLog(weightKg: 60, reps: 6, done: true),
            SetLog(weightKg: 60, reps: 5, done: true),
            SetLog(weightKg: 55, reps: 6, done: true)
        ])
        let items = WorkoutSessionBuilder.planItems(from: [entry])
        XCTAssertEqual(items.first?.sets, 4)
        XCTAssertEqual(items.first?.reps, 6)
    }

    func testTopWeightAndVolumeOnlyCountCompletedSets() {
        let entry = ExerciseLog(exerciseId: "bench", group: .chest, sets: [
            SetLog(weightKg: 60, reps: 6, done: true),
            SetLog(weightKg: 100, reps: 1, done: false)      // planned, never lifted
        ])
        XCTAssertEqual(entry.topWeight, 60)
        XCTAssertEqual(entry.volumeKg, 360)
        XCTAssertEqual(entry.doneSets, 1)
    }

    func testSetSummaryReadsAsWeightByReps() {
        XCTAssertEqual(SetLog(weightKg: 60, reps: 6).summary, "60 kg × 6")
        XCTAssertEqual(SetLog(weightKg: nil, reps: 12).summary, "× 12")
    }
}

final class ProgramMigrationTests: XCTestCase {
    private func plan(_ items: [(String, Int, Int)]) -> WorkoutDayPlan {
        WorkoutDayPlan(rest: false, items: items.map { PlanExercise(exerciseId: $0.0, sets: $0.1, reps: $0.2) })
    }
    private let groups: [String: MuscleGroup] = [
        "bench": .chest, "fly": .chest, "ohp": .shoulders, "curl": .biceps, "row": .back
    ]
    private func group(_ id: String) -> MuscleGroup { groups[id] ?? .fullBody }

    func testNothingToMigrateReturnsNil() {
        XCTAssertNil(ProgramMigration.program(from: [:], group: group))
        XCTAssertNil(ProgramMigration.program(from: ["1": WorkoutDayPlan()], group: group))
    }

    func testBuildsSevenWeekdayBoundDays() {
        let p = ProgramMigration.program(from: ["1": plan([("bench", 4, 6)])], group: group)
        XCTAssertNotNil(p)
        XCTAssertEqual(p?.days.count, 7)
        XCTAssertEqual(p?.days.map(\.weekday), Array(0..<7))
        XCTAssertTrue(p!.isWeekdayBound)
        XCTAssertEqual(p?.days[1].name, "Monday")
    }

    func testGroupsADaysExercisesByMuscleKeepingOrder() {
        let p = ProgramMigration.program(
            from: ["1": plan([("bench", 4, 6), ("ohp", 3, 8), ("fly", 3, 12), ("curl", 3, 10)])],
            group: group)
        let monday = p!.days[1]
        XCTAssertEqual(monday.blocks.map(\.group), [.chest, .shoulders, .biceps])
        XCTAssertEqual(monday.blocks[0].items.map(\.exerciseId), ["bench", "fly"])
        XCTAssertEqual(monday.exerciseCount, 4)
    }

    func testSetsAndRepsSurviveTheMove() {
        let p = ProgramMigration.program(from: ["3": plan([("row", 5, 3)])], group: group)
        let item = p!.days[3].blocks.first?.items.first
        XCTAssertEqual(item?.sets, 5)
        XCTAssertEqual(item?.reps, 3)
    }

    func testEmptyWeekdaysBecomeRestDays() {
        let p = ProgramMigration.program(from: ["1": plan([("bench", 4, 6)])], group: group)
        XCTAssertTrue(p!.days[0].isRestDay)
        XCTAssertEqual(p!.days[0].name, "Rest")
        XCTAssertFalse(p!.days[1].isRestDay)
        XCTAssertEqual(p!.trainingDayCount, 1)
    }
}

final class TrainingStateDecodeTests: XCTestCase {
    /// A save written before programs existed must still open, and must not
    /// claim to have been migrated.
    func testLegacyTrainingStateDecodesWithNoPrograms() throws {
        let data = Data(#"{"customExercises":[],"weekPlan":{},"dayLog":{}}"#.utf8)
        let t = try JSONDecoder().decode(TrainingState.self, from: data)
        XCTAssertTrue(t.programs.isEmpty)
        XCTAssertNil(t.activeProgramId)
        XCTAssertFalse(t.migratedWeekPlan)
        XCTAssertNil(t.activeProgram)
    }

    func testLegacyDayLogDecodesWithoutTheSessionFields() throws {
        let data = Data(#"{"done":true,"items":[{"exerciseId":"x","sets":3,"reps":10}]}"#.utf8)
        let log = try JSONDecoder().decode(WorkoutDayLog.self, from: data)
        XCTAssertTrue(log.done)
        XCTAssertNil(log.entries)
        XCTAssertFalse(log.restOverride)
        XCTAssertFalse(log.hasSession)
        XCTAssertEqual(log.loggedItems?.count, 1)
    }

    func testActiveProgramResolvesById() {
        var t = TrainingState()
        let p = WorkoutProgram(name: "Cut — PPL")
        t.programs = [WorkoutProgram(name: "Other"), p]
        t.activeProgramId = p.id
        XCTAssertEqual(t.activeProgram?.name, "Cut — PPL")
    }

    /// History exists the moment a set is ticked, before you slide to finish.
    func testHasSessionNeedsACompletedSet() {
        var log = WorkoutDayLog()
        log.entries = [ExerciseLog(exerciseId: "a", group: .chest, sets: [SetLog(reps: 10, done: false)])]
        XCTAssertFalse(log.hasSession)
        log.entries?[0].sets[0].done = true
        XCTAssertTrue(log.hasSession)
    }

    func testSkippingClearsAnyPartialSession() {
        var log = WorkoutDayLog()
        log.entries = [ExerciseLog(exerciseId: "a", group: .chest, sets: [SetLog(reps: 10, done: true)])]
        log.skip()
        XCTAssertNil(log.entries)
        XCTAssertEqual(log.state, .skipped)
    }

    func testProgramExerciseDecodesWithoutRestOrNote() throws {
        let data = Data(#"{"exerciseId":"x","sets":4,"reps":6}"#.utf8)
        let e = try JSONDecoder().decode(ProgramExercise.self, from: data)
        XCTAssertEqual(e.restSec, 90)
        XCTAssertNil(e.note)
        XCTAssertFalse(e.id.isEmpty)
    }
}

@MainActor
final class ProgramHelperTests: XCTestCase {
    func testCopyNameNeverCollides() {
        XCTAssertEqual(AppState.copyName("Push A", taken: []), "Push A copy")
        XCTAssertEqual(AppState.copyName("Push A", taken: ["Push A copy"]), "Push A copy 2")
        XCTAssertEqual(AppState.copyName("Push A", taken: ["Push A copy", "Push A copy 2"]), "Push A copy 3")
    }

    /// A duplicated day must share nothing with its original, or editing one
    /// edits both.
    func testFreshIdsRewritesEveryIdButKeepsTheContent() {
        let day = ProgramDay(name: "Push A", weekday: 1, blocks: [
            ProgramMuscleBlock(group: .chest, items: [
                ProgramExercise(exerciseId: "bench", sets: 4, reps: 6, restSec: 120)
            ])
        ])
        let copy = AppState.freshIds(day)
        XCTAssertNotEqual(copy.id, day.id)
        XCTAssertNotEqual(copy.blocks[0].id, day.blocks[0].id)
        XCTAssertNotEqual(copy.blocks[0].items[0].id, day.blocks[0].items[0].id)
        XCTAssertEqual(copy.blocks[0].items[0].exerciseId, "bench")
        XCTAssertEqual(copy.blocks[0].items[0].sets, 4)
        XCTAssertEqual(copy.blocks[0].items[0].restSec, 120)
        XCTAssertEqual(copy.name, "Push A")
    }

    /// The +1 on a downward move is the whole reason this helper exists — drive
    /// it through a real `move(fromOffsets:toOffset:)` so the rule is proven,
    /// not just restated.
    func testMoveOffsetActuallyMovesTheRow() {
        func moved(_ items: [String], index: Int, delta: Int) -> [String] {
            var a = items
            guard let to = AppState.moveOffset(from: index, delta: delta, count: a.count) else { return a }
            a.move(fromOffsets: IndexSet(integer: index), toOffset: to)
            return a
        }
        let base = ["A", "B", "C", "D"]
        XCTAssertEqual(moved(base, index: 0, delta: 1), ["B", "A", "C", "D"])
        XCTAssertEqual(moved(base, index: 2, delta: -1), ["A", "C", "B", "D"])
        XCTAssertEqual(moved(base, index: 3, delta: 1), base, "last row can't move down")
        XCTAssertEqual(moved(base, index: 0, delta: -1), base, "first row can't move up")
        XCTAssertNil(AppState.moveOffset(from: 1, delta: 0, count: 4))
        XCTAssertNil(AppState.moveOffset(from: 9, delta: -1, count: 4))
    }

    func testDaysBetweenIsSignedAndZeroOnTheSameDay() {
        XCTAssertEqual(AppState.daysBetween("2026-08-24", and: "2026-08-24"), 0)
        XCTAssertEqual(AppState.daysBetween("2026-08-24", and: "2026-08-27"), 3)
        XCTAssertEqual(AppState.daysBetween("2026-08-27", and: "2026-08-24"), -3)
        XCTAssertEqual(AppState.daysBetween("2026-02-26", and: "2026-03-02"), 4)
    }

    func testNilIfBlankTrimsAndDropsEmpty() {
        XCTAssertNil("   ".nilIfBlank)
        XCTAssertNil("".nilIfBlank)
        XCTAssertEqual("  Cut  ".nilIfBlank, "Cut")
    }
}
