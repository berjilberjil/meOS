import SwiftUI

/// The weekly meal plan the Today checklist runs off — a day selector, roomy
/// rows, and copy-a-day to other days. Training used to share this screen; it
/// lives in Fitness → Train now, because a program is a hierarchy (days →
/// muscles → exercises) and a weekday grid could never hold one.
struct WeeklyPlannerView: View {
    @EnvironmentObject var state: AppState
    @State private var weekday: String = String(Calendar(identifier: .gregorian).component(.weekday, from: Date()) - 1)
    @State private var addingMeal: MealKey?
    @State private var newFood = false
    @State private var showClearMeals = false
    #if os(macOS)
    @State private var askGenerate = false
    @State private var askApply = false
    @State private var pendingPlan: GeneratedPlan?
    #endif

    private let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    /// One letter so all 7 days fit a phone-width capsule.
    private let dayLetters = ["S", "M", "T", "W", "T", "F", "S"]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            #if os(macOS)
            generateRow.knRise(0)
            #endif

            VStack(alignment: .leading, spacing: 10) {
                Picker("", selection: $weekday) { ForEach((0..<7).map { (String($0), dayLetters[$0]) }, id: \.0) { opt in Text(opt.1).tag(opt.0) } }.pickerStyle(.segmented).labelsHidden()
                HStack(spacing: 8) {
                    Button { showClearMeals = true } label: {
                        Label("Clear meals", systemImage: "trash")
                    }
                    .buttonStyle(.borderless).tint(Palette.faint)
                    .disabled(weekMealsEmpty)
                    .holdToDelete(isPresented: $showClearMeals,
                                  title: "Clear the whole meal plan?",
                                  message: "Removes every planned food Mon–Sun. Your food library and today's log stay.",
                                  confirmLabel: "Hold to clear") {
                        state.clearMealPlan()
                    }
                    Spacer(minLength: 0)
                    CopyDayMenu(weekday: weekday, dayNames: dayNames, disabled: copyDisabled) { targets in
                        state.copyMealPlanDay(from: weekday, to: targets)
                    }
                }
            }
            .knRise(1)

            mealsColumn.knRise(2)
        }
        .onAppear { if !WeekdayKeys.all.contains(weekday) { weekday = state.todayWeekday } }
        #if os(macOS)
        .alert("Generate a new week?", isPresented: $askGenerate) {
            Button("Cancel", role: .cancel) {}
            Button("Generate draft") { Task { await runGenerate() } }
        } message: {
            Text("This only builds a draft. Your current meals and program stay until you confirm the next step.")
        }
        .confirmationDialog("Replace your current plan?", isPresented: $askApply, titleVisibility: .visible) {
            Button("Keep current plan", role: .cancel) { pendingPlan = nil }
            Button("Replace meals & rebuild the program", role: .destructive) {
                if let plan = pendingPlan { state.confirmGeneratedPlan(plan) }
                pendingPlan = nil
            }
        } message: {
            Text(pendingPlan?.summary ?? "This overwrites every planned meal and rewrites the active program's days. Logged workouts stay.")
        }
        #endif
        .sheet(item: $addingMeal) { meal in
            FoodPickerSheet(meal: meal,
                            add: { f, q in state.addFoodToPlan(weekday: weekday, meal: meal, foodId: f.id, quantity: q) },
                            newCustom: { newFood = true })
        }
        .sheet(isPresented: $newFood) { FoodEditor(food: nil) }
    }

    private var copyDisabled: Bool {
        MealKey.allCases.allSatisfy { state.planItems(weekday, $0).isEmpty }
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
                    .font(.caption2.weight(.heavy)).tracking(0.7)
                    .foregroundStyle(Palette.muted)
                Text("Build my meals + training week around my goal.")
                    .font(.callout.weight(.semibold)).foregroundStyle(Palette.text)
                HStack(spacing: 8) {
                    let goal = state.fitnessProfile.goal.label.uppercased()
                    let kcal = state.calorieTargets()?.goalCalories
                    Text(kcal == nil ? goal : "\(goal) · \(kcal!) KCAL")
                        .font(.caption2.weight(.heavy))
                        .foregroundStyle(Palette.faint)
                    Spacer()
                    Button { askGenerate = true } label: {
                        HStack(spacing: 6) {
                            if state.planBusy { ProgressView().controlSize(.small).tint(.white) }
                            Text(state.planBusy ? "Building…" : "Generate plan")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(state.planBusy)
                }
                if let s = state.planSummary {
                    Label(s, systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(Palette.green)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let e = state.planError {
                    Label(e, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(Palette.amber)
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
                            .font(.footnote.weight(.heavy)).foregroundStyle(Palette.text)
                        let items = state.planItems(weekday, meal)
                        if items.isEmpty {
                            Text("No foods planned.").font(.caption).foregroundStyle(Palette.faint)
                        }
                        ForEach(items) { item in
                            PlanMealRow(food: state.food(item.foodId)) {
                                state.removePlanItem(weekday: weekday, meal: meal, itemId: item.id)
                            }
                        }
                        Button { addingMeal = meal } label: { Label("Add food", systemImage: "plus.circle.fill") }
                            .buttonStyle(.borderless).tint(Palette.brand)
                    }
                }
            }
        }
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
                Text(food?.name ?? "Unknown").font(.footnote.weight(.semibold)).foregroundStyle(Palette.text).lineLimit(1)
                Text("\(food?.servingLabel ?? "") · \(Int(food?.perServing.calories ?? 0)) kcal")
                    .font(.caption2).foregroundStyle(Palette.faint).lineLimit(1)
            }
            Spacer()
            Button { showDelete = true } label: { Image(systemName: "xmark").font(.caption2.weight(.bold)) }
                .buttonStyle(.borderless)
                .holdToDelete(isPresented: $showDelete, title: "Remove \(food?.name ?? "food")?",
                              message: "Removes it from this day's plan.", confirmLabel: "Hold to remove") { remove() }
        }
    }
}

