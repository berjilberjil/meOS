import SwiftUI

// Today's focus — the daily crush list. Beyond a checklist it keeps three things:
// a focus timer that walks the day's tasks one at a time, a calendar record of how
// every past day went, and the streak that falls out of it.

// MARK: - Timer engine

/// Lives outside the view tree so a running session survives closing the sheet,
/// switching tabs, or the card redrawing.
@MainActor
final class FocusTimer: ObservableObject {
    static let shared = FocusTimer()

    @Published private(set) var itemID: String?
    @Published private(set) var total = 0        // planned seconds
    @Published private(set) var remaining = 0
    @Published private(set) var running = false

    private var ticker: Timer?
    private var lastTick: Date?
    /// Seconds run since they were last written into the day plan.
    private var unbanked = 0

    var isActive: Bool { itemID != nil }
    var finished: Bool { isActive && remaining == 0 }
    var progress: Double { total > 0 ? Double(total - remaining) / Double(total) : 0 }

    var clock: String {
        let m = remaining / 60, s = remaining % 60
        return String(format: "%d:%02d", m, s)
    }

    func begin(_ item: FocusItem, minutes: Int) {
        stopTicking()
        itemID = item.id
        total = max(60, minutes * 60)
        remaining = total
        unbanked = 0
        running = false
        resume()
    }

    func resume() {
        guard isActive, !running, remaining > 0 else { return }
        running = true
        lastTick = Date()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.step() }
        }
        // .common so the countdown keeps ticking while a sheet or menu is tracking.
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    func pause() {
        guard running else { return }
        step()                     // bank the partial second before stopping
        running = false
        stopTicking()
    }

    func add(minutes: Int) {
        guard isActive else { return }
        total += minutes * 60
        remaining += minutes * 60
        if !running { resume() }
    }

    func end() {
        stopTicking()
        itemID = nil
        running = false
        total = 0; remaining = 0
    }

    /// Seconds run since the last drain — the caller writes them into the day plan.
    func drainSpent() -> Int {
        let s = unbanked
        unbanked = 0
        return s
    }

    private func step() {
        let now = Date()
        // Wall-clock delta, so a slept Mac or a backgrounded phone doesn't lose time.
        let delta = max(0, Int(now.timeIntervalSince(lastTick ?? now).rounded()))
        lastTick = now
        guard delta > 0 else { return }
        unbanked += min(delta, remaining + delta)
        remaining = max(0, remaining - delta)
        if remaining == 0 {
            running = false
            stopTicking()
            Haptics.success()
            SoundPlayer.drop()
        }
    }

    private func stopTicking() {
        ticker?.invalidate()
        ticker = nil
        lastTick = nil
    }
}

// MARK: - The card

struct FocusCard: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var timer = FocusTimer.shared
    @AppStorage("focus.defaultMinutes") private var defaultMinutes = 25

    @State private var newFocus = ""
    @FocusState private var addFieldActive: Bool
    @State private var pendingDelete: String?
    @State private var showCalendar = false
    @State private var showSession = false

    private var items: [FocusItem] { state.todayPlan().todos }
    private var doneCount: Int { items.filter(\.done).count }
    private var nextUp: FocusItem? { items.first { !$0.done } }
    private var focusedSecondsToday: Int { items.reduce(0) { $0 + $1.spent } }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                header
                if timer.isActive { runningPill }

                if items.isEmpty {
                    Text("Add the things you need to crush today. Start a focus block and go one at a time.")
                        .font(.system(size: 13)).foregroundStyle(Palette.faint)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    progressBar
                    ForEach(items) { item in row(item) }
                }

                addField

                if showCalendar {
                    Divider().overlay(Palette.border).padding(.top, 2)
                    FocusCalendarPanel()
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .holdToDelete(
            isPresented: Binding(get: { pendingDelete != nil },
                                 set: { if !$0 { pendingDelete = nil } }),
            title: "Remove this to-do?",
            message: "This can't be undone."
        ) {
            if let id = pendingDelete { state.removeTodo(id) }
            pendingDelete = nil
        }
        .sheet(isPresented: $showSession) { sessionSheet }
    }

    @ViewBuilder private var sessionSheet: some View {
        let view = FocusSessionView(defaultMinutes: defaultMinutes) { showSession = false }
            .environmentObject(state)
        #if os(iOS)
        view.presentationDetents([.large]).presentationBackground(Palette.bg)
        #else
        view.frame(width: 460)
        #endif
    }

    private var header: some View {
        HStack(spacing: 8) {
            SectionTitle(text: "Today's focus")
            if !items.isEmpty {
                Text("\(doneCount)/\(items.count)")
                    .font(.system(size: 11, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(doneCount == items.count ? Palette.green : Palette.faint)
            }
            let streak = state.focusStreak()
            if streak > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "flame.fill").font(.system(size: 9, weight: .bold))
                    Text("\(streak)").font(.system(size: 10, weight: .heavy, design: .rounded))
                }
                .foregroundStyle(Palette.flame)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Palette.flame.opacity(0.14), in: Capsule())
                .help("\(streak) clean day\(streak == 1 ? "" : "s") in a row")
            }
            Spacer(minLength: 4)
            if focusedSecondsToday >= 60 {
                Text("\(focusedSecondsToday / 60)m focused")
                    .font(.system(size: 10, weight: .heavy, design: .rounded)).foregroundStyle(Palette.faint)
            }
            Button { withAnimation(.knNormal) { showCalendar.toggle() } } label: {
                Image(systemName: showCalendar ? "calendar.badge.minus" : "calendar")
                    .font(.system(size: 13, weight: .bold))
            }
            .buttonStyle(KIconButtonStyle(size: 26, color: showCalendar ? Palette.brand : Palette.faint))
            .help(showCalendar ? "Hide the record" : "See the record")

            if nextUp != nil {
                Button { startSession() } label: {
                    HStack(spacing: 5) {
                        Image(systemName: timer.isActive ? "timer" : "play.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text(timer.isActive ? "Open" : "Focus")
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                    }
                }
                .buttonStyle(KSoftButtonStyle(tint: Palette.teal))
            }
        }
    }

    /// A live strip while a block runs, so the timer is visible without the sheet.
    private var runningPill: some View {
        let item = items.first { $0.id == timer.itemID }
        return Button { showSession = true } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle().stroke(Palette.teal.opacity(0.25), lineWidth: 3)
                    Circle().trim(from: 0, to: max(0.02, timer.progress))
                        .stroke(timer.finished ? Palette.green : Palette.teal,
                                style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item?.text ?? "Focus block")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.text)
                        .lineLimit(1)
                    Text(timer.finished ? "Time's up" : (timer.running ? "Focusing" : "Paused"))
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .foregroundStyle(timer.finished ? Palette.green : Palette.faint)
                }
                Spacer(minLength: 0)
                Text(timer.clock)
                    .font(.system(size: 17, weight: .heavy, design: .rounded)).monospacedDigit()
                    .foregroundStyle(timer.finished ? Palette.green : Palette.teal)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(Palette.teal.opacity(0.10), in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Palette.teal.opacity(0.35), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(KPressStyle())
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.surface2)
                Capsule().fill(doneCount == items.count ? Palette.green : Palette.teal)
                    .frame(width: geo.size.width * (items.isEmpty ? 0 : Double(doneCount) / Double(items.count)))
            }
        }
        .frame(height: 5)
        .animation(.knNormal, value: doneCount)
    }

    private func row(_ item: FocusItem) -> some View {
        let isCurrent = timer.itemID == item.id
        return HStack(spacing: 10) {
            Button { state.toggleTodo(item.id) } label: {
                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(item.done ? Palette.green : Palette.teal)
            }
            .buttonStyle(KPressStyle())

            VStack(alignment: .leading, spacing: 1) {
                Text(item.text)
                    .font(.system(size: 15, weight: .medium))
                    .strikethrough(item.done, color: Palette.faint)
                    .foregroundStyle(item.done ? Palette.faint : Palette.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if item.spent >= 60 {
                    Text("\(item.spent / 60)m focused")
                        .font(.system(size: 10, weight: .heavy, design: .rounded)).foregroundStyle(Palette.faint)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { state.toggleTodo(item.id) }

            if !item.done {
                Button { start(item) } label: {
                    Image(systemName: isCurrent ? "timer" : "play.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(isCurrent ? Palette.teal : Palette.muted)
                }
                .buttonStyle(KPressStyle())
                .help(isCurrent ? "Open the running block" : "Focus on this one")
            }
            Button { pendingDelete = item.id } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(KIconButtonStyle(size: 22))
        }
    }

    private var addField: some View {
        HStack(spacing: 8) {
            TextField("", text: $newFocus,
                      prompt: Text("Add a to-do…").foregroundColor(Palette.faint))
                .textFieldStyle(.plain).font(.system(size: 14)).foregroundStyle(Palette.text)
                .focused($addFieldActive)
                .onSubmit(add)
            Button(action: add) {
                Image(systemName: "plus.circle.fill").font(.system(size: 18))
                    .foregroundStyle(Palette.teal)
            }
            .buttonStyle(KPressStyle())
            .opacity(newFocus.isEmpty ? 0.35 : 1)
            .disabled(newFocus.isEmpty)
        }
        .knField(focused: addFieldActive)
    }

    private func add() {
        let t = newFocus.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        state.addTodo(t)
        newFocus = ""
    }

    private func startSession() {
        if !timer.isActive, let next = nextUp {
            timer.begin(next, minutes: next.mins ?? defaultMinutes)
        }
        showSession = true
    }

    private func start(_ item: FocusItem) {
        if timer.itemID != item.id {
            bank()
            timer.begin(item, minutes: item.mins ?? defaultMinutes)
        }
        showSession = true
    }

    private func bank() {
        if let id = timer.itemID { state.addTodoSpent(id, seconds: timer.drainSpent()) }
    }
}

// MARK: - The focus session

/// One task at a time: a countdown, then "Done & next" pulls the following one in.
struct FocusSessionView: View {
    var defaultMinutes: Int
    let onClose: () -> Void

    @EnvironmentObject var state: AppState
    @ObservedObject private var timer = FocusTimer.shared

    private var items: [FocusItem] { state.todayPlan().todos }
    private var current: FocusItem? { items.first { $0.id == timer.itemID } }
    private var queue: [FocusItem] { items.filter { !$0.done && $0.id != timer.itemID } }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Focus").font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(Palette.text)
                Spacer()
                Button { endSession() } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .bold))
                }
                .buttonStyle(KIconButtonStyle(size: 28))
            }
            .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 6)

            if let item = current {
                ring
                Text(item.text)
                    .font(.system(size: 19, weight: .semibold)).foregroundStyle(Palette.text)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 28).padding(.top, 16)

                lengthChips.padding(.top, 14)
                controls.padding(.horizontal, 20).padding(.top, 18)
                upNext.padding(.horizontal, 20).padding(.top, 20)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 38)).foregroundStyle(Palette.green)
                    Text("Nothing left to crush.")
                        .font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.text)
                    Text("Add a to-do on Today to start another block.")
                        .font(.system(size: 13)).foregroundStyle(Palette.faint)
                }
                .padding(.vertical, 48)
            }
            Spacer(minLength: 12)
        }
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity)
        .background(Palette.bg)
    }

    private var ring: some View {
        ZStack {
            Circle().stroke(Palette.surface2, lineWidth: 12)
            Circle().trim(from: 0, to: max(0.004, timer.progress))
                .stroke(timer.finished ? Palette.green : Palette.teal,
                        style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.9), value: timer.remaining)
            VStack(spacing: 2) {
                Text(timer.clock)
                    .font(.system(size: 44, weight: .heavy, design: .rounded)).monospacedDigit()
                    .foregroundStyle(timer.finished ? Palette.green : Palette.text)
                Text(timer.finished ? "Time's up" : (timer.running ? "focusing" : "paused"))
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(Palette.faint)
            }
        }
        .frame(width: 208, height: 208)
        .padding(.top, 10)
    }

    private var lengthChips: some View {
        HStack(spacing: 8) {
            ForEach([10, 25, 45], id: \.self) { m in
                Button { restart(minutes: m) } label: {
                    Text("\(m)m").font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(timer.total == m * 60 ? .white : Palette.muted)
                        .padding(.horizontal, 13).padding(.vertical, 7)
                        .background(timer.total == m * 60 ? Palette.teal : Palette.surface2, in: Capsule())
                }
                .buttonStyle(KPressStyle())
            }
            Button { timer.add(minutes: 5) } label: {
                Text("+5").font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(Palette.teal)
                    .padding(.horizontal, 13).padding(.vertical, 7)
                    .background(Palette.teal.opacity(0.14), in: Capsule())
            }
            .buttonStyle(KPressStyle())
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            Button { doneAndNext() } label: {
                HStack(spacing: 7) {
                    Image(systemName: "checkmark").font(.system(size: 14, weight: .bold))
                    Text(queue.isEmpty ? "Done — finish up" : "Done & next")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(KPrimaryButtonStyle(tint: Palette.green, fullWidth: true))

            HStack(spacing: 10) {
                Button { toggleRun() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: timer.running ? "pause.fill" : "play.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text(timer.running ? "Pause" : "Resume")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(KSecondaryButtonStyle(fullWidth: true))
                .disabled(timer.finished)
                .opacity(timer.finished ? 0.5 : 1)

                Button { skip() } label: {
                    Text(queue.isEmpty ? "Stop" : "Skip").frame(maxWidth: .infinity)
                }
                .buttonStyle(KSecondaryButtonStyle(fullWidth: true))
            }
        }
    }

    @ViewBuilder private var upNext: some View {
        if !queue.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                SectionTitle(text: "Up next")
                ForEach(queue.prefix(4)) { q in
                    HStack(spacing: 8) {
                        Circle().fill(Palette.border).frame(width: 5, height: 5)
                        Text(q.text).font(.system(size: 13)).foregroundStyle(Palette.muted).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }
                if queue.count > 4 {
                    Text("+\(queue.count - 4) more").font(.system(size: 11)).foregroundStyle(Palette.faint)
                }
            }
        }
    }

    // MARK: Actions

    private func bank() {
        if let id = timer.itemID { state.addTodoSpent(id, seconds: timer.drainSpent()) }
    }

    private func toggleRun() {
        if timer.running { timer.pause(); bank() } else { timer.resume() }
    }

    private func restart(minutes: Int) {
        guard let item = current else { return }
        bank()
        state.setTodoMinutes(item.id, minutes)
        timer.begin(item, minutes: minutes)
    }

    private func doneAndNext() {
        guard let item = current else { return }
        timer.pause()
        bank()
        state.completeTodo(item.id)
        Haptics.success()
        advance()
    }

    private func skip() {
        timer.pause()
        bank()
        advance()
    }

    private func advance() {
        // `queue` was computed before the completion landed, so re-read the plan.
        let remaining = state.todayPlan().todos.filter { !$0.done && $0.id != timer.itemID }
        if let next = remaining.first {
            timer.begin(next, minutes: next.mins ?? defaultMinutes)
        } else {
            timer.end()
            onClose()
        }
    }

    private func endSession() {
        timer.pause()
        bank()
        onClose()
    }
}

// MARK: - The record

/// A month of days coloured by how the focus list went: green all done, amber
/// partial, red logged-but-missed. Tap a day to read it back.
struct FocusCalendarPanel: View {
    @EnvironmentObject var state: AppState
    @State private var year = 0
    @State private var month = 0
    @State private var selected: String = AppState.dateKey(Date())

    private func verdict(_ key: String) -> Color? {
        switch FocusRecord.verdict(state.plan(for: key).todos) {
        case .empty:   return nil
        case .done:    return Palette.green
        case .partial: return Palette.amber
        case .missed:  return Palette.red.opacity(0.8)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            KMonthHeader(year: year, month: month, showToday: false,
                         onPrev: { shift(-1) }, onNext: { shift(1) })
            KMonthGrid(year: year, month: month, selected: selected,
                       dot: { verdict($0) },
                       onTap: { selected = $0 })
            legend
            dayRecap
        }
        .onAppear {
            if year == 0 {
                let c = CalMath.cal.dateComponents([.year, .month], from: Date())
                year = c.year ?? 2026; month = c.month ?? 1
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 12) {
            legendDot(Palette.green, "all done")
            legendDot(Palette.amber, "partly")
            legendDot(Palette.red.opacity(0.8), "missed")
            Spacer(minLength: 0)
        }
    }

    private func legendDot(_ c: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(c).frame(width: 6, height: 6)
            Text(label).font(.system(size: 10, weight: .heavy, design: .rounded)).foregroundStyle(Palette.faint)
        }
    }

    @ViewBuilder private var dayRecap: some View {
        let todos = state.plan(for: selected).todos
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Text(Fmt.day(selected))
                    .font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundStyle(Palette.text)
                if !todos.isEmpty {
                    Text("\(todos.filter(\.done).count)/\(todos.count)")
                        .font(.system(size: 11, weight: .semibold)).monospacedDigit().foregroundStyle(Palette.faint)
                }
                Spacer(minLength: 0)
                let mins = FocusRecord.focusedMinutes(todos)
                if mins > 0 {
                    Text("\(mins)m focused")
                        .font(.system(size: 10, weight: .heavy, design: .rounded)).foregroundStyle(Palette.teal)
                }
            }
            if todos.isEmpty {
                Text("Nothing on the list that day.")
                    .font(.system(size: 12)).foregroundStyle(Palette.faint)
            } else {
                ForEach(todos) { t in
                    HStack(spacing: 8) {
                        Image(systemName: t.done ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 12)).foregroundStyle(t.done ? Palette.green : Palette.border)
                        Text(t.text).font(.system(size: 12))
                            .strikethrough(t.done, color: Palette.faint)
                            .foregroundStyle(t.done ? Palette.faint : Palette.muted)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .padding(.top, 2)
    }

    private func shift(_ d: Int) {
        let (y, m) = CalMath.addMonth(year: year, month: month, delta: d)
        withAnimation(.knFast) { year = y; month = m }
    }
}
