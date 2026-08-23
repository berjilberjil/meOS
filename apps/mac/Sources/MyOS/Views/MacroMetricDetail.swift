import SwiftUI
import Charts

/// One indicator, opened. The chart, every change we can compute, where the
/// number came from, and the other indicators it is usually read against.
struct MacroMetricDetail: View {
    let metric: MacroMetric
    var snapshot: MacroSnapshot?

    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var range: MacroRange = .y1

    private var series: [MacroPoint] { MacroFormat.series(metric.history, range: range) }

    var body: some View {
        let content = ScrollView {
            VStack(alignment: .leading, spacing: Gap.screen) {
                header
                headline
                ranges
                chart
                changes
                if let note = metric.note { noteBlock(note) }
                sourceBlock
                related
            }
            .padding(20)
        }
        .background(Palette.bg)

        #if os(iOS)
        content.presentationDetents([.large]).presentationBackground(Palette.bg)
        #else
        content.frame(width: 520, height: 680)
        #endif
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(metric.name)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.text)
                Text("\(metric.category) · \(metric.country)")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(Palette.faint)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 12, weight: .bold))
            }
            .buttonStyle(KIconButtonStyle(size: 28))
        }
    }

    private var headline: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(MacroFormat.value(metric))
                .font(.system(size: 36, weight: .heavy, design: .rounded)).monospacedDigit()
                .foregroundStyle(metric.available ? Palette.text : Palette.faint)
            if metric.available {
                Text(MacroFormat.change(metric.change1D, isRate: metric.isRate))
                    .font(.system(size: 15, weight: .heavy, design: .rounded)).monospacedDigit()
                    .foregroundStyle(MacroFormat.tint(metric.change1D))
            }
            Spacer(minLength: 0)
            qualityBadge
        }
    }

    private var qualityBadge: some View {
        Text(metric.grade.label.uppercased())
            .font(.system(size: 9, weight: .heavy, design: .rounded)).tracking(0.6)
            .foregroundStyle(metric.grade.tint)
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background(metric.grade.tint.opacity(0.14), in: Capsule())
    }

    private var ranges: some View {
        HStack(spacing: 6) {
            ForEach(MacroRange.allCases) { r in
                Button { range = r } label: {
                    Text(r.rawValue)
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundStyle(r == range ? Brandmark.ink : Palette.muted)
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(r == range ? Palette.brand : Palette.surface2, in: Capsule())
                }
                .buttonStyle(KPressStyle())
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder private var chart: some View {
        if series.count > 1 {
            Chart(series, id: \.d) { p in
                LineMark(x: .value("Date", p.d), y: .value(metric.name, p.v))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Palette.brand)
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartXAxis {
                // Dates as strings keep the axis honest about gaps (weekends,
                // holidays) instead of interpolating across days with no print.
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine().foregroundStyle(Palette.border)
                    AxisValueLabel().font(.system(size: 9)).foregroundStyle(Palette.faint)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine().foregroundStyle(Palette.border)
                    AxisValueLabel().font(.system(size: 9)).foregroundStyle(Palette.faint)
                }
            }
            .frame(height: 200)
        } else {
            Card(padding: 20) {
                Text(metric.available
                     ? "Not enough history yet to chart this one."
                     : "Data unavailable for this date.")
                    .font(.system(size: 13)).foregroundStyle(Palette.faint)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var changes: some View {
        let rows: [(String, MacroDelta?)] = [
            ("1D", metric.change1D), ("1W", metric.change7D), ("1M", metric.change30D),
            ("YTD", metric.changeYTD), ("1Y", metric.change1Y)
        ]
        return HStack(spacing: 8) {
            ForEach(rows, id: \.0) { label, d in
                VStack(spacing: 3) {
                    Text(label)
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .foregroundStyle(Palette.faint)
                    Text(MacroFormat.change(d, isRate: metric.isRate))
                        .font(.system(size: 12, weight: .heavy, design: .rounded)).monospacedDigit()
                        .foregroundStyle(MacroFormat.tint(d))
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Palette.surface2, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            }
        }
    }

    private func noteBlock(_ note: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 11)).foregroundStyle(Palette.amber)
            Text(note).font(.system(size: 12)).foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private var sourceBlock: some View {
        VStack(alignment: .leading, spacing: 5) {
            row("Source", metric.source)
            row("Frequency", metric.frequency)
            row("Last updated", metric.asOf.map { Fmt.day($0) } ?? "—")
            if !metric.sourceUrl.isEmpty, let url = URL(string: metric.sourceUrl) {
                Link(destination: url) {
                    Text(metric.sourceUrl)
                        .font(.system(size: 11)).foregroundStyle(Palette.brand)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .heavy, design: .rounded)).tracking(0.5)
                .foregroundStyle(Palette.faint)
                .frame(width: 90, alignment: .leading)
            Text(value).font(.system(size: 12)).foregroundStyle(Palette.muted)
            Spacer(minLength: 0)
        }
    }

    /// What this is usually read against — same category first, then the ones
    /// that move with it by convention.
    @ViewBuilder private var related: some View {
        let others = (snapshot?.metrics ?? [])
            .filter { $0.id != metric.id && ($0.category == metric.category || $0.country == metric.country) }
            .prefix(6)
        if !others.isEmpty {
            VStack(alignment: .leading, spacing: Gap.tight) {
                Text("READ ALONGSIDE")
                    .font(.system(size: 10, weight: .heavy, design: .rounded)).tracking(0.6)
                    .foregroundStyle(Palette.faint)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                    ForEach(Array(others)) { m in
                        HStack(spacing: 6) {
                            Text(m.name).font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Palette.muted).lineLimit(1)
                            Spacer(minLength: 0)
                            Text(MacroFormat.value(m))
                                .font(.system(size: 11, weight: .heavy, design: .rounded)).monospacedDigit()
                                .foregroundStyle(Palette.text)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(Palette.surface2, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                    }
                }
            }
        }
    }
}

/// The Settings row that is the only way in. Deliberately not in the sidebar.
struct MacroEntryCard: View {
    var boxed = true
    @State private var open = false

    var body: some View {
        let inner = Button { open = true } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Palette.blue.opacity(0.16))
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.blue)
                }
                .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Macro Intelligence")
                        .font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.text)
                    Text("Track global markets, economic indicators and macro conditions.")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.faint)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(KPressStyle())

        Group {
            if boxed { Card { inner } } else { inner }
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $open) { MacroPulseView() }
        #else
        .sheet(isPresented: $open) { MacroPulseView().frame(width: 900, height: 720) }
        #endif
    }
}
