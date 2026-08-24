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
                    .font(.caption.weight(.heavy)).tracking(0.8)
                    .foregroundStyle(Palette.muted)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(Int(eaten.calories.rounded()))")
                        .font(.largeTitle.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(Palette.amber)
                    Text(goal > 0 ? "/ \(goal) kcal" : "kcal")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Palette.muted)
                    Spacer()
                    if goal > 0 {
                        Text("\(remain) left")
                            .font(.footnote.weight(.semibold))
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
                .font(.caption2.weight(.heavy)).tracking(0.4)
                .foregroundStyle(tint)
            if let target, target > 0 {
                Text("\(have)")
                    .font(.body.weight(.bold)).monospacedDigit()
                    .foregroundStyle(Palette.text)
                Text("/ \(target)g").font(.caption2).foregroundStyle(Palette.faint)
                MeterBar(fraction: min(1, Double(have) / Double(target)), tint: tint, height: 5)
            } else {
                Text("\(have)g")
                    .font(.body.weight(.bold)).monospacedDigit()
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
            WorkoutChecklistCard()
        }
        .sheet(item: $editingMeal) { meal in
            MealLogEditorSheet(date: date, meal: meal, initialItems: seed(meal))
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
                .font(.body.weight(.semibold)).foregroundStyle(Palette.text)
            Spacer()
            switch st {
            case .logged:
                let m = macros(logged)
                Text("\(Int(m.calories)) kcal · \(Int(m.protein))g P")
                    .font(.caption2.weight(.semibold)).monospacedDigit().foregroundStyle(Palette.muted)
                Image(systemName: "checkmark.circle.fill").font(.subheadline).foregroundStyle(Palette.green)
            case .skipped:
                Image(systemName: "minus.circle.fill").font(.subheadline).foregroundStyle(Palette.faint)
            case .unconfirmed:
                EmptyView()
            }
        }
    }

    @ViewBuilder private var unconfirmedBody: some View {
        if planned.isEmpty {
            Text("Nothing planned. Add, scan, or skip it.")
                .font(.caption).foregroundStyle(Palette.faint)
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
            Text("Skipped").font(.footnote.weight(.semibold)).strikethrough().foregroundStyle(Palette.faint)
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
            Text(f?.name ?? "Unknown").font(.footnote.weight(.semibold)).foregroundStyle(Palette.text).lineLimit(1)
            Spacer()
            Text("\(Fmt.trimKg(item.quantity)) × · \(kcal) kcal")
                .font(.caption2).monospacedDigit().foregroundStyle(Palette.faint).lineLimit(1)
        }
        .opacity(ghost ? 0.55 : 1)
    }

    private func macros(_ items: [PlanItem]) -> Macros {
        items.reduce(Macros.zero) { $0 + (state.food($1.foodId)?.perServing.scaled($1.quantity) ?? .zero) }
    }
}

// MARK: - The workout checklist card

/// Today's training, resolved from the active program — you never pick a
/// workout, you just do the one that's on. The card owns its own sheets so
/// Today, the Fitness tab and the day detail all behave identically.
struct WorkoutChecklistCard: View {
    /// The day being shown. Today unless the Today page has been swiped.
    var day: String? = nil
    @EnvironmentObject var state: AppState

    @State private var session = false
    @State private var choosing = false
    @State private var editingDay = false
    @State private var movingDay = false

    private var date: String { day ?? state.todayKey }
    private var resolved: (program: WorkoutProgram, day: ProgramDay)? { state.programDay(for: date) }
    private var dayLog: WorkoutDayLog { state.workoutDayLog(date) }
    private var isRest: Bool { state.isRestDay(date) }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                header
                content
            }
        }
        .sheet(isPresented: $session) { WorkoutSessionView(date: date) }
        .sheet(isPresented: $choosing) {
            ProgramDayPickerSheet(date: date) { session = true }
        }
        .sheet(isPresented: $editingDay) {
            if let r = resolved { ProgramDaySheet(programId: r.program.id, dayId: r.day.id) }
        }
        .sheet(isPresented: $movingDay) {
            if let r = resolved { DaySettingsSheet(programId: r.program.id, day: r.day) }
        }
    }

    // MARK: Header

    @ViewBuilder private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Label("Workout", systemImage: "figure.strengthtraining.traditional")
                    .font(.footnote.weight(.heavy)).foregroundStyle(Palette.text)
                if let r = resolved {
                    Text(r.day.isRestDay ? r.program.name : "\(r.day.name) · \(r.program.name)")
                        .font(.caption2).foregroundStyle(Palette.faint)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            switch dayLog.state {
            case .done:    Image(systemName: "checkmark.circle.fill").font(.subheadline).foregroundStyle(Palette.green)
            case .skipped: Image(systemName: "minus.circle.fill").font(.subheadline).foregroundStyle(Palette.faint)
            case .unconfirmed: EmptyView()
            }
            if resolved != nil { optionsMenu }
        }
    }

    /// Everything you might want to do to today's workout without rebuilding it.
    private var optionsMenu: some View {
        Menu {
            if let r = resolved, !r.day.isRestDay {
                Button("Edit this workout") { editingDay = true }
                Button("Move it to another day") { movingDay = true }
            }
            Button(isRest ? "Train anyway" : "Choose another workout") { choosing = true }
            if !isRest && dayLog.state != .done {
                Button("Mark done as planned") { state.markWorkoutDone(date: date) }
            }
            Divider()
            if dayLog.restOverride {
                Button("Undo rest day") { state.setRestOverride(date: date, false) }
            } else {
                Button("Make today a rest day") { state.setRestOverride(date: date, true) }
            }
            if dayLog.state == .skipped {
                Button("Undo skip") { state.unskipWorkout(date: date) }
            } else if !isRest {
                Button("Skip today", role: .destructive) { state.skipWorkout(date: date) }
            }
            if dayLog.entries != nil {
                Divider()
                Button("Start the log over") { state.resetSession(date: date) }
            }
        } label: {
            Image(systemName: "ellipsis").font(.footnote.weight(.bold)).foregroundStyle(Palette.faint)
                .frame(width: 28, height: 28).contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 28)
    }

    // MARK: Body

    @ViewBuilder private var content: some View {
        if resolved == nil {
            noProgram
        } else if dayLog.state == .skipped {
            skippedBody
        } else if isRest && !dayLog.hasSession {
            restBody
        } else if dayLog.state == .done {
            doneBody
        } else {
            plannedBody
        }
    }

    private var noProgram: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(state.programs.isEmpty
                 ? "No training program yet."
                 : "No program is active, so nothing is scheduled.")
                .font(.footnote.weight(.semibold)).foregroundStyle(Palette.text)
            Text("Build one in Fitness → Programs: name it, add your days, pick the muscles and exercises. After that Today always knows what's on.")
                .font(.caption).foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var restBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "moon.zzz.fill").foregroundStyle(Palette.blue)
                Text(dayLog.restOverride ? "Rest day — you called it." : "Rest day — nothing scheduled.")
                    .font(.footnote).foregroundStyle(Palette.muted)
            }
            Button { choosing = true } label: { Label("Train anyway", systemImage: "figure.run") }
                .buttonStyle(KGhostButtonStyle())
        }
    }

    /// What's on today, by muscle — the thing you actually want to read before
    /// you leave the house.
    @ViewBuilder private var plannedBody: some View {
        if let r = resolved {
            if r.day.exerciseCount == 0 {
                VStack(alignment: .leading, spacing: 10) {
                    Text("\(r.day.name) has no exercises yet.")
                        .font(.footnote).foregroundStyle(Palette.faint)
                    Button { editingDay = true } label: { Label("Build this day", systemImage: "plus") }
                        .buttonStyle(KSecondaryButtonStyle())
                }
            } else {
                VStack(spacing: Gap.tight) {
                    ForEach(r.day.blocks.filter { !$0.items.isEmpty }) { block in groupRow(block) }
                }
                if dayLog.hasSession {
                    inProgress
                } else {
                    Button { session = true } label: {
                        Label("Start workout", systemImage: "play.fill")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(KPrimaryButtonStyle(fullWidth: true))
                }
            }
        }
    }

    private var inProgress: some View {
        let entries = dayLog.entries ?? []
        let done = entries.reduce(0) { $0 + $1.doneSets }
        let total = entries.reduce(0) { $0 + $1.sets.count }
        return VStack(alignment: .leading, spacing: 8) {
            MeterBar(fraction: Double(done) / Double(max(1, total)), tint: Palette.brand, height: 6)
            Text("\(done) of \(total) sets logged")
                .font(.caption2.weight(.semibold)).monospacedDigit().foregroundStyle(Palette.faint)
            Button { session = true } label: {
                Label("Continue workout", systemImage: "play.fill").font(.subheadline.weight(.semibold))
            }
            .buttonStyle(KPrimaryButtonStyle(fullWidth: true))
        }
    }

    private func groupRow(_ block: ProgramMuscleBlock) -> some View {
        HStack(spacing: 10) {
            Image(systemName: block.group.icon)
                .font(.caption.weight(.bold)).foregroundStyle(block.group.tint)
                .frame(width: 26, height: 26)
                .background(block.group.tint.opacity(0.15),
                            in: RoundedRectangle(cornerRadius: Radius.xs, style: .continuous))
            Text(block.group.label)
                .font(.footnote.weight(.semibold)).foregroundStyle(Palette.text)
            Spacer(minLength: 4)
            Text("\(block.items.count) exercise\(block.items.count == 1 ? "" : "s")")
                .font(.caption2).monospacedDigit().foregroundStyle(Palette.faint)
        }
    }

    @ViewBuilder private var doneBody: some View {
        let entries = (dayLog.entries ?? []).filter { $0.doneSets > 0 }
        if entries.isEmpty {
            // Marked done as planned — there are no set logs to show, so show
            // what the plan was rather than the word "Logged".
            VStack(spacing: Gap.tight) {
                ForEach(resolved?.day.blocks.filter { !$0.items.isEmpty } ?? []) { block in
                    groupRow(block)
                }
            }
            Text("Done as planned.").font(.caption2).foregroundStyle(Palette.faint)
        } else {
            VStack(spacing: 6) {
                ForEach(entries) { e in
                    HStack(spacing: 10) {
                        Circle().fill(e.group.tint).frame(width: 6, height: 6)
                        Text(state.exercise(e.exerciseId)?.name ?? "Exercise")
                            .font(.footnote.weight(.semibold)).foregroundStyle(Palette.text).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(e.topWeight.map { "\(e.doneSets) × \(Fmt.trimKg($0)) kg" } ?? "\(e.doneSets) sets")
                            .font(.caption2.weight(.semibold)).monospacedDigit().foregroundStyle(Palette.faint)
                    }
                }
            }
        }
        Button { session = true } label: { Label("Edit what I logged", systemImage: "pencil") }
            .buttonStyle(KGhostButtonStyle())
    }

    private var skippedBody: some View {
        HStack {
            Text("Skipped").font(.footnote.weight(.semibold)).strikethrough().foregroundStyle(Palette.faint)
            Spacer()
            Button { state.unskipWorkout(date: date) } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                .buttonStyle(KGhostButtonStyle())
        }
    }
}

// MARK: - Run a different day from the active program

/// "Choose another workout" — every day in the active program, pick one for
/// this date. The program's schedule is untouched; only this date moves.
struct ProgramDayPickerSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let date: String
    var thenStart: () -> Void = {}

    var body: some View {
        SheetShell(title: "Choose today\u{2019}s workout",
                   subtitle: "Runs it for \(Fmt.day(date)) only — your program keeps its schedule.") {
            VStack(alignment: .leading, spacing: Gap.tight) {
                if let p = state.activeProgram {
                    ForEach(p.days.filter { !$0.isRestDay }) { d in
                        Button {
                            state.setWorkoutOverride(date: date, dayId: d.id)
                            state.resetSession(date: date)
                            dismiss()
                            thenStart()
                        } label: {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(d.name)
                                        .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.text)
                                    Text(d.groupSummary.isEmpty ? "Nothing planned" : d.groupSummary)
                                        .font(.caption).foregroundStyle(Palette.muted)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 4)
                                Text("\(d.exerciseCount)")
                                    .font(.footnote.weight(.heavy)).monospacedDigit()
                                    .foregroundStyle(Palette.faint)
                                Image(systemName: "chevron.right")
                                    .font(.caption2.weight(.bold)).foregroundStyle(Palette.faint)
                            }
                            .padding(13)
                            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .strokeBorder(Palette.border, lineWidth: 1))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(KPressStyle())
                        .onHover { h in cursor(h) }
                    }
                    if state.workoutDayLog(date).dayId != nil {
                        Button {
                            state.setWorkoutOverride(date: date, dayId: nil)
                            state.resetSession(date: date)
                            dismiss()
                        } label: { Label("Back to the scheduled day", systemImage: "arrow.uturn.backward") }
                            .buttonStyle(KGhostButtonStyle())
                    }
                } else {
                    Text("No active program.").font(.footnote).foregroundStyle(Palette.faint)
                }
            }
        }
    }
}

/// The day editor, in a sheet — so "change one exercise" from Today never
/// costs a trip through the Programs tab.
struct ProgramDaySheet: View {
    @Environment(\.dismiss) private var dismiss
    let programId: String
    let dayId: String

    var body: some View {
        ScrollView {
            ProgramDayEditorView(programId: programId, dayId: dayId, back: { dismiss() })
                .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 28)
        }
        #if os(macOS)
        .frame(width: 560)
        .frame(minHeight: 620)
        .background(Palette.bg)
        #else
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.bg)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Palette.bg)
        #endif
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
                            .font(.callout.weight(.semibold))
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
                    Image(systemName: meal.icon).font(.body.weight(.semibold)).foregroundStyle(mealTint)
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(meal.label)
                        .font(.title2.weight(.semibold)).foregroundStyle(Palette.text)
                    Text(draft.isEmpty ? "Nothing logged" : "\(draft.count) food\(draft.count == 1 ? "" : "s")")
                        .font(.footnote).foregroundStyle(Palette.muted)
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").font(.footnote.weight(.bold)) }
                    .buttonStyle(KIconButtonStyle(size: 32))
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(Int(mealMacros.calories.rounded()))")
                    .font(.largeTitle.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(mealTint)
                Text("kcal")
                    .font(.callout.weight(.semibold))
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
                .font(.caption2.weight(.heavy))
                .foregroundStyle(tint)
            Text("\(grams)g")
                .font(.callout.weight(.bold))
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
                .font(.title2.weight(.semibold))
                .foregroundStyle(mealTint)
            Text("Nothing in this meal yet")
                .font(.callout.weight(.semibold))
                .foregroundStyle(Palette.text)
            Text("Add a food or scan a plate.")
                .font(.footnote)
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
                .font(.callout.weight(.semibold))
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
                    .font(.callout.weight(.semibold)).foregroundStyle(Palette.text).lineLimit(1)
                Text("\(food?.servingLabel ?? "serving") · \(Int(macros.calories.rounded())) kcal")
                    .font(.footnote).monospacedDigit().foregroundStyle(Palette.faint).lineLimit(1)
            }
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                qtyBtn("minus") { item.quantity = max(0.5, item.quantity - 0.5) }
                Text(Fmt.trimKg(item.quantity))
                    .font(.body.weight(.bold)).monospacedDigit()
                    .foregroundStyle(Palette.text).frame(minWidth: 28)
                qtyBtn("plus") { item.quantity += 0.5 }
            }
            Button { showDelete = true } label: {
                Image(systemName: "xmark").font(.caption2.weight(.bold))
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
            Image(systemName: icon).font(.caption.weight(.bold)).foregroundStyle(Palette.text)
                .frame(width: 34, height: 34)
                .background(Palette.surface2, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        }
        .buttonStyle(KPressStyle(scale: 0.9))
    }
}
