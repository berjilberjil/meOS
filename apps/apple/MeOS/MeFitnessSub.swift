import SwiftUI
import PhotosUI

extension Fmt {
    static func kg(_ v: Double) -> String { v == v.rounded() ? "\(Int(v)) kg" : String(format: "%.1f kg", v) }
}

// MARK: - Workout session (set-by-set)

struct MeWorkoutSession: View {
    @EnvironmentObject var state: AppState
    let date: String
    @State private var picking = false

    var body: some View {
        let log = state.workoutDayLog(date)
        let entries = log.entries ?? []
        let done = entries.flatMap(\.sets).filter(\.done)
        let volume = entries.reduce(0) { $0 + $1.volumeKg }
        Screen(title: log.title ?? state.programDay(for: date)?.day.name ?? "Workout",
               sub: "\(done.count) sets · \(Int(volume)) kg") {
            if entries.isEmpty {
                if state.isRestDay(date) {
                    Empty(icon: "bed.double", text: "Rest day. Recover well.")
                    MButton(title: "Train anyway", icon: "figure.strengthtraining.traditional") { picking = true }
                } else {
                    Empty(icon: "dumbbell", text: "Ready when you are.")
                    MButton(title: "Start workout", icon: "play.fill") { withAnimation(DS.spring) { state.startSession(date: date) } }
                }
            }
            ForEach(entries) { e in
                MCard {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(state.exercise(e.exerciseId)?.name ?? "Exercise").font(.title2.bold())
                            if let w = state.lastWeight(exerciseId: e.exerciseId, before: date) {
                                Text("Last time \(Fmt.kg(w))").font(.subheadline).foregroundStyle(Color.dim)
                            }
                        }
                        Spacer()
                        Menu {
                            Button("Remove exercise", systemImage: "trash", role: .destructive) { state.removeSessionExercise(date: date, entryId: e.id) }
                        } label: { Image(systemName: "ellipsis").font(.title3).frame(width: 44, height: 44) }
                    }
                    ForEach(Array(e.sets.enumerated()), id: \.element.id) { i, s in
                        MeSetRow(index: i + 1, set: s) { f in state.updateSet(date: date, entryId: e.id, setId: s.id, f) }
                            .contextMenu { Button("Remove set", role: .destructive) { state.removeSet(date: date, entryId: e.id, setId: s.id) } }
                    }
                    Button { withAnimation(DS.spring) { state.addSet(date: date, entryId: e.id) } } label: {
                        Label("Add set", systemImage: "plus").font(.headline)
                    }
                }
            }
            if !entries.isEmpty {
                MButton(title: log.done ? "Done" : "Finish workout", icon: "checkmark") {
                    Haptics.success(); withAnimation(DS.spring) { state.finishSession(date: date) }
                }
                .disabled(log.done).opacity(log.done ? 0.4 : 1)
                HStack {
                    Button("Skip today") { state.skipWorkout(date: date) }
                    Spacer()
                    Button("Other day") { picking = true }
                }
                .font(.headline).foregroundStyle(Color.dim)
            }
        }
        .sheet(isPresented: $picking) { MeDayPicker(date: date).presentationDetents([.medium, .large]) }
    }
}

struct MeSetRow: View {
    let index: Int
    let set: SetLog
    let update: (@escaping (inout SetLog) -> Void) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text("\(index)").font(.headline).foregroundStyle(Color.dim).frame(width: 22)
            pill("\(set.weightKg.map { Fmt.kg($0) } ?? "BW")", minus: { update { $0.weightKg = max(0, ($0.weightKg ?? 0) - 2.5) } },
                 plus: { update { $0.weightKg = ($0.weightKg ?? 0) + 2.5 } })
            pill("\(set.reps)×", minus: { update { $0.reps = max(1, $0.reps - 1) } }, plus: { update { $0.reps += 1 } })
            Spacer(minLength: 0)
            Button { withAnimation(DS.bouncy) { update { $0.done.toggle() } } } label: {
                Image(systemName: set.done ? "checkmark.circle.fill" : "circle").font(.system(size: 34))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.press).sensoryFeedback(.success, trigger: set.done) { !$0 && $1 }
        }
    }
    private func pill(_ v: String, minus: @escaping () -> Void, plus: @escaping () -> Void) -> some View {
        HStack(spacing: 2) {
            Button(action: minus) { Image(systemName: "minus").frame(width: 30, height: 40) }
            Text(v).font(.headline).monospacedDigit().frame(minWidth: 48).contentTransition(.numericText())
            Button(action: plus) { Image(systemName: "plus").frame(width: 30, height: 40) }
        }
        .buttonStyle(.press).background(Color.hairline, in: .capsule)
    }
}

struct MeDayPicker: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let date: String
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Train which day?").font(.largeTitle.bold()).padding(.top, 24)
                ForEach(state.activeProgram?.days.filter { !$0.isRestDay } ?? []) { d in
                    Button {
                        state.setWorkoutOverride(date: date, dayId: d.id); state.resetSession(date: date); dismiss()
                    } label: { Row(icon: "dumbbell", title: d.name, detail: d.groupSummary) }
                    .buttonStyle(.press)
                }
                Button { state.setRestOverride(date: date, true); dismiss() } label: { Row(icon: "bed.double", title: "Make it a rest day") }
                    .buttonStyle(.press)
            }
            .padding(DS.pad)
        }
    }
}

// MARK: - Programs

struct MePrograms: View {
    @EnvironmentObject var state: AppState
    @State private var newName = ""
    var body: some View {
        Screen(title: "Programs", sub: state.activeProgram.map { "Active · \($0.name)" } ?? "None active") {
            ForEach(state.programs) { p in
                NavigationLink { MeProgramDetail(id: p.id) } label: {
                    MCard(inverted: p.id == state.activeProgram?.id) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(p.name).font(.title2.bold())
                                Text("\(p.trainingDayCount) training days · \(p.days.count) total").font(.subheadline).opacity(0.6)
                            }
                            Spacer()
                            if p.id == state.activeProgram?.id { Image(systemName: "checkmark.circle.fill").font(.title2) }
                        }
                    }
                }
                .buttonStyle(.press)
                .contextMenu {
                    Button("Set active", systemImage: "checkmark") { state.setActiveProgram(p.id) }
                    Button("Duplicate", systemImage: "plus.square.on.square") { _ = state.duplicateProgram(p.id) }
                    Button("Delete", systemImage: "trash", role: .destructive) { state.deleteProgram(p.id) }
                }
            }
            MField(icon: "plus", placeholder: "New program name", text: $newName)
                .onSubmit {
                    guard !newName.isEmpty else { return }
                    withAnimation(DS.spring) { _ = state.createProgram(name: newName, days: [ProgramDay(name: "Day 1")]) }
                    newName = ""
                }
        }
    }
}

struct MeProgramDetail: View {
    @EnvironmentObject var state: AppState
    let id: String
    private let weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    var body: some View {
        if let p = state.program(id) {
            Screen(title: p.name, sub: p.id == state.activeProgram?.id ? "Active" : "Program") {
                if p.id != state.activeProgram?.id {
                    MButton(title: "Set as active", icon: "checkmark") { withAnimation(DS.spring) { state.setActiveProgram(p.id) } }
                }
                ForEach(p.days) { d in
                    NavigationLink { MeProgramDay(programId: p.id, dayId: d.id) } label: {
                        Row(icon: d.isRestDay ? "bed.double" : "dumbbell",
                            title: d.name,
                            detail: (d.weekday.map { weekdays[$0] + " · " } ?? "") + (d.isRestDay ? "Rest" : "\(d.exerciseCount) exercises · \(d.groupSummary)"))
                    }
                    .buttonStyle(.press)
                    .contextMenu {
                        Button("Duplicate", systemImage: "plus.square.on.square") { state.duplicateDay(p.id, d.id) }
                        Button("Delete", systemImage: "trash", role: .destructive) { state.deleteDay(p.id, d.id) }
                    }
                }
                Button {
                    state.mutateProgram(p.id) { $0.days.append(ProgramDay(name: "Day \($0.days.count + 1)")) }
                } label: { Label("Add day", systemImage: "plus").font(.headline).frame(maxWidth: .infinity).frame(height: 56).background(Color.card, in: .rect(cornerRadius: 22)) }
                .buttonStyle(.press)
            }
        }
    }
}

struct MeProgramDay: View {
    @EnvironmentObject var state: AppState
    let programId: String
    let dayId: String
    @State private var addingTo: String?
    @State private var name = ""
    private let weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    var body: some View {
        if let day = state.program(programId)?.days.first(where: { $0.id == dayId }) {
            Screen(title: day.name, sub: day.isRestDay ? "Rest day" : "\(day.exerciseCount) exercises") {
                MField(icon: "pencil", placeholder: "Day name", text: $name)
                    .onSubmit { state.renameDay(programId, dayId, to: name) }
                ScrollView(.horizontal) {
                    HStack {
                        Button { state.setDayWeekday(programId, dayId, weekday: nil) } label: { Chip(text: "Rotation", on: day.weekday == nil) }
                        ForEach(0..<7) { i in Button { state.setDayWeekday(programId, dayId, weekday: i) } label: { Chip(text: weekdays[i], on: day.weekday == i) } }
                    }
                }
                .scrollIndicators(.hidden).buttonStyle(.press)
                MCard { Toggle("Rest day", isOn: Binding(get: { day.rest }, set: { state.setDayRest(programId, dayId, $0) })).font(.title3.weight(.semibold)) }
                ForEach(day.blocks) { b in
                    MCard {
                        HStack {
                            Text(b.group.label).font(.title2.bold())
                            Spacer()
                            Button { addingTo = b.id } label: { Image(systemName: "plus").font(.title3.bold()) }
                            Menu { Button("Remove group", role: .destructive) { state.removeBlock(programId, dayId, b.id) } } label: { Image(systemName: "ellipsis").font(.title3).frame(width: 36, height: 36) }
                        }
                        ForEach(b.items) { it in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(state.exercise(it.exerciseId)?.name ?? "Exercise").font(.headline)
                                HStack(spacing: 8) {
                                    stepper("\(it.sets) sets") { v in state.updateProgramExercise(programId, dayId, b.id, itemId: it.id) { $0.sets = max(1, $0.sets + v) } }
                                    stepper("\(it.reps) reps") { v in state.updateProgramExercise(programId, dayId, b.id, itemId: it.id) { $0.reps = max(1, $0.reps + v) } }
                                    stepper("\(it.restSec)s") { v in state.updateProgramExercise(programId, dayId, b.id, itemId: it.id) { $0.restSec = max(0, $0.restSec + v * 15) } }
                                }
                            }
                            .padding(.vertical, 4)
                            .contextMenu { Button("Remove", role: .destructive) { state.removeProgramExercise(programId, dayId, b.id, itemId: it.id) } }
                        }
                    }
                }
                Menu {
                    ForEach(MuscleGroup.allCases) { g in Button(g.label) { _ = state.addBlock(programId, dayId, group: g) } }
                } label: {
                    Label("Add muscle group", systemImage: "plus").font(.headline).frame(maxWidth: .infinity).frame(height: 56)
                        .background(Color.card, in: .rect(cornerRadius: 22))
                }
            }
            .onAppear { name = day.name }
            .sheet(item: Binding(get: { addingTo.map { IDBox(id: $0) } }, set: { addingTo = $0?.id })) { box in
                let group = day.blocks.first { $0.id == box.id }?.group
                MeExercisePicker(group: group) { exId in state.addProgramExercise(programId, dayId, box.id, exerciseId: exId) }
            }
        }
    }
    private func stepper(_ text: String, _ change: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 0) {
            Button { change(-1) } label: { Image(systemName: "minus").frame(width: 28, height: 36) }
            Text(text).font(.subheadline.weight(.semibold)).monospacedDigit()
            Button { change(1) } label: { Image(systemName: "plus").frame(width: 28, height: 36) }
        }
        .buttonStyle(.press).background(Color.hairline, in: .capsule)
    }
}

struct IDBox: Identifiable { let id: String }

struct MeExercisePicker: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let group: MuscleGroup?
    let pick: (String) -> Void
    @State private var query = ""
    var body: some View {
        NavigationStack {
            List {
                ForEach((group.map { state.exercises(in: $0) } ?? state.allExercises).filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }) { ex in
                    Button { pick(ex.id); dismiss() } label: {
                        VStack(alignment: .leading) { Text(ex.name).font(.headline); Text(ex.primary).font(.subheadline).foregroundStyle(Color.dim) }
                    }
                    .foregroundStyle(.primary)
                }
            }
            .listStyle(.plain)
            .searchable(text: $query)
            .navigationTitle(group?.label ?? "Exercises").navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - History

struct MeWorkoutHistory: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        let days = (0..<60).compactMap { i -> (String, WorkoutDayLog)? in
            let k = AppState.dateKey(Calendar.current.date(byAdding: .day, value: -i, to: .now)!)
            let l = state.workoutDayLog(k)
            return (l.done || l.skipped) ? (k, l) : nil
        }
        let last28 = days.filter { state.daysUntil($0.0).map { $0 > -28 } ?? false }
        Screen(title: "History", sub: "Last 60 days") {
            HStack(spacing: DS.gap) {
                MCard(inverted: true) { Stat(value: "\(last28.filter { $0.1.done }.count)", label: "done · 28d") }
                MCard { Stat(value: "\(last28.filter { $0.1.skipped }.count)", label: "skipped · 28d") }
            }
            if days.isEmpty { Empty(icon: "clock", text: "No workouts logged yet.") }
            ForEach(days, id: \.0) { k, l in
                NavigationLink { MeWorkoutSession(date: k) } label: {
                    Row(icon: l.done ? "checkmark.circle.fill" : "xmark.circle", title: l.title ?? "Workout",
                        detail: Fmt.day(k) + (l.entries.map { " · \(Int($0.reduce(0) { $0 + $1.volumeKg })) kg" } ?? ""))
                }
                .buttonStyle(.press)
            }
        }
    }
}

// MARK: - Weekly report

struct MeWeeklyReports: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        Screen(title: "Weekly report", sub: "Every Friday, 6pm") {
            MButton(title: state.weeklyBusy ? "Reading your week…" : "Read my week now", icon: "sparkles") {
                Task { _ = await state.generateWeeklyReport(notify: false) }
            }
            .disabled(state.weeklyBusy)
            if let err = state.weeklyError { Text(err).font(.subheadline) }
            if state.weekly.isEmpty { Empty(icon: "doc.text.magnifyingglass", text: "No reports yet.") }
            ForEach(state.weekly.sorted { $0.at > $1.at }) { r in
                MCard(inverted: r.id == state.weekly.max(by: { $0.at < $1.at })?.id) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(r.verdict).font(.system(size: 34, weight: .bold)).tracking(-0.8)
                        Spacer()
                        Text("\(Int(r.percent))%").font(.title2.bold())
                    }
                    Text(r.headline).font(.title3.weight(.semibold))
                    Text(r.read).opacity(0.75)
                    if !r.workouts.isEmpty { MLabel("Training"); ForEach(r.workouts, id: \.self) { Text("· " + $0) } }
                    if !r.diet.isEmpty { MLabel("Diet"); ForEach(r.diet, id: \.self) { Text("· " + $0) } }
                    Text(r.cheer).font(.headline).padding(.top, 6)
                    Text("\(Fmt.day(r.weekStart)) – \(Fmt.day(r.weekEnd))").font(.caption).opacity(0.5)
                }
                .onAppear { if !r.seen { state.markWeeklyReportSeen(r.id) } }
            }
        }
    }
}

// MARK: - Targets & profile

struct MeTargets: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        let p = state.fitnessProfile
        let t = state.calorieTargets()
        Screen(title: "Targets", sub: "Goal · \(p.goal.label)") {
            HStack { ForEach(FitnessGoal.allCases, id: \.self) { g in Button { state.updateFitnessProfile { $0.goal = g } } label: { Chip(text: g.label, on: p.goal == g) } } }
                .buttonStyle(.press)
            HStack { ForEach(Sex.allCases, id: \.self) { s in Button { state.updateFitnessProfile { $0.sex = s } } label: { Chip(text: s.label, on: p.sex == s) } } }
                .buttonStyle(.press)
            MCard {
                Text("Activity").font(.title3.bold())
                ForEach(ActivityLevel.allCases, id: \.self) { a in
                    Button { state.updateFitnessProfile { $0.activity = a } } label: {
                        HStack {
                            VStack(alignment: .leading) { Text(a.label).font(.headline); Text(a.hint).font(.subheadline).foregroundStyle(Color.dim) }
                            Spacer()
                            if p.activity == a { Image(systemName: "checkmark").font(.headline) }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.press)
                }
            }
            MCard {
                BigStepper(label: "Height", value: state.profile.heightCm.map { "\(Int($0)) cm" } ?? "—",
                           minus: { state.updateProfile { $0.heightCm = ($0.heightCm ?? 170) - 1 } },
                           plus: { state.updateProfile { $0.heightCm = ($0.heightCm ?? 170) + 1 } })
                BigStepper(label: "Target", value: p.targetWeightKg.map { Fmt.kg($0) } ?? "—",
                           minus: { state.updateFitnessProfile { $0.targetWeightKg = ($0.targetWeightKg ?? state.latestWeightKg ?? 70) - 0.5 } },
                           plus: { state.updateFitnessProfile { $0.targetWeightKg = ($0.targetWeightKg ?? state.latestWeightKg ?? 70) + 0.5 } })
            }
            if let t {
                MCard(inverted: true) {
                    Text("Suggested").font(.headline).opacity(0.7)
                    Stat(value: "\(t.goalCalories)", label: "kcal · BMR \(t.bmr) · TDEE \(t.tdee)", big: true)
                    Text("Protein \(t.proteinG)g · Fat \(t.fatG)g · Carbs \(t.carbG)g").font(.headline)
                    Button {
                        Haptics.success()
                        state.updateFitnessProfile { $0.calorieTargetKcal = Double(t.goalCalories); $0.proteinTargetG = Double(t.proteinG) }
                    } label: {
                        Text("Use as my daily targets").font(.headline).frame(maxWidth: .infinity).frame(height: 52)
                            .foregroundStyle(Color.ink).background(Color.paper, in: .rect(cornerRadius: 16))
                    }
                    .buttonStyle(.press)
                }
            }
            MCard {
                BigStepper(label: "Calories", value: "\(state.kcalTarget)",
                           minus: { state.updateFitnessProfile { $0.calorieTargetKcal = Double(state.kcalTarget - 50) } },
                           plus: { state.updateFitnessProfile { $0.calorieTargetKcal = Double(state.kcalTarget + 50) } })
                BigStepper(label: "Protein", value: "\(state.proteinTarget)g",
                           minus: { state.updateFitnessProfile { $0.proteinTargetG = Double(state.proteinTarget - 5) } },
                           plus: { state.updateFitnessProfile { $0.proteinTargetG = Double(state.proteinTarget + 5) } })
                BigStepper(label: "Water", value: "\(state.waterTarget)ml",
                           minus: { state.updateFitnessProfile { $0.waterTargetMl = Double(state.waterTarget - 250) } },
                           plus: { state.updateFitnessProfile { $0.waterTargetMl = Double(state.waterTarget + 250) } })
                BigStepper(label: "Steps", value: state.stepGoals.daily.formatted(),
                           minus: { state.setStepGoals(daily: state.stepGoals.daily - 500, stretch: nil) },
                           plus: { state.setStepGoals(daily: state.stepGoals.daily + 500, stretch: nil) })
                BigStepper(label: "Stretch", value: state.stepGoals.stretch.formatted(),
                           minus: { state.setStepGoals(daily: nil, stretch: state.stepGoals.stretch - 500) },
                           plus: { state.setStepGoals(daily: nil, stretch: state.stepGoals.stretch + 500) })
            }
        }
    }
}

// MARK: - Meals (today's log) and the weekly plan

struct MeMealEditor: View {
    @EnvironmentObject var state: AppState
    let date: String
    let meal: MealKey
    @State private var picking = false

    var body: some View {
        let items = state.mealEditorItems(date: date, meal: meal)
        let st = state.mealState(date, meal)
        Screen(title: meal.label, sub: st == .logged ? "Logged" : st == .skipped ? "Skipped" : "Not logged yet") {
            ForEach(items) { it in
                if let f = state.food(it.foodId) {
                    MCard {
                        Text(f.name).font(.title3.bold())
                        Text("\(Int(f.perServing.calories * it.quantity)) kcal · \(Int(f.perServing.protein * it.quantity))g protein · \(f.servingLabel)")
                            .font(.subheadline).foregroundStyle(Color.dim)
                        BigStepper(label: "Qty", value: String(format: "%g", it.quantity),
                                   minus: { setQty(items, it.id, max(0.5, it.quantity - 0.5)) },
                                   plus: { setQty(items, it.id, it.quantity + 0.5) })
                    }
                    .contextMenu { Button("Remove", role: .destructive) { state.setMealItems(date: date, meal: meal, items: items.filter { $0.id != it.id }) } }
                }
            }
            Button { picking = true } label: { Row(icon: "plus", title: "Add food") }.buttonStyle(.press)
            if st != .logged && !items.isEmpty {
                MButton(title: "Ate it", icon: "checkmark") { Haptics.success(); state.setMealItems(date: date, meal: meal, items: items) }
            }
            Button(st == .skipped ? "Unskip" : "Skip this meal") {
                st == .skipped ? state.unskipMeal(date: date, meal: meal) : state.skipMeal(date: date, meal: meal)
            }
            .font(.headline).foregroundStyle(Color.dim).frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $picking) {
            MeFoodPicker { id in state.setMealItems(date: date, meal: meal, items: items + [PlanItem(foodId: id)]) }
        }
    }
    private func setQty(_ items: [PlanItem], _ id: String, _ q: Double) {
        state.setMealItems(date: date, meal: meal, items: items.map { var i = $0; if i.id == id { i.quantity = q }; return i })
    }
}

struct MeFoodPicker: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let pick: (String) -> Void
    @State private var query = ""
    var body: some View {
        NavigationStack {
            List {
                ForEach(state.allFoods.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }) { f in
                    Button { pick(f.id); dismiss() } label: {
                        HStack {
                            VStack(alignment: .leading) { Text(f.name).font(.headline); Text(f.servingLabel).font(.subheadline).foregroundStyle(Color.dim) }
                            Spacer()
                            Text("\(Int(f.perServing.calories))").font(.headline).monospacedDigit()
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
            .listStyle(.plain).searchable(text: $query)
            .navigationTitle("Add food").navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct MeMealPlan: View {
    @EnvironmentObject var state: AppState
    @State private var weekday = AppState.weekdayKey(AppState.dateKey(.now))
    @State private var adding: MealKey?
    @State private var generated: GeneratedPlan?
    private let names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    var body: some View {
        Screen(title: "Meal plan", sub: "Weekly") {
            ScrollView(.horizontal) {
                HStack { ForEach(WeekdayKeys.all, id: \.self) { d in Button { withAnimation(DS.spring) { weekday = d } } label: { Chip(text: names[Int(d) ?? 0], on: weekday == d) } } }
            }
            .scrollIndicators(.hidden).buttonStyle(.press).sensoryFeedback(.selection, trigger: weekday)
            ForEach(MealKey.allCases) { m in
                let items = state.planItems(weekday, m)
                MCard {
                    HStack {
                        Label(m.label, systemImage: m.symbol).font(.title3.bold())
                        Spacer()
                        Text("\(Int(items.reduce(0) { $0 + (state.food($1.foodId)?.perServing.calories ?? 0) * $1.quantity })) kcal").font(.headline).foregroundStyle(Color.dim)
                        Button { adding = m } label: { Image(systemName: "plus").font(.title3.bold()).frame(width: 40, height: 40) }
                    }
                    ForEach(items) { it in
                        HStack {
                            Text(state.food(it.foodId)?.name ?? "Food").font(.headline)
                            Spacer()
                            Text("×" + String(format: "%g", it.quantity)).foregroundStyle(Color.dim)
                            Button { state.removePlanItem(weekday: weekday, meal: m, itemId: it.id) } label: { Image(systemName: "xmark").foregroundStyle(Color.dim) }
                        }
                    }
                }
            }
            Menu {
                ForEach(WeekdayKeys.others(except: weekday), id: \.self) { d in
                    Button("Copy to \(names[Int(d) ?? 0])") { state.copyMealPlanDay(from: weekday, to: [d]) }
                }
                Button("Copy to every day") { state.copyMealPlanDay(from: weekday, to: WeekdayKeys.others(except: weekday)) }
            } label: { Row(icon: "doc.on.doc", title: "Copy this day") }
            Button { Task { generated = await state.generateWeeklyPlan() } } label: {
                Row(icon: "sparkles", title: state.planBusy ? "Building your week…" : "Generate my week", detail: "Meals + training from your library and targets")
            }
            .buttonStyle(.press).disabled(state.planBusy)
            if let err = state.planError { Text(err).font(.subheadline) }
            Button("Clear the whole week", role: .destructive) { state.clearMealPlan() }.font(.headline).frame(maxWidth: .infinity)
        }
        .sheet(item: $adding) { m in MeFoodPicker { id in state.addFoodToPlan(weekday: weekday, meal: m, foodId: id) } }
        .alert("Use this plan?", isPresented: Binding(get: { generated != nil }, set: { if !$0 { generated = nil } })) {
            Button("Use it") { if let g = generated { state.confirmGeneratedPlan(g) }; generated = nil }
            Button("Cancel", role: .cancel) { generated = nil }
        } message: { Text(state.planSummary ?? "Replaces your meal plan and training program.") }
    }
}

// MARK: - Library

struct MeLibrary: View {
    @EnvironmentObject var state: AppState
    @State private var foods = true
    @State private var query = ""
    @State private var adding = false

    var body: some View {
        Screen(title: "Library", sub: foods ? "\(state.allFoods.count) foods" : "\(state.allExercises.count) exercises") {
            HStack {
                Button { withAnimation(DS.spring) { foods = true } } label: { Chip(text: "Foods", on: foods) }
                Button { withAnimation(DS.spring) { foods = false } } label: { Chip(text: "Exercises", on: !foods) }
            }
            .buttonStyle(.press)
            MField(icon: "magnifyingglass", placeholder: "Search", text: $query)
            if foods {
                ForEach(state.allFoods.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }) { f in
                    MCard {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(f.name).font(.headline)
                                Text("\(f.category.label) · \(f.servingLabel)").font(.subheadline).foregroundStyle(Color.dim)
                            }
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text("\(Int(f.perServing.calories)) kcal").font(.headline)
                                Text("P\(Int(f.perServing.protein)) C\(Int(f.perServing.carbs)) F\(Int(f.perServing.fats))").font(.caption).foregroundStyle(Color.dim)
                            }
                        }
                    }
                    .contextMenu { if !f.isDefault { Button("Delete", role: .destructive) { state.deleteFood(f.id) } } }
                }
            } else {
                ForEach(MuscleGroup.allCases) { g in
                    let list = state.exercises(in: g).filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
                    if !list.isEmpty {
                        MLabel(g.label)
                        ForEach(list) { ex in
                            MCard {
                                Text(ex.name).font(.headline)
                                Text([ex.primary, ex.equipment].filter { !$0.isEmpty }.joined(separator: " · ")).font(.subheadline).foregroundStyle(Color.dim)
                            }
                        }
                    }
                }
            }
        }
        .meActions { if foods { Button { adding = true } label: { Image(systemName: "plus") } } }
        .sheet(isPresented: $adding) { MeAddFood().presentationDetents([.large]) }
    }
}

struct MeAddFood: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var serving = "1 serving"
    @State private var cat: FoodCategory = .other
    @State private var kcal = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var fiber = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("New food").font(.largeTitle.bold()).padding(.top, 24)
                MField(icon: "fork.knife", placeholder: "Name", text: $name)
                MField(icon: "scalemass", placeholder: "Serving", text: $serving)
                ScrollView(.horizontal) { HStack { ForEach(FoodCategory.allCases, id: \.self) { c in Button { cat = c } label: { Chip(text: c.label, on: cat == c) } } } }
                    .scrollIndicators(.hidden).buttonStyle(.press)
                HStack { MField(icon: "flame", placeholder: "kcal", text: $kcal); MField(icon: "p.circle", placeholder: "Protein", text: $protein) }
                HStack { MField(icon: "c.circle", placeholder: "Carbs", text: $carbs); MField(icon: "f.circle", placeholder: "Fat", text: $fat) }
                MField(icon: "leaf", placeholder: "Fiber", text: $fiber)
                MButton(title: "Save", icon: "checkmark") {
                    let m = Macros(calories: Double(kcal) ?? 0, protein: Double(protein) ?? 0, carbs: Double(carbs) ?? 0, fiber: Double(fiber) ?? 0, fats: Double(fat) ?? 0)
                    _ = state.addFood(Food(name: name, category: cat, servingLabel: serving, perServing: m)); dismiss()
                }
                .disabled(name.isEmpty).opacity(name.isEmpty ? 0.3 : 1)
            }
            .keyboardType(.default)
            .padding(DS.pad)
        }
    }
}


// MARK: - Body photos

struct MeBodyPhotos: View {
    @EnvironmentObject var state: AppState
    @State private var photos: [ProgressPhoto] = []
    @State private var pick: [PhotosPickerItem] = []
    @State private var viewing: ProgressPhoto?
    @State private var compare: [ProgressPhoto] = []
    @State private var comparing = false

    var body: some View {
        Screen(title: "Body", sub: "\(photos.count) photos") {
            PhotosPicker(selection: $pick, maxSelectionCount: 5, matching: .images) { Row(icon: "plus", title: "Add today’s photo") }
                .buttonStyle(.press)
            if compare.count == 2 {
                MButton(title: "Compare", icon: "rectangle.split.2x1") { comparing = true }
            } else if !photos.isEmpty {
                Text(compare.isEmpty ? "Long-press two photos to compare." : "Pick one more.").font(.subheadline).foregroundStyle(Color.dim)
            }
            LazyVGrid(columns: Array(repeating: .init(spacing: 6), count: 3), spacing: 6) {
                ForEach(photos) { p in
                    Button { viewing = p } label: {
                        MeLocalImage(url: ProgressPhotoStore.url(for: p.id)).aspectRatio(3 / 4, contentMode: .fill)
                            .clipShape(.rect(cornerRadius: 16))
                            .overlay(alignment: .bottomLeading) { Text(Fmt.day(p.date)).font(.caption2.bold()).padding(6).foregroundStyle(.white).shadow(radius: 3) }
                            .overlay { if compare.contains(p) { RoundedRectangle(cornerRadius: 16).stroke(Color.ink, lineWidth: 4) } }
                    }
                    .buttonStyle(.press)
                    .onLongPressGesture { withAnimation(DS.spring) { if compare.contains(p) { compare.removeAll { $0 == p } } else { compare = Array((compare + [p]).suffix(2)) } } }
                }
            }
        }
        .onAppear(perform: reload)
        .onChange(of: pick) { _, items in
            Task {
                for it in items { if let d = try? await it.loadTransferable(type: Data.self), let img = UIImage(data: d), let j = img.jpegData(compressionQuality: 0.85) {
                    _ = ProgressPhotoStore.save(jpeg: j, date: state.todayKey)
                } }
                pick = []; reload(); await ProgressPhotoSync.push()
            }
        }
        .fullScreenCover(item: $viewing) { p in MePhotoViewer(url: ProgressPhotoStore.url(for: p.id), caption: Fmt.day(p.date)) {
            state.recycleProgressPhoto(p); viewing = nil; reload()
        } }
        .fullScreenCover(isPresented: $comparing) { MeCompare(a: compare[0], b: compare[1]) }
    }
    private func reload() { photos = ProgressPhotoStore.list().sorted { $0.date > $1.date } }
}

struct MeCompare: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let a: ProgressPhoto
    let b: ProgressPhoto
    var body: some View {
        let (old, new) = a.date < b.date ? (a, b) : (b, a)
        let days = abs(state.daysUntil(old.date).map { d in d - (state.daysUntil(new.date) ?? 0) } ?? 0)
        let w1 = state.fitnessDay(old.date).weightKg, w2 = state.fitnessDay(new.date).weightKg
        VStack(spacing: 16) {
            HStack { Spacer(); Button { dismiss() } label: { BigIcon(name: "xmark", size: 18) }.buttonStyle(.press) }
            HStack(spacing: 8) {
                ForEach([old, new]) { p in
                    VStack { MeLocalImage(url: ProgressPhotoStore.url(for: p.id)).aspectRatio(3 / 4, contentMode: .fit).clipShape(.rect(cornerRadius: 20)); Text(Fmt.day(p.date)).font(.headline) }
                }
            }
            Text("\(days) days apart" + ((w1 != nil && w2 != nil) ? " · \(String(format: "%+.1f", w2! - w1!)) kg" : "")).font(.title2.bold())
            Spacer()
        }
        .padding(DS.pad)
    }
}

struct MeLocalImage: View {
    let url: URL
    @State private var image: UIImage?
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFill() } else { Color.hairline }
        }
        .task(id: url) { image = await Task.detached { UIImage(contentsOfFile: url.path)?.preparingThumbnail(of: CGSize(width: 900, height: 1200)) }.value }
    }
}

struct MePhotoViewer: View {
    @Environment(\.dismiss) private var dismiss
    let url: URL
    var caption: String = ""
    var onDelete: (() -> Void)?
    @State private var scale: CGFloat = 1
    @State private var drag: CGSize = .zero
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea().opacity(1 - min(abs(drag.height) / 400, 0.6))
            MeLocalImage(url: url).aspectRatio(contentMode: .fit)
                .scaleEffect(scale).offset(drag)
                .gesture(MagnifyGesture().onChanged { scale = max(1, $0.magnification) }.onEnded { _ in withAnimation(DS.spring) { scale = 1 } })
                .simultaneousGesture(DragGesture().onChanged { drag = $0.translation }.onEnded { v in
                    if abs(v.translation.height) + abs(v.velocity.height) * 0.2 > 180 { dismiss() } else { withAnimation(DS.bouncy) { drag = .zero } }
                })
            VStack {
                HStack {
                    Text(caption).font(.headline).foregroundStyle(.white)
                    Spacer()
                    if let onDelete { Button { onDelete() } label: { Image(systemName: "trash").font(.title3).foregroundStyle(.white).frame(width: 44, height: 44) } }
                    Button { dismiss() } label: { Image(systemName: "xmark").font(.title3.bold()).foregroundStyle(.white).frame(width: 44, height: 44) }
                }
                .padding()
                Spacer()
            }
        }
    }
}

// MARK: - Step streak calendar

struct MeStreakCalendar: View {
    @EnvironmentObject var state: AppState
    @State private var month = Date.now
    var body: some View {
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.year, .month], from: month))!
        let count = cal.range(of: .day, in: .month, for: start)!.count
        let lead = (cal.component(.weekday, from: start) + 6) % 7
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(month.formatted(.dateTime.month(.wide).year())).font(.title2.bold())
                Spacer()
                Button { withAnimation(DS.spring) { month = cal.date(byAdding: .month, value: -1, to: month)! } } label: { BigIcon(name: "chevron.left", size: 16) }
                Button { withAnimation(DS.spring) { month = cal.date(byAdding: .month, value: 1, to: month)! } } label: { BigIcon(name: "chevron.right", size: 16) }
            }
            .buttonStyle(.press)
            LazyVGrid(columns: Array(repeating: .init(spacing: 6), count: 7), spacing: 6) {
                ForEach(["M", "T", "W", "T", "F", "S", "S"].indices, id: \.self) { i in Text(["M", "T", "W", "T", "F", "S", "S"][i]).font(.caption.bold()).foregroundStyle(Color.dim) }
                ForEach(0..<lead, id: \.self) { _ in Color.clear.frame(height: 40) }
                ForEach(1...count, id: \.self) { d in
                    let k = AppState.dateKey(cal.date(byAdding: .day, value: d - 1, to: start)!)
                    let s = state.stepDay(k)
                    let hit = s == .hit || s == .stretch
                    Text("\(d)").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).frame(height: 40)
                        .foregroundStyle(hit ? Color.paper : .ink)
                        .background(hit ? Color.ink : (s == .short ? Color.hairline : Color.clear), in: .rect(cornerRadius: 12))
                        .overlay { if s == .stretch { RoundedRectangle(cornerRadius: 12).stroke(Color.paper, lineWidth: 2).padding(3) } }
                }
            }
            HStack(spacing: 16) {
                Label("Goal", systemImage: "square.fill"); Label("Short", systemImage: "square.fill").foregroundStyle(Color.dim)
            }
            .font(.caption)
        }
        .padding(DS.pad)
    }
}
