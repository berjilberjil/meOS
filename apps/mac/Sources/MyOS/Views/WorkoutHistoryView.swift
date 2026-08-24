import SwiftUI

/// What you actually trained. Reads only `training.dayLog` — a program can be
/// renamed, rebuilt or deleted and these entries still say what happened,
/// because each one snapshots its own title, muscle groups and sets.
struct WorkoutHistoryView: View {
    @EnvironmentObject var state: AppState
    @State private var expanded: String?

    private var dates: [String] { state.workoutHistoryDates() }

    var body: some View {
        VStack(alignment: .leading, spacing: Gap.screen) {
            if dates.isEmpty {
                Card(padding: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 24, weight: .semibold)).foregroundStyle(Palette.brand)
                        Text("No workouts logged yet")
                            .font(.system(size: 18, weight: .semibold)).foregroundStyle(Palette.text)
                        Text("Start a workout from Today and every set you tick lands here.")
                            .font(.system(size: 13)).foregroundStyle(Palette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .knRise(0)
            } else {
                summary.knRise(0)
                VStack(alignment: .leading, spacing: Gap.row) {
                    KFieldLabel(text: "Recent workouts")
                    ForEach(dates, id: \.self) { d in
                        HistoryRow(date: d,
                                   isOpen: expanded == d,
                                   toggle: { withAnimation(.knNormal) { expanded = expanded == d ? nil : d } })
                    }
                }
                .knRise(1)
            }
        }
    }

    /// The last 28 days at a glance — this is the number that tells you whether
    /// a program is being run or just admired.
    private var summary: some View {
        let recent = dates.filter { ($0 >= AppState.addDays(-27, to: state.todayKey)) }
        let done = recent.filter { state.workoutDayLog($0).done }.count
        let sets = recent.reduce(0) { acc, d in
            acc + (state.workoutDayLog(d).entries?.reduce(0) { $0 + $1.doneSets } ?? 0)
        }
        let volume = recent.reduce(0.0) { acc, d in
            acc + (state.workoutDayLog(d).entries?.reduce(0.0) { $0 + $1.volumeKg } ?? 0)
        }
        return Card(padding: 16) {
            HStack(spacing: 18) {
                stat("\(done)", done == 1 ? "workout" : "workouts")
                stat("\(sets)", "sets")
                stat(volume >= 1000 ? "\(Int((volume / 1000).rounded()))t" : "\(Int(volume.rounded()))kg", "volume")
                Spacer(minLength: 0)
                Text("LAST 28 DAYS")
                    .font(.system(size: 9, weight: .heavy, design: .rounded)).tracking(0.6)
                    .foregroundStyle(Palette.faint)
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 20, weight: .bold, design: .rounded)).monospacedDigit()
                .foregroundStyle(Palette.text)
            Text(label.uppercased()).font(.system(size: 9, weight: .heavy, design: .rounded)).tracking(0.5)
                .foregroundStyle(Palette.faint)
        }
    }
}

private struct HistoryRow: View {
    @EnvironmentObject var state: AppState
    let date: String
    let isOpen: Bool
    let toggle: () -> Void

    private var log: WorkoutDayLog { state.workoutDayLog(date) }
    private var entries: [ExerciseLog] { (log.entries ?? []).filter { $0.doneSets > 0 } }
    private var groups: [MuscleGroup] {
        var seen: [MuscleGroup] = []
        for e in entries where !seen.contains(e.group) { seen.append(e.group) }
        return seen
    }

    var body: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: isOpen ? 12 : 0) {
                Button(action: toggle) { summaryRow }
                    .buttonStyle(KPressStyle())
                    .onHover { h in cursor(h) }
                if isOpen { detail }
            }
        }
    }

    private var summaryRow: some View {
        HStack(spacing: 12) {
            Image(systemName: log.done ? "checkmark.circle.fill" : "circle.dotted")
                .font(.system(size: 16)).foregroundStyle(log.done ? Palette.green : Palette.amber)
            VStack(alignment: .leading, spacing: 3) {
                Text(log.title ?? "Workout")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(Palette.faint)
                if !groups.isEmpty && !isOpen {
                    HStack(spacing: 4) {
                        ForEach(groups.prefix(4), id: \.self) { g in
                            Circle().fill(g.tint).frame(width: 6, height: 6)
                        }
                        Text(groups.map(\.label).joined(separator: " · "))
                            .font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 4)
            Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                .font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.faint)
        }
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        let sets = entries.reduce(0) { $0 + $1.doneSets }
        let volume = entries.reduce(0.0) { $0 + $1.volumeKg }
        var bits = [Fmt.day(date)]
        if sets > 0 { bits.append("\(sets) set\(sets == 1 ? "" : "s")") }
        if volume > 0 { bits.append("\(Int(volume.rounded())) kg") }
        if !log.done { bits.append("in progress") }
        return bits.joined(separator: " · ")
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 10) {
            if entries.isEmpty {
                Text("Marked done without logging sets.")
                    .font(.system(size: 12)).foregroundStyle(Palette.faint)
            }
            ForEach(entries) { e in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        Circle().fill(e.group.tint).frame(width: 6, height: 6)
                        Text(state.exercise(e.exerciseId)?.name ?? "Exercise")
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.text)
                        Spacer(minLength: 4)
                        Text(e.group.label)
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .foregroundStyle(Palette.faint)
                    }
                    ForEach(Array(e.sets.enumerated()), id: \.element.id) { i, s in
                        HStack(spacing: 10) {
                            Text("Set \(i + 1)")
                                .font(.system(size: 11)).foregroundStyle(Palette.faint)
                                .frame(width: 42, alignment: .leading)
                            Text(s.summary)
                                .font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit()
                                .foregroundStyle(Palette.text)
                            Spacer(minLength: 0)
                        }
                    }
                    if let n = e.note, !n.isEmpty {
                        Text(n).font(.system(size: 11)).foregroundStyle(Palette.faint)
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }
}
