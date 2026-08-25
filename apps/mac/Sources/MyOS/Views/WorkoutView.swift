import SwiftUI

/// The exercise Library — browse every exercise (seed + custom), filter by
/// category, watch the demo GIF, and add/edit custom exercises. Planning a day
/// happens in the weekly planner; this is the "show all / add new" surface.
struct WorkoutLibrarySection: View {
    @EnvironmentObject var state: AppState
    @State private var newExercise = false
    @State private var detail: Exercise?
    @State private var libQuery = ""
    /// Filed by muscle group now — "Arms" was one shelf holding both the curls
    /// and the pushdowns, which is not how anyone looks for an exercise.
    @State private var libGroup: MuscleGroup?
    @FocusState private var libSearchFocused: Bool

    private var libResults: [Exercise] {
        let q = libQuery.lowercased().trimmingCharacters(in: .whitespaces)
        return state.allExercises.filter { ex in
            (libGroup == nil || ex.group == libGroup) &&
            (q.isEmpty || ex.name.lowercased().contains(q) || ex.primary.lowercased().contains(q))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Palette.faint)
                    TextField("", text: $libQuery, prompt: Text("Search all exercises…").foregroundColor(Palette.faint))
                        .textFieldStyle(.plain).foregroundStyle(Palette.text).focused($libSearchFocused)
                }
                .knField(focused: libSearchFocused)
                Button { newExercise = true } label: { Label("New", systemImage: "plus") }
                    .buttonStyle(.borderless)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    libGroupChip(nil, "All")
                    ForEach(MuscleGroup.allCases) { g in libGroupChip(g, g.label) }
                }
                .padding(.vertical, 1)
            }
            ForEach(MuscleGroup.allCases.sorted { $0.sortRank < $1.sortRank }) { grp in
                let items = libResults.filter { $0.group == grp }
                if !items.isEmpty {
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Circle().fill(grp.tint).frame(width: 7, height: 7)
                                SectionTitle(text: "\(grp.label) · \(items.count)")
                            }
                            ForEach(items) { ex in libRow(ex) }
                        }
                    }
                }
            }
            if libResults.isEmpty {
                Card { Text("No exercises match.").font(.footnote).foregroundStyle(Palette.faint) }
            }
        }
        .sheet(isPresented: $newExercise) { ExerciseEditor(exercise: nil) }
        .sheet(item: $detail) { ex in ExerciseDetailSheet(exercise: ex) }
    }

    private func libGroupChip(_ g: MuscleGroup?, _ label: String) -> some View {
        let on = libGroup == g
        let tint = g?.tint ?? Palette.action
        return Button { libGroup = g } label: {
            Text(label).font(.caption.weight(.heavy))
                .foregroundStyle(on ? .white : Palette.muted)
                .padding(.horizontal, 11).padding(.vertical, 6)
                .background(on ? tint : Palette.surfaceElevated.opacity(0.6), in: Capsule())
        }
        .buttonStyle(.plain)
        .onHover { h in cursor(h) }
    }

    private func libRow(_ ex: Exercise) -> some View {
        HStack(spacing: 11) {
            ExerciseIcon(category: ex.category, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(ex.name).font(.footnote.weight(.semibold)).foregroundStyle(Palette.text).lineLimit(1)
                Text("\(ex.equipment) · \(ex.primary.isEmpty ? ex.group.label : ex.primary)")
                    .font(.caption2).foregroundStyle(Palette.faint).lineLimit(1)
            }
            Spacer(minLength: 6)
            if ex.gifId != nil {
                Image(systemName: "play.circle.fill").font(.footnote).foregroundStyle(Palette.blue)
            }
            if !ex.isDefault { Text("custom").font(.caption2.weight(.semibold)).foregroundStyle(Palette.faint) }
        }
        .padding(.vertical, 3)
        .frame(minHeight: 44)          // still a comfortable tap target
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
        case .chest: return Palette.warning
        case .back: return Palette.blue
        case .shoulders: return Palette.attention
        case .arms: return Palette.information
        case .legs: return Palette.green
        case .core: return Palette.attention
        case .cardio: return Palette.activity
        case .boxing: return Palette.warning
        }
    }
}

// MARK: - Exercise picker

struct ExercisePickerSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    /// Opened from a muscle-group block: start on that group's exercises so
    /// picking a chest variation is one tap, not a search.
    var group: MuscleGroup? = nil
    var title: String = "Add exercise"
    let add: (Exercise) -> Void
    let newCustom: () -> Void
    @State private var query = ""
    @State private var group2: MuscleGroup?
    @State private var didSeed = false
    @FocusState private var searchFocused: Bool

    private var results: [Exercise] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return state.allExercises.filter { ex in
            (group2 == nil || ex.group == group2) &&
            (q.isEmpty || ex.name.lowercased().contains(q) || ex.primary.lowercased().contains(q))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title).font(.body.weight(.heavy)).foregroundStyle(Palette.text)
                Spacer()
                Button { dismiss(); newCustom() } label: { Label("New", systemImage: "plus") }
                    .buttonStyle(.borderless)
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
                    groupChip(nil, "All")
                    ForEach(MuscleGroup.allCases) { g in groupChip(g, g.label) }
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
            }
            Divider().overlay(Palette.border)
            ScrollView {
                VStack(spacing: 6) {
                    if results.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group2 == nil ? "Nothing matches." : "No \(group2!.label.lowercased()) exercises yet.")
                                .font(.footnote.weight(.semibold)).foregroundStyle(Palette.text)
                            Text("Clear the filter to see everything, or add your own with New.")
                                .font(.caption).foregroundStyle(Palette.muted)
                                .fixedSize(horizontal: false, vertical: true)
                            if group2 != nil {
                                Button { group2 = nil } label: { Label("Show all exercises", systemImage: "line.3.horizontal.decrease") }
                                    .buttonStyle(.bordered)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 20)
                    }
                    ForEach(results) { ex in
                        Button { add(ex); dismiss() } label: {
                            HStack(spacing: 10) {
                                ExerciseIcon(category: ex.category, size: 30)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(ex.name).font(.footnote.weight(.semibold)).foregroundStyle(Palette.text)
                                    Text("\(ex.group.label) · \(ex.equipment)").font(.caption2).foregroundStyle(Palette.faint)
                                }
                                Spacer()
                                if ex.gifId != nil {
                                    Image(systemName: "play.circle.fill").font(.footnote).foregroundStyle(Palette.blue)
                                }
                                if !ex.isDefault { Text("custom").font(.caption2.weight(.semibold)).foregroundStyle(Palette.faint) }
                                Image(systemName: "plus.circle.fill").font(.callout).foregroundStyle(Palette.action)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 7).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .onHover { h in cursor(h) }
                    }
                }
                .padding(16)
            }
            .frame(maxHeight: 400)
        }
        #if os(macOS)
        .frame(width: 480)
        #else
        .frame(maxWidth: .infinity)
        #endif
        .background(Palette.elevated)
        .onAppear { if !didSeed { group2 = group; didSeed = true } }
    }

    private func groupChip(_ g: MuscleGroup?, _ label: String) -> some View {
        let on = group2 == g
        let tint = g?.tint ?? Palette.action
        return Button { group2 = g } label: {
            Text(label).font(.caption.weight(.heavy))
                .foregroundStyle(on ? .white : Palette.muted)
                .padding(.horizontal, 11).padding(.vertical, 6)
                .background(on ? tint : Palette.surfaceElevated.opacity(0.6), in: Capsule())
        }
        .buttonStyle(.plain)
        .onHover { h in cursor(h) }
    }
}

// MARK: - Custom exercise editor

struct ExerciseEditor: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let exercise: Exercise?
    @State private var draft: Exercise
    @State private var showDelete = false

    init(exercise: Exercise?) {
        self.exercise = exercise
        _draft = State(initialValue: exercise ?? Exercise(name: "", category: .chest, equipment: "Barbell",
                                                         primary: "", muscleGroup: .chest))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(exercise == nil ? "New exercise" : "Edit exercise")
                .font(.body.weight(.heavy)).foregroundStyle(Palette.text)
            KLabeledField(label: "Name", placeholder: "e.g. Incline dumbbell press", text: $draft.name)
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    KFieldLabel(text: "Muscle group")
                    Menu {
                        ForEach(MuscleGroup.allCases) { g in
                            Button(g.label) { draft.muscleGroup = g; draft.category = g.category }
                        }
                    } label: { menuLabel(draft.group.label) }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden)
                }
                KLabeledField(label: "Equipment", placeholder: "Barbell / Dumbbell / …", text: $draft.equipment)
            }
            KLabeledField(label: "Primary muscle", placeholder: "e.g. Upper chest", text: $draft.primary)
            KLabeledField(label: "Demo GIF id (optional)", placeholder: "ExerciseDB id, e.g. EIeI8Vf",
                          text: Binding(get: { draft.gifId ?? "" }, set: { draft.gifId = $0.isEmpty ? nil : $0 }))
            HStack {
                if let exercise, !exercise.isDefault {
                    Button("Delete") { showDelete = true }
                        .buttonStyle(.borderless).tint(Palette.warning)
                        .holdToDelete(isPresented: $showDelete, title: "Delete \(exercise.name)?",
                                      message: "Removes it from your exercise library.") {
                            state.deleteExercise(exercise.id); dismiss()
                        }
                }
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.borderless)
                Button("Save") {
                    if exercise == nil { state.addExercise(draft) } else { state.updateExercise(draft) }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        #if os(macOS)
        .frame(width: 460)
        #else
        .frame(maxWidth: .infinity)
        #endif
        .background(Palette.elevated)
    }

    private func menuLabel(_ text: String) -> some View {
        HStack { Text(text).foregroundStyle(Palette.text)
            Spacer(); Image(systemName: "chevron.down").font(.caption2.weight(.bold)).foregroundStyle(Palette.faint) }
        .font(.footnote.weight(.semibold))
        .padding(.horizontal, 13).padding(.vertical, 10)
        .background(Palette.background, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
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
                    Text(exercise.name).font(.body.weight(.heavy)).foregroundStyle(Palette.text)
                    Text("\(exercise.category.label) · \(exercise.equipment) · \(exercise.primary)")
                        .font(.caption).foregroundStyle(Palette.muted)
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").font(.footnote.weight(.bold)) }
                    .buttonStyle(.borderless)
            }

            #if os(macOS)
            HStack(alignment: .top, spacing: 16) {
                demoView.frame(width: 240, height: 240)
                musclesPanel.frame(maxWidth: .infinity, alignment: .leading)
            }
            #else
            VStack(alignment: .leading, spacing: 16) {
                demoView.frame(height: 240).frame(maxWidth: .infinity)
                musclesPanel.frame(maxWidth: .infinity, alignment: .leading)
            }
            #endif
        }
        .padding(20)
        #if os(macOS)
        .frame(width: 560)
        #else
        .frame(maxWidth: .infinity)
        #endif
        .background(Palette.elevated)
    }

    private var demoView: some View {
        Group {
            if let url = exercise.gifURL {
                GIFView(url: url)
            } else {
                ZStack { Palette.surfaceElevated.opacity(0.5)
                    VStack(spacing: 8) {
                        ExerciseIcon(category: exercise.category, size: 54)
                        Text("No demo").font(.caption2).foregroundStyle(Palette.faint)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(Palette.border, lineWidth: 2))
    }

    private var musclesPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            KFieldLabel(text: "Muscles worked")
            if exercise.muscles.isEmpty {
                Text("—").font(.footnote).foregroundStyle(Palette.faint)
            } else {
                MiniBody(slugs: exercise.muscles).frame(height: 200)
                FlowLayout(spacing: 6, runSpacing: 6) {
                    ForEach(exercise.muscles, id: \.self) { slug in
                        Text(MuscleSlug.name(slug))
                            .font(.caption2.weight(.semibold)).foregroundStyle(Palette.text)
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(Palette.action.opacity(0.15), in: Capsule())
                    }
                }
            }
        }
    }
}
