import SwiftUI

/// The weekly workout plan — per weekday split, exercises with sets×reps, in-app
/// GIF demos, and add/edit custom exercises. Lives in the Fitness tab's "Workout" sub.
struct WorkoutView: View {
    @EnvironmentObject var state: AppState
    @State private var weekday: String = ""
    @State private var picking = false
    @State private var newExercise = false
    @State private var detail: Exercise?

    private let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    private var plan: WorkoutDayPlan { state.workoutPlan(weekday) }
    private var isToday: Bool { weekday == state.todayWeekday }

    enum WorkoutMode: String, Hashable { case plan, exercises }
    @State private var mode: WorkoutMode = .plan
    @State private var libQuery = ""
    @State private var libCat: WorkoutCategory?
    @FocusState private var libSearchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Segmented(options: (0..<7).map { (String($0), dayNames[$0]) }, selection: $weekday)
                .knRise(0)
            Segmented(options: [(WorkoutMode.plan, "Plan"), (WorkoutMode.exercises, "All exercises")], selection: $mode)
                .knRise(1)

            if mode == .plan {
                generateRow.knRise(2)
                dayCard.knRise(3)
                HStack(spacing: 10) {
                    Button { newExercise = true } label: { Label("New exercise", systemImage: "plus") }
                        .buttonStyle(KGhostButtonStyle())
                    Spacer()
                    Menu {
                        ForEach(0..<7, id: \.self) { d in
                            if String(d) != weekday {
                                Button("Copy to \(dayNames[d])") { state.copyWorkoutDay(from: weekday, to: [String(d)]) }
                            }
                        }
                        Button("Copy to all other days") {
                            state.copyWorkoutDay(from: weekday, to: (0..<7).map(String.init))
                        }
                    } label: { Label("Copy day", systemImage: "doc.on.doc") }
                        .menuStyle(.borderlessButton)
                        .disabled(plan.items.isEmpty)
                }
                .knRise(4)
            } else {
                exerciseLibrary.knRise(2)
            }
        }
        .onAppear { if weekday.isEmpty { weekday = state.todayWeekday } }
        .sheet(isPresented: $picking) {
            ExercisePickerSheet { ex in state.addPlanExercise(weekday: weekday, exerciseId: ex.id) }
                newCustom: { newExercise = true }
        }
        .sheet(isPresented: $newExercise) { ExerciseEditor(exercise: nil) }
        .sheet(item: $detail) { ex in ExerciseDetailSheet(exercise: ex) }
    }

    private var generateRow: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "wand.and.stars").font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.brand)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Generate my week").font(.system(size: 14, weight: .heavy, design: .rounded)).foregroundStyle(Palette.text)
                        Text("AI drafts a split + meal plan from your goal — then edit it.")
                            .font(.system(size: 11)).foregroundStyle(Palette.faint)
                    }
                    Spacer()
                    Button { Task { await state.generateWeeklyPlan() } } label: {
                        HStack(spacing: 6) {
                            if state.planBusy { ProgressView().controlSize(.small).tint(.white) }
                            Text(state.planBusy ? "Building…" : "Generate")
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
                }
            }
        }
    }

    private var dayCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    HStack(spacing: 7) {
                        SectionTitle(text: fullDayName + (isToday ? " · today" : ""))
                    }
                    Spacer()
                    Toggle("Rest day", isOn: Binding(get: { plan.rest },
                                                     set: { state.setRestDay(weekday, $0) }))
                        .toggleStyle(.switch).tint(Palette.brand)
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.muted)
                }

                if plan.rest {
                    HStack(spacing: 8) {
                        Image(systemName: "moon.zzz.fill").foregroundStyle(Palette.blue)
                        Text("Rest day — recover.").font(.system(size: 13)).foregroundStyle(Palette.muted)
                    }
                    .padding(.vertical, 8)
                } else {
                    if plan.items.isEmpty {
                        Text("No exercises yet. Add some to build this day.")
                            .font(.system(size: 13)).foregroundStyle(Palette.faint)
                    }
                    ForEach(plan.items) { item in exerciseRow(item) }
                    Button { picking = true } label: { Label("Add exercise", systemImage: "plus.circle.fill") }
                        .buttonStyle(KGhostButtonStyle(color: Palette.brand))
                }
            }
        }
    }

    private func exerciseRow(_ item: PlanExercise) -> some View {
        let ex = state.exercise(item.exerciseId)
        return HStack(spacing: 11) {
            Button { if let ex { detail = ex } } label: {
                ExerciseIcon(category: ex?.category ?? .core, size: 34)
            }
            .buttonStyle(KPressStyle())
            VStack(alignment: .leading, spacing: 2) {
                Text(ex?.name ?? "Unknown").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.text).lineLimit(1)
                Text("\(ex?.category.label ?? "") · \(ex?.primary ?? "")").font(.system(size: 11)).foregroundStyle(Palette.faint).lineLimit(1)
            }
            Spacer()
            setsReps(item)
            Button { state.removePlanExercise(weekday: weekday, itemId: item.id) } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(KIconButtonStyle(size: 22))
        }
    }

    private func setsReps(_ item: PlanExercise) -> some View {
        HStack(spacing: 10) {
            stepper(value: item.sets, label: "sets",
                    dec: { state.setPlanSets(weekday: weekday, itemId: item.id, sets: item.sets - 1) },
                    inc: { state.setPlanSets(weekday: weekday, itemId: item.id, sets: item.sets + 1) })
            Text("×").font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.faint)
            stepper(value: item.reps, label: "reps",
                    dec: { state.setPlanReps(weekday: weekday, itemId: item.id, reps: item.reps - 1) },
                    inc: { state.setPlanReps(weekday: weekday, itemId: item.id, reps: item.reps + 1) })
        }
    }

    private func stepper(value: Int, label: String, dec: @escaping () -> Void, inc: @escaping () -> Void) -> some View {
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

    private var fullDayName: String {
        ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][Int(weekday) ?? 0]
    }

    // MARK: - All-exercises library (browse + add to the selected day)

    private var libResults: [Exercise] {
        let q = libQuery.lowercased().trimmingCharacters(in: .whitespaces)
        return state.allExercises.filter { ex in
            (libCat == nil || ex.category == libCat) &&
            (q.isEmpty || ex.name.lowercased().contains(q) || ex.primary.lowercased().contains(q))
        }
    }

    @ViewBuilder private var exerciseLibrary: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Palette.faint)
                    TextField("", text: $libQuery, prompt: Text("Search all exercises…").foregroundColor(Palette.faint))
                        .textFieldStyle(.plain).foregroundStyle(Palette.text).focused($libSearchFocused)
                }
                .knField(focused: libSearchFocused)
                Button { newExercise = true } label: { Label("New", systemImage: "plus") }
                    .buttonStyle(KGhostButtonStyle())
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    libCatChip(nil, "All")
                    ForEach(WorkoutCategory.allCases, id: \.self) { c in libCatChip(c, c.label) }
                }
                .padding(.vertical, 1)
            }
            Text("Tap an exercise for its demo. \"Add\" puts it on \(dayNames[Int(weekday) ?? 0]).")
                .font(.system(size: 11)).foregroundStyle(Palette.faint)

            ForEach(WorkoutCategory.allCases, id: \.self) { cat in
                let items = libResults.filter { $0.category == cat }
                if !items.isEmpty {
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionTitle(text: "\(cat.label) · \(items.count)")
                            ForEach(items) { ex in libRow(ex) }
                        }
                    }
                }
            }
            if libResults.isEmpty {
                Card { Text("No exercises match.").font(.system(size: 13)).foregroundStyle(Palette.faint) }
            }
        }
    }

    private func libCatChip(_ c: WorkoutCategory?, _ label: String) -> some View {
        let on = libCat == c
        return Button { libCat = c } label: {
            Text(label).font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(on ? .white : Palette.muted)
                .padding(.horizontal, 11).padding(.vertical, 6)
                .background(on ? Palette.brand : Palette.surface2.opacity(0.6), in: Capsule())
        }
        .buttonStyle(KPressStyle())
        .onHover { h in cursor(h) }
    }

    private func libRow(_ ex: Exercise) -> some View {
        HStack(spacing: 11) {
            ExerciseIcon(category: ex.category, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(ex.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.text).lineLimit(1)
                Text("\(ex.equipment) · \(ex.primary)").font(.system(size: 11)).foregroundStyle(Palette.faint).lineLimit(1)
            }
            Spacer(minLength: 6)
            if ex.gifId != nil {
                Image(systemName: "play.circle.fill").font(.system(size: 14)).foregroundStyle(Palette.blue)
            }
            if !ex.isDefault { Text("CUSTOM").font(.system(size: 8, weight: .heavy)).foregroundStyle(Palette.brand) }
            Button { state.addPlanExercise(weekday: weekday, exerciseId: ex.id) } label: {
                Text("Add").font(.system(size: 12, weight: .heavy, design: .rounded))
            }
            .buttonStyle(KSoftButtonStyle(tint: Palette.brand))
            .help("Add to \(dayNames[Int(weekday) ?? 0])")
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { detail = ex }
    }
}

// MARK: - Category icon

struct ExerciseIcon: View {
    let category: WorkoutCategory
    var size: CGFloat = 34
    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size * 0.44, weight: .bold)).foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }
    var icon: String {
        switch category {
        case .chest: return "figure.strengthtraining.traditional"
        case .back: return "figure.rower"
        case .shoulders: return "figure.arms.open"
        case .arms: return "dumbbell.fill"
        case .legs: return "figure.walk"
        case .core: return "figure.core.training"
        case .cardio: return "figure.run"
        case .boxing: return "figure.boxing"
        }
    }
    var color: Color {
        switch category {
        case .chest: return Palette.red
        case .back: return Palette.blue
        case .shoulders: return Palette.amber
        case .arms: return Palette.purple
        case .legs: return Palette.green
        case .core: return Palette.amber
        case .cardio: return Palette.flame
        case .boxing: return Palette.red
        }
    }
}

// MARK: - Exercise picker

struct ExercisePickerSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let add: (Exercise) -> Void
    let newCustom: () -> Void
    @State private var query = ""
    @State private var category: WorkoutCategory?
    @FocusState private var searchFocused: Bool

    private var results: [Exercise] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return state.allExercises.filter { ex in
            (category == nil || ex.category == category) &&
            (q.isEmpty || ex.name.lowercased().contains(q) || ex.primary.lowercased().contains(q))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Add exercise").font(.system(size: 17, weight: .heavy, design: .rounded)).foregroundStyle(Palette.text)
                Spacer()
                Button { dismiss(); newCustom() } label: { Label("New", systemImage: "plus") }
                    .buttonStyle(KGhostButtonStyle())
            }
            .padding(16)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Palette.faint)
                TextField("", text: $query, prompt: Text("Search exercises…").foregroundColor(Palette.faint))
                    .textFieldStyle(.plain).foregroundStyle(Palette.text).focused($searchFocused)
            }
            .knField(focused: searchFocused).padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    catChip(nil, "All")
                    ForEach(WorkoutCategory.allCases, id: \.self) { c in catChip(c, c.label) }
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
            }
            Divider().overlay(Palette.border)
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(results) { ex in
                        Button { add(ex); dismiss() } label: {
                            HStack(spacing: 10) {
                                ExerciseIcon(category: ex.category, size: 30)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(ex.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.text)
                                    Text("\(ex.category.label) · \(ex.equipment)").font(.system(size: 11)).foregroundStyle(Palette.faint)
                                }
                                Spacer()
                                if ex.gifId != nil {
                                    Image(systemName: "play.circle.fill").font(.system(size: 13)).foregroundStyle(Palette.blue)
                                }
                                if !ex.isDefault { Text("CUSTOM").font(.system(size: 8, weight: .heavy)).foregroundStyle(Palette.brand) }
                                Image(systemName: "plus.circle.fill").font(.system(size: 16)).foregroundStyle(Palette.brand)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 7).contentShape(Rectangle())
                        }
                        .buttonStyle(KPressStyle())
                        .onHover { h in cursor(h) }
                    }
                }
                .padding(16)
            }
            .frame(maxHeight: 400)
        }
        .frame(width: 480)
        .background(Palette.elevated)
    }

    private func catChip(_ c: WorkoutCategory?, _ label: String) -> some View {
        let on = category == c
        return Button { category = c } label: {
            Text(label).font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(on ? .white : Palette.muted)
                .padding(.horizontal, 11).padding(.vertical, 6)
                .background(on ? Palette.brand : Palette.surface2.opacity(0.6), in: Capsule())
        }
        .buttonStyle(KPressStyle())
        .onHover { h in cursor(h) }
    }
}

// MARK: - Custom exercise editor

struct ExerciseEditor: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let exercise: Exercise?
    @State private var draft: Exercise

    init(exercise: Exercise?) {
        self.exercise = exercise
        _draft = State(initialValue: exercise ?? Exercise(name: "", category: .chest, equipment: "Barbell", primary: ""))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(exercise == nil ? "New exercise" : "Edit exercise")
                .font(.system(size: 18, weight: .heavy, design: .rounded)).foregroundStyle(Palette.text)
            KLabeledField(label: "Name", placeholder: "e.g. Incline dumbbell press", text: $draft.name)
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    KFieldLabel(text: "Category")
                    Menu {
                        ForEach(WorkoutCategory.allCases, id: \.self) { c in Button(c.label) { draft.category = c } }
                    } label: { menuLabel(draft.category.label) }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden)
                }
                KLabeledField(label: "Equipment", placeholder: "Barbell / Dumbbell / …", text: $draft.equipment)
            }
            KLabeledField(label: "Primary muscle", placeholder: "e.g. Upper chest", text: $draft.primary)
            KLabeledField(label: "Demo GIF id (optional)", placeholder: "ExerciseDB id, e.g. EIeI8Vf",
                          text: Binding(get: { draft.gifId ?? "" }, set: { draft.gifId = $0.isEmpty ? nil : $0 }))
            HStack {
                if let exercise, !exercise.isDefault {
                    Button("Delete", role: .destructive) { state.deleteExercise(exercise.id); dismiss() }
                        .buttonStyle(KGhostButtonStyle(color: Palette.red))
                }
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(KGhostButtonStyle())
                Button("Save") {
                    if exercise == nil { state.addExercise(draft) } else { state.updateExercise(draft) }
                    dismiss()
                }
                .buttonStyle(KPrimaryButtonStyle())
                .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24).frame(width: 460)
        .background(Palette.elevated)
    }

    private func menuLabel(_ text: String) -> some View {
        HStack { Text(text).foregroundStyle(Palette.text)
            Spacer(); Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(Palette.faint) }
        .font(.system(size: 13, weight: .semibold))
        .padding(.horizontal, 13).padding(.vertical, 10)
        .background(Palette.bg, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Palette.border, lineWidth: 2))
    }
}

// MARK: - Exercise detail (GIF demo + muscles + body highlight)

struct ExerciseDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let exercise: Exercise

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.name).font(.system(size: 18, weight: .heavy, design: .rounded)).foregroundStyle(Palette.text)
                    Text("\(exercise.category.label) · \(exercise.equipment) · \(exercise.primary)")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 13, weight: .bold)) }
                    .buttonStyle(KIconButtonStyle(size: 28))
            }

            HStack(alignment: .top, spacing: 16) {
                // Demo
                Group {
                    if let url = exercise.gifURL {
                        GIFView(url: url)
                    } else {
                        ZStack { Palette.surface2.opacity(0.5)
                            VStack(spacing: 8) {
                                ExerciseIcon(category: exercise.category, size: 54)
                                Text("No demo").font(.system(size: 11)).foregroundStyle(Palette.faint)
                            }
                        }
                    }
                }
                .frame(width: 240, height: 240)
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(Palette.border, lineWidth: 2))

                // Muscles worked → body highlight
                VStack(alignment: .leading, spacing: 10) {
                    KFieldLabel(text: "Muscles worked")
                    if exercise.muscles.isEmpty {
                        Text("—").font(.system(size: 13)).foregroundStyle(Palette.faint)
                    } else {
                        MiniBody(slugs: exercise.muscles).frame(height: 200)
                        FlowLayout(spacing: 6, runSpacing: 6) {
                            ForEach(exercise.muscles, id: \.self) { slug in
                                Text(MuscleSlug.name(slug))
                                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.text)
                                    .padding(.horizontal, 9).padding(.vertical, 4)
                                    .background(Palette.brand.opacity(0.15), in: Capsule())
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20).frame(width: 560)
        .background(Palette.elevated)
    }
}
