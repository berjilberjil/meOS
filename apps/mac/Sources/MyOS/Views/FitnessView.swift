import SwiftUI
import Charts

struct FitnessView: View {
    @EnvironmentObject var state: AppState
    private let cols = [GridItem(.adaptive(minimum: 168), spacing: 12)]

    private var today: FitnessDay { state.fitnessDay(state.todayKey) }

    private var fp: FitnessProfile { state.fitnessProfile }

    /// Today first, then the thing that decides what Today says. Training got
    /// its own tab (programs + history) because it is a hierarchy now, not a
    /// list of exercises hanging off a weekday.
    enum FitSub: String, CaseIterable, Hashable {
        case today, train, meals, library, body
        var label: String {
            switch self {
            case .today: return "Today"
            case .train: return "Train"
            case .meals: return "Meals"
            case .library: return "Library"
            case .body: return "Body"
            }
        }
    }
    @State private var sub: FitSub = .today

    enum TrainSub: String, CaseIterable, Hashable {
        case programs, history
        var label: String { self == .programs ? "Programs" : "History" }
    }
    @State private var trainSub: TrainSub = .programs

    var body: some View {
        VStack(alignment: .leading, spacing: Gap.screen) {
            #if os(macOS)   // iOS: the navigation bar owns the title
            ScreenTitle(text: "Fitness")
                .knRise(0)
            #endif

            #if os(iOS)
            Picker("", selection: $sub) { ForEach(FitSub.allCases.map { ($0, $0.label) }, id: \.0) { opt in Text(opt.1).tag(opt.0) } }.pickerStyle(.segmented).labelsHidden()
                .knRise(1)
            #else
            Picker("", selection: $sub) { ForEach(FitSub.allCases.map { ($0, $0.label) }, id: \.0) { opt in Text(opt.1).tag(opt.0) } }.pickerStyle(.segmented).labelsHidden()
                .knRise(1)
            #endif

            Group {
                switch sub {
                case .today:   todayContent
                case .train:   trainContent
                case .meals:   WeeklyPlannerView()
                case .library: FitnessLibraryView()
                case .body:    BodyView()
                }
            }
            .id(sub)
        }
    }

    @ViewBuilder private var trainContent: some View {
        VStack(alignment: .leading, spacing: Gap.screen) {
            Picker("", selection: $trainSub) { ForEach(TrainSub.allCases.map { ($0, $0.label) }, id: \.0) { opt in Text(opt.1).tag(opt.0) } }.pickerStyle(.segmented).labelsHidden()
            Group {
                switch trainSub {
                case .programs: ProgramsView()
                case .history:  WorkoutHistoryView()
                }
            }
            .id(trainSub)
        }
    }

    @State private var showFitnessSettings = false

    @ViewBuilder private var todayContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            // First thing on the tab: the day's weight is the number every
            // other number here is computed from.
            WeightCard(day: state.todayKey).cardAccent(.green).knRise(1)
            // Directly under the dial that logs it: log the number, then
            // read it back. The seven-chip strip in Fitness settings was
            // the only history there was, and it was buried under a
            // disclosure inside a card you had to know to open.
            WeightHistoryCard().cardAccent(.green).knRise(2)
            FitnessTodayView().knRise(3)
            ActivityStepsCard().knRise(4)
            #if os(iOS)
            BodyPhotosCard().knRise(5)
            #else
            ProgressPhotosCard().knRise(5)
            #endif
            settingsDisclosure.knRise(6)
        }
    }

    // MARK: - Fitness settings (goal, targets) — tucked under a disclosure

    private var settingsDisclosure: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button { withAnimation(.knNormal) { showFitnessSettings.toggle() } } label: {
                HStack {
                    Label("Fitness settings", systemImage: "slider.horizontal.3")
                        .font(.footnote.weight(.semibold)).foregroundStyle(Palette.muted)
                    Spacer()
                    Image(systemName: showFitnessSettings ? "chevron.up" : "chevron.down")
                        .font(.caption2.weight(.bold)).foregroundStyle(Palette.faint)
                }
                .padding(.vertical, 4).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showFitnessSettings {
                nutritionCard
                weightCard
                stepsCard
                caloriesCard
                profileCard
            }
        }
    }

    // MARK: - Steps (manual now; iPhone HealthKit sync writes the same field next month)

    @State private var stepsInput = ""
    @FocusState private var stepsFocused: Bool

    private var stepsCard: some View {
        let steps = today.steps ?? 0
        let goals = state.stepGoals
        let target = goals.daily
        return Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionTitle(text: "Steps")
                    Spacer()
                    Text("\(target.formatted()) · \(goals.stretch.formatted())")
                        .font(.caption2.weight(.semibold)).monospacedDigit().foregroundStyle(Palette.muted)
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(steps.formatted())
                        .font(.largeTitle.weight(.heavy)).monospacedDigit()
                        .foregroundStyle(Palette.text)
                    Text("steps today").font(.caption).foregroundStyle(Palette.muted)
                    Spacer()
                    if steps >= goals.stretch {
                        Text("Both goals").font(.caption2.weight(.heavy))
                            .foregroundStyle(Palette.complete)
                    } else if steps >= target {
                        Text("Goal hit").font(.caption2.weight(.heavy))
                            .foregroundStyle(Palette.complete)
                    }
                }
                StepGoalBar(steps: steps, goals: goals)
                stepsLogRow(steps)
                Text("\(target.formatted()) is the goal the streak counts. \(goals.stretch.formatted()) is the one worth chasing. Both are editable in your profile.")
                    .font(.caption2).foregroundStyle(Palette.faint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The steps field plus its three buttons.
    ///
    /// This row is why "the fitness settings are all messed up" on the
    /// phone. It was one `HStack`: a 140pt fixed field, a Log button, two
    /// quick-add buttons and a `Spacer` — about 380pt of content, laid
    /// out inside roughly 300pt of usable width on an iPhone. SwiftUI
    /// does not wrap an HStack; it compresses it. So the field shrank
    /// under its own text, the buttons squeezed to their titles and
    /// then past them, and "+1k" and "+2k" ended up sharing a few
    /// points of width each. They were not misbehaving — they were
    /// slivers, and a sliver is very hard to hit.
    ///
    /// Two lines on the phone, one on the Mac. Nothing has a fixed
    /// width on iOS and every button is a full `KTapTarget` tall, so
    /// they are hittable without aiming.
    @ViewBuilder private func stepsLogRow(_ steps: Int) -> some View {
        let field = HStack(spacing: 6) {
            TextField("", text: $stepsInput,
                      prompt: Text("Set today's steps").foregroundColor(Palette.faint))
                .textFieldStyle(.plain).font(.callout.weight(.heavy)).monospacedDigit()
                .foregroundStyle(Palette.text)
                .focused($stepsFocused)
                .onSubmit(saveSteps)
                #if os(iOS)
                // A step count is digits. The default keyboard made
                // every entry a two-step trip through the numeric plane.
                .keyboardType(.numberPad)
                #else
                .frame(width: 140)
                #endif
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Palette.background, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(stepsFocused ? Palette.action : Palette.border, lineWidth: 2))

        let logButton = Button("Log", action: saveSteps)
            .buttonStyle(.borderedProminent)
            .disabled(Int(stepsInput.trimmingCharacters(in: .whitespaces)) == nil)

        #if os(iOS)
        VStack(spacing: 10) {
            field
            HStack(spacing: 8) {
                logButton.frame(maxWidth: .infinity, minHeight: KTapTarget.min)
                ForEach([1000, 2000], id: \.self) { d in
                    Button { state.setTodaySteps(steps + d) } label: {
                        Text("+\(d / 1000)k").frame(maxWidth: .infinity, minHeight: KTapTarget.min)
                    }
                    .buttonStyle(.bordered).tint(Palette.activity)
                }
            }
        }
        #else
        HStack(spacing: 10) {
            field
            logButton
            ForEach([1000, 2000], id: \.self) { d in
                Button { state.setTodaySteps(steps + d) } label: { Text("+\(d / 1000)k") }
                    .buttonStyle(.bordered).tint(Palette.activity)
            }
            Spacer()
        }
        #endif
    }

    private func saveSteps() {
        guard let n = Int(stepsInput.trimmingCharacters(in: .whitespaces)), n >= 0 else { return }
        state.setTodaySteps(n); stepsInput = ""; stepsFocused = false
    }

    // MARK: - Weight (easy logging)

    private var weightCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionTitle(text: "Weight")
                    Spacer()
                    if let t = fp.targetWeightKg { Text("goal \(Fmt.trimKg(t)) kg").font(.caption2).foregroundStyle(Palette.faint) }
                }
                weightLogRow
                recentWeightsInline
            }
        }
    }

    /// Same story as `stepsLogRow` — a Mac-width row of fixed-size
    /// controls that an iPhone could only squash. Stacked on the
    /// phone, with the two half-kilo steppers given a real tap
    /// target instead of the 32×30 they had.
    @ViewBuilder private var weightLogRow: some View {
        let field = HStack(spacing: 6) {
            TextField("", text: $weightInput,
                      prompt: Text(today.weightKg.map { Fmt.trimKg($0) } ?? "Today's weight")
                        .foregroundColor(Palette.faint))
                .textFieldStyle(.plain).font(.title2.weight(.heavy)).monospacedDigit()
                .foregroundStyle(Palette.text)
                .focused($weightFocused)
                .onSubmit(saveWeight)
                #if os(iOS)
                // Decimals: 72.4 is a normal thing to type here.
                .keyboardType(.decimalPad)
                #else
                .frame(width: 120)
                #endif
            Text("kg").font(.footnote).foregroundStyle(Palette.muted)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Palette.background, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(weightFocused ? Palette.action : Palette.border, lineWidth: 2))

        let logButton = Button("Log", action: saveWeight)
            .buttonStyle(.borderedProminent)
            .disabled(Double(weightInput.trimmingCharacters(in: .whitespaces)) == nil)

        #if os(iOS)
        VStack(spacing: 10) {
            field
            HStack(spacing: 8) {
                logButton.frame(maxWidth: .infinity, minHeight: KTapTarget.min)
                KStepButton(icon: "minus", accent: Palette.blue) { bumpWeight(-0.5) }
                KStepButton(icon: "plus", accent: Palette.blue) { bumpWeight(0.5) }
            }
        }
        #else
        HStack(spacing: 12) {
            field
            logButton
            KStepButton(icon: "minus", accent: Palette.blue) { bumpWeight(-0.5) }
            KStepButton(icon: "plus", accent: Palette.blue) { bumpWeight(0.5) }
            Spacer()
        }
        #endif
    }

    @State private var weightInput = ""
    @FocusState private var weightFocused: Bool
    private func saveWeight() {
        guard let w = Fmt.parseWeightKg(weightInput) else { return }
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
                                Text("\(Fmt.trimKg(state.fitness[d]?.weightKg ?? 0))").font(.footnote.weight(.bold)).monospacedDigit().foregroundStyle(Palette.text)
                                Text(Fmt.day(d)).font(.caption2).foregroundStyle(Palette.faint)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Palette.surfaceElevated.opacity(0.5), in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
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
                // Rows, not a grid of cards inside a card. Same six numbers,
                // same accent colours, roughly a third less visual weight —
                // container-on-container was the noisiest thing in the app.
                VStack(spacing: 0) {
                    macroRow("Calories", eaten.calories, t.map { Double($0.goalCalories) }, "kcal", Palette.attention)
                    macroDivider
                    macroRow("Protein", eaten.protein, t.map { Double($0.proteinG) }, "g", Palette.green)
                    macroDivider
                    macroRow("Carbs", eaten.carbs, t.map { Double($0.carbG) }, "g", Palette.blue)
                    macroDivider
                    macroRow("Fiber", eaten.fiber, 30, "g", Palette.information)
                    macroDivider
                    macroRow("Fats", eaten.fats, t.map { Double($0.fatG) }, "g", Palette.nutrition)
                    macroDivider
                    waterRow
                }
                if !vits.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        KFieldLabel(text: "Vitamins covered today")
                        FlowLayout(spacing: 6, runSpacing: 6) {
                            ForEach(vits, id: \.self) { v in
                                Text(v).font(.caption2.weight(.semibold)).foregroundStyle(Palette.green)
                                    .padding(.horizontal, 9).padding(.vertical, 4)
                                    .background(Palette.green.opacity(0.14), in: Capsule())
                            }
                        }
                    }
                }
            }
        }
    }

    private var macroDivider: some View {
        Rectangle().fill(Palette.border.opacity(0.7)).frame(height: 1)
    }

    /// Name on the left in its accent, the number on the right, the bar under
    /// both. The accent stays on the label and the meter — it never becomes the
    /// background of anything.
    private func macroRow(_ label: String, _ have: Double, _ target: Double?, _ unit: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(label.uppercased())
                    .font(.caption2.weight(.heavy)).tracking(0.6)
                    .foregroundStyle(tint)
                Spacer(minLength: 8)
                Text("\(Int(have.rounded()))")
                    .font(.body.weight(.heavy))
                    .monospacedDigit().foregroundStyle(Palette.text)
                if let target, target > 0 {
                    Text("/ \(Int(target)) \(unit)").font(.caption).foregroundStyle(Palette.faint)
                } else {
                    Text(unit).font(.caption).foregroundStyle(Palette.faint)
                }
            }
            if let target, target > 0 {
                ProgressView(value: min(1, have / target)).progressViewStyle(.linear).tint(tint)
            }
        }
        .padding(.vertical, 11)
    }

    private var waterRow: some View {
        let ml = today.waterMl ?? 0
        let target = max(1, fp.waterTargetMl ?? 3000)   // a 0-L goal must not NaN the meter
        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("WATER")
                    .font(.caption2.weight(.heavy)).tracking(0.6)
                    .foregroundStyle(Palette.blue)
                Spacer(minLength: 8)
                Text(Fmt.trimKg(ml / 1000))
                    .font(.body.weight(.heavy))
                    .monospacedDigit().foregroundStyle(Palette.text)
                Text("/ \(Fmt.trimKg(target / 1000)) L").font(.caption).foregroundStyle(Palette.faint)
            }
            ProgressView(value: min(1, ml / target)).progressViewStyle(.linear).tint(Palette.blue)
            HStack(spacing: 6) {
                KStepButton(icon: "minus", accent: Palette.blue) {
                    state.updateFitness(state.todayKey) { $0.waterMl = max(0, ml - 250) }
                }
                KStepButton(icon: "plus", accent: Palette.blue) {
                    state.updateFitness(state.todayKey) { $0.waterMl = ml + 250 }
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 2)
        }
        .padding(.vertical, 11)
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
                        calCol("Maintain", c.maintain, Palette.attention, on: fp.goal == .maintain)
                        calCol("Bulk", c.bulk, Palette.green, on: fp.goal == .bulk)
                    }
                    Text("BMR \(c.bmr) · TDEE \(c.tdee) kcal · \(fp.activity.label.lowercased()) activity")
                        .font(.caption2).foregroundStyle(Palette.faint)

                    Divider().overlay(Palette.border)
                    HStack(spacing: 10) {
                        macroPill("Protein", "\(c.proteinG)g", Palette.green)
                        macroPill("Carbs", "\(c.carbG)g", Palette.attention)
                        macroPill("Fat", "\(c.fatG)g", Palette.nutrition)
                        macroPill("Target", "\(c.goalCalories) kcal", Palette.action)
                    }

                    Button {
                        state.updateFitnessProfile {
                            $0.calorieTargetKcal = Double(c.goalCalories)
                            $0.proteinTargetG = Double(c.proteinG)
                        }
                    } label: { Label("Use as my daily targets", systemImage: "target") }
                    .buttonStyle(.bordered)
                } else {
                    Text("Add your height, age, sex and a weight (above) to see your maintenance, cut and bulk calories.")
                        .font(.footnote).foregroundStyle(Palette.faint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func calCol(_ label: String, _ kcal: Int, _ tint: Color, on: Bool) -> some View {
        VStack(spacing: 4) {
            Text(label.uppercased()).font(.caption2.weight(.heavy)).tracking(0.6)
                .foregroundStyle(on ? tint : Palette.faint)
            Text("\(kcal)").font(.title2.weight(.heavy)).monospacedDigit()
                .foregroundStyle(on ? .white : Palette.text)
            Text("kcal").font(.caption2).foregroundStyle(Palette.faint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(on ? tint.opacity(0.9) : Palette.surfaceElevated.opacity(0.5),
                    in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(on ? tint : Palette.border, lineWidth: on ? 2 : 1))
    }

    private func macroPill(_ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.footnote.weight(.heavy)).monospacedDigit()
                .foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.6)
            Text(label.uppercased()).font(.caption2.weight(.heavy)).tracking(0.5)
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
                Text(label.uppercased()).font(.caption2.weight(.semibold)).tracking(0.8)
                    .foregroundStyle(Palette.faint)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value != nil ? Fmt.trimKg(value!) : "—")
                        .font(.title2.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(accent)
                    Text(unit).font(.caption).foregroundStyle(Palette.muted)
                }
                if let target, target > 0 {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: min(1, (value ?? 0) / target)).progressViewStyle(.linear).tint(accent)
                        Text("\(Fmt.trimKg(value ?? 0)) / \(Fmt.trimKg(target)) \(unit)")
                            .font(.caption2.weight(.medium)).foregroundStyle(Palette.faint)
                    }
                } else if let note {
                    Text(note).font(.caption2.weight(.medium)).foregroundStyle(Palette.faint)
                }
                HStack(spacing: 8) {
                    KStepButton(icon: "minus", accent: accent) { set((value ?? 0) - step) }
                    KStepButton(icon: "plus", accent: accent) { set((value ?? 0) + step) }
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
                    Text("No weigh-ins yet.").font(.footnote).foregroundStyle(Palette.faint)
                }
                ForEach(Array(dates), id: \.self) { d in
                    HStack {
                        Text(Fmt.day(d)).font(.caption).foregroundStyle(Palette.muted)
                        Spacer()
                        Text("\(Fmt.trimKg(state.fitness[d]?.weightKg ?? 0)) kg")
                            .font(.footnote.weight(.semibold)).monospacedDigit()
                            .foregroundStyle(Palette.text)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
}

/// Steps — today at a glance, with the daily record behind the calendar button.
///
/// Shared by Today and Fitness. Every day in the month is dotted by how close it
/// came to the goal; tapping one reads it back and lets you correct it, which
/// matters because only the iPhone has a pedometer — anything on the Mac is
/// typed in.
struct ActivityStepsCard: View {
    /// The day being shown. Today unless the Today page has been swiped.
    var day: String? = nil
    /// Today shows one date and pages by swipe, so the per-card month grid is
    /// redundant there. Kept for the full-screen tabs.
    var showsCalendar: Bool = true
    @EnvironmentObject var state: AppState

    @State private var showCalendar = false
    @State private var showSheet = false
    @State private var year = CalMath.cal.component(.year, from: Date())
    @State private var month = CalMath.cal.component(.month, from: Date())
    @State private var selected: String = AppState.dateKey(Date())

    /// Bold on Today, washed on the Fitness tab. Read here so the chart's ink
    /// can flip to white without the card being told twice.

    private var goals: StepGoals { state.stepGoals }
    private var target: Int { goals.daily }
    private func steps(_ key: String) -> Int { state.fitness[key]?.steps ?? 0 }
    private func fraction(_ n: Int) -> Double { target > 0 ? min(1, Double(n) / Double(target)) : 0 }

    /// The celebration only belongs on the page for the day it happened — Today
    /// swipes through days, and a party on last Tuesday is a bug.
    private var celebration: StepCelebration? {
        guard let c = state.stepCelebration, (day ?? state.todayKey) == c.day else { return nil }
        return c
    }

    /// nil = nothing logged. Otherwise goal hit / past halfway / short — the same
    /// green-amber-red reading the focus record uses.
    private func dot(_ key: String) -> Color? {
        let n = steps(key)
        guard n > 0 else { return nil }
        guard target > 0 else { return Palette.green }
        if n >= goals.stretch { return Palette.complete }
        let f = Double(n) / Double(target)
        if f >= 1 { return Palette.green }
        if f >= 0.5 { return Palette.muted }
        return Palette.warning
    }

    var body: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                if let celebration {
                    StepCelebrationCard(celebration: celebration) {
                        withAnimation(.knNormal) { state.stepCelebration = nil }
                    }
                }
                summaryRow
                if showCalendar {
                    Divider().overlay(Palette.border).padding(.top, 2)
                    record.transition(.knReveal)
                }
            }
        }
        // No `.task` here on purpose. This card is on the Today page, which is
        // paged by day — so a per-card task means seven serial main-actor
        // CoreMotion queries per live page, fired while you are mid-swipe.
        // `MainView` runs the backfill once at launch and once per foreground.
        .sheet(isPresented: $showSheet) {
            ActivitySheet(day: day ?? state.todayKey).environmentObject(state)
        }
    }

    // MARK: Today

    /// The number is the button — the calendar toggle sits outside it, because a
    /// button inside a button is a tap the inner one never gets.
    private var summaryRow: some View {
        HStack(spacing: 12) {
            Button { showSheet = true } label: { summary.contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .accessibilityLabel("See this week's activity")

            if showsCalendar {
                Button { withAnimation(.knNormal) { showCalendar.toggle() } } label: {
                    Image(systemName: showCalendar ? "calendar.badge.minus" : "calendar")
                        .font(.footnote.weight(.bold))
                }
                .buttonStyle(.borderless)
                .tint(showCalendar ? Palette.action : Palette.faint)
                .help(showCalendar ? "Hide the record" : "See every day")
                .accessibilityLabel(showCalendar ? "Hide the activity calendar" : "Show the activity calendar")
            }
        }
    }

    /// The week, as a chart. One progress bar only ever answered "how far
    /// through today", which the number above it already says; seven days
    /// answers the question the card is actually asked — is this a good week.
    private var summary: some View {
        let key = day ?? state.todayKey
        let n = steps(key)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "figure.walk").font(.callout.weight(.semibold))
                Text("Activity").font(.subheadline.weight(.semibold))
                Spacer(minLength: 4)
                if target > 0 {
                    Text("\(Int((fraction(n) * 100).rounded()))%")
                        .font(.caption.weight(.heavy)).monospacedDigit().opacity(0.85)
                }
                Image(systemName: "chevron.right").font(.caption2.weight(.bold)).opacity(0.7)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(n.formatted())
                    .font(.largeTitle.weight(.heavy)).monospacedDigit()
                Text("of \(target.formatted()) steps")
                    .font(.footnote.weight(.semibold)).opacity(0.85)
            }
            weekChart(endingOn: key)
            #if os(iOS)
            Text("from Apple Health").font(.caption2).opacity(0.7)
            #endif
        }
        .foregroundStyle(Palette.text)
    }

    /// Seven `BarMark`s and a dashed goal line. On a bold card the ink is white
    /// at two opacities — the day you are reading solid, the rest recessive.
    private func weekChart(endingOn key: String) -> some View {
        let days = (0..<7).reversed().map { AppState.addDays(-$0, to: key) }
        let ink: Color = Palette.activity
        return Chart {
            ForEach(days, id: \.self) { d in
                BarMark(x: .value("Day", d), y: .value("Steps", steps(d)))
                    .foregroundStyle(ink.opacity(d == key ? 1 : 0.42))
                    .cornerRadius(3)
            }
            if target > 0 {
                RuleMark(y: .value("Goal", target))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(ink.opacity(0.55))
            }
        }
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let d = value.as(String.self) {
                        Text(Fmt.weekdayInitial(d))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(ink.opacity(d == key ? 1 : 0.6))
                    }
                }
            }
        }
        .chartYAxis(.hidden)
        .frame(height: 60)
    }

    // MARK: The record

    private var record: some View {
        VStack(alignment: .leading, spacing: 12) {
            KMonthHeader(year: year, month: month, showToday: false,
                         onPrev: { shift(-1) }, onNext: { shift(1) })
            KMonthGrid(year: year, month: month, selected: selected,
                       dot: { dot($0) },
                       onTap: { selected = $0 })
            monthSummary
            legend
            dayRecap
        }
    }

    /// Counts for the month on screen, blank days dropped so the average is over
    /// days actually walked rather than over the calendar.
    private var loggedInMonth: [Int] {
        (1...CalMath.daysInMonth(year: year, month: month))
            .map { steps(CalMath.key(year, month, $0)) }
            .filter { $0 > 0 }
    }

    private var monthSummary: some View {
        let logged = loggedInMonth
        let total = logged.reduce(0, +)
        let avg = logged.isEmpty ? 0 : total / logged.count
        let hit = target > 0 ? logged.filter { $0 >= target }.count : 0
        return HStack(spacing: 16) {
            stat(total.formatted(), "total")
            stat(avg.formatted(), "avg / day")
            stat("\(hit)", hit == 1 ? "day at goal" : "days at goal")
            Spacer(minLength: 0)
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.footnote.weight(.heavy)).monospacedDigit()
                .foregroundStyle(Palette.text)
            Text(label).font(.caption2.weight(.heavy)).foregroundStyle(Palette.faint)
        }
    }

    private var legend: some View {
        HStack(spacing: 12) {
            legendDot(Palette.green, "goal")
            legendDot(Palette.muted, "halfway")
            legendDot(Palette.warning, "short")
            Spacer(minLength: 0)
        }
    }

    private func legendDot(_ c: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(c).frame(width: 6, height: 6)
            Text(label).font(.caption2.weight(.heavy)).foregroundStyle(Palette.faint)
        }
    }

    private var dayRecap: some View {
        let n = steps(selected)
        let isFuture = selected > AppState.dateKey(Date())
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Text(Fmt.day(selected))
                    .font(.footnote.weight(.heavy)).foregroundStyle(Palette.text)
                Spacer(minLength: 0)
                if target > 0 && n > 0 {
                    Text("\(Int((Double(n) / Double(target) * 100).rounded()))% of goal")
                        .font(.caption2.weight(.heavy))
                        .foregroundStyle(n >= target ? Palette.green : Palette.faint)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(n.formatted())
                    .font(.title2.weight(.heavy)).monospacedDigit()
                    .foregroundStyle(n > 0 ? Palette.text : Palette.faint)
                Text("steps").font(.caption2).foregroundStyle(Palette.muted)
                Spacer(minLength: 0)
                if !isFuture {
                    KStepButton(icon: "minus", accent: Palette.activity) {
                        state.setSteps(max(0, n - 500), on: selected)
                    }
                    KStepButton(icon: "plus", accent: Palette.activity) {
                        state.setSteps(n + 500, on: selected)
                    }
                }
            }
            ProgressView(value: fraction(n)).progressViewStyle(.linear).tint(Palette.activity)
            Text(isFuture ? "Hasn\u{2019}t happened yet."
                          : (n > 0 ? "500 steps a tap." : "Nothing logged that day."))
                .font(.caption2).foregroundStyle(Palette.faint)
        }
        // A floor so paging from a logged day to a blank one can't collapse the
        // panel and yank every card below it up the page.
        .frame(minHeight: 96, alignment: .top)
    }

    private func shift(_ d: Int) {
        let (y, m) = CalMath.addMonth(year: year, month: month, delta: d)
        withAnimation(.knFast) { year = y; month = m }
    }
}

/// A +/- stepper with hover + press feedback.
