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
                HStack(spacing: 10) {
                    SectionTitle(text: fullDayName)
                    Spacer()
                    Text(isRest ? "Rest day" : "Training")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isRest ? Palette.blue : Palette.muted)
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
                        Text("Rest day — recover.").font(.system(size: 13)).foregroundStyle(Palette.muted)
                    }
                    .padding(.vertical, 6)
                } else {
                    if workoutPlan.items.isEmpty {
                        Text("No exercises yet. Add some to build this day.")
                            .font(.system(size: 13)).foregroundStyle(Palette.faint)
                    }
                    ForEach(workoutPlan.items) { item in
                        PlanExerciseRow(
                            item: item,
                            exercise: state.exercise(item.exerciseId),
                            setsDec: { state.setPlanSets(weekday: weekday, itemId: item.id, sets: item.sets - 1) },
                            setsInc: { state.setPlanSets(weekday: weekday, itemId: item.id, sets: item.sets + 1) },
                            repsDec: { state.setPlanReps(weekday: weekday, itemId: item.id, reps: item.reps - 1) },
                            repsInc: { state.setPlanReps(weekday: weekday, itemId: item.id, reps: item.reps + 1) },
                            remove: { state.removePlanExercise(weekday: weekday, itemId: item.id) })
                    }
                    Button { pickingExercise = true } label: { Label("Add exercise", systemImage: "plus.circle.fill") }
                        .buttonStyle(KGhostButtonStyle(color: Palette.brand))
                }
            }
        }
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

private struct PlanExerciseRow: View {
    let item: PlanExercise
    let exercise: Exercise?
    let setsDec: () -> Void
    let setsInc: () -> Void
    let repsDec: () -> Void
    let repsInc: () -> Void
    let remove: () -> Void
    @State private var showDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                ExerciseIcon(category: exercise?.category ?? .core, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise?.name ?? "Unknown")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(exercise?.category.label ?? "") · \(exercise?.primary ?? "")")
                        .font(.system(size: 11)).foregroundStyle(Palette.faint)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Button { showDelete = true } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                    .buttonStyle(KIconButtonStyle(size: 22))
                    .holdToDelete(isPresented: $showDelete, title: "Remove \(exercise?.name ?? "exercise")?",
                                  message: "Removes it from this day's plan.", confirmLabel: "Hold to remove") { remove() }
            }
            HStack(spacing: 10) {
                stepper(item.sets, "sets", dec: setsDec, inc: setsInc)
                Text("×").font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.faint)
                stepper(item.reps, "reps", dec: repsDec, inc: repsInc)
                Spacer(minLength: 0)
            }
            .padding(.leading, 44)
        }
        .padding(.vertical, 4)
    }

    private func stepper(_ value: Int, _ label: String, dec: @escaping () -> Void, inc: @escaping () -> Void) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                miniBtn("minus", dec)
                Text("\(value)").font(.system(size: 13, weight: .heavy, design: .rounded)).monospacedDigit()
                    .foregroundStyle(Palette.text).frame(minWidth: 20)
                miniBtn("plus", inc)
            }
            Text(label.uppercased()).font(.system(size: 7, weight: .heavy)).tracking(0.5).foregroundStyle(Palette.faint)
        }
    }
    private func miniBtn(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 9, weight: .bold)).foregroundStyle(Palette.text)
                .frame(width: 22, height: 20)
                .background(Palette.surface2, in: RoundedRectangle(cornerRadius: Radius.xs, style: .continuous))
        }
        .buttonStyle(KPressStyle(scale: 0.9))
    }
}
