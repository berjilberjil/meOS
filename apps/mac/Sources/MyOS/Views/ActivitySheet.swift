import SwiftUI
import Charts

/// Activity, opened up. The card on Today answers "am I near my goal"; this
/// answers "how has the week actually gone" — which is a different question and
/// needs the days next to each other.
///
/// Everything here is steps, because steps is what the app actually has. There
/// is no distance or calorie row inventing numbers out of a stride estimate.
struct ActivitySheet: View {
    /// The day the sheet opens on — today unless Today has been swiped.
    var day: String

    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    /// The day being READ. Tapping a ring moves this WITHOUT moving the strip,
    /// so you can compare days without the week sliding under you.
    @State private var selected: String
    /// The last day of the strip. Only the date picker moves this.
    @State private var anchor: String

    init(day: String) {
        self.day = day
        _selected = State(initialValue: day)
        _anchor = State(initialValue: day)
    }

    private var goals: StepGoals { state.stepGoals }
    private var target: Int { goals.daily }
    private func steps(_ key: String) -> Int { state.fitness[key]?.steps ?? 0 }

    /// The seven days ending on the anchor, oldest first.
    private var week: [String] { (0..<7).reversed().map { AppState.addDays(-$0, to: anchor) } }

    /// Any date, not just the last seven. Picking one re-anchors the strip.
    private var selectedDate: Binding<Date> {
        Binding(
            get: { CalMath.date(fromKey: selected) ?? Date() },
            set: { picked in
                let key = AppState.dateKey(picked)
                selected = key
                anchor = key
            }
        )
    }

    private var today: Int { steps(selected) }

    var body: some View {
        let content = ScrollView {
            VStack(alignment: .leading, spacing: Gap.screen) {
                header
                DatePicker("Date", selection: selectedDate,
                           in: ...Date(), displayedComponents: .date)
                    .datePickerStyle(.compact)
                weekStrip
                ring
                streak
                stats
                bars
            }
            .padding(20)
        }
        .background(Palette.background)
        .cardAccent(.activity)

        #if os(iOS)
        content.presentationDetents([.large]).presentationBackground(Palette.background)
        #else
        content.frame(width: 460, height: 640)
        #endif
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Activity")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Palette.text)
                Text(Fmt.day(selected))
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(Palette.faint)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.caption.weight(.bold))
            }
            .buttonStyle(.borderless)
        }
    }

    /// Seven small rings, the way a week reads at a glance. The day on screen
    /// gets the filled label.
    private var weekStrip: some View {
        HStack(spacing: 0) {
            ForEach(week, id: \.self) { key in
                let n = steps(key)
                let f = target > 0 ? min(1, Double(n) / Double(target)) : 0
                let on = key == selected
                Button { selected = key } label: {
                    VStack(spacing: 6) {
                        Text(Fmt.weekdayInitial(key))
                            .font(.caption2.weight(.heavy))
                            .foregroundStyle(on ? Palette.text : Palette.faint)
                        ZStack {
                            Circle().stroke(Palette.border, lineWidth: 3.5)
                            Circle().trim(from: 0, to: max(0.001, f))
                                .stroke(tint(n), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            if on {
                                Circle().stroke(Palette.accent, lineWidth: 1.5).padding(-3.5)
                            }
                        }
                        .frame(width: 26, height: 26)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(Fmt.day(key)), \(n) steps")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    private var ring: some View {
        StepGoalRing(steps: today, goals: goals)
    }

    /// The streak lives here now, next to the thing it is counted on.
    private var streak: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("\(state.stepStreak)")
                    .font(.largeTitle.weight(.bold)).monospacedDigit()
                    .foregroundStyle(state.stepStreak > 0 ? Palette.text : Palette.faint)
                Text("day streak")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(state.stepStreak > 0 ? Palette.muted : Palette.faint)
                Spacer(minLength: 0)
            }
            Text(streakLine)
                .font(.caption).foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            StepStreakStrip()
        }
    }

    /// No freeze days, so the line has to be honest about what is at stake.
    private var streakLine: String {
        let n = state.stepStreak
        let todayHit = steps(state.todayKey) >= goals.daily
        if todayHit {
            return n > 1 ? "\(n) days in a row at \(goals.daily.formatted())+." : "Day one. Tomorrow is what makes it a streak."
        }
        if n > 0 {
            let left = max(0, goals.daily - steps(state.todayKey))
            return "\(left.formatted()) more today or the \(n)-day run ends at midnight."
        }
        return "Hit \(goals.daily.formatted()) today to start one."
    }

    private var stats: some View {
        let logged = week.map { steps($0) }.filter { $0 > 0 }
        let avg = logged.isEmpty ? 0 : logged.reduce(0, +) / logged.count
        let best = week.map { steps($0) }.max() ?? 0
        let hit = target > 0 ? week.filter { steps($0) >= target }.count : 0
        return HStack(spacing: 10) {
            stat(avg.formatted(), "avg / day")
            stat(best.formatted(), "best day")
            stat("\(hit)/7", "at goal")
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.body.weight(.heavy)).monospacedDigit()
                .foregroundStyle(Palette.text)
            Text(label)
                .font(.caption2.weight(.heavy))
                .foregroundStyle(Palette.faint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .cardSkin(.elevated, radius: Radius.md)
    }

    /// The week as bars. Scaled to the bigger of the goal and the best day, so a
    /// day that beat the goal still has somewhere to go.
    private var bars: some View {
        let counts = week.map { steps($0) }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Last 7 days")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Palette.faint)
                Spacer(minLength: 0)
                if target > 0 {
                    Text("goal \(target.formatted())")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Palette.faint)
                }
            }
            // Swift Charts, not seven hand-sized Capsules. The x value is the
            // ISO key (unique) and the axis label is the weekday initial —
            // initials repeat across a week, so they cannot be the value.
            Chart {
                ForEach(Array(week.enumerated()), id: \.element) { i, key in
                    BarMark(x: .value("Day", key), y: .value("Steps", counts[i]))
                        .foregroundStyle(tint(counts[i]))
                        .cornerRadius(5)
                        .opacity(key == selected ? 1 : 0.72)
                }
                if target > 0 {
                    RuleMark(y: .value("Goal", target))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(Palette.faint)
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let key = value.as(String.self) {
                            Text(Fmt.weekdayInitial(key))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(key == selected ? Palette.text : Palette.faint)
                        }
                    }
                }
            }
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 148)
        }
    }

    /// Steps read against the goal, and nothing else. Met is green, short is
    /// orange, and a day with nothing logged is uncoloured — an unworn watch is
    /// not a missed goal.
    private func tint(_ n: Int) -> Color {
        guard n > 0 else { return Palette.faint }
        guard target > 0 else { return Palette.activity }
        return Double(n) / Double(target) >= 1 ? Palette.complete : Palette.activity
    }

    private func compact(_ n: Int) -> String {
        n >= 1000 ? String(format: "%.1fk", Double(n) / 1000) : "\(n)"
    }
}
