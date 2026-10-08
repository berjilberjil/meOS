import SwiftUI

extension AppState {
    /// Daily kcal target: the saved one, else the Mifflin-St Jeor goal.
    var kcalTarget: Int { fitnessProfile.calorieTargetKcal.map { Int($0) } ?? calorieTargets()?.goalCalories ?? 2000 }
    var proteinTarget: Int { fitnessProfile.proteinTargetG.map { Int($0) } ?? calorieTargets()?.proteinG ?? 120 }
    var waterTarget: Int { Int(fitnessProfile.waterTargetMl ?? 3000) }
    var firstName: String { profile.name.split(separator: " ").first.map(String.init) ?? username }

    /// Upcoming events projected through their repeat rule, soonest first.
    func upcoming(limit: Int = 3) -> [(event: EventItem, date: String)] {
        events.compactMap { e in EventRecurrence.next(e, onOrAfter: todayKey).map { (e, $0) } }
            .sorted { $0.1 < $1.1 }.prefix(limit).map { $0 }
    }
}

struct MeToday: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject private var mio: MioController
    @ObservedObject private var timer = FocusTimer.shared
    @State private var offset = 0
    @State private var draft = ""
    @State private var showTimer = false
    @State private var editMeal: MealKey?
    @Namespace private var ns

    private var date: Date { Calendar.current.date(byAdding: .day, value: offset, to: .now)! }
    private var key: String { AppState.dateKey(date) }

    var body: some View {
        let steps = state.steps(on: key)
        let eaten = state.consumed(key)
        Screen(title: offset == 0 ? "Hi, \(state.firstName)" : date.formatted(.dateTime.weekday(.wide)),
               sub: date.formatted(.dateTime.day().month(.wide))) {
            dayBar.appear(0)
            MioCompanionCard().appear(1)

            NavigationLink { MeSteps().zoomFrom("steps", in: ns) } label: {
                MCard(inverted: true) {
                    HStack {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("\(state.stepStreak) day streak", systemImage: "flame.fill").font(.subheadline.weight(.semibold))
                            Stat(value: steps.formatted(), label: "of \(state.stepsTarget.formatted()) steps", big: true)
                        }
                        Spacer()
                        Ring(progress: Double(steps) / Double(max(1, state.stepsTarget)), width: 12, color: .paper)
                            .frame(width: 84, height: 84)
                            .overlay { Image(systemName: "figure.walk").font(.title.weight(.bold)) }
                    }
                }
                .matchedTransitionSource(id: "steps", in: ns)
            }
            .buttonStyle(.press).appear(2)

            NavigationLink { MeIntake(dateKey: key) } label: {
                MCard {
                    HStack(alignment: .bottom) {
                        Stat(value: "\(Int(eaten.calories))", label: "of \(state.kcalTarget) kcal")
                        Spacer()
                        Stat(value: "\(Int(eaten.protein))g", label: "of \(state.proteinTarget)g protein").multilineTextAlignment(.trailing)
                    }
                    Bar(progress: eaten.calories / Double(max(1, state.kcalTarget)))
                }
            }
            .buttonStyle(.press).appear(3)

            focusCard.appear(4)
            meals.appear(5)

            if let next = state.upcoming(limit: 1).first {
                NavigationLink { MeEvents() } label: {
                    MCard {
                        HStack(spacing: 16) {
                            BigIcon(name: next.event.special ? "star.fill" : "calendar")
                            VStack(alignment: .leading) {
                                Text("Coming up").font(.subheadline).foregroundStyle(Color.dim)
                                Text(next.event.title).font(.title3.bold()).lineLimit(1)
                            }
                            Spacer()
                            Text(countdown(next.date)).font(.headline)
                        }
                    }
                }
                .buttonStyle(.press).appear(6)
            }
        }
        .refreshable { await state.syncNow() }
        .navigationDestination(item: $editMeal) { MeMealEditor(date: key, meal: $0) }
        .sheet(isPresented: $showTimer) { MeFocusTimer().presentationDetents([.large]) }
        .meActions {
            if let err = state.lastSyncError {
                Image(systemName: "exclamationmark.icloud").help(err)
            }
        }
    }

    private func countdown(_ k: String) -> String {
        switch state.daysUntil(k) ?? 0 { case 0: "Today"; case 1: "Tomorrow"; case let n: "\(n) days" }
    }

    private var dayBar: some View {
        HStack {
            Button { withAnimation(DS.spring) { offset -= 1 } } label: { BigIcon(name: "chevron.left", size: 18) }
            Spacer()
            if offset != 0 {
                Button { withAnimation(DS.spring) { offset = 0 } } label: { Chip(text: "Back to Today", on: true) }
                    .transition(.scale.combined(with: .opacity))
            }
            Spacer()
            Button { withAnimation(DS.spring) { offset += 1 } } label: { BigIcon(name: "chevron.right", size: 18) }
                .disabled(offset >= 7).opacity(offset >= 7 ? 0.3 : 1)
        }
        .buttonStyle(.press)
        .sensoryFeedback(.selection, trigger: offset)
    }

    private var focusCard: some View {
        let todos = state.plan(for: key).todos
        return MCard {
            HStack {
                Text("Focus").font(.title2.bold())
                Spacer()
                if offset == 0 {
                    Button { state.setTaskMode(true) } label: { Label("Task Mode", systemImage: "scope").font(.subheadline.weight(.semibold)) }
                        .buttonStyle(.press)
                }
            }
            if timer.isActive {
                Button { showTimer = true } label: {
                    HStack {
                        Image(systemName: timer.running ? "timer" : "pause.fill")
                        Text(timer.itemTitle).lineLimit(1)
                        Spacer()
                        Text(timer.clock).monospacedDigit().contentTransition(.numericText(countsDown: true))
                    }
                    .font(.headline).padding(14).foregroundStyle(Color.paper).background(Color.ink, in: .rect(cornerRadius: 18))
                }
                .buttonStyle(.press)
            }
            ForEach(todos) { t in
                HStack(spacing: 14) {
                    Button {
                        let completing = !t.done
                        withAnimation(DS.bouncy) { state.toggleTodo(t.id) }
                        if completing { mio.handle(.taskCompleted) }
                    } label: {
                        Image(systemName: t.done ? "checkmark.circle.fill" : "circle").font(.system(size: 30))
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.press).sensoryFeedback(.success, trigger: t.done) { !$0 && $1 }
                    VStack(alignment: .leading) {
                        Text(t.text).font(.title3.weight(.semibold)).strikethrough(t.done).opacity(t.done ? 0.4 : 1)
                        Text("\(t.spent / 60) / \(t.mins ?? 25) min").font(.subheadline).foregroundStyle(Color.dim)
                    }
                    Spacer()
                    if !t.done && offset == 0 {
                        Button {
                            timer.begin(t, minutes: t.mins ?? 25)
                            mio.handle(.focusStarted(title: t.text))
                            showTimer = true
                        } label: {
                            Image(systemName: "play.fill").font(.title3).frame(width: 48, height: 48).background(Color.hairline, in: .circle)
                        }
                        .buttonStyle(.press)
                    }
                }
                .contextMenu { Button("Delete", systemImage: "trash", role: .destructive) { state.removeTodo(t.id) } }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            HStack {
                Image(systemName: "plus").font(.title3.weight(.semibold))
                TextField("Add a task", text: $draft).font(.title3).submitLabel(.done)
                    .onSubmit {
                        let added = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        withAnimation(DS.spring) { state.addTodo(draft, on: key) }; draft = ""
                        if added { mio.handle(.taskCreated) }
                    }
            }
        }
    }

    private var meals: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                ForEach(MealKey.allCases) { m in
                    let st = state.mealState(key, m)
                    let kcal = state.mealDisplayItems(date: key, meal: m).reduce(0.0) { $0 + (state.food($1.foodId)?.perServing.calories ?? 0) * $1.quantity }
                    Button { if st == .unconfirmed && !state.mealDisplayItems(date: key, meal: m).isEmpty { withAnimation(DS.bouncy) { state.tickMeal(date: key, meal: m) } } else { editMeal = m } } label: {
                        VStack(alignment: .leading, spacing: 18) {
                            Image(systemName: st == .logged ? "checkmark" : st == .skipped ? "xmark" : m.symbol)
                                .font(.system(size: 28, weight: .semibold)).contentTransition(.symbolEffect(.replace))
                            VStack(alignment: .leading) {
                                Text(m.label).font(.headline)
                                Text(st == .skipped ? "Skipped" : "\(Int(kcal)) kcal").font(.subheadline).opacity(0.6)
                            }
                        }
                        .padding(18).frame(width: 140, alignment: .leading)
                        .foregroundStyle(st == .logged ? Color.paper : .ink)
                        .background(st == .logged ? Color.ink : Color.card, in: .rect(cornerRadius: 24))
                    }
                    .buttonStyle(.press)
                    .contextMenu {
                        Button("Edit", systemImage: "pencil") { editMeal = m }
                        if st == .skipped { Button("Unskip") { state.unskipMeal(date: key, meal: m) } }
                        else { Button("Skip") { state.skipMeal(date: key, meal: m) } }
                    }
                    .sensoryFeedback(.success, trigger: st == .logged) { !$0 && $1 }
                }
            }
        }
        .scrollIndicators(.hidden).scrollClipDisabled()
    }
}

extension MealKey {
    var symbol: String {
        switch self { case .breakfast: "sunrise"; case .lunch: "sun.max"; case .dinner: "moon"; case .snacks: "cup.and.saucer" }
    }
}

// MARK: - Focus timer (drives MeOS's FocusTimer so spent time is banked the same way)

struct MeFocusTimer: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject private var mio: MioController
    @ObservedObject private var timer = FocusTimer.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 28) {
            Capsule().fill(Color.hairline).frame(width: 40, height: 5).padding(.top, 10)
            Text(timer.isActive ? timer.itemTitle : "No task running").font(.title2.bold()).multilineTextAlignment(.center)
            ZStack {
                Ring(progress: timer.progress, width: 16)
                Text(timer.clock).font(.system(size: 72, weight: .bold, design: .rounded)).monospacedDigit()
                    .contentTransition(.numericText(countsDown: true)).animation(DS.spring, value: timer.remaining)
            }
            .frame(width: 280, height: 280)
            HStack(spacing: 10) {
                ForEach([10, 25, 45], id: \.self) { m in
                    Button { restart(m) } label: { Chip(text: "\(m)m", on: timer.total == m * 60) }
                }
                Button { timer.add(minutes: 5) } label: { Chip(text: "+5") }
            }
            .buttonStyle(.press)
            Spacer()
            HStack(spacing: 16) {
                Button { timer.running ? timer.pause() : timer.resume() } label: {
                    BigIcon(name: timer.running ? "pause.fill" : "play.fill", size: 30).contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.press)
                MButton(title: "Done & next", icon: "checkmark") { finish(done: true) }
            }
            Button("Stop") { finish(done: false) }.font(.headline).foregroundStyle(Color.dim)
        }
        .padding(DS.pad)
        .sensoryFeedback(.impact, trigger: timer.running)
        .onChange(of: timer.finished) { _, f in if f { bank() } }
    }

    private func restart(_ m: Int) {
        guard let id = timer.itemID, let t = state.todayPlan().todos.first(where: { $0.id == id }) else { return }
        bank(); state.setTodoMinutes(id, m); timer.begin(t, minutes: m)
    }
    private func bank() {
        if let id = timer.itemID { state.addTodoSpent(id, seconds: timer.drainSpent()) }
    }
    private func finish(done: Bool) {
        timer.pause(); bank()
        let id = timer.itemID
        if done, let id { state.completeTodo(id); mio.handle(.focusCompleted) }
        timer.end()
        if done, let next = state.todayPlan().todos.first(where: { !$0.done && $0.id != id }) {
            timer.begin(next, minutes: next.mins ?? 25)
        } else { dismiss() }
    }
}

// MARK: - Task Mode

struct MeTaskMode: View {
    @EnvironmentObject var state: AppState
    @State private var drag: CGFloat = 0
    @State private var draft = ""
    private var current: FocusItem? { state.todayPlan().todos.first { !$0.done } }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text("TASK MODE").font(.caption.weight(.bold)).tracking(2)
                if state.taskModeCameFromElsewhere { Text("· from \(state.taskMode.device)").font(.caption).foregroundStyle(Color.dim) }
                Spacer()
                Button { state.setTaskMode(false) } label: { BigIcon(name: "xmark", size: 18) }.buttonStyle(.press)
            }
            Spacer()
            if let t = current {
                Text(t.text).font(.system(size: 48, weight: .bold)).tracking(-1.2)
                    .id(t.id).transition(.move(edge: .bottom).combined(with: .opacity))
                Text("\(t.mins ?? 25) min planned · \(t.spent / 60) done").font(.title3).foregroundStyle(Color.dim)
            } else {
                Text("All clear.").font(.system(size: 48, weight: .bold))
            }
            MField(icon: "plus", placeholder: "Add a to-do", text: $draft)
                .onSubmit { withAnimation(DS.spring) { state.addTodo(draft) }; draft = "" }
            Spacer()
            if current != nil { slider }
        }
        .padding(DS.pad)
        .animation(DS.spring, value: current?.id)
    }

    // 1:1 tracking, rubber-band past the end, commit on projected position.
    private var slider: some View {
        GeometryReader { g in
            let maxX = g.size.width - 72
            ZStack(alignment: .leading) {
                Capsule().fill(Color.card)
                Text("Slide to done").font(.headline).frame(maxWidth: .infinity).opacity(1 - drag / maxX)
                Circle().fill(Color.ink).frame(width: 64, height: 64)
                    .overlay { Image(systemName: "checkmark").font(.title2.bold()).foregroundStyle(Color.paper) }
                    .padding(4).offset(x: drag)
                    .gesture(DragGesture()
                        .onChanged { v in
                            let x = max(0, v.translation.width)
                            drag = x > maxX ? maxX + (x - maxX) * 0.2 : x
                        }
                        .onEnded { v in
                            if v.translation.width + v.velocity.width * 0.2 > maxX * 0.8, let t = current {
                                Haptics.success()
                                withAnimation(DS.bouncy) { drag = maxX; state.completeTodo(t.id) }
                                withAnimation(DS.spring.delay(0.25)) { drag = 0 }
                            } else {
                                withAnimation(DS.bouncy) { drag = 0 }
                            }
                        })
            }
        }
        .frame(height: 72)
    }
}
