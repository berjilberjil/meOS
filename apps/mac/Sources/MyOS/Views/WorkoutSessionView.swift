import SwiftUI

/// Reps as typed: empty is zero, and bounded so `Int(_:)` can never trap.
extension SetRow {
    static func wholeReps(_ s: String) -> Int {
        let t = s.trimmingCharacters(in: .whitespaces).filter(\.isNumber)
        guard !t.isEmpty, let n = Int(t) else { return 0 }
        return min(max(n, 0), 10_000)
    }
}

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
                                .font(.footnote).foregroundStyle(Palette.faint)
                        }
                    }
                    // Keyed by muscle group, not position: groups come and go as
                    // exercises are added, and an index id would remount every
                    // card below the insertion and lose their in-flight state.
                    ForEach(Array(sections.enumerated()), id: \.element.0) { _, section in
                        VStack(alignment: .leading, spacing: Gap.tight) {
                            HStack(spacing: 8) {
                                Circle().fill(section.group.tint).frame(width: 7, height: 7)
                                Text(section.group.label.uppercased())
                                    .font(.caption2.weight(.heavy)).tracking(0.7)
                                    .foregroundStyle(section.group.tint)
                            }
                            .padding(.top, 4)
                            ForEach(section.entries) { entry in
                                SessionExerciseCard(date: date, entry: entry)
                            }
                        }
                    }
                    Button { adding = true } label: { Label("Add an exercise today", systemImage: "plus") }
                        .buttonStyle(.bordered).controlSize(.large).frame(maxWidth: .infinity)
                    Text("Anything you change here is today's log only — your program keeps its shape.")
                        .font(.caption2).foregroundStyle(Palette.faint)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 20)
            }
            footer
        }
        #if os(macOS)
        .frame(width: 560)
        .frame(minHeight: 620)
        .background(Palette.background)
        #else
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Palette.background)
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
                        .font(.title2.weight(.semibold)).foregroundStyle(Palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle).font(.caption).foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 4)
                Menu {
                    Button("Mark done as planned") { state.markWorkoutDone(date: date); dismiss() }
                    Button("Start over") { state.resetSession(date: date) }
                    Button("Skip this workout", role: .destructive) {
                        state.skipWorkout(date: date); dismiss()
                    }
                } label: {
                    Image(systemName: "ellipsis").font(.footnote.weight(.bold)).foregroundStyle(Palette.faint)
                        .frame(width: 30, height: 30).contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 30)
                Button { dismiss() } label: { Image(systemName: "xmark").font(.footnote.weight(.bold)) }
                    .buttonStyle(.borderless)
            }
            if totalSets > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("\(doneSets) of \(totalSets) sets")
                            .font(.caption.weight(.semibold)).monospacedDigit()
                            .foregroundStyle(Palette.muted)
                        Spacer()
                        if volume > 0 {
                            Text("\(Int(volume.rounded())) kg volume")
                                .font(.caption.weight(.semibold)).monospacedDigit()
                                .foregroundStyle(Palette.faint)
                        }
                    }
                    ProgressView(value: Double(doneSets) / Double(max(1, totalSets))).progressViewStyle(.linear).tint(Palette.action)
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
                .font(.caption2).foregroundStyle(Palette.faint)
        }
        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 20)
        .background(Palette.background)
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
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.text)
                            .fixedSize(horizontal: false, vertical: true)
                        if let p = previous, let top = p.entry.topWeight {
                            Text("Last time \(Fmt.trimKg(top)) kg · \(Fmt.day(p.date))")
                                .font(.caption2).foregroundStyle(Palette.faint)
                        } else if let n = entry.note, !n.isEmpty {
                            Text(n).font(.caption2).foregroundStyle(Palette.faint).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 4)
                    Menu {
                        Button("Add a set") { state.addSet(date: date, entryId: entry.id) }
                        Button("Remove this exercise", role: .destructive) { showDelete = true }
                    } label: {
                        Image(systemName: "ellipsis").font(.footnote.weight(.bold)).foregroundStyle(Palette.faint)
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
                    Label("Add set", systemImage: "plus").font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderless).tint(entry.group.tint)
            }
        }
        .onAppear {
            if previous == nil {
                previous = state.history(ofExercise: entry.exerciseId, limit: 2, before: date).first
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
                .font(.caption2.weight(.heavy)).tracking(0.5)
                .foregroundStyle(Palette.faint)
                .frame(width: 42, alignment: .leading)

            if weighted {
                numberField(text: $weight, field: .weight, unit: "kg", width: 62) {
                    state.updateSet(date: date, entryId: entryId, setId: set.id) {
                        $0.weightKg = Double(weight.trimmingCharacters(in: .whitespaces))
                    }
                }
            }
            Text("×").font(.caption.weight(.bold)).foregroundStyle(Palette.faint)
            numberField(text: $reps, field: .reps, unit: "reps", width: 52) {
                state.updateSet(date: date, entryId: entryId, setId: set.id) {
                    // Empty means zero, not "keep what was there". `?? $0.reps`
                    // left the previous number in the record while the box showed
                    // the "—" prompt, and the next render put that number back
                    // into the box — so a set you had cleared was logged at its
                    // old count. The weight field beside it already clears to nil.
                    $0.reps = Self.wholeReps(reps)
                }
            }

            Spacer(minLength: 4)

            Button {
                Haptics.selection()
                state.updateSet(date: date, entryId: entryId, setId: set.id) { s in
                    // Ticking commits whatever is typed, so a set is never
                    // marked done with a stale number behind it.
                    if weighted { s.weightKg = Double(weight.trimmingCharacters(in: .whitespaces)) }
                    s.reps = Self.wholeReps(reps)
                    s.done.toggle()
                }
            } label: {
                Image(systemName: set.done ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(set.done ? Palette.green : Palette.faint)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(set.done ? "Set \(index + 1) done" : "Mark set \(index + 1) done")

            Button { state.removeSet(date: date, entryId: entryId, setId: set.id) } label: {
                Image(systemName: "xmark").font(.caption2.weight(.bold))
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 5).padding(.horizontal, 8)
        .background(set.done ? Palette.green.opacity(0.10) : Palette.surfaceElevated.opacity(0.4),
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
                .font(.subheadline.weight(.bold)).monospacedDigit()
                .foregroundStyle(Palette.text)
                .frame(width: width)
                .focused($focus, equals: field)
                .onSubmit(commit)
                .onChange(of: text.wrappedValue) { _ in commit() }
                #if os(iOS)
                .keyboardType(field == .weight ? .decimalPad : .numberPad)
                #endif
            Text(unit).font(.caption2).foregroundStyle(Palette.faint)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(Palette.background, in: RoundedRectangle(cornerRadius: Radius.xs, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
            .strokeBorder(focus == field ? Palette.action : Palette.border, lineWidth: 1.5))
    }
}
