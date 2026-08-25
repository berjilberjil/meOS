import SwiftUI

// A workout day: muscle groups down the page, exercise variations inside each.
// Everything is edited in place — changing an exercise or its sets never opens
// a stack of screens.

// MARK: - Muscle group presentation

extension MuscleGroup {
    var tint: Color {
        switch self {
        case .chest: return Palette.red
        case .back: return Palette.blue
        case .shoulders: return Palette.amber
        case .biceps: return Palette.purple
        case .triceps: return Palette.coral
        case .forearms: return Palette.gold
        case .quads: return Palette.green
        case .hamstrings: return Palette.teal
        case .glutes: return Palette.rose
        case .calves: return Palette.ice
        case .abs: return Palette.flame
        case .cardio: return Palette.flame
        case .fullBody: return Palette.brand
        }
    }
    var icon: String {
        switch self {
        case .chest: return "figure.strengthtraining.traditional"
        case .back: return "figure.rower"
        case .shoulders: return "figure.arms.open"
        case .biceps, .triceps, .forearms: return "dumbbell.fill"
        case .quads, .hamstrings, .glutes, .calves: return "figure.walk"
        case .abs: return "figure.core.training"
        case .cardio: return "figure.run"
        case .fullBody: return "figure.mixed.cardio"
        }
    }
}

/// The coloured muscle indicator used everywhere a group is named.
struct MuscleChip: View {
    let group: MuscleGroup
    var compact = false
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(group.tint).frame(width: 6, height: 6)
            Text(group.label)
                .font(.system(size: compact ? 10 : 11, weight: .heavy, design: .rounded))
                .foregroundStyle(compact ? Palette.muted : group.tint)
                .lineLimit(1)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(group.tint.opacity(compact ? 0.10 : 0.14), in: Capsule())
    }
}

// MARK: - The day

struct ProgramDayEditorView: View {
    @EnvironmentObject var state: AppState
    let programId: String
    let dayId: String
    let back: () -> Void

    @State private var addingGroup = false
    @State private var settings = false
    /// Which block the exercise picker is filling.
    @State private var pickingInto: ProgramMuscleBlock?
    /// Which slot "Change exercise" is replacing.
    @State private var replacing: ReplaceTarget?
    @State private var newExercise = false

    struct ReplaceTarget: Identifiable, Hashable {
        let blockId: String
        let itemId: String
        let group: MuscleGroup
        var id: String { itemId }
    }

    private var program: WorkoutProgram? { state.program(programId) }
    private var day: ProgramDay? { program?.days.first { $0.id == dayId } }

    var body: some View {
        VStack(alignment: .leading, spacing: Gap.screen) {
            if let p = program, let d = day {
                BackBar(title: p.name, action: back).knRise(0)
                header(p, d).knRise(1)
                if d.isRestDay {
                    restCard(d).knRise(2)
                } else {
                    blocks(d).knRise(2)
                }
            }
        }
        .sheet(isPresented: $settings) {
            if let d = day { DaySettingsSheet(programId: programId, day: d) }
        }
        .sheet(isPresented: $addingGroup) {
            MuscleGroupPickerSheet(taken: day?.blocks.map(\.group) ?? []) { g in
                state.addBlock(programId, dayId, group: g)
            }
        }
        .sheet(item: $pickingInto) { block in
            ExercisePickerSheet(group: block.group,
                                add: { ex in
                                    state.addProgramExercise(programId, dayId, block.id, exerciseId: ex.id)
                                },
                                newCustom: { newExercise = true })
        }
        .sheet(item: $replacing) { target in
            ExercisePickerSheet(group: target.group, title: "Change exercise",
                                add: { ex in
                                    state.replaceProgramExercise(programId, dayId, target.blockId,
                                                                 itemId: target.itemId, with: ex.id)
                                },
                                newCustom: { newExercise = true })
        }
        .sheet(isPresented: $newExercise) { ExerciseEditor(exercise: nil) }
    }

    // MARK: Header

    private func header(_ p: WorkoutProgram, _ d: ProgramDay) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(d.name)
                    .font(.title.weight(.semibold)).foregroundStyle(Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button { settings = true } label: {
                    Image(systemName: "slider.horizontal.3").font(.footnote.weight(.bold))
                }
                .buttonStyle(.borderless)
                .help("Rename, schedule or make it a rest day")
            }
            Text(subtitle(d)).font(.footnote).foregroundStyle(Palette.faint)
            if !d.isRestDay && !d.groups.isEmpty {
                FlowLayout(spacing: 6, runSpacing: 6) {
                    ForEach(d.groups, id: \.self) { g in MuscleChip(group: g) }
                }
            }
        }
    }

    private func subtitle(_ d: ProgramDay) -> String {
        var bits: [String] = []
        if let wd = d.weekday { bits.append(ProgramMigration.weekdayNames[wd]) }
        if d.isRestDay { bits.append("Rest day") }
        else { bits.append("\(d.exerciseCount) exercise\(d.exerciseCount == 1 ? "" : "s")") }
        return bits.joined(separator: " · ")
    }

    private func restCard(_ d: ProgramDay) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Label("Rest day", systemImage: "moon.zzz.fill")
                    .font(.callout.weight(.semibold)).foregroundStyle(Palette.blue)
                Text("Nothing scheduled. Turn it back into a training day whenever you want — anything you had planned is still here.")
                    .font(.footnote).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Button { state.setDayRest(programId, dayId, false) } label: {
                    Label("Make it a training day", systemImage: "figure.strengthtraining.traditional")
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: Muscle groups

    private func blocks(_ d: ProgramDay) -> some View {
        VStack(alignment: .leading, spacing: Gap.row) {
            if d.blocks.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Which muscles does this day train?")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.text)
                        Text("Add a muscle group, then pick the exercises you use for it on this day. Another day can train the same muscle with completely different exercises.")
                            .font(.footnote).foregroundStyle(Palette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            ForEach(Array(d.blocks.enumerated()), id: \.element.id) { i, block in
                MuscleBlockSection(programId: programId, dayId: dayId, block: block,
                                   index: i, count: d.blocks.count,
                                   addExercise: { pickingInto = block },
                                   replace: { itemId in
                                       replacing = ReplaceTarget(blockId: block.id, itemId: itemId, group: block.group)
                                   })
            }
            Button { addingGroup = true } label: { Label("Add muscle group", systemImage: "plus") }
                .buttonStyle(.bordered).controlSize(.large).frame(maxWidth: .infinity)
        }
    }
}

// MARK: - One muscle group and its exercises

private struct MuscleBlockSection: View {
    @EnvironmentObject var state: AppState
    let programId: String
    let dayId: String
    let block: ProgramMuscleBlock
    let index: Int
    let count: Int
    let addExercise: () -> Void
    let replace: (String) -> Void
    @State private var showDelete = false

    var body: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                header
                if block.items.isEmpty {
                    Text("No exercises yet.").font(.caption).foregroundStyle(Palette.faint)
                } else {
                    VStack(spacing: Gap.tight) {
                        ForEach(Array(block.items.enumerated()), id: \.element.id) { i, item in
                            ProgramExerciseRow(programId: programId, dayId: dayId, blockId: block.id,
                                               item: item, index: i, count: block.items.count,
                                               tint: block.group.tint,
                                               replace: { replace(item.id) })
                        }
                    }
                }
                Button(action: addExercise) { Label("Add exercise", systemImage: "plus") }
                    .buttonStyle(.borderless).tint(block.group.tint)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: block.group.icon)
                .font(.footnote.weight(.bold)).foregroundStyle(block.group.tint)
                .frame(width: 28, height: 28)
                .background(block.group.tint.opacity(0.15),
                            in: RoundedRectangle(cornerRadius: Radius.xs, style: .continuous))
            Text(block.group.label.uppercased())
                .font(.caption.weight(.heavy)).tracking(0.7)
                .foregroundStyle(block.group.tint)
            Spacer(minLength: 4)
            Text("\(block.items.count)")
                .font(.caption2.weight(.heavy)).monospacedDigit()
                .foregroundStyle(Palette.faint)
            Menu {
                Button("Move up") { move(-1) }.disabled(index == 0)
                Button("Move down") { move(1) }.disabled(index >= count - 1)
                Divider()
                Button("Remove muscle group", role: .destructive) { showDelete = true }
            } label: {
                Image(systemName: "ellipsis").font(.caption.weight(.bold)).foregroundStyle(Palette.faint)
                    .frame(width: 26, height: 26).contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 26)
            .holdToDelete(isPresented: $showDelete, title: "Remove \(block.group.label)?",
                          message: "Takes the group and its \(block.items.count) exercise\(block.items.count == 1 ? "" : "s") off this day.",
                          confirmLabel: "Hold to remove") {
                state.removeBlock(programId, dayId, block.id)
            }
        }
    }

    private func move(_ delta: Int) {
        guard let to = AppState.moveOffset(from: index, delta: delta, count: count) else { return }
        state.moveBlocks(programId, dayId, from: IndexSet(integer: index), to: to)
    }
}

/// An exercise slot. Collapsed it reads "4 × 6 · 90s rest"; tapping opens the
/// sets/reps/rest controls and the change/duplicate/remove actions in place —
/// no sheet, no second screen.
private struct ProgramExerciseRow: View {
    @EnvironmentObject var state: AppState
    let programId: String
    let dayId: String
    let blockId: String
    let item: ProgramExercise
    let index: Int
    let count: Int
    let tint: Color
    let replace: () -> Void

    @State private var expanded = false
    @State private var showDelete = false
    @State private var note = ""

    private var exercise: Exercise? { state.exercise(item.exerciseId) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { withAnimation(.knNormal) { expanded.toggle() } } label: { summary }
                .buttonStyle(.plain)
                .onHover { h in cursor(h) }
            if expanded { controls }
        }
        .padding(11)
        .background(HueFill(level: .strong).opacity(expanded ? 0.6 : 0.35),
                    in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(expanded ? tint.opacity(0.4) : Palette.border, lineWidth: 1))
    }

    private var summary: some View {
        HStack(spacing: 10) {
            ExerciseIcon(category: exercise?.category ?? .core, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise?.name ?? "Exercise")
                    .font(.footnote.weight(.semibold)).foregroundStyle(Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail).font(.caption2).foregroundStyle(Palette.faint).lineLimit(1)
            }
            Spacer(minLength: 6)
            Text("\(item.sets) × \(item.reps)")
                .font(.footnote.weight(.heavy)).monospacedDigit()
                .foregroundStyle(Palette.muted)
            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                .font(.caption2.weight(.bold)).foregroundStyle(Palette.faint)
        }
        .contentShape(Rectangle())
    }

    private var detail: String {
        var bits: [String] = []
        if let e = exercise, !e.equipment.isEmpty { bits.append(e.equipment) }
        if item.restSec > 0 { bits.append("\(item.restSec)s rest") }
        if let n = item.note, !n.isEmpty { bits.append(n) }
        return bits.joined(separator: " · ")
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                KStepper(label: "Sets", value: item.sets, accent: tint,
                         dec: { update { $0.sets -= 1 } }, inc: { update { $0.sets += 1 } })
                KStepper(label: "Reps", value: item.reps, accent: tint,
                         dec: { update { $0.reps -= 1 } }, inc: { update { $0.reps += 1 } })
                Spacer(minLength: 0)
            }
            HStack(spacing: 14) {
                KStepper(label: "Rest (s)", value: item.restSec, accent: tint,
                         dec: { update { $0.restSec = max(0, $0.restSec - 15) } },
                         inc: { update { $0.restSec += 15 } })
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                Button(action: replace) { Label("Change exercise", systemImage: "arrow.left.arrow.right") }
                    .buttonStyle(.borderless).tint(tint)
                Menu {
                    Button("Move up") { move(-1) }.disabled(index == 0)
                    Button("Move down") { move(1) }.disabled(index >= count - 1)
                    Button("Duplicate") { state.duplicateProgramExercise(programId, dayId, blockId, itemId: item.id) }
                    Divider()
                    Button("Remove", role: .destructive) { showDelete = true }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                        .font(.footnote.weight(.semibold)).foregroundStyle(Palette.muted)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .holdToDelete(isPresented: $showDelete, title: "Remove \(exercise?.name ?? "exercise")?",
                              message: "Takes it off this day. The exercise stays in your library.",
                              confirmLabel: "Hold to remove") {
                    state.removeProgramExercise(programId, dayId, blockId, itemId: item.id)
                }
                Spacer(minLength: 0)
            }
            noteField
        }
    }

    private var noteField: some View {
        VStack(alignment: .leading, spacing: 5) {
            KFieldLabel(text: "Note")
            TextField("", text: $note, prompt: Text("e.g. pause at the bottom").foregroundColor(Palette.faint))
                .textFieldStyle(.plain).font(.footnote).foregroundStyle(Palette.text)
                .knField()
                .onAppear { note = item.note ?? "" }
                .onChange(of: note) { v in update { $0.note = v.nilIfBlank } }
        }
    }

    private func update(_ f: @escaping (inout ProgramExercise) -> Void) {
        state.updateProgramExercise(programId, dayId, blockId, itemId: item.id, f)
    }

    private func move(_ delta: Int) {
        guard let to = AppState.moveOffset(from: index, delta: delta, count: count) else { return }
        state.moveProgramExercises(programId, dayId, blockId, from: IndexSet(integer: index), to: to)
    }
}

// MARK: - Pick a muscle group

struct MuscleGroupPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let taken: [MuscleGroup]
    let pick: (MuscleGroup) -> Void

    private let cols = [GridItem(.adaptive(minimum: 130), spacing: 10)]

    var body: some View {
        SheetShell(title: "Add muscle group",
                   subtitle: "Pick what this day trains. Exercises come next.") {
            LazyVGrid(columns: cols, spacing: 10) {
                ForEach(MuscleGroup.allCases) { g in
                    let on = taken.contains(g)
                    Button {
                        pick(g); dismiss()
                    } label: {
                        HStack(spacing: 9) {
                            Image(systemName: g.icon)
                                .font(.footnote.weight(.bold)).foregroundStyle(g.tint)
                                .frame(width: 30, height: 30)
                                .background(g.tint.opacity(0.15),
                                            in: RoundedRectangle(cornerRadius: Radius.xs, style: .continuous))
                            Text(g.label)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(on ? Palette.faint : Palette.text)
                                .lineLimit(1).minimumScaleFactor(0.8)
                            Spacer(minLength: 0)
                            if on { Image(systemName: "checkmark").font(.caption2.weight(.bold)).foregroundStyle(Palette.faint) }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity)
                        .background(.hueFill, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(on ? g.tint.opacity(0.5) : Palette.border, lineWidth: 1))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { h in cursor(h) }
                }
            }
        }
    }
}

// MARK: - Day settings (name, weekday, rest)

struct DaySettingsSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let programId: String
    /// nil = creating a new day.
    let day: ProgramDay?

    @State private var name = ""
    @State private var weekday: Int? = nil
    @State private var rest = false

    private static let names = ProgramMigration.weekdayNames
    private static let letters = ["S", "M", "T", "W", "T", "F", "S"]

    var body: some View {
        SheetShell(title: day == nil ? "Add a day" : "Day settings",
                   subtitle: "Name it whatever you call it — \u{201C}Push A\u{201D}, \u{201C}Day 1\u{201D}, \u{201C}Leg day\u{201D}.") {
            VStack(alignment: .leading, spacing: 16) {
                KLabeledField(label: "Name", placeholder: "Push A", text: $name)

                VStack(alignment: .leading, spacing: 8) {
                    KFieldLabel(text: "Runs on")
                    HStack(spacing: 4) {
                        dayButton(nil, "In order")
                        ForEach(0..<7, id: \.self) { i in dayButton(i, Self.letters[i]) }
                    }
                    Text(weekday == nil
                         ? "No weekday — this day takes its turn in the rotation."
                         : "Every \(Self.names[weekday!]).")
                        .font(.caption2).foregroundStyle(Palette.faint)
                }

                Toggle(isOn: $rest) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Rest day").font(.footnote.weight(.semibold)).foregroundStyle(Palette.text)
                        Text("Keeps any exercises on it, just doesn't schedule them.")
                            .font(.caption2).foregroundStyle(Palette.faint)
                    }
                }
                .toggleStyle(.switch).tint(Palette.brand)

                HStack {
                    Spacer()
                    Button("Cancel") { dismiss() }.buttonStyle(.borderless)
                    Button(day == nil ? "Add day" : "Save", action: save)
                        .buttonStyle(.borderedProminent)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .onAppear {
            name = day?.name ?? ""
            weekday = day?.weekday
            rest = day?.isRestDay ?? false
        }
    }

    private func dayButton(_ value: Int?, _ label: String) -> some View {
        let on = weekday == value
        return Button { weekday = value } label: {
            Text(label)
                .font(.caption2.weight(.heavy))
                .foregroundStyle(on ? .white : Palette.muted)
                .lineLimit(1).minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity).padding(.vertical, 9)
                .background(on ? Palette.brand : Palette.surface2.opacity(0.6),
                            in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { h in cursor(h) }
    }

    private func save() {
        if let day {
            state.renameDay(programId, day.id, to: name)
            state.setDayWeekday(programId, day.id, weekday: weekday)
            state.setDayRest(programId, day.id, rest)
        } else {
            state.addDay(to: programId, name: name, weekday: weekday, rest: rest)
        }
        dismiss()
    }
}

// MARK: - Create / edit a program

struct ProgramEditorSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    /// nil = creating.
    let program: WorkoutProgram?
    let onCreate: (String) -> Void

    @State private var name = ""
    @State private var notes = ""
    @State private var goal = ""
    @State private var dayCount = 4
    @State private var byWeekday = true

    private var isNew: Bool { program == nil }

    var body: some View {
        SheetShell(title: isNew ? "New program" : "Edit program",
                   subtitle: isNew ? "Any split, any number of days. Nothing is fixed." : nil) {
            VStack(alignment: .leading, spacing: 16) {
                KLabeledField(label: "Name", placeholder: "Cut — PPL", text: $name)
                KLabeledField(label: "Description (optional)", placeholder: "6 days, high volume", text: $notes)
                KLabeledField(label: "Goal or type (optional)", placeholder: "Cut / Strength / Hypertrophy", text: $goal)

                if isNew {
                    VStack(alignment: .leading, spacing: 8) {
                        KFieldLabel(text: "How the week runs")
                        Picker("", selection: $byWeekday) { ForEach([(true, "By weekday"), (false, "Day 1, 2, 3…")], id: \.0) { opt in Text(opt.1).tag(opt.0) } }.pickerStyle(.segmented).labelsHidden()
                        Text(byWeekday
                             ? "Days sit on Monday–Sunday. Today reads the calendar."
                             : "Days rotate in order from today, however many there are.")
                            .font(.caption2).foregroundStyle(Palette.faint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        KFieldLabel(text: "Workout days to start with")
                        HStack(spacing: 14) {
                            KStepper(label: "Days", value: dayCount,
                                     dec: { dayCount = max(1, dayCount - 1) },
                                     inc: { dayCount = min(byWeekday ? 7 : 14, dayCount + 1) })
                            Spacer(minLength: 0)
                        }
                        Text(byWeekday
                             ? "The other \(max(0, 7 - dayCount)) day\(7 - dayCount == 1 ? "" : "s") start as rest. Add, rename or delete any of them after."
                             : "Named Day 1…Day \(dayCount). Rename them to anything.")
                            .font(.caption2).foregroundStyle(Palette.faint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack {
                    Spacer()
                    Button("Cancel") { dismiss() }.buttonStyle(.borderless)
                    Button(isNew ? "Create" : "Save", action: save)
                        .buttonStyle(.borderedProminent)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .onAppear {
            name = program?.name ?? ""
            notes = program?.notes ?? ""
            goal = program?.goal ?? ""
        }
    }

    private func save() {
        if let program {
            state.updateProgram(program.id, name: name, notes: .some(notes), goal: .some(goal))
        } else {
            let created = state.createProgram(name: name, notes: notes, goal: goal, days: startingDays())
            onCreate(created.id)
        }
        dismiss()
    }

    /// Monday-first for weekday programs — that is how a week reads, even
    /// though the calendar keys start on Sunday.
    private func startingDays() -> [ProgramDay] {
        if byWeekday {
            let order = [1, 2, 3, 4, 5, 6, 0]
            return order.enumerated().map { i, wd in
                let training = i < dayCount
                return ProgramDay(name: training ? ProgramMigration.weekdayNames[wd] : "Rest",
                                  weekday: wd, rest: !training)
            }
        }
        return (1...dayCount).map { ProgramDay(name: "Day \($0)") }
    }
}

// MARK: - Sheet chrome

/// Every sheet in this section: a title, an optional line under it, a close
/// button, and its own ScrollView + padding — iOS sheets sit outside the
/// screen container, so they get neither for free.
struct SheetShell<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.title3.weight(.semibold)).foregroundStyle(Palette.text)
                    if let subtitle {
                        Text(subtitle).font(.footnote).foregroundStyle(Palette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 4)
                Button { dismiss() } label: { Image(systemName: "xmark").font(.footnote.weight(.bold)) }
                    .buttonStyle(.borderless)
            }
            .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 14)

            ScrollView { content.padding(.horizontal, 20).padding(.bottom, 24) }
        }
        #if os(macOS)
        .frame(width: 480)
        .frame(minHeight: 380, maxHeight: 640)
        .background(Palette.elevated)
        #else
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.hueCanvas)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.hueCanvas)
        #endif
    }
}
