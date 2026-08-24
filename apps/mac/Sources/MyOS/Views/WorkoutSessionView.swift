import SwiftUI

// Logging a workout. Reads the program day, writes only history — nothing in
// here can reach back into the template, which is why you can drop a set or
// swap in an extra exercise on a bad day without breaking Monday forever.

struct WorkoutSessionView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let date: String
    @State private var adding = false
    @State private var newExercise = false

    private var log: WorkoutDayLog { state.workoutDayLog(date) }
    private var entries: [ExerciseLog] { log.entries ?? [] }
    private var title: String { log.title ?? state.programDay(for: date)?.day.name ?? "Workout" }

    /// Grouped for display, but the array order is what the user set — a group
    /// is a run of consecutive entries, not a re-sort.
    private var sections: [(group: MuscleGroup, entries: [ExerciseLog])] {
        var out: [(MuscleGroup, [ExerciseLog])] = []
        for e in entries {
            if let last = out.last, last.0 == e.group { out[out.count - 1].1.append(e) }
            else { out.append((e.group, [e])) }
        }
        return out
    }

    private var doneSets: Int { entries.reduce(0) { $0 + $1.doneSets } }
    private var totalSets: Int { entries.reduce(0) { $0 + $1.sets.count } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: Gap.row) {
                    if entries.isEmpty {
                        Card {
                            Text("Nothing to log — this day has no exercises yet.")
                                .font(.system(size: 13)).foregroundStyle(Palette.faint)
                        }
                    }
                    ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                        VStack(alignment: .leading, spacing: Gap.tight) {
                            HStack(spacing: 8) {
                                Circle().fill(section.group.tint).frame(width: 7, height: 7)
                                Text(section.group.label.uppercased())
                                    .font(.system(size: 11, weight: .heavy, design: .rounded)).tracking(0.7)
                                    .foregroundStyle(section.group.tint)
                            }
                            .padding(.top, 4)
                            ForEach(section.entries) { entry in
                                SessionExerciseCard(date: date, entry: entry)
                            }
                        }
                    }
                    Button { adding = true } label: { Label("Add an exercise today", systemImage: "plus") }
                        .buttonStyle(KSecondaryButtonStyle(fullWidth: true))
                    Text("Anything you change here is today's log only — your program keeps its shape.")
                        .font(.system(size: 11)).foregroundStyle(Palette.faint)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 20)
            }
            footer
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
        .onAppear { state.startSession(date: date) }
        .sheet(isPresented: $adding) {
            ExercisePickerSheet(add: { ex in state.addSessionExercise(date: date, exerciseId: ex.id) },
                                newCustom: { newExercise = true })
        }
        .sheet(isPresented: $newExercise) { ExerciseEditor(exercise: nil) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 24, weight: .semibold)).foregroundStyle(Palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 4)
                Menu {
                    Button("Mark done as planned") { state.markWorkoutDone(date: date); dismiss() }
                    Button("Start over") { state.resetSession(date: date) }
                    Button("Skip this workout", role: .destructive) {
                        state.skipWorkout(date: date); dismiss()
                    }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 14, weight: .bold)).foregroundStyle(Palette.faint)
                        .frame(width: 30, height: 30).contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 30)
                Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 13, weight: .bold)) }
                    .buttonStyle(KIconButtonStyle(size: 30))
            }
            if totalSets > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("\(doneSets) of \(totalSets) sets")
                            .font(.system(size: 12, weight: .semibold)).monospacedDigit()
                            .foregroundStyle(Palette.muted)
                        Spacer()
                        if volume > 0 {
                            Text("\(Int(volume.rounded())) kg volume")
                                .font(.system(size: 12, weight: .semibold)).monospacedDigit()
                                .foregroundStyle(Palette.faint)
                        }
                    }
                    MeterBar(fraction: Double(doneSets) / Double(max(1, totalSets)), tint: Palette.brand, height: 6)
                }
            }
        }
        .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 14)
        .background(Palette.elevated)
    }

    private var volume: Double { entries.reduce(0) { $0 + $1.volumeKg } }

    private var subtitle: String {
        var bits = [Fmt.day(date)]
        if let p = state.programDay(for: date)?.program { bits.append(p.name) }
        return bits.joined(separator: " · ")
    }

    private var footer: some View {
        VStack(spacing: 10) {
            SlideToConfirm(label: "Slide to finish", tint: Palette.green) {
                state.finishSession(date: date)
                dismiss()
            }
            Text(doneSets == 0 ? "Tick the sets you actually did first."
                               : "Untouched sets are dropped — history says what happened.")
                .font(.system(size: 11)).foregroundStyle(Palette.faint)
        }
        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 20)
        .background(Palette.bg)
    }
}

// MARK: - One exercise being logged

private struct SessionExerciseCard: View {
    @EnvironmentObject var state: AppState
    let date: String
    let entry: ExerciseLog
    @State private var showDelete = false

    private var exercise: Exercise? { state.exercise(entry.exerciseId) }
    /// Looked up once. `history` sorts every logged date, and this card
    /// re-renders on every character typed into a set.
    @State private var previous: (date: String, entry: ExerciseLog)?

    var body: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    ExerciseIcon(category: exercise?.category ?? .core, size: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(exercise?.name ?? "Exercise")
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
                            .fixedSize(horizontal: false, vertical: true)
                        if let p = previous, let top = p.entry.topWeight {
                            Text("Last time \(Fmt.trimKg(top)) kg · \(Fmt.day(p.date))")
                                .font(.system(size: 11)).foregroundStyle(Palette.faint)
                        } else if let n = entry.note, !n.isEmpty {
                            Text(n).font(.system(size: 11)).foregroundStyle(Palette.faint).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 4)
                    Menu {
                        Button("Add a set") { state.addSet(date: date, entryId: entry.id) }
                        Button("Remove this exercise", role: .destructive) { showDelete = true }
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.faint)
                            .frame(width: 28, height: 28).contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 28)
                    .holdToDelete(isPresented: $showDelete,
                                  title: "Drop \(exercise?.name ?? "this")?",
                                  message: "Takes it off today's log only.",
                                  confirmLabel: "Hold to drop") {
                        state.removeSessionExercise(date: date, entryId: entry.id)
                    }
                }

                VStack(spacing: 6) {
                    ForEach(Array(entry.sets.enumerated()), id: \.element.id) { i, set in
                        SetRow(date: date, entryId: entry.id, index: i, set: set,
                               weighted: exercise?.weighted ?? true)
                    }
                }

                Button { state.addSet(date: date, entryId: entry.id) } label: {
                    Label("Add set", systemImage: "plus").font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(KGhostButtonStyle(color: entry.group.tint))
            }
        }
        .onAppear {
            if previous == nil {
                previous = state.history(ofExercise: entry.exerciseId, limit: 2).first { $0.date != date }
            }
        }
    }
}

/// A single set: what you loaded, how many you got, and whether it happened.
private struct SetRow: View {
    @EnvironmentObject var state: AppState
    let date: String
    let entryId: String
    let index: Int
    let set: SetLog
    let weighted: Bool

    @State private var weight = ""
    @State private var reps = ""
    @FocusState private var focus: Field?
    private enum Field: Hashable { case weight, reps }

    var body: some View {
        HStack(spacing: 8) {
            Text("SET \(index + 1)")
                .font(.system(size: 10, weight: .heavy, design: .rounded)).tracking(0.5)
                .foregroundStyle(Palette.faint)
                .frame(width: 42, alignment: .leading)

            if weighted {
                numberField(text: $weight, field: .weight, unit: "kg", width: 62) {
                    state.updateSet(date: date, entryId: entryId, setId: set.id) {
                        $0.weightKg = Double(weight.trimmingCharacters(in: .whitespaces))
                    }
                }
            }
            Text("×").font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.faint)
            numberField(text: $reps, field: .reps, unit: "reps", width: 52) {
                state.updateSet(date: date, entryId: entryId, setId: set.id) {
                    $0.reps = Int(reps.trimmingCharacters(in: .whitespaces)) ?? $0.reps
                }
            }

            Spacer(minLength: 4)

            Button {
                Haptics.selection()
                state.updateSet(date: date, entryId: entryId, setId: set.id) { s in
                    // Ticking commits whatever is typed, so a set is never
                    // marked done with a stale number behind it.
                    if weighted { s.weightKg = Double(weight.trimmingCharacters(in: .whitespaces)) }
                    s.reps = Int(reps.trimmingCharacters(in: .whitespaces)) ?? s.reps
                    s.done.toggle()
                }
            } label: {
                Image(systemName: set.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(set.done ? Palette.green : Palette.faint)
            }
            .buttonStyle(KPressStyle(scale: 0.88))
            .accessibilityLabel(set.done ? "Set \(index + 1) done" : "Mark set \(index + 1) done")

            Button { state.removeSet(date: date, entryId: entryId, setId: set.id) } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(KIconButtonStyle(size: 22))
        }
        .padding(.vertical, 5).padding(.horizontal, 8)
        .background(set.done ? Palette.green.opacity(0.10) : Palette.surface2.opacity(0.4),
                    in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        .onAppear {
            weight = set.weightKg.map { Fmt.trimKg($0) } ?? ""
            reps = set.reps > 0 ? "\(set.reps)" : ""
        }
    }

    private func numberField(text: Binding<String>, field: Field, unit: String,
                             width: CGFloat, commit: @escaping () -> Void) -> some View {
        HStack(spacing: 3) {
            TextField("", text: text, prompt: Text("—").foregroundColor(Palette.faint))
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .bold, design: .rounded)).monospacedDigit()
                .foregroundStyle(Palette.text)
                .frame(width: width)
                .focused($focus, equals: field)
                .onSubmit(commit)
                .onChange(of: text.wrappedValue) { _ in commit() }
                #if os(iOS)
                .keyboardType(field == .weight ? .decimalPad : .numberPad)
                #endif
            Text(unit).font(.system(size: 10)).foregroundStyle(Palette.faint)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(Palette.bg, in: RoundedRectangle(cornerRadius: Radius.xs, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
            .strokeBorder(focus == field ? Palette.brand : Palette.border, lineWidth: 1.5))
    }
}
