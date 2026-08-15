import SwiftUI

// Reusable editor blocks shared by the primary tabs and Settings, so a value
// edited in either place writes the same underlying state and stays in sync.

// MARK: - Fitness profile editor

/// Goal + targets. Height writes `Profile.heightCm` (identical to the Profile
/// tab); the rest writes `fitnessProfile`. Used in the Fitness tab and Settings.
struct FitnessProfileEditor: View {
    @EnvironmentObject var state: AppState
    private let cols = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    KFieldLabel(text: "Goal")
                    Segmented(options: FitnessGoal.allCases.map { ($0, $0.label) },
                              selection: Binding(get: { state.fitnessProfile.goal },
                                                 set: { g in state.updateFitnessProfile { $0.goal = g } }))
                }
                VStack(alignment: .leading, spacing: 6) {
                    KFieldLabel(text: "Sex")
                    Segmented(options: Sex.allCases.map { ($0, $0.label) },
                              selection: Binding(get: { state.fitnessProfile.sex },
                                                 set: { s in state.updateFitnessProfile { $0.sex = s } }))
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                KFieldLabel(text: "Activity")
                activityMenu
            }
            LazyVGrid(columns: cols, spacing: 12) {
                KLabeledNumberField(label: "Height (cm)", placeholder: "172", decimals: 0,
                    value: Binding(get: { state.profile.heightCm },
                                   set: { v in state.updateProfile { $0.heightCm = v } }))
                KLabeledNumberField(label: "Target weight (kg)", placeholder: "72", decimals: 1,
                    value: Binding(get: { state.fitnessProfile.targetWeightKg },
                                   set: { v in state.updateFitnessProfile { $0.targetWeightKg = v } }))
                KLabeledNumberField(label: "Calorie target", placeholder: "2200", decimals: 0,
                    value: Binding(get: { state.fitnessProfile.calorieTargetKcal },
                                   set: { v in state.updateFitnessProfile { $0.calorieTargetKcal = v } }))
                KLabeledNumberField(label: "Protein target (g)", placeholder: "140", decimals: 0,
                    value: Binding(get: { state.fitnessProfile.proteinTargetG },
                                   set: { v in state.updateFitnessProfile { $0.proteinTargetG = v } }))
                KLabeledNumberField(label: "Water target (L)", placeholder: "3", decimals: 2,
                    value: Binding(get: { state.fitnessProfile.waterTargetMl.map { $0 / 1000 } },
                                   set: { v in state.updateFitnessProfile { $0.waterTargetMl = v.map { $0 * 1000 } } }))
            }
        }
    }

    private var activityMenu: some View {
        Menu {
            ForEach(ActivityLevel.allCases, id: \.self) { a in
                Button { state.updateFitnessProfile { $0.activity = a } } label: {
                    Text("\(a.label) — \(a.hint)")
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(state.fitnessProfile.activity.label)
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.text)
                Text("· \(state.fitnessProfile.activity.hint)")
                    .font(.system(size: 11)).foregroundStyle(Palette.faint)
                Spacer()
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(Palette.faint)
            }
            .padding(.horizontal, 13).padding(.vertical, 10)
            .background(Palette.bg, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Palette.border, lineWidth: 2))
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden)
    }
}

// MARK: - Journal presets editor (manage the quick-add chips)

/// Edit the six journal preset sets. Each section shows its chips (removable)
/// plus an add field. Writes `journalPresets`.
struct JournalPresetsEditor: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            section("Morning reflection", Palette.amber, \.morning)
            section("Night reflection", Palette.blue, \.night)
            section("Wins", Palette.green, \.wins)
            section("Mistakes", Palette.red, \.mistakes)
            section("Lessons", Palette.blue, \.lessons)
            section("Gratitude", Palette.purple, \.gratitude)
        }
    }

    private func section(_ title: String, _ tint: Color,
                         _ kp: WritableKeyPath<JournalPresets, [String]>) -> some View {
        JournalPresetSection(
            title: title, tint: tint, items: state.journalPresets[keyPath: kp],
            add: { s in state.updateJournalPresets { $0[keyPath: kp].append(s) } },
            remove: { i in state.updateJournalPresets { $0[keyPath: kp].remove(at: i) } })
    }
}

/// One preset section — removable chips + an add field (add-on-blur too).
private struct JournalPresetSection: View {
    let title: String
    let tint: Color
    let items: [String]
    let add: (String) -> Void
    let remove: (Int) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Circle().fill(tint).frame(width: 7, height: 7)
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.text)
            }
            if !items.isEmpty {
                FlowLayout(spacing: 7, runSpacing: 7) {
                    ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                        RemovableChip(text: item, tint: tint) { remove(i) }
                    }
                }
            }
            HStack(spacing: 8) {
                TextField("", text: $text,
                          prompt: Text("Add a chip…").foregroundColor(Palette.faint))
                    .textFieldStyle(.plain).font(.system(size: 13)).foregroundStyle(Palette.text)
                    .focused($focused)
                    .onSubmit(commit)
                Button(action: commit) {
                    Image(systemName: "plus.circle.fill").font(.system(size: 16)).foregroundStyle(tint)
                }
                .buttonStyle(KPressStyle())
                .opacity(text.isEmpty ? 0.35 : 1)
                .disabled(text.isEmpty)
            }
            .knField(focused: focused)
            .onChange(of: focused) { _, now in if !now { commit() } }
            .onDisappear { commit() }
        }
    }

    private func commit() {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        add(t); text = ""
    }
}
