import SwiftUI

/// Calories + macros first — intake vs target, each macro in its own colour.
struct DayMacroHero: View {
    /// The day being shown. Today unless the Today page has been swiped.
    var day: String? = nil
    @EnvironmentObject var state: AppState

    var body: some View {
        let date = day ?? state.todayKey
        let eaten = state.consumed(date)
        let t = state.calorieTargets()
        let goal = t?.goalCalories ?? Int(state.fitnessProfile.calorieTargetKcal ?? 0)
        let remain = goal > 0 ? max(0, goal - Int(eaten.calories.rounded())) : 0
        let frac = goal > 0 ? min(1, eaten.calories / Double(goal)) : 0
        return Card(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                Text("INTAKE")
                    .font(.system(size: 12, weight: .heavy, design: .rounded)).tracking(0.8)
                    .foregroundStyle(Palette.muted)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(Int(eaten.calories.rounded()))")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Palette.amber)
                    Text(goal > 0 ? "/ \(goal) kcal" : "kcal")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Palette.muted)
                    Spacer()
                    if goal > 0 {
                        Text("\(remain) left")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Palette.faint)
                    }
                }
                MeterBar(fraction: frac, tint: Palette.amber, height: 10)
                HStack(spacing: 8) {
                    macro("Protein", Int(eaten.protein.rounded()), t?.proteinG, Palette.green)
                    macro("Carbs", Int(eaten.carbs.rounded()), t?.carbG, Palette.blue)
                    macro("Fibre", Int(eaten.fiber.rounded()), 30, Palette.purple)
                    macro("Fat", Int(eaten.fats.rounded()), t?.fatG, Palette.red)
                }
            }
        }
    }

    private func macro(_ label: String, _ have: Int, _ target: Int?, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .heavy, design: .rounded)).tracking(0.4)
                .foregroundStyle(tint)
            if let target, target > 0 {
                Text("\(have)")
                    .font(.system(size: 18, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(Palette.text)
                Text("/ \(target)g").font(.system(size: 11)).foregroundStyle(Palette.faint)
                MeterBar(fraction: min(1, Double(have) / Double(target)), tint: tint, height: 5)
            } else {
                Text("\(have)g")
                    .font(.system(size: 18, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(Palette.text)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The Fitness "Today" surface — a plan-driven checklist. Each meal and the day's
/// workout is a card in one of three states: unconfirmed (planned items ghosted,
/// with slide-to-log / edit / scan / skip), logged (actual items + macros,
/// checkmarked), or skipped (struck through, undoable). Weekly templates are never
/// touched here — only today's log.
struct FitnessTodayView: View {
    @EnvironmentObject var state: AppState
    @State private var editingMeal: MealKey?
    @State private var editingWorkout = false
    @State private var scanningMeal: MealKey?
    @State private var scanPayload: FoodScanPayload?

    private var date: String { state.todayKey }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DayMacroHero()
            ForEach(MealKey.allCases) { meal in
                MealChecklistCard(meal: meal,
                                  edit: { editingMeal = meal },
                                  scan: { scanningMeal = meal })
            }
            WorkoutChecklistCard(edit: { editingWorkout = true })
        }
        .sheet(item: $editingMeal) { meal in
            MealLogEditorSheet(date: date, meal: meal, initialItems: seed(meal))
        }
        .sheet(isPresented: $editingWorkout) {
            WorkoutDayEditorSheet(date: date, initialItems: state.workoutItemsForDay(date))
        }
        .sheet(item: $scanningMeal) { meal in
            FoodScanSheet { summary, foods in
                scanPayload = FoodScanPayload(summary: summary, foods: foods, defaultMeal: meal)
            }
        }
        .sheet(item: $scanPayload) { p in
            FoodScanReviewSheet(summary: p.summary, foods: p.foods, logDate: date, defaultMeal: p.defaultMeal)
        }
    }

    /// The editor seeds from the actual log if logged, else from today's plan.
    private func seed(_ meal: MealKey) -> [PlanItem] {
        state.mealEditorItems(date: date, meal: meal)
    }
}

// MARK: - A meal checklist card

struct MealChecklistCard: View {
    @EnvironmentObject var state: AppState
    let meal: MealKey
    let edit: () -> Void
    let scan: () -> Void

    private var date: String { state.todayKey }
    private var st: MealLog.MealState { state.mealState(date, meal) }
    private var planned: [PlanItem] { state.planItems(state.todayWeekday, meal) }
    private var logged: [PlanItem] { state.mealLog(date).items(meal) }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                header
                switch st {
                case .unconfirmed: unconfirmedBody
                case .logged:      loggedBody
                case .skipped:     skippedBody
                }
            }
        }
    }

    @ViewBuilder private var header: some View {
        HStack(spacing: 8) {
            Label(meal.label, systemImage: meal.icon)
                .font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.text)
            Spacer()
            switch st {
            case .logged:
                let m = macros(logged)
                Text("\(Int(m.calories)) kcal · \(Int(m.protein))g P")
                    .font(.system(size: 11, weight: .semibold)).monospacedDigit().foregroundStyle(Palette.muted)
                Image(systemName: "checkmark.circle.fill").font(.system(size: 15)).foregroundStyle(Palette.green)
            case .skipped:
                Image(systemName: "minus.circle.fill").font(.system(size: 15)).foregroundStyle(Palette.faint)
            case .unconfirmed:
                EmptyView()
            }
        }
    }

    @ViewBuilder private var unconfirmedBody: some View {
        if planned.isEmpty {
            Text("Nothing planned. Add, scan, or skip it.")
                .font(.system(size: 12)).foregroundStyle(Palette.faint)
        } else {
            ForEach(planned) { item in itemRow(item, ghost: true) }
            SlideToConfirm(label: "Slide to log", tint: Palette.green) {
                state.tickMeal(date: date, meal: meal)
            }
        }
        actionRow
    }

    @ViewBuilder private var loggedBody: some View {
        ForEach(logged) { item in itemRow(item, ghost: false) }
        HStack(spacing: 8) {
            Button(action: edit) { Label("Edit", systemImage: "pencil") }.buttonStyle(KGhostButtonStyle())
            Button(action: scan) { Label("Add / scan", systemImage: "camera.viewfinder") }.buttonStyle(KGhostButtonStyle())
            Spacer()
        }
    }

    @ViewBuilder private var skippedBody: some View {
        HStack {
            Text("Skipped").font(.system(size: 13, weight: .semibold)).strikethrough().foregroundStyle(Palette.faint)
            Spacer()
            Button { state.unskipMeal(date: date, meal: meal) } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                .buttonStyle(KGhostButtonStyle())
        }
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            Button(action: edit) { Label("Edit", systemImage: "pencil") }.buttonStyle(KGhostButtonStyle())
            Button(action: scan) { Label("Scan", systemImage: "camera.viewfinder") }.buttonStyle(KGhostButtonStyle())
            Spacer()
            Button { state.skipMeal(date: date, meal: meal) } label: { Label("Skip", systemImage: "xmark") }
                .buttonStyle(KGhostButtonStyle(color: Palette.faint))
        }
    }

    private func itemRow(_ item: PlanItem, ghost: Bool) -> some View {
        let f = state.food(item.foodId)
        let kcal = Int((f?.perServing.scaled(item.quantity).calories) ?? 0)
        return HStack(spacing: 10) {
            FoodIcon(category: f?.category ?? .other, name: f?.name ?? "", size: 28)
            Text(f?.name ?? "Unknown").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.text).lineLimit(1)
            Spacer()
            Text("\(Fmt.trimKg(item.quantity)) × · \(kcal) kcal")
                .font(.system(size: 11)).monospacedDigit().foregroundStyle(Palette.faint).lineLimit(1)
        }
        .opacity(ghost ? 0.55 : 1)
    }

    private func macros(_ items: [PlanItem]) -> Macros {
        items.reduce(Macros.zero) { $0 + (state.food($1.foodId)?.perServing.scaled($1.quantity) ?? .zero) }
    }
}

// MARK: - The workout checklist card

struct WorkoutChecklistCard: View {
    /// The day being shown. Today unless the Today page has been swiped.
    var day: String? = nil
    @EnvironmentObject var state: AppState
    let edit: () -> Void

    private var date: String { day ?? state.todayKey }
    /// The plan for **the day being shown**. This used to read
    /// `state.todayWeekday` while `items` read the paged date, so swiping to
    /// another day showed today's rest-day banner over that day's exercises.
    private var plan: WorkoutDayPlan { state.workoutPlan(AppState.weekdayKey(date)) }
    private var dayLog: WorkoutDayLog { state.workoutDayLog(date) }
    private var items: [PlanExercise] { state.workoutItemsForDay(date) }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                header
                if plan.isRestDay && dayLog.state == .unconfirmed {
                    HStack(spacing: 8) {
                        Image(systemName: "moon.zzz.fill").foregroundStyle(Palette.blue)
                        Text("Rest day — no workout scheduled.")
                            .font(.system(size: 13)).foregroundStyle(Palette.muted)
                    }
                } else {
                    switch dayLog.state {
                    case .unconfirmed: unconfirmedBody
                    case .done:        doneBody
                    case .skipped:     skippedBody
                    }
                }
            }
        }
    }

    @ViewBuilder private var header: some View {
        HStack(spacing: 8) {
            Label("Workout", systemImage: "figure.strengthtraining.traditional")
                .font(.system(size: 14, weight: .heavy, design: .rounded)).foregroundStyle(Palette.text)
            Spacer()
            switch dayLog.state {
            case .done:    Image(systemName: "checkmark.circle.fill").font(.system(size: 15)).foregroundStyle(Palette.green)
            case .skipped: Image(systemName: "minus.circle.fill").font(.system(size: 15)).foregroundStyle(Palette.faint)
            case .unconfirmed: EmptyView()
            }
        }
    }

    @ViewBuilder private var unconfirmedBody: some View {
        if items.isEmpty {
            Text("No workout planned. Add exercises or skip it.")
                .font(.system(size: 12)).foregroundStyle(Palette.faint)
        } else {
            ForEach(items) { pe in exerciseRow(pe, ghost: true) }
            SlideToConfirm(label: "Slide to log", tint: Palette.green) { state.tickWorkout(date: date) }
        }
        HStack(spacing: 8) {
            Button(action: edit) { Label("Edit", systemImage: "pencil") }.buttonStyle(KGhostButtonStyle())
            Spacer()
            Button { state.skipWorkout(date: date) } label: { Label("Skip", systemImage: "xmark") }
                .buttonStyle(KGhostButtonStyle(color: Palette.faint))
        }
    }

    @ViewBuilder private var doneBody: some View {
        ForEach(items) { pe in exerciseRow(pe, ghost: false) }
        HStack {
            Button(action: edit) { Label("Edit", systemImage: "pencil") }.buttonStyle(KGhostButtonStyle())
            Spacer()
        }
    }

    @ViewBuilder private var skippedBody: some View {
        HStack {
            Text("Skipped").font(.system(size: 13, weight: .semibold)).strikethrough().foregroundStyle(Palette.faint)
            Spacer()
            Button { state.unskipWorkout(date: date) } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                .buttonStyle(KGhostButtonStyle())
        }
    }

    private func exerciseRow(_ pe: PlanExercise, ghost: Bool) -> some View {
        let ex = state.exercise(pe.exerciseId)
        return HStack(spacing: 10) {
            ExerciseIcon(category: ex?.category ?? .core, size: 28)
            Text(ex?.name ?? "Exercise").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.text).lineLimit(1)
            Spacer()
            Text("\(pe.sets) × \(pe.reps)").font(.system(size: 12, weight: .semibold)).monospacedDigit().foregroundStyle(Palette.muted)
        }
        .opacity(ghost ? 0.55 : 1)
    }
}

// MARK: - Edit a meal's logged items

struct MealLogEditorSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let date: String
    let meal: MealKey
    @State private var draft: [PlanItem]
    @State private var adding = false
    @State private var newFood = false

    init(date: String, meal: MealKey, initialItems: [PlanItem]) {
        self.date = date; self.meal = meal
        _draft = State(initialValue: initialItems.map { PlanItem(foodId: $0.foodId, quantity: $0.quantity) })
    }

    private var mealMacros: Macros {
        draft.reduce(into: Macros()) { acc, item in
            guard let f = state.food(item.foodId) else { return }
            acc = acc + f.perServing.scaled(item.quantity)
        }
    }

    private var mealTint: Color {
        switch meal {
        case .breakfast: return Palette.amber
        case .lunch:     return Palette.gold
        case .dinner:    return Palette.purple
        case .snacks:    return Palette.coral
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 10) {
                    if draft.isEmpty {
                        emptyState
                    } else {
                        ForEach($draft) { $item in
                            DraftFoodRow(item: $item, food: state.food(item.foodId)) {
                                draft.removeAll { $0.id == item.id }
                            }
                        }
                    }
                    Button { adding = true } label: {
                        Label("Add food", systemImage: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(KSecondaryButtonStyle(fullWidth: true))
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 20)
            }
            footer
        }
        #if os(macOS)
        .frame(width: 480)
        .frame(minHeight: 560)
        .background(Palette.elevated)
        #else
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.bg)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Palette.bg)
        #endif
        .sheet(isPresented: $adding) {
            FoodPickerSheet(meal: meal, add: { f, q in draft.append(PlanItem(foodId: f.id, quantity: q)) },
                            newCustom: { newFood = true })
        }
        .sheet(isPresented: $newFood) { FoodEditor(food: nil) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(mealTint.opacity(0.18))
                    Image(systemName: meal.icon).font(.system(size: 18, weight: .semibold)).foregroundStyle(mealTint)
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(meal.label)
                        .font(.system(size: 24, weight: .semibold)).foregroundStyle(Palette.text)
                    Text(draft.isEmpty ? "Nothing logged" : "\(draft.count) food\(draft.count == 1 ? "" : "s")")
                        .font(.system(size: 13)).foregroundStyle(Palette.muted)
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 14, weight: .bold)) }
                    .buttonStyle(KIconButtonStyle(size: 32))
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(Int(mealMacros.calories.rounded()))")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(mealTint)
                Text("kcal")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Palette.muted)
            }
            HStack(spacing: 8) {
                macroChip("P", Int(mealMacros.protein.rounded()), Palette.green)
                macroChip("C", Int(mealMacros.carbs.rounded()), Palette.blue)
                macroChip("F", Int(mealMacros.fats.rounded()), Palette.red)
                macroChip("Fib", Int(mealMacros.fiber.rounded()), Palette.purple)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 16)
        .background(Palette.elevated)
    }

    private func macroChip(_ label: String, _ grams: Int, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundStyle(tint)
            Text("\(grams)g")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Palette.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: meal.icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(mealTint)
            Text("Nothing in this meal yet")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Palette.text)
            Text("Add a food or scan a plate.")
                .font(.system(size: 14))
                .foregroundStyle(Palette.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(Palette.border, lineWidth: 1))
    }

    private var footer: some View {
        VStack(spacing: 12) {
            SlideToConfirm(label: "Slide to log", tint: Palette.green) {
                state.setMealItems(date: date, meal: meal, items: draft); dismiss()
            }
            Button("Cancel") { dismiss() }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Palette.muted)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 20)
        .background(Palette.bg)
    }
}

private struct DraftFoodRow: View {
    @Binding var item: PlanItem
    let food: Food?
    let remove: () -> Void
    @State private var showDelete = false

    private var macros: Macros { (food?.perServing ?? .zero).scaled(item.quantity) }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            FoodIcon(category: food?.category ?? .other, name: food?.name ?? "", size: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text(food?.name ?? "Unknown")
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.text).lineLimit(1)
                Text("\(food?.servingLabel ?? "serving") · \(Int(macros.calories.rounded())) kcal")
                    .font(.system(size: 13)).monospacedDigit().foregroundStyle(Palette.faint).lineLimit(1)
            }
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                qtyBtn("minus") { item.quantity = max(0.5, item.quantity - 0.5) }
                Text(Fmt.trimKg(item.quantity))
                    .font(.system(size: 17, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(Palette.text).frame(minWidth: 28)
                qtyBtn("plus") { item.quantity += 0.5 }
            }
            Button { showDelete = true } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(KIconButtonStyle(size: 28))
            .holdToDelete(isPresented: $showDelete, title: "Remove \(food?.name ?? "food")?",
                          message: "Takes it off this meal. The food stays in your library.",
                          confirmLabel: "Hold to remove") { remove() }
        }
        .padding(14)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(Palette.border, lineWidth: 1))
    }

    private func qtyBtn(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.text)
                .frame(width: 34, height: 34)
                .background(Palette.surface2, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        }
        .buttonStyle(KPressStyle(scale: 0.9))
    }
}

// MARK: - Edit today's workout

struct WorkoutDayEditorSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let date: String
    @State private var draft: [PlanExercise]
    @State private var adding = false
    @State private var newExercise = false

    init(date: String, initialItems: [PlanExercise]) {
        self.date = date
        _draft = State(initialValue: initialItems.map { PlanExercise(exerciseId: $0.exerciseId, sets: $0.sets, reps: $0.reps) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Edit workout", systemImage: "figure.strengthtraining.traditional")
                    .font(.system(size: 17, weight: .heavy, design: .rounded)).foregroundStyle(Palette.text)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 13, weight: .bold)) }
                    .buttonStyle(KIconButtonStyle(size: 28))
            }
            .padding(16)
            Divider().overlay(Palette.border)
            ScrollView {
                VStack(spacing: 8) {
                    if draft.isEmpty {
                        Text("Nothing yet — add an exercise.").font(.system(size: 12)).foregroundStyle(Palette.faint)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach($draft) { $item in
                        DraftExerciseRow(item: $item, exercise: state.exercise(item.exerciseId)) {
                            draft.removeAll { $0.id == item.id }
                        }
                    }
                    Button { adding = true } label: { Label("Add exercise", systemImage: "plus.circle.fill") }
                        .buttonStyle(KGhostButtonStyle(color: Palette.brand))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(16)
            }
            .frame(maxHeight: 420)
            Divider().overlay(Palette.border)
            VStack(spacing: 12) {
                SlideToConfirm(label: "Slide to log", tint: Palette.brand) {
                    state.tickWorkout(date: date, items: draft); dismiss()
                }
                Button("Cancel") { dismiss() }.buttonStyle(KGhostButtonStyle())
            }
            .padding(16)
        }
        #if os(macOS)
        .frame(width: 460)
        #else
        .frame(maxWidth: .infinity)
        #endif
        .background(Palette.elevated)
        .sheet(isPresented: $adding) {
            ExercisePickerSheet(add: { ex in draft.append(PlanExercise(exerciseId: ex.id)) },
                                newCustom: { newExercise = true })
        }
        .sheet(isPresented: $newExercise) { ExerciseEditor(exercise: nil) }
    }
}

private struct DraftExerciseRow: View {
    @Binding var item: PlanExercise
    let exercise: Exercise?
    let remove: () -> Void

    var body: some View {
        ExercisePlanRow(
            name: exercise?.name ?? "Exercise",
            subtitle: [exercise?.category.label, exercise?.primary].compactMap { $0 }
                .filter { !$0.isEmpty }.joined(separator: " · "),
            category: exercise?.category ?? .core,
            sets: item.sets, reps: item.reps,
            onSets: { item.sets = max(1, $0) },
            onReps: { item.reps = max(1, $0) },
            remove: remove)
    }
}
