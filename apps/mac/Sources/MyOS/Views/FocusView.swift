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
    /// Kept alongside the id so the menu bar and the "time's up" notification can
    /// name the task without reaching into AppState.
    @Published private(set) var itemTitle = ""
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
        itemTitle = item.text
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
        itemTitle = ""
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
            // The menu bar can run a block with no window on screen, so a sound
            // nobody is looking at isn't enough.
            FocusNotify.timesUp(task: itemTitle)
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
    /// The day being shown. Today unless the Today page has been swiped.
    var day: String? = nil
    /// Today shows one date and pages by swipe, so the per-card month grid is
    /// redundant there. Kept for the full-screen tabs.
    var showsCalendar: Bool = true
    @EnvironmentObject var state: AppState
    @ObservedObject private var timer = FocusTimer.shared
    @AppStorage("focus.defaultMinutes") private var defaultMinutes = 25

    @State private var newFocus = ""
    @FocusState private var addFieldActive: Bool
    @State private var pendingDelete: String?
    @State private var showCalendar = false

    private var items: [FocusItem] { state.plan(for: day ?? state.todayKey).todos }
    /// Task Mode always runs today's list, so a card showing a past day doesn't
    /// offer it.
    private var isToday: Bool { (day ?? state.todayKey) == state.todayKey }
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
                        .transition(.knReveal)
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
            if showsCalendar {
            Button { withAnimation(.knNormal) { showCalendar.toggle() } } label: {
                Image(systemName: showCalendar ? "calendar.badge.minus" : "calendar")
                    .font(.system(size: 13, weight: .bold))
            }
            .buttonStyle(KIconButtonStyle(size: 26, color: showCalendar ? Palette.brand : Palette.faint))
            .help(showCalendar ? "Hide the record" : "See the record")
            }

            if nextUp != nil, isToday {
                Button { startSession() } label: {
                    HStack(spacing: 5) {
                        Image(systemName: timer.isActive ? "timer" : "play.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text(timer.isActive ? "Open" : "Task Mode")
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                    }
                }
                .buttonStyle(KSoftButtonStyle(tint: Palette.teal))
                .help("Everything else goes away until you turn it off")
            }
        }
    }

    /// A live strip while a block runs, so the timer is visible without the sheet.
    private var runningPill: some View {
        let item = items.first { $0.id == timer.itemID }
        return Button { state.setTaskMode(true) } label: {
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
        state.setTaskMode(true)
    }

    private func start(_ item: FocusItem) {
        if timer.itemID != item.id {
            bank()
            timer.begin(item, minutes: item.mins ?? defaultMinutes)
        }
        state.setTaskMode(true)
    }

    private func bank() {
        if let id = timer.itemID { state.addTodoSpent(id, seconds: timer.drainSpent()) }
    }
}

// MARK: - The focus session

/// One task at a time: a countdown, the slide that finishes it, and the rest of
/// today underneath. This is the whole of Task Mode — `TaskModeView` just gives
/// it the screen.
struct FocusSessionView: View {
    var defaultMinutes: Int
    let onClose: () -> Void

    @EnvironmentObject var state: AppState
    @ObservedObject private var timer = FocusTimer.shared
    @State private var newTask = ""
    @FocusState private var addFieldActive: Bool

    private var items: [FocusItem] { state.todayPlan().todos }
    private var current: FocusItem? { items.first { $0.id == timer.itemID } }
    private var queue: [FocusItem] { TaskMode.remaining(items, excluding: timer.itemID) }

    var body: some View {
        VStack(spacing: 0) {
            header

            if let item = current {
                // The mode is taller than a phone now that the whole list is on
                // it, so it scrolls — the timer and the slide stay above the fold.
                ScrollView {
                    VStack(spacing: 0) {
                        now(item)
                        ring.padding(.top, 14)
                        lengthChips.padding(.top, 16)
                        SlideToComplete(title: queue.isEmpty ? "slide to finish up" : "slide to done") {
                            doneAndNext()
                        }
                        // A fresh slider per task: the knob parks at the end
                        // after a slide, and that is only right until the next one.
                        .id(item.id)
                        .padding(.horizontal, 20).padding(.top, 20)
                        controls.padding(.horizontal, 20).padding(.top, 10)
                        todayList.padding(.horizontal, 20).padding(.top, 26)
                    }
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
            } else {
                emptyState
                Spacer(minLength: 12)
            }
        }
        .frame(maxWidth: 460)
        .frame(maxWidth: .infinity)
        .background(Palette.bg)
    }

    /// The only chrome in the mode: what it is, how far in, and the way out.
    private var header: some View {
        HStack(spacing: 8) {
            Text("TASK MODE")
                .font(.system(size: 11, weight: .heavy, design: .rounded)).tracking(1.2)
                .foregroundStyle(Palette.teal)
            if !items.isEmpty {
                Text("\(TaskMode.doneCount(items))/\(items.count)")
                    .font(.system(size: 11, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(Palette.faint)
            }
            Spacer(minLength: 4)
            Button { endSession() } label: {
                HStack(spacing: 5) {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                    Text("Exit").font(.system(size: 11, weight: .heavy, design: .rounded))
                }
            }
            .buttonStyle(KSoftButtonStyle(tint: Palette.muted))
            .help("Leave Task Mode — on every device")
        }
        .padding(.horizontal, 20)
        // Clears the traffic lights: the mode hides the sidebar this normally sits beside.
        .padding(.leading, Self.trafficLightInset)
        .padding(.top, Self.topInset).padding(.bottom, 10)
    }

    /// Which task, and what the clock is doing — the two things that were never
    /// obvious enough at a glance.
    private func now(_ item: FocusItem) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text("NOW")
                    .font(.system(size: 11, weight: .heavy, design: .rounded)).tracking(1)
                    .foregroundStyle(Palette.faint)
                Circle().fill(stateColor).frame(width: 4, height: 4)
                Text(stateWord)
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(stateColor)
            }
            Text(item.text)
                .font(.system(size: 24, weight: .semibold)).foregroundStyle(Palette.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
    }

    private var stateWord: String {
        if timer.finished { return "time's up" }
        return timer.running ? "focusing" : "paused"
    }

    private var stateColor: Color {
        if timer.finished { return Palette.green }
        return timer.running ? Palette.teal : Palette.amber
    }

    /// Nothing running: either the list is empty (write one) or the day is done.
    @ViewBuilder private var emptyState: some View {
        let empty = items.isEmpty
        VStack(spacing: 11) {
            Image(systemName: empty ? "list.bullet.rectangle" : "checkmark.seal.fill")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(empty ? Palette.teal : Palette.green)
            Text(empty ? "Nothing on today's list." : "Day crushed.")
                .font(.system(size: 19, weight: .semibold)).foregroundStyle(Palette.text)
            Text(subtitle(empty: empty))
                .font(.system(size: 13)).foregroundStyle(Palette.faint)
                .fixedSize(horizontal: false, vertical: true)
            addField.padding(.top, 8)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 28).padding(.vertical, 44)
    }

    private func subtitle(empty: Bool) -> String {
        if empty { return "Write down what you need to crush. The first one starts the clock." }
        let streak = state.focusStreak()
        return streak > 0 ? "\(streak) clean day\(streak == 1 ? "" : "s") in a row." : "Everything on the list is done."
    }

    private var addField: some View {
        HStack(spacing: 8) {
            TextField("", text: $newTask,
                      prompt: Text("Add a to-do…").foregroundColor(Palette.faint))
                .textFieldStyle(.plain).font(.system(size: 15)).foregroundStyle(Palette.text)
                .focused($addFieldActive)
                .onSubmit(addTask)
            Button(action: addTask) {
                Image(systemName: "plus.circle.fill").font(.system(size: 18))
                    .foregroundStyle(Palette.teal)
            }
            .buttonStyle(KPressStyle())
            .opacity(newTask.isEmpty ? 0.35 : 1)
            .disabled(newTask.isEmpty)
        }
        .knField(focused: addFieldActive)
    }

    private func addTask() {
        let t = newTask.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        state.addTodo(t)
        newTask = ""
    }

    private static var topInset: CGFloat {
        #if os(macOS)
        return 30
        #else
        return 18
        #endif
    }

    private static var trafficLightInset: CGFloat {
        #if os(macOS)
        return 62
        #else
        return 0
        #endif
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
                Text("of \(max(1, timer.total / 60))m")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(Palette.faint)
            }
        }
        .frame(width: 220, height: 220)
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

    /// The rest of the day, in the mode. Tapping one moves the block onto it, so
    /// the order is a suggestion rather than a queue you are stuck in.
    @ViewBuilder private var todayList: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: Gap.tight) {
                HStack(spacing: 6) {
                    Text("TODAY")
                        .font(.system(size: 10, weight: .heavy, design: .rounded)).tracking(0.8)
                        .foregroundStyle(Palette.faint)
                    Text(queue.isEmpty ? "· last one" : "· \(queue.count) left")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .foregroundStyle(Palette.faint)
                    Spacer(minLength: 0)
                }
                ForEach(items) { item in listRow(item) }
                addField.padding(.top, 6)
            }
        }
    }

    private func listRow(_ item: FocusItem) -> some View {
        let isCurrent = item.id == timer.itemID
        return Button { jump(to: item) } label: {
            HStack(spacing: 9) {
                Image(systemName: item.done ? "checkmark.circle.fill" : (isCurrent ? "timer" : "circle"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(item.done ? Palette.green : (isCurrent ? Palette.teal : Palette.border))
                Text(item.text)
                    .font(.system(size: 14, weight: isCurrent ? .semibold : .regular))
                    .strikethrough(item.done, color: Palette.faint)
                    .foregroundStyle(item.done ? Palette.faint : (isCurrent ? Palette.text : Palette.muted))
                    .lineLimit(1)
                Spacer(minLength: 6)
                if item.done, item.spent >= 60 {
                    Text("\(item.spent / 60)m")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .foregroundStyle(Palette.faint)
                } else if !item.done {
                    Text("\(item.mins ?? defaultMinutes)m")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .foregroundStyle(isCurrent ? Palette.teal : Palette.faint)
                }
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(KPressStyle())
        .disabled(item.done)
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

    /// Move the block onto another task on the list.
    private func jump(to item: FocusItem) {
        guard !item.done, item.id != timer.itemID else { return }
        timer.pause()
        bank()
        timer.begin(item, minutes: item.mins ?? defaultMinutes)
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
            // Nothing left. Stay in the mode and say so — leaving is always a
            // deliberate act, because the switch is synced to the other device.
            timer.end()
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
    /// Seeded from today at construction. These used to start at 0/0 and get
    /// corrected in `.onAppear`, which rendered one frame of a nonsense month
    /// ("January 0") before snapping — a visible flash every time you opened it.
    @State private var year = CalMath.cal.component(.year, from: Date())
    @State private var month = CalMath.cal.component(.month, from: Date())
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
        // A floor under the recap so tapping from a 6-todo day to an empty one
        // doesn't collapse the panel and yank everything below it up the page.
        .frame(minHeight: 96, alignment: .top)
    }

    private func shift(_ d: Int) {
        let (y, m) = CalMath.addMonth(year: year, month: month, delta: d)
        withAnimation(.knFast) { year = y; month = m }
    }
}
