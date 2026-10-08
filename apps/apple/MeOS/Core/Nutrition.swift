import Foundation

// Calorie + macro math, mirrored from fitOS (Mifflin-St Jeor). BMR from weight/
// height/age/sex, TDEE = BMR × activity, then the goal offset gives cut/maintain/
// bulk. Macros: protein by bodyweight, fat 25% of calories, carbs fill the rest.

/// The computed calorie + macro picture for a given goal.
struct CalorieTargets: Hashable {
    let bmr: Int
    let tdee: Int
    let maintain: Int
    let cut: Int
    let bulk: Int
    /// Calories for the currently-selected goal (maintain/cut/bulk).
    let goalCalories: Int
    let proteinG: Int
    let fatG: Int
    let carbG: Int
}

enum Nutrition {
    /// Mifflin-St Jeor BMR (kcal/day).
    static func bmr(sex: Sex, weightKg: Double, heightCm: Double, age: Int) -> Double {
        let base = 10 * weightKg + 6.25 * heightCm - 5 * Double(age)
        return base + (sex == .male ? 5 : -161)
    }

    /// Protein target grams for a goal — a touch higher on a cut to protect muscle.
    static func proteinG(weightKg: Double, goal: FitnessGoal) -> Double {
        let perKg: Double = goal == .cut ? 2.0 : 1.8
        return perKg * weightKg
    }

    /// Full picture from body stats + goal + activity.
    static func targets(sex: Sex, weightKg: Double, heightCm: Double, age: Int,
                        activity: ActivityLevel, goal: FitnessGoal) -> CalorieTargets {
        let bmrV: Double = bmr(sex: sex, weightKg: weightKg, heightCm: heightCm, age: age)
        let tdee: Double = bmrV * activity.multiplier
        // The same 1000 kcal floor as the selected goal. Without it the Calories
        // card could offer a "Cut" number below — or under a nonsense profile,
        // beneath zero — the floor the app enforces the moment you pick it, so
        // the figure you chose from was never the figure you got.
        let cut: Double = max(1000, tdee + FitnessGoal.cut.calorieOffset)
        let bulk: Double = max(1000, tdee + FitnessGoal.bulk.calorieOffset)
        let goalCals: Double = max(1000, tdee + goal.calorieOffset)

        let protein: Double = proteinG(weightKg: weightKg, goal: goal)
        let fat: Double = goalCals * 0.25 / 9                       // 25% of calories from fat
        let carbsRaw: Double = (goalCals - protein * 4 - fat * 9) / 4
        let carbs: Double = max(0, carbsRaw)

        // Clamped like `Fmt.trimKg` and `KLabeledNumberField.format` — this was
        // the one place in that family still converting an unbounded Double.
        // `Int(_:)` traps outside Int64, and the input is a height or weight the
        // user typed: twenty digits gives a BMR of 6.25e20. Nothing crashes on
        // the profile screen itself, so the value is committed, pushed and
        // synced — and then Today and Fitness trap on every render, on both
        // devices, for good.
        func r(_ x: Double) -> Int {
            guard x.isFinite else { return 0 }
            return Int(min(max(x.rounded(), -1_000_000), 10_000_000))
        }
        return CalorieTargets(
            bmr: r(bmrV), tdee: r(tdee),
            maintain: r(tdee), cut: r(cut), bulk: r(bulk),
            goalCalories: r(goalCals),
            proteinG: r(protein), fatG: r(fat), carbG: r(carbs))
    }
}
