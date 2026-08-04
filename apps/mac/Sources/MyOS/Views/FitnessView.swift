import SwiftUI

struct FitnessView: View {
    @EnvironmentObject var state: AppState
    private let cols = [GridItem(.adaptive(minimum: 168), spacing: 12)]

    private var today: FitnessDay { state.fitnessDay(state.todayKey) }

    private var fp: FitnessProfile { state.fitnessProfile }

    enum FitSub: String, CaseIterable, Hashable {
        case today, food, workout, body
        var label: String {
            switch self {
            case .today: return "Today"
            case .food: return "Food"
            case .workout: return "Workout"
            case .body: return "Body"
            }
        }
    }
    @State private var sub: FitSub = .today

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Fitness").font(.system(size: 24, weight: .semibold)).foregroundStyle(Palette.text)
                .knRise(0)

            Segmented(options: FitSub.allCases.map { ($0, $0.label) }, selection: $sub)
                .knRise(1)

            Group {
                switch sub {
                case .today:   todayContent
                case .food:    FoodView()
                case .workout: WorkoutView()
                case .body:    BodyView()
                }
            }
            .id(sub)
        }
    }

    @ViewBuilder private var todayContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            profileCard.knRise(2)
            caloriesCard.knRise(3)
            weightCard.knRise(4)
            nutritionCard.knRise(5)
            ProgressPhotosCard().knRise(6)
        }
    }

    // MARK: - Weight (easy logging)

    private var weightCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionTitle(text: "Weight")
                    Spacer()
                    if let t = fp.targetWeightKg { Text("goal \(Fmt.trimKg(t)) kg").font(.system(size: 11)).foregroundStyle(Palette.faint) }
                }
                HStack(spacing: 12) {
                    // Type today's weight directly — no tapping a stepper 40 times.
                    HStack(spacing: 6) {
                        TextField("", text: $weightInput, prompt: Text(today.weightKg.map { Fmt.trimKg($0) } ?? "Today's weight").foregroundColor(Palette.faint))
                            .textFieldStyle(.plain).font(.system(size: 22, weight: .heavy, design: .rounded)).monospacedDigit()
                            .foregroundStyle(Palette.text).frame(width: 120)
                            .focused($weightFocused)
                            .onSubmit(saveWeight)
                        Text("kg").font(.system(size: 13)).foregroundStyle(Palette.muted)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Palette.bg, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(weightFocused ? Palette.brand : Palette.border, lineWidth: 2))
                    Button("Log", action: saveWeight).buttonStyle(KPrimaryButtonStyle())
                        .disabled(Double(weightInput.trimmingCharacters(in: .whitespaces)) == nil)
                    StepButton(icon: "minus", accent: Palette.blue) { bumpWeight(-0.5) }
                    StepButton(icon: "plus", accent: Palette.blue) { bumpWeight(0.5) }
                    Spacer()
                }
                recentWeightsInline
            }
        }
    }

    @State private var weightInput = ""
    @FocusState private var weightFocused: Bool
    private func saveWeight() {
        guard let w = Double(weightInput.trimmingCharacters(in: .whitespaces)), w > 0 else { return }
        state.setTodayWeight(w); weightInput = ""; weightFocused = false
    }
    private func bumpWeight(_ d: Double) {
        let base = today.weightKg ?? state.latestWeightKg ?? 0
        state.setTodayWeight(max(0, base + d))
    }

    private var recentWeightsInline: some View {
        let dates = state.fitness.keys.filter { state.fitness[$0]?.weightKg != nil }.sorted(by: >).prefix(7)
        return Group {
            if !dates.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(dates), id: \.self) { d in
                            VStack(spacing: 2) {
                                Text("\(Fmt.trimKg(state.fitness[d]?.weightKg ?? 0))").font(.system(size: 13, weight: .bold)).monospacedDigit().foregroundStyle(Palette.text)
                                Text(Fmt.day(d)).font(.system(size: 9)).foregroundStyle(Palette.faint)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Palette.surface2.opacity(0.5), in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Detailed nutrition (from the food log)

    private var nutritionCard: some View {
        let eaten = state.consumed(state.todayKey)
        let t = state.calorieTargets()
        let vits = state.vitaminsCovered(state.todayKey)
        return Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    SectionTitle(text: "Today's nutrition")
                    Spacer()
                    Button { sub = .food } label: { Label("Log food", systemImage: "fork.knife") }
                        .buttonStyle(KGhostButtonStyle(color: Palette.brand))
                }
                LazyVGrid(columns: cols, spacing: 12) {
                    macroStat("Calories", eaten.calories, t.map { Double($0.goalCalories) }, "kcal", Palette.amber)
                    macroStat("Protein", eaten.protein, t.map { Double($0.proteinG) }, "g", Palette.green)
                    macroStat("Carbs", eaten.carbs, t.map { Double($0.carbG) }, "g", Palette.blue)
                    macroStat("Fiber", eaten.fiber, 30, "g", Palette.purple)
                    macroStat("Fats", eaten.fats, t.map { Double($0.fatG) }, "g", Palette.red)
                    waterStat
                }
                if !vits.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        KFieldLabel(text: "Vitamins covered today")
                        FlowLayout(spacing: 6, runSpacing: 6) {
                            ForEach(vits, id: \.self) { v in
                                Text(v).font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.green)
                                    .padding(.horizontal, 9).padding(.vertical, 4)
                                    .background(Palette.green.opacity(0.14), in: Capsule())
                            }
                        }
                    }
                }
            }
        }
    }

    private func macroStat(_ label: String, _ have: Double, _ target: Double?, _ unit: String, _ tint: Color) -> some View {
        Card(padding: 13) {
            VStack(alignment: .leading, spacing: 7) {
                Text(label.uppercased()).font(.system(size: 9, weight: .heavy, design: .rounded)).tracking(0.6).foregroundStyle(Palette.faint)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(Int(have.rounded()))").font(.system(size: 22, weight: .heavy, design: .rounded)).monospacedDigit().foregroundStyle(tint)
                    Text(unit).font(.system(size: 10)).foregroundStyle(Palette.muted)
                }
                if let target, target > 0 {
                    MeterBar(fraction: min(1, have / target), tint: tint, height: 6)
                    Text("of \(Int(target)) \(unit)").font(.system(size: 9)).foregroundStyle(Palette.faint)
                }
            }
        }
    }

    private var waterStat: some View {
        let ml = today.waterMl ?? 0
        let target = fp.waterTargetMl ?? 3000
        return Card(padding: 13) {
            VStack(alignment: .leading, spacing: 7) {
                Text("WATER").font(.system(size: 9, weight: .heavy, design: .rounded)).tracking(0.6).foregroundStyle(Palette.faint)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(Fmt.trimKg(ml / 1000)).font(.system(size: 22, weight: .heavy, design: .rounded)).monospacedDigit().foregroundStyle(Palette.blue)
                    Text("L").font(.system(size: 10)).foregroundStyle(Palette.muted)
                }
                MeterBar(fraction: min(1, ml / target), tint: Palette.blue, height: 6)
                HStack(spacing: 6) {
                    StepButton(icon: "minus", accent: Palette.blue) { state.updateFitness(state.todayKey) { $0.waterMl = max(0, ml - 250) } }
                    StepButton(icon: "plus", accent: Palette.blue) { state.updateFitness(state.todayKey) { $0.waterMl = ml + 250 } }
                }
            }
        }
    }

    private var profileCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(text: "Fitness profile")
                FitnessProfileEditor()
            }
        }
    }

    // MARK: - Calories (maintain / cut / bulk)

    private var caloriesCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(text: "Calories")
                if let c = state.calorieTargets() {
                    HStack(spacing: 10) {
                        calCol("Cut", c.cut, Palette.blue, on: fp.goal == .cut)
                        calCol("Maintain", c.maintain, Palette.amber, on: fp.goal == .maintain)
                        calCol("Bulk", c.bulk, Palette.green, on: fp.goal == .bulk)
                    }
                    Text("BMR \(c.bmr) · TDEE \(c.tdee) kcal · \(fp.activity.label.lowercased()) activity")
                        .font(.system(size: 11)).foregroundStyle(Palette.faint)

                    Divider().overlay(Palette.border)
                    HStack(spacing: 10) {
                        macroPill("Protein", "\(c.proteinG)g", Palette.green)
                        macroPill("Carbs", "\(c.carbG)g", Palette.amber)
                        macroPill("Fat", "\(c.fatG)g", Palette.red)
                        macroPill("Target", "\(c.goalCalories) kcal", Palette.brand)
                    }

                    Button {
                        state.updateFitnessProfile {
                            $0.calorieTargetKcal = Double(c.goalCalories)
                            $0.proteinTargetG = Double(c.proteinG)
                        }
                    } label: { Label("Use as my daily targets", systemImage: "target") }
                    .buttonStyle(KSecondaryButtonStyle())
                } else {
                    Text("Add your height, age, sex and a weight (above) to see your maintenance, cut and bulk calories.")
                        .font(.system(size: 13)).foregroundStyle(Palette.faint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func calCol(_ label: String, _ kcal: Int, _ tint: Color, on: Bool) -> some View {
        VStack(spacing: 4) {
            Text(label.uppercased()).font(.system(size: 10, weight: .heavy, design: .rounded)).tracking(0.6)
                .foregroundStyle(on ? tint : Palette.faint)
            Text("\(kcal)").font(.system(size: 22, weight: .heavy, design: .rounded)).monospacedDigit()
                .foregroundStyle(on ? .white : Palette.text)
            Text("kcal").font(.system(size: 10)).foregroundStyle(Palette.faint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(on ? tint.opacity(0.9) : Palette.surface2.opacity(0.5),
                    in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(on ? tint : Palette.border, lineWidth: on ? 2 : 1))
    }

    private func macroPill(_ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 14, weight: .heavy, design: .rounded)).monospacedDigit()
                .foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.6)
            Text(label.uppercased()).font(.system(size: 8, weight: .heavy, design: .rounded)).tracking(0.5)
                .foregroundStyle(Palette.faint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    private func metric(_ label: String, value: Double?, unit: String, step: Double,
                        accent: Color, target: Double? = nil, note: String? = nil,
                        set: @escaping (Double) -> Void) -> some View {
        Card(padding: 15) {
            VStack(alignment: .leading, spacing: 10) {
                Text(label.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(0.8)
                    .foregroundStyle(Palette.faint)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value != nil ? Fmt.trimKg(value!) : "—")
                        .font(.system(size: 25, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(accent)
                    Text(unit).font(.system(size: 12)).foregroundStyle(Palette.muted)
                }
                if let target, target > 0 {
                    VStack(alignment: .leading, spacing: 4) {
                        MeterBar(fraction: min(1, (value ?? 0) / target), tint: accent, height: 7)
                        Text("\(Fmt.trimKg(value ?? 0)) / \(Fmt.trimKg(target)) \(unit)")
                            .font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.faint)
                    }
                } else if let note {
                    Text(note).font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.faint)
                }
                HStack(spacing: 8) {
                    StepButton(icon: "minus", accent: accent) { set((value ?? 0) - step) }
                    StepButton(icon: "plus", accent: accent) { set((value ?? 0) + step) }
                }
            }
        }
    }

    private var recentWeights: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle(text: "Recent weight")
                let dates = state.fitness.keys.filter { state.fitness[$0]?.weightKg != nil }.sorted(by: >).prefix(7)
                if dates.isEmpty {
                    Text("No weigh-ins yet.").font(.system(size: 13)).foregroundStyle(Palette.faint)
                }
                ForEach(Array(dates), id: \.self) { d in
                    HStack {
                        Text(Fmt.day(d)).font(.system(size: 12)).foregroundStyle(Palette.muted)
                        Spacer()
                        Text("\(Fmt.trimKg(state.fitness[d]?.weightKg ?? 0)) kg")
                            .font(.system(size: 13, weight: .semibold)).monospacedDigit()
                            .foregroundStyle(Palette.text)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
}

/// A +/- stepper with hover + press feedback.
private struct StepButton: View {
    let icon: String
    let accent: Color
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 12, weight: .bold)).foregroundStyle(accent)
                .frame(width: 34, height: 28)
                .background(hover ? accent.opacity(0.14) : Palette.surface2,
                            in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        }
        .buttonStyle(KPressStyle(scale: 0.92))
        .onHover { h in hover = h; cursor(h) }
        .animation(.knFast, value: hover)
    }
}
