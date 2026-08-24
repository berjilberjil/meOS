import SwiftUI

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

    private var target: Int { state.stepsTarget }
    private func steps(_ key: String) -> Int { state.fitness[key]?.steps ?? 0 }

    /// The seven days ending on the one being shown, oldest first.
    private var week: [String] { (0..<7).reversed().map { AppState.addDays(-$0, to: day) } }

    private var today: Int { steps(day) }
    private var fraction: Double { target > 0 ? min(1, Double(today) / Double(target)) : 0 }

    var body: some View {
        let content = ScrollView {
            VStack(alignment: .leading, spacing: Gap.screen) {
                header
                weekStrip
                ring
                stats
                bars
            }
            .padding(20)
        }
        .background(Palette.bg)

        #if os(iOS)
        content.presentationDetents([.large]).presentationBackground(Palette.bg)
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
                Text(Fmt.day(day))
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(Palette.faint)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.caption.weight(.bold))
            }
            .buttonStyle(KIconButtonStyle(size: 28))
        }
    }

    /// Seven small rings, the way a week reads at a glance. The day on screen
    /// gets the filled label.
    private var weekStrip: some View {
        HStack(spacing: 0) {
            ForEach(week, id: \.self) { key in
                let n = steps(key)
                let f = target > 0 ? min(1, Double(n) / Double(target)) : 0
                VStack(spacing: 6) {
                    Text(Fmt.weekdayInitial(key))
                        .font(.caption2.weight(.heavy))
                        .foregroundStyle(key == day ? Palette.text : Palette.faint)
                    ZStack {
                        Circle().stroke(Palette.surface2, lineWidth: 3.5)
                        Circle().trim(from: 0, to: max(0.001, f))
                            .stroke(tint(n), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    .frame(width: 26, height: 26)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var ring: some View {
        ZStack {
            Circle().stroke(Palette.surface2, lineWidth: 14)
            Circle().trim(from: 0, to: max(0.002, fraction))
                .stroke(tint(today), style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
                Text(today.formatted())
                    .font(.largeTitle.weight(.heavy)).monospacedDigit()
                    .foregroundStyle(Palette.text)
                Text("of \(target.formatted()) steps")
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(Palette.faint)
            }
        }
        .frame(width: 190, height: 190)
        .frame(maxWidth: .infinity)
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
        .background(Palette.surface2, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    /// The week as bars. Scaled to the bigger of the goal and the best day, so a
    /// day that beat the goal still has somewhere to go.
    private var bars: some View {
        let counts = week.map { steps($0) }
        let ceiling = max(target, counts.max() ?? 0, 1)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("LAST 7 DAYS")
                    .font(.caption2.weight(.heavy)).tracking(0.6)
                    .foregroundStyle(Palette.faint)
                Spacer(minLength: 0)
                if target > 0 {
                    Text("goal \(target.formatted())")
                        .font(.caption2.weight(.heavy))
                        .foregroundStyle(Palette.faint)
                }
            }
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(Array(week.enumerated()), id: \.element) { i, key in
                    let n = counts[i]
                    VStack(spacing: 6) {
                        Text(n > 0 ? compact(n) : "–")
                            .font(.caption2.weight(.heavy)).monospacedDigit()
                            .foregroundStyle(Palette.faint)
                        Capsule()
                            .fill(tint(n))
                            .frame(height: max(3, 96 * CGFloat(n) / CGFloat(ceiling)))
                        Text(Fmt.weekdayInitial(key))
                            .font(.caption2.weight(.heavy))
                            .foregroundStyle(key == day ? Palette.text : Palette.faint)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 128, alignment: .bottom)
        }
    }

    /// Nothing logged is grey, not red — an unworn watch is not a missed goal.
    private func tint(_ n: Int) -> Color {
        guard n > 0 else { return Palette.border }
        guard target > 0 else { return Palette.flame }
        let f = Double(n) / Double(target)
        if f >= 1 { return Palette.green }
        return f >= 0.5 ? Palette.amber : Palette.flame
    }

    private func compact(_ n: Int) -> String {
        n >= 1000 ? String(format: "%.1fk", Double(n) / 1000) : "\(n)"
    }
}
