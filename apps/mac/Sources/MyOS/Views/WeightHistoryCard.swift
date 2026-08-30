import SwiftUI
import Charts

/// Every weigh-in you have, as a line.
///
/// Before this the only way to see a past weight was a strip of seven
/// chips under the logging field — the last week, as text, with no
/// sense of direction. A weight is the one number in MyOS that means
/// nothing on its own: 79.4 is neither good nor bad, and the only
/// question ever asked of it is which way it has been going. That
/// question needs a shape, so it gets a chart.
///
/// It lives on the Fitness tab rather than Today. Today answers "what
/// about right now", and a quarter of weigh-ins is not a right-now
/// question; the dial on Today already logs the number, and this is
/// where you come to read it back.
struct WeightHistoryCard: View {
    @EnvironmentObject var state: AppState
    @State private var range: WeightHistory.Range = .quarter

    private var points: [WeightHistory.Point] {
        WeightHistory.series(state.fitness, range: range, today: state.todayKey)
    }
    private var target: Double? {
        let t = state.fitnessProfile.targetWeightKg
        return (t ?? 0) > 0 ? t : nil
    }

    var body: some View {
        let pts = points
        let summary = WeightHistory.summary(pts)
        return Card {
            VStack(alignment: .leading, spacing: 14) {
                header
                if let summary, pts.count >= 2 {
                    stats(summary)
                    chart(pts)
                } else {
                    empty(logged: summary != nil)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                SectionTitle(text: "Weight trend")
                Spacer()
                if let target {
                    Text("goal \(Fmt.trimKg(target)) kg")
                        .font(.caption2.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(Palette.faint)
                }
            }
            Picker("", selection: $range) {
                ForEach(WeightHistory.Range.allCases) { r in Text(r.label).tag(r) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    /// Direction first, because that is the only thing being asked.
    private func stats(_ s: WeightHistory.Summary) -> some View {
        HStack(alignment: .top, spacing: Space.sm) {
            stat(changeLabel(s.change), "change",
                 // Neither direction is "wrong" without knowing the goal,
                 // and MyOS reserves orange for what has actually gone
                 // wrong. So movement is the accent and a plateau is not.
                 tint: abs(s.change) < 0.05 ? Palette.muted : Palette.action)
            stat("\(Fmt.trimKg(s.lightest))", "lightest")
            stat("\(Fmt.trimKg(s.heaviest))", "heaviest")
            stat("\(s.count)", s.count == 1 ? "weigh-in" : "weigh-ins")
        }
    }

    private func stat(_ value: String, _ label: String, tint: Color = Palette.text) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(value)
                .font(.body.weight(.bold)).monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(label.uppercased())
                .font(.myCaption).tracking(0.4)
                .foregroundStyle(Palette.faint)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func changeLabel(_ d: Double) -> String {
        if abs(d) < 0.05 { return "—" }
        return (d > 0 ? "+" : "−") + Fmt.trimKg(abs(d))
    }

    private func chart(_ pts: [WeightHistory.Point]) -> some View {
        let window = WeightHistory.domain(pts, target: target)
        return Chart {
            // The area is what makes a two-kilo drift legible at this
            // height — the line alone reads as almost horizontal.
            //
            // `yStart` is not decoration. An `AreaMark` given only a `y`
            // fills from the value down to a baseline of zero, and zero
            // kilos is about thirty plot-heights below a window that
            // spans 76 to 81. Charts does not clip marks to the plot
            // area, so that fill painted straight out of the bottom of
            // the card and on down the page, over everything under it.
            // The floor of the window is where the area actually ends.
            ForEach(pts) { p in
                AreaMark(x: .value("Day", p.date),
                         yStart: .value("kg", window.lowerBound),
                         yEnd: .value("kg", p.kg))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(.linearGradient(colors: [Palette.action.opacity(0.28),
                                                              Palette.action.opacity(0.02)],
                                                     startPoint: .top, endPoint: .bottom))
            }
            ForEach(pts) { p in
                LineMark(x: .value("Day", p.date), y: .value("kg", p.kg))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Palette.action)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
            }
            // Only when they are countable. Thirty dots on a 90-day
            // window is a dotted line, not a set of readings.
            if pts.count <= 20 {
                ForEach(pts) { p in
                    PointMark(x: .value("Day", p.date), y: .value("kg", p.kg))
                        .foregroundStyle(Palette.action)
                        .symbolSize(28)
                }
            }
            if let target {
                RuleMark(y: .value("Goal", target))
                    .foregroundStyle(Palette.blue.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("goal").font(.caption2).foregroundStyle(Palette.blue)
                    }
            }
        }
        .chartYScale(domain: window)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(Palette.border)
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    .font(.caption2).foregroundStyle(Palette.faint)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(Palette.border)
                AxisValueLabel().font(.caption2).foregroundStyle(Palette.faint)
            }
        }
        .frame(height: 170)
    }

    /// Two different nothings, and they need two different sentences.
    /// "No weigh-ins yet" in front of somebody who logged one this
    /// morning reads as the app having lost it.
    private func empty(logged: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(logged ? "One weigh-in so far." : "No weigh-ins in this range.")
                .font(.footnote.weight(.semibold)).foregroundStyle(Palette.muted)
            Text(logged
                 ? "Log again tomorrow and the line starts."
                 : "Log a weight above, or widen the range.")
                .font(.caption2).foregroundStyle(Palette.faint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 18)
    }
}
