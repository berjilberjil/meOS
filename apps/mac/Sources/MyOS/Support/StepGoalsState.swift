import Foundation

// The step goals, the streak, and the moment one of them is crossed.
//
// Kept out of AppState.swift, which is already the biggest file in the app.
// Everything here reads `fitness` and `fitnessProfile` and writes back through
// the same `updateFitness` / `push` path as any other fitness edit.

extension AppState {

    // MARK: - Goals

    var stepGoals: StepGoals {
        StepGoals(daily: fitnessProfile.stepsTarget, stretch: fitnessProfile.stepsStretch)
    }

    /// Set either goal. Passing nil restores that goal's default.
    ///
    /// The two are written together because they constrain each other: raising
    /// the mandatory goal above the stretch has to move the stretch with it, or
    /// the profile holds a pair that `StepGoals` will silently correct on every
    /// read and the field would spring back while being typed into.
    func setStepGoals(daily: Int?, stretch: Int?) {
        let resolved = StepGoals(daily: daily, stretch: stretch)
        updateFitnessProfile {
            $0.stepsTarget = resolved.daily
            $0.stepsStretch = resolved.stretch
        }
    }

    func steps(on date: String) -> Int { max(0, fitness[date]?.steps ?? 0) }

    // MARK: - Streak

    /// Days in a row ending today where the mandatory goal was met. No freeze —
    /// one day under the line ends it. Today is pending until midnight.
    var stepStreak: Int {
        StepStreak.count(fitness: fitness, goals: stepGoals, today: todayKey)
    }

    func stepDay(_ date: String) -> StepDay {
        StepStreak.day(date, fitness: fitness, goals: stepGoals, today: todayKey)
    }

    /// The streak as it stood at the end of a given day, so a celebration can
    /// say "day 12" on the day it was earned rather than counting from now.
    func stepStreak(endingOn date: String) -> Int {
        StepStreak.count(fitness: fitness, goals: stepGoals, today: date)
    }

    // MARK: - Crossing a goal

    /// Note any goals `date` has reached and hand back the highest one that had
    /// not been celebrated yet.
    ///
    /// Marking happens for every day, celebrating only for today: typing
    /// Saturday's steps in on Monday should not throw a party on Monday, but it
    /// must still be recorded so it never throws one later either.
    ///
    /// The mark is written *before* anything is shown, so a second call — the
    /// pedometer re-reporting the same day, the other device pulling it down —
    /// finds the goal already hailed and stays quiet.
    @discardableResult
    func hailStepGoals(on date: String) -> StepCelebration? {
        let goals = stepGoals
        let count = steps(on: date)
        let already = Set(fitness[date]?.hailed ?? [])
        let fresh = goals.fresh(steps: count, alreadyHailed: fitness[date]?.hailed)
        guard !fresh.isEmpty else { return nil }

        updateFitness(date) { $0.hailed = Array(already.union(fresh)).sorted() }

        guard date == todayKey, let level = fresh.max() else { return nil }
        return StepCelebration(level: level,
                               steps: count,
                               target: goals.target(level),
                               next: goals.next(after: level),
                               streak: stepStreak(endingOn: date),
                               quote: StepQuotes.line(day: date, level: level),
                               day: date)
    }

    /// Note the goals, and if one was just crossed, make a noise about it.
    ///
    /// The three things fire together on purpose: the card is what you look at,
    /// the notification is what reaches you when the app is not open — which is
    /// most of the time, since the steps happen while walking — and the sound is
    /// what makes it feel like something happened rather than a number changing.
    func celebrateStepsIfCrossed(on date: String) {
        guard let celebration = hailStepGoals(on: date) else { return }
        stepCelebration = celebration
        SoundPlayer.celebrate()
        Haptics.success()
        StepNotify.goalHit(celebration)
    }
}
