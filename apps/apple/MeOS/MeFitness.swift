import SwiftUI
import Charts

struct MeFitness: View {
    @EnvironmentObject var state: AppState
    @Namespace private var ns

    var body: some View {
        let today = state.todayKey
        let eaten = state.consumed(today)
        let workout = state.workoutItemsForDay(today)
        let log = state.workoutDayLog(today)
        Screen(title: "Fitness", sub: "Goal · \(state.fitnessProfile.goal.label)") {
            LazyVGrid(columns: [.init(spacing: DS.gap), .init()], spacing: DS.gap) {
                tile("steps", "figure.walk", state.steps(on: today).formatted(), "steps") { MeSteps() }
                tile("weight", "scalemass", state.latestWeightKg.map { String(format: "%.1f", $0) } ?? "—", "kg") { MeWeight() }
                tile("intake", "fork.knife", "\(Int(eaten.calories))", "kcal") { MeIntake(dateKey: today) }
                tile("body", "figure.stand", "Body", "photos") { MeBodyPhotos() }
            }
            .appear(0)

            MCard(inverted: true) {
                Label(log.done ? "Done today" : log.skipped ? "Skipped" : "Today", systemImage: log.done ? "checkmark" : "flame").font(.headline).opacity(0.7)
                Text(log.title ?? (workout.isEmpty ? "Rest day" : "\(workout.count) exercises"))
                    .font(.system(size: 32, weight: .bold)).tracking(-0.6)
                if true {
                    NavigationLink { MeWorkoutSession(date: today) } label: {
                        Label(log.done ? "Open workout" : "Start workout", systemImage: "play.fill").font(.title3.weight(.semibold))
                            .frame(maxWidth: .infinity).frame(height: 56)
                            .foregroundStyle(Color.ink).background(Color.paper, in: .rect(cornerRadius: 18))
                    }
                    .buttonStyle(.press).padding(.top, 8)
                }
            }
            .appear(1)

            MCard {
                Label("Water", systemImage: "drop").font(.title3.bold())
                let ml = Int(state.fitnessDay(today).waterMl ?? 0)
                HStack {
                    Button { water(-250) } label: { BigIcon(name: "minus", size: 20) }
                    Spacer()
                    Stat(value: "\(ml)", label: "of \(state.waterTarget) ml").multilineTextAlignment(.center)
                    Spacer()
                    Button { water(250) } label: { BigIcon(name: "plus", size: 20, inverted: true) }
                }
                .buttonStyle(.press)
                .sensoryFeedback(.increase, trigger: ml)
            }
            .appear(2)

            LazyVGrid(columns: [.init(spacing: DS.gap), .init()], spacing: DS.gap) {
                link("Programs", "list.bullet.rectangle") { MePrograms() }
                link("Meal plan", "calendar") { MeMealPlan() }
                link("Library", "books.vertical") { MeLibrary() }
                link("History", "clock.arrow.circlepath") { MeWorkoutHistory() }
                link("Weekly report", "doc.text.magnifyingglass") { MeWeeklyReports() }
                link("Targets", "target") { MeTargets() }
            }
            .appear(3)
        }
    }

    private func water(_ d: Double) {
        withAnimation(DS.spring) { state.updateFitness(state.todayKey) { $0.waterMl = max(0, ($0.waterMl ?? 0) + d) } }
    }

    private func tile<D: View>(_ id: String, _ icon: String, _ value: String, _ label: String, @ViewBuilder dest: @escaping () -> D) -> some View {
        NavigationLink { dest().zoomFrom(id, in: ns) } label: {
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: icon).font(.system(size: 30, weight: .semibold))
                Stat(value: value, label: label)
            }
            .padding(DS.pad).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.card, in: .rect(cornerRadius: DS.radius))
            .matchedTransitionSource(id: id, in: ns)
        }
        .buttonStyle(.press)
    }

    private func link<D: View>(_ title: String, _ icon: String, @ViewBuilder dest: @escaping () -> D) -> some View {
        NavigationLink { dest() } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.title3.weight(.semibold))
                Text(title).font(.headline).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .padding(18).frame(maxWidth: .infinity).background(Color.card, in: .rect(cornerRadius: 22))
        }
        .buttonStyle(.press)
    }
}

struct MeSteps: View {
    @EnvironmentObject var state: AppState
    @State private var showCal = false
    var body: some View {
        let today = state.todayKey
        let steps = state.steps(on: today)
        let week: [(String, Int)] = (0..<7).reversed().map { i in
            let k = AppState.dateKey(Calendar.current.date(byAdding: .day, value: -i, to: .now)!)
            return (String(k.suffix(2)), state.steps(on: k))
        }
        Screen(title: "Steps", sub: "\(state.stepStreak) day streak") {
            Ring(progress: Double(steps) / Double(max(1, state.stepsTarget)), width: 22)
                .frame(width: 240, height: 240)
                .overlay { Stat(value: steps.formatted(), label: "of \(state.stepsTarget.formatted())", big: true).multilineTextAlignment(.center) }
                .frame(maxWidth: .infinity).padding(.vertical, 20)
            HStack(spacing: 12) {
                ForEach([1000, 2000], id: \.self) { n in
                    Button { withAnimation(DS.spring) { state.setTodaySteps(steps + n) } } label: {
                        Text("+\(n / 1000)k").font(.title2.bold()).frame(maxWidth: .infinity).frame(height: 64)
                            .background(Color.card, in: .rect(cornerRadius: 22))
                    }
                    .buttonStyle(.press)
                }
            }
            MCard {
                Text("This week").font(.title3.bold())
                Chart(week, id: \.0) { d, v in
                    BarMark(x: .value("Day", d), y: .value("Steps", v), width: 22).foregroundStyle(Color.ink).clipShape(.capsule)
                    RuleMark(y: .value("Goal", state.stepsTarget)).foregroundStyle(Color.dim).lineStyle(.init(dash: [4]))
                }
                .frame(height: 170)
            }
            Button { showCal = true } label: {
                MCard { HStack { Label("Streak calendar", systemImage: "calendar").font(.headline); Spacer(); Image(systemName: "chevron.right") } }
            }
            .buttonStyle(.press)
        }
        .sensoryFeedback(.success, trigger: steps >= state.stepsTarget)
        .sheet(isPresented: $showCal) {
            ScrollView { MeStreakCalendar() }
                .presentationDetents([.large]).tint(.primary)
        }
    }
}

struct MeWeight: View {
    @EnvironmentObject var state: AppState
    @State private var base: Double = 0
    @State private var delta: Double = 0

    var body: some View {
        let target = state.fitnessProfile.targetWeightKg
        let history: [(Int, Double)] = state.fitness.compactMap { k, d in d.weightKg.map { (k, $0) } }
            .sorted { $0.0 < $1.0 }.suffix(90).enumerated().map { ($0.offset, $0.element.1) }
        Screen(title: "Weight", sub: target.map { "Target \(String(format: "%.1f", $0)) kg" } ?? "Log today") {
            VStack(spacing: 12) {
                Text(String(format: "%.2f", base + delta)).font(.system(size: 80, weight: .bold, design: .rounded))
                    .monospacedDigit().contentTransition(.numericText())
                Text("kg · drag to adjust").foregroundStyle(Color.dim)
                HStack(spacing: 7) {
                    ForEach(0..<30) { i in Capsule().fill(Color.ink.opacity(i % 5 == 0 ? 1 : 0.3)).frame(width: 3, height: i % 5 == 0 ? 36 : 20) }
                }
                .offset(x: CGFloat((delta * 20 * 12).truncatingRemainder(dividingBy: 50)))
            }
            .frame(maxWidth: .infinity).padding(.vertical, 30)
            .background(Color.card, in: .rect(cornerRadius: DS.radius))
            .gesture(DragGesture().onChanged { v in delta = (v.translation.width / 12).rounded() * 0.05 }
                .onEnded { _ in base += delta; delta = 0 })
            .sensoryFeedback(.selection, trigger: delta)

            MButton(title: "Log weight", icon: "checkmark") {
                Haptics.success()
                withAnimation(DS.spring) { state.setTodayWeight((base * 20).rounded() / 20) }
            }
            if history.count > 1 {
                MCard {
                    Text("Trend").font(.title3.bold())
                    Chart {
                        ForEach(history, id: \.0) { i, v in
                            LineMark(x: .value("i", i), y: .value("kg", v)).interpolationMethod(.catmullRom).foregroundStyle(Color.ink).lineStyle(.init(lineWidth: 3))
                        }
                        if let target { RuleMark(y: .value("Goal", target)).foregroundStyle(Color.dim).lineStyle(.init(dash: [4])) }
                    }
                    .chartYScale(domain: .automatic(includesZero: false)).chartXAxis(.hidden).frame(height: 180)
                }
            }
        }
        .onAppear { base = state.latestWeightKg ?? 70 }
    }
}

struct MeIntake: View {
    @EnvironmentObject var state: AppState
    let dateKey: String

    var body: some View {
        let m = state.consumed(dateKey)
        Screen(title: "Intake", sub: Fmt.day(dateKey)) {
            macro("Calories", m.calories, Double(state.kcalTarget), "kcal")
            macro("Protein", m.protein, Double(state.proteinTarget), "g")
            macro("Water", state.fitnessDay(dateKey).waterMl ?? 0, Double(state.waterTarget), "ml")
            HStack(spacing: 10) {
                Chip(text: "C \(Int(m.carbs))g"); Chip(text: "F \(Int(m.fats))g"); Chip(text: "Fib \(Int(m.fiber))g")
            }
            ForEach(MealKey.allCases) { meal in
                let items = state.mealDisplayItems(date: dateKey, meal: meal)
                let st = state.mealState(dateKey, meal)
                NavigationLink { MeMealEditor(date: dateKey, meal: meal) } label: { MCard {
                    HStack(spacing: 16) {
                        BigIcon(name: meal.symbol, inverted: st == .logged)
                        VStack(alignment: .leading) {
                            Text(meal.label).font(.title3.bold())
                            Text(st == .skipped ? "Skipped" : items.compactMap { state.food($0.foodId)?.name }.joined(separator: ", "))
                                .foregroundStyle(Color.dim).lineLimit(2)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(Color.dim)
                    }
                } }
                .buttonStyle(.press)
            }
            let vit = state.vitaminsCovered(dateKey)
            if !vit.isEmpty {
                MCard { Text("Vitamins").font(.title3.bold()); Text(vit.joined(separator: " · ")).foregroundStyle(Color.dim) }
            }
        }
    }
    private func macro(_ name: String, _ v: Double, _ t: Double, _ unit: String) -> some View {
        MCard {
            HStack { Text(name).font(.title3.bold()); Spacer(); Text("\(Int(v)) / \(Int(t)) \(unit)").font(.headline).foregroundStyle(Color.dim) }
            Bar(progress: v / max(1, t))
        }
    }
}
