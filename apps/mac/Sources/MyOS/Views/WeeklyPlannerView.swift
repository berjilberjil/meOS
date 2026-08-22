import SwiftUI

/// The weekly planner — set a 7-day meal + workout plan the Today checklist runs
/// off. A day selector, a Meals/Workouts toggle, roomy rows, and copy-a-day to
/// other days. Full content width (not a cramped sheet).
struct WeeklyPlannerView: View {
    @EnvironmentObject var state: AppState
    @State private var weekday: String = String(Calendar(identifier: .gregorian).component(.weekday, from: Date()) - 1)
    enum PlanMode: String, Hashable { case meals, workouts }
    @State private var mode: PlanMode = .meals
    @State private var addingMeal: MealKey?
    @State private var pickingExercise = false
    @State private var newFood = false
    @State private var newExercise = false
    @State private var showClearMeals = false
    #if os(macOS)
    @State private var askGenerate = false
    @State private var askApply = false
    @State private var pendingPlan: GeneratedPlan?
    #endif

    private let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    /// One letter so all 7 days fit a phone-width capsule.
    private let dayLetters = ["S", "M", "T", "W", "T", "F", "S"]
    private var workoutPlan: WorkoutDayPlan { state.workoutPlan(weekday) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            #if os(macOS)
            generateRow.knRise(0)
            #endif

            VStack(alignment: .leading, spacing: 10) {
                Segmented(
                    options: (0..<7).map { (String($0), dayLetters[$0]) },
                    selection: $weekday,
                    fillsWidth: true
                )
                HStack(spacing: 8) {
                    if mode == .meals {
                        Button { showClearMeals = true } label: {
                            Label("Clear meals", systemImage: "trash")
                        }
                        .buttonStyle(KGhostButtonStyle(color: Palette.faint))
                        .disabled(weekMealsEmpty)
                        .holdToDelete(isPresented: $showClearMeals,
                                      title: "Clear the whole meal plan?",
                                      message: "Removes every planned food Mon–Sun. Your food library and today's log stay.",
                                      confirmLabel: "Hold to clear") {
                            state.clearMealPlan()
                        }
                    }
                    Spacer(minLength: 0)
                    CopyDayMenu(weekday: weekday, dayNames: dayNames, disabled: copyDisabled) { targets in
                        if mode == .meals { state.copyMealPlanDay(from: weekday, to: targets) }
                        else { state.copyWorkoutDay(from: weekday, to: targets) }
                    }
                }
            }
            .knRise(1)

            Segmented(options: [(PlanMode.meals, "Meals"), (PlanMode.workouts, "Workouts")], selection: $mode)
                .knRise(2)

            if mode == .meals { mealsColumn.knRise(3) } else { workoutColumn.knRise(3) }
        }
        .onAppear { if !WeekdayKeys.all.contains(weekday) { weekday = state.todayWeekday } }
        #if os(macOS)
        .alert("Generate a new week?", isPresented: $askGenerate) {
            Button("Cancel", role: .cancel) {}
            Button("Generate draft") { Task { await runGenerate() } }
        } message: {
            Text("This only builds a draft. Your current meals and workouts stay until you confirm the next step.")
        }
        .confirmationDialog("Replace your current plan?", isPresented: $askApply, titleVisibility: .visible) {
            Button("Keep current plan", role: .cancel) { pendingPlan = nil }
            Button("Replace meals & workouts", role: .destructive) {
                if let plan = pendingPlan { state.confirmGeneratedPlan(plan) }
                pendingPlan = nil
            }
        } message: {
            Text(pendingPlan?.summary ?? "This overwrites every planned meal and workout for the week.")
        }
        #endif
        .sheet(item: $addingMeal) { meal in
            FoodPickerSheet(meal: meal,
                            add: { f, q in state.addFoodToPlan(weekday: weekday, meal: meal, foodId: f.id, quantity: q) },
                            newCustom: { newFood = true })
        }
        .sheet(isPresented: $newFood) { FoodEditor(food: nil) }
        .sheet(isPresented: $pickingExercise) {
            ExercisePickerSheet(add: { ex in state.addPlanExercise(weekday: weekday, exerciseId: ex.id) },
                                newCustom: { newExercise = true })
        }
        .sheet(isPresented: $newExercise) { ExerciseEditor(exercise: nil) }
    }

    private var copyDisabled: Bool {
        mode == .meals
            ? MealKey.allCases.allSatisfy { state.planItems(weekday, $0).isEmpty }
            : workoutPlan.items.isEmpty
    }

    private var weekMealsEmpty: Bool {
        WeekdayKeys.all.allSatisfy { wd in
            MealKey.allCases.allSatisfy { state.planItems(wd, $0).isEmpty }
        }
    }

    // MARK: - Generate my week (AI) — Mac only. iPhone must not draft over a real plan.

    #if os(macOS)
    private var generateRow: some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Text("AI WEEK PLAN")
                    .font(.system(size: 11, weight: .heavy, design: .rounded)).tracking(0.7)
                    .foregroundStyle(Palette.muted)
                Text("Build my meals + workouts around my goal.")
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.text)
                HStack(spacing: 8) {
                    let goal = state.fitnessProfile.goal.label.uppercased()
                    let kcal = state.calorieTargets()?.goalCalories
                    Text(kcal == nil ? goal : "\(goal) · \(kcal!) KCAL")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundStyle(Palette.faint)
                    Spacer()
                    Button { askGenerate = true } label: {
                        HStack(spacing: 6) {
                            if state.planBusy { ProgressView().controlSize(.small).tint(.white) }
                            Text(state.planBusy ? "Building…" : "Generate plan")
                        }
                    }
                    .buttonStyle(KPrimaryButtonStyle())
                    .disabled(state.planBusy)
                }
                if let s = state.planSummary {
                    Label(s, systemImage: "checkmark.circle.fill").font(.system(size: 12)).foregroundStyle(Palette.green)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let e = state.planError {
                    Label(e, systemImage: "exclamationmark.triangle.fill").font(.system(size: 12)).foregroundStyle(Palette.amber)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func runGenerate() async {
        if let plan = await state.generateWeeklyPlan() {
            pendingPlan = plan
            askApply = true
        }
    }
    #endif

    // MARK: - Meals column

    private var mealsColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(MealKey.allCases) { meal in
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(meal.label, systemImage: meal.icon)
                            .font(.system(size: 14, weight: .heavy, design: .rounded)).foregroundStyle(Palette.text)
                        let items = state.planItems(weekday, meal)
                        if items.isEmpty {
                            Text("No foods planned.").font(.system(size: 12)).foregroundStyle(Palette.faint)
                        }
                        ForEach(items) { item in
                            PlanMealRow(food: state.food(item.foodId)) {
                                state.removePlanItem(weekday: weekday, meal: meal, itemId: item.id)
                            }
                        }
                        Button { addingMeal = meal } label: { Label("Add food", systemImage: "plus.circle.fill") }
                            .buttonStyle(KGhostButtonStyle(color: Palette.brand))
                    }
                }
            }
        }
    }

    // MARK: - Workout column

    private var workoutColumn: some View {
        let isRest = workoutPlan.isRestDay
        return Card {
            VStack(alignment: .leading, spacing: 12) {
                // One statement about the day, not two. It used to print
                // "Rest day" beside a Training toggle beside a list of
                // exercises, and you had to work out which one was true.
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        SectionTitle(text: fullDayName)
                        Text(isRest ? "Rest day" : muscleSummary)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(isRest ? Palette.blue : Palette.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Toggle("Rest day", isOn: Binding(
                        get: { isRest },
                        set: { state.setRestDay(weekday, $0) }
                    ))
                    .toggleStyle(.switch).tint(Palette.brand)
                    .labelsHidden()
                    .accessibilityLabel(isRest ? "Rest day on" : "Mark as rest day")
                }
                if isRest {
                    HStack(spacing: 8) {
                        Image(systemName: "moon.zzz.fill").foregroundStyle(Palette.blue)
                        Text("No workout scheduled.").font(.system(size: 13)).foregroundStyle(Palette.muted)
                    }
                    .padding(.vertical, 6)
                } else {
                    if workoutPlan.items.isEmpty {
                        Text("No exercises yet. Add some to build this day.")
                            .font(.system(size: 13)).foregroundStyle(Palette.faint)
                    }
                    ForEach(workoutPlan.items) { item in
                        let ex = state.exercise(item.exerciseId)
                        ExercisePlanRow(
                            name: ex?.name ?? "Unknown",
                            subtitle: [ex?.category.label, ex?.primary].compactMap { $0 }
                                .filter { !$0.isEmpty }.joined(separator: " · "),
                            category: ex?.category ?? .core,
                            sets: item.sets, reps: item.reps,
                            onSets: { state.setPlanSets(weekday: weekday, itemId: item.id, sets: $0) },
                            onReps: { state.setPlanReps(weekday: weekday, itemId: item.id, reps: $0) },
                            remove: { state.removePlanExercise(weekday: weekday, itemId: item.id) })
                    }
                    Button { pickingExercise = true } label: { Label("Add exercise", systemImage: "plus.circle.fill") }
                        .buttonStyle(KGhostButtonStyle(color: Palette.brand))
                }
            }
        }
    }

    /// "Chest + Shoulders + Triceps" — what this day actually trains, from the
    /// exercises on it. Empty list reads as a day still being built.
    private var muscleSummary: String {
        let muscles = workoutPlan.items
            .compactMap { state.exercise($0.exerciseId)?.category.label }
        var seen: [String] = []
        for m in muscles where !seen.contains(m) { seen.append(m) }
        if seen.isEmpty { return "Nothing planned yet" }
        return seen.prefix(3).joined(separator: " + ")
    }

    private var fullDayName: String {
        ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][Int(weekday) ?? 0]
    }
}

// MARK: - Rows (own structs so each carries its own hold-to-delete popover)

private struct PlanMealRow: View {
    let food: Food?
    let remove: () -> Void
    @State private var showDelete = false

    var body: some View {
        HStack(spacing: 10) {
            FoodIcon(category: food?.category ?? .other, name: food?.name ?? "", size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(food?.name ?? "Unknown").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.text).lineLimit(1)
                Text("\(food?.servingLabel ?? "") · \(Int(food?.perServing.calories ?? 0)) kcal")
                    .font(.system(size: 11)).foregroundStyle(Palette.faint).lineLimit(1)
            }
            Spacer()
            Button { showDelete = true } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                .buttonStyle(KIconButtonStyle(size: 22))
                .holdToDelete(isPresented: $showDelete, title: "Remove \(food?.name ?? "food")?",
                              message: "Removes it from this day's plan.", confirmLabel: "Hold to remove") { remove() }
        }
    }
}

