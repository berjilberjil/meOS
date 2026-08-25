#if os(macOS)
import SwiftUI
import AppKit

/// The macOS menu bar item. It is deliberately independent of Task Mode: the
/// point is being able to crush a task with the MyOS window shut, whether or not
/// the app has taken over the screen.
struct MenuBarView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var timer = FocusTimer.shared
    @AppStorage("focus.defaultMinutes") private var defaultMinutes = 25

    private var items: [FocusItem] { state.todayPlan().todos }
    private var current: FocusItem? { items.first { $0.id == timer.itemID } }
    private var queue: [FocusItem] { TaskMode.remaining(items, excluding: timer.itemID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if state.phase != .loggedIn {
                locked
            } else if let item = current {
                running(item)
            } else {
                idle
            }

            Divider().overlay(Palette.border)
            footer
        }
        .padding(14)
        .frame(width: 288)
        .background(Palette.background)
    }

    // MARK: - States

    private var locked: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("MyOS is locked")
                .font(.footnote.weight(.semibold)).foregroundStyle(Palette.text)
            Text("Unlock the app to see today's list.")
                .font(.caption).foregroundStyle(Palette.faint)
        }
    }

    private func running(_ item: FocusItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                ring
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.text)
                        .font(.footnote.weight(.semibold)).foregroundStyle(Palette.text)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    Text(timer.finished ? "Time's up" : (timer.running ? "Focusing" : "Paused"))
                        .font(.caption2.weight(.heavy))
                        .foregroundStyle(timer.finished ? Palette.green : Palette.faint)
                }
                Spacer(minLength: 0)
            }

            Button { doneAndNext() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark").font(.caption2.weight(.bold))
                    Text(queue.isEmpty ? "Done — finish up" : "Done & next")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(Palette.green).controlSize(.large).frame(maxWidth: .infinity)

            HStack(spacing: 8) {
                Button { toggleRun() } label: {
                    HStack(spacing: 5) {
                        Image(systemName: timer.running ? "pause.fill" : "play.fill")
                            .font(.caption2.weight(.bold))
                        Text(timer.running ? "Pause" : "Resume")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).controlSize(.large).frame(maxWidth: .infinity)
                .disabled(timer.finished)
                .opacity(timer.finished ? 0.5 : 1)

                Button { timer.add(minutes: 5) } label: {
                    Text("+5m").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).controlSize(.large).frame(maxWidth: .infinity)
            }

            upNext
        }
    }

    private var idle: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let next = TaskMode.nextTask(in: items) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("UP NEXT")
                        .font(.caption2.weight(.heavy)).tracking(0.6)
                        .foregroundStyle(Palette.faint)
                    Text(next.text)
                        .font(.footnote.weight(.semibold)).foregroundStyle(Palette.text)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                Button { start(next) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill").font(.caption2.weight(.bold))
                        Text("Start \(next.mins ?? defaultMinutes)m block")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(Palette.success).controlSize(.large).frame(maxWidth: .infinity)
                upNext
            } else if items.isEmpty {
                Text("Nothing on today's list.")
                    .font(.footnote.weight(.semibold)).foregroundStyle(Palette.text)
                Text("Open MyOS and write down what you need to crush.")
                    .font(.caption2).foregroundStyle(Palette.faint)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: 7) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.subheadline).foregroundStyle(Palette.green)
                    Text("Day crushed.")
                        .font(.footnote.weight(.semibold)).foregroundStyle(Palette.text)
                }
            }
        }
    }

    private var ring: some View {
        ZStack {
            Circle().stroke(Palette.surfaceElevated, lineWidth: 5)
            Circle().trim(from: 0, to: max(0.01, timer.progress))
                .stroke(timer.finished ? Palette.green : Palette.success,
                        style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(timer.clock)
                .font(.footnote.weight(.heavy)).monospacedDigit()
                .foregroundStyle(timer.finished ? Palette.green : Palette.text)
        }
        .frame(width: 58, height: 58)
    }

    @ViewBuilder private var upNext: some View {
        if !queue.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Text("THEN")
                    .font(.caption2.weight(.heavy)).tracking(0.6)
                    .foregroundStyle(Palette.faint)
                // Clicking one jumps the queue — the same as picking it in the app.
                ForEach(queue.prefix(4)) { q in
                    Button { start(q) } label: {
                        HStack(spacing: 7) {
                            Circle().fill(Palette.border).frame(width: 4, height: 4)
                            Text(q.text).font(.caption).foregroundStyle(Palette.muted)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Focus on this one instead")
                }
                if queue.count > 4 {
                    Text("+\(queue.count - 4) more")
                        .font(.caption2).foregroundStyle(Palette.faint)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button { state.toggleTaskMode() } label: {
                HStack(spacing: 5) {
                    Image(systemName: state.taskMode.on ? "checkmark.circle.fill" : "target")
                        .font(.caption2.weight(.bold))
                    Text("Task Mode")
                }
            }
            .buttonStyle(.bordered).tint(state.taskMode.on ? Palette.success : Palette.muted)
            .disabled(state.phase != .loggedIn)
            .help("Hide everything but today's task, on every device")

            Spacer(minLength: 0)

            Button { openApp() } label: {
                Text("Open MyOS").font(.caption2.weight(.heavy))
            }
            .buttonStyle(.borderless).tint(Palette.faint)
        }
    }

    // MARK: - Actions

    private func bank() {
        if let id = timer.itemID { state.addTodoSpent(id, seconds: timer.drainSpent()) }
    }

    private func toggleRun() {
        if timer.running { timer.pause(); bank() } else { timer.resume() }
    }

    private func start(_ item: FocusItem) {
        guard timer.itemID != item.id else { return }
        bank()
        timer.begin(item, minutes: item.mins ?? defaultMinutes)
    }

    private func doneAndNext() {
        guard let item = current else { return }
        timer.pause()
        bank()
        state.completeTodo(item.id)
        let remaining = TaskMode.remaining(state.todayPlan().todos, excluding: timer.itemID)
        if let next = remaining.first {
            timer.begin(next, minutes: next.mins ?? defaultMinutes)
        } else {
            timer.end()
        }
    }

    private func openApp() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSApplication.shared.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
    }
}

/// What sits in the menu bar itself: the countdown while a block runs, otherwise
/// a target with however many things are left today.
struct MenuBarLabel: View {
    @ObservedObject var state: AppState
    @ObservedObject private var timer = FocusTimer.shared

    private var left: Int { TaskMode.remaining(state.todayPlan().todos).count }

    var body: some View {
        if state.phase == .loggedIn, timer.isActive {
            HStack(spacing: 4) {
                Image(systemName: timer.finished ? "checkmark.circle.fill" : "timer")
                Text(TaskMode.menuLabel(task: timer.itemTitle, clock: timer.clock))
            }
        } else if state.phase == .loggedIn, left > 0 {
            HStack(spacing: 3) {
                Image(systemName: "target")
                Text("\(left)")
            }
        } else {
            Image(systemName: "target")
        }
    }
}
#endif
