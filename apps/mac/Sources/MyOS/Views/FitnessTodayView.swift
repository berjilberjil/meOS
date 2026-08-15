import SwiftUI

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
        VStack(alignment: .leading, spacing: 14) {
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
        state.mealState(date, meal) == .logged
            ? state.mealLog(date).items(meal)
            : state.planItems(state.todayWeekday, meal)
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
                .font(.system(size: 14, weight: .heavy, design: .rounded)).foregroundStyle(Palette.text)
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
            FoodIcon(category: f?.category ?? .other, size: 26)
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
    @EnvironmentObject var state: AppState
    let edit: () -> Void

    private var date: String { state.todayKey }
    private var plan: WorkoutDayPlan { state.workoutPlan(state.todayWeekday) }
    private var dayLog: WorkoutDayLog { state.workoutDayLog(date) }
    private var items: [PlanExercise] { state.workoutItemsForDay(date) }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                header
                if plan.rest && dayLog.state == .unconfirmed {
                    Text("Rest day — recover well.").font(.system(size: 13)).foregroundStyle(Palette.muted)
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
            SlideToConfirm(label: "Slide: done", tint: Palette.green) { state.tickWorkout(date: date) }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Edit \(meal.label)", systemImage: meal.icon)
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
                        Text("Nothing yet — add a food.").font(.system(size: 12)).foregroundStyle(Palette.faint)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach($draft) { $item in
                        DraftFoodRow(item: $item, food: state.food(item.foodId)) {
                            draft.removeAll { $0.id == item.id }
                        }
                    }
                    Button { adding = true } label: { Label("Add food", systemImage: "plus.circle.fill") }
                        .buttonStyle(KGhostButtonStyle(color: Palette.brand))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(16)
            }
            .frame(maxHeight: 420)
            Divider().overlay(Palette.border)
            HStack {
                Button("Cancel") { dismiss() }.buttonStyle(KGhostButtonStyle())
                Spacer()
                SlideToConfirm(label: "Slide to save", tint: Palette.brand) {
                    state.setMealItems(date: date, meal: meal, items: draft); dismiss()
                }
                .frame(width: 220)
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
            FoodPickerSheet(meal: meal, add: { f, q in draft.append(PlanItem(foodId: f.id, quantity: q)) },
                            newCustom: { newFood = true })
        }
        .sheet(isPresented: $newFood) { FoodEditor(food: nil) }
    }
}

private struct DraftFoodRow: View {
    @Binding var item: PlanItem
    let food: Food?
    let remove: () -> Void
    @State private var showDelete = false

    var body: some View {
        HStack(spacing: 10) {
            FoodIcon(category: food?.category ?? .other, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(food?.name ?? "Unknown").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.text).lineLimit(1)
                Text(food?.servingLabel ?? "").font(.system(size: 11)).foregroundStyle(Palette.faint).lineLimit(1)
            }
            Spacer()
            HStack(spacing: 4) {
                qtyBtn("minus") { item.quantity = max(0.5, item.quantity - 0.5) }
                Text(Fmt.trimKg(item.quantity)).font(.system(size: 12, weight: .bold)).monospacedDigit()
                    .foregroundStyle(Palette.text).frame(minWidth: 26)
                qtyBtn("plus") { item.quantity += 0.5 }
            }
            Button { showDelete = true } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                .buttonStyle(KIconButtonStyle(size: 22))
                .holdToDelete(isPresented: $showDelete, title: "Remove \(food?.name ?? "food")?",
                              message: "Removes it from this meal.", confirmLabel: "Hold to remove") { remove() }
        }
    }

    private func qtyBtn(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.text)
                .frame(width: 24, height: 22)
                .background(Palette.surface2, in: RoundedRectangle(cornerRadius: Radius.xs, style: .continuous))
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
            HStack {
                Button("Cancel") { dismiss() }.buttonStyle(KGhostButtonStyle())
                Spacer()
                SlideToConfirm(label: "Slide to save", tint: Palette.brand) {
                    state.tickWorkout(date: date, items: draft); dismiss()
                }
                .frame(width: 220)
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
    @State private var showDelete = false

    var body: some View {
        HStack(spacing: 10) {
            ExerciseIcon(category: exercise?.category ?? .core, size: 30)
            Text(exercise?.name ?? "Exercise").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.text).lineLimit(1)
            Spacer()
            HStack(spacing: 6) {
                qtyBtn("minus") { item.sets = max(1, item.sets - 1) }
                Text("\(item.sets)").font(.system(size: 12, weight: .bold)).monospacedDigit().foregroundStyle(Palette.text).frame(minWidth: 16)
                qtyBtn("plus") { item.sets += 1 }
                Text("×").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.faint)
                qtyBtn("minus") { item.reps = max(1, item.reps - 1) }
                Text("\(item.reps)").font(.system(size: 12, weight: .bold)).monospacedDigit().foregroundStyle(Palette.text).frame(minWidth: 18)
                qtyBtn("plus") { item.reps += 1 }
            }
            Button { showDelete = true } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                .buttonStyle(KIconButtonStyle(size: 22))
                .holdToDelete(isPresented: $showDelete, title: "Remove \(exercise?.name ?? "exercise")?",
                              message: "Removes it from today's workout.", confirmLabel: "Hold to remove") { remove() }
        }
    }

    private func qtyBtn(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 9, weight: .bold)).foregroundStyle(Palette.text)
                .frame(width: 22, height: 20)
                .background(Palette.surface2, in: RoundedRectangle(cornerRadius: Radius.xs, style: .continuous))
        }
        .buttonStyle(KPressStyle(scale: 0.9))
    }
}
