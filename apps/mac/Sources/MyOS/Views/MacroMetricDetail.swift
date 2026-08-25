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
    /// What the pointer is over, so the chart can be read rather than admired.
    @State private var hover: MacroPoint?

    private var series: [MacroPoint] { MacroFormat.series(metric.history, range: range) }
    private var plotted: [(date: Date, point: MacroPoint)] {
        series.compactMap { p in MacroFormat.date(p.d).map { ($0, p) } }
    }

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
        .background(Palette.background)

        #if os(iOS)
        content.presentationDetents([.large]).presentationBackground(Palette.background)
        #else
        content.frame(width: 520, height: 680)
        #endif
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(metric.name)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Palette.text)
                Text("\(metric.category) · \(metric.country)")
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(Palette.faint)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.caption.weight(.bold))
            }
            .buttonStyle(.borderless)
        }
    }

    private var headline: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(MacroFormat.value(metric))
                .font(.largeTitle.weight(.heavy)).monospacedDigit()
                .foregroundStyle(metric.available ? Palette.text : Palette.faint)
            if metric.available {
                Text(MacroFormat.change(metric.change1D, isRate: metric.isRate))
                    .font(.subheadline.weight(.heavy)).monospacedDigit()
                    .foregroundStyle(MacroFormat.tint(metric.change1D))
            }
            Spacer(minLength: 0)
            qualityBadge
        }
    }

    private var qualityBadge: some View {
        Text(metric.grade.label.uppercased())
            .font(.caption2.weight(.heavy)).tracking(0.6)
            .foregroundStyle(metric.grade.tint)
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background(metric.grade.tint.opacity(0.14), in: Capsule())
    }

    private var ranges: some View {
        HStack(spacing: 6) {
            ForEach(MacroRange.allCases) { r in
                Button { range = r } label: {
                    Text(r.rawValue)
                        .font(.caption2.weight(.heavy))
                        .foregroundStyle(r == range ? Brandmark.ink : Palette.muted)
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(r == range ? Palette.action : Palette.surfaceElevated, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder private var chart: some View {
        if plotted.count > 1 {
            VStack(alignment: .leading, spacing: 6) {
                // The readout sits above the plot in fixed space, so following the
                // line does not make the chart jump.
                HStack(spacing: 8) {
                    if let h = hover {
                        Text(Fmt.day(h.d))
                            .font(.caption2.weight(.heavy))
                            .foregroundStyle(Palette.faint)
                        Text(MacroFormat.reading(h.v, unit: metric.unit))
                            .font(.footnote.weight(.heavy)).monospacedDigit()
                            .foregroundStyle(Palette.text)
                    }
                    Spacer(minLength: 0)
                }
                .frame(height: 16)

                Chart {
                    ForEach(plotted, id: \.point.d) { row in
                        LineMark(x: .value("Date", row.date), y: .value(metric.name, row.point.v))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(Palette.action)
                    }
                    if let h = hover, let d = MacroFormat.date(h.d) {
                        RuleMark(x: .value("Date", d))
                            .foregroundStyle(Palette.faint.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        PointMark(x: .value("Date", d), y: .value(metric.name, h.v))
                            .foregroundStyle(Palette.action)
                            .symbolSize(60)
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine().foregroundStyle(Palette.border)
                        AxisValueLabel(format: .dateTime.month(.abbreviated).year(.twoDigits))
                            .font(.caption2).foregroundStyle(Palette.faint)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine().foregroundStyle(Palette.border)
                        AxisValueLabel().font(.caption2).foregroundStyle(Palette.faint)
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            #if os(macOS)
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let p): hover = nearest(to: p, proxy: proxy, geo: geo)
                                case .ended: hover = nil
                                }
                            }
                            #endif
                            // Touch gets the same readout by dragging along the line.
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { v in hover = nearest(to: v.location, proxy: proxy, geo: geo) }
                                    .onEnded { _ in hover = nil }
                            )
                    }
                }
                .frame(height: 200)
            }
        } else {
            Card(padding: 20) {
                Text(metric.available
                     ? "Not enough history yet to chart this one."
                     : "Data unavailable for this date.")
                    .font(.footnote).foregroundStyle(Palette.faint)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// The observation closest to the pointer's x, which is what "hovering the
    /// line" means when the series has gaps for weekends and holidays.
    private func nearest(to location: CGPoint, proxy: ChartProxy, geo: GeometryProxy) -> MacroPoint? {
        guard let plotFrame = proxy.plotFrame else { return nil }
        let x = location.x - geo[plotFrame].origin.x
        guard let target: Date = proxy.value(atX: x) else { return nil }
        return plotted.min { a, b in
            abs(a.date.timeIntervalSince(target)) < abs(b.date.timeIntervalSince(target))
        }?.point
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
                        .font(.caption2.weight(.heavy))
                        .foregroundStyle(Palette.faint)
                    Text(MacroFormat.change(d, isRate: metric.isRate))
                        .font(.caption.weight(.heavy)).monospacedDigit()
                        .foregroundStyle(MacroFormat.tint(d))
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Palette.surfaceElevated, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            }
        }
    }

    private func noteBlock(_ note: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .font(.caption2).foregroundStyle(Palette.attention)
            Text(note).font(.caption).foregroundStyle(Palette.muted)
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
                        .font(.caption2).foregroundStyle(Palette.action)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(label.uppercased())
                .font(.caption2.weight(.heavy)).tracking(0.5)
                .foregroundStyle(Palette.faint)
                .frame(width: 90, alignment: .leading)
            Text(value).font(.caption).foregroundStyle(Palette.muted)
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
                    .font(.caption2.weight(.heavy)).tracking(0.6)
                    .foregroundStyle(Palette.faint)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                    ForEach(Array(others)) { m in
                        HStack(spacing: 6) {
                            Text(m.name).font(.caption2.weight(.semibold))
                                .foregroundStyle(Palette.muted).lineLimit(1)
                            Spacer(minLength: 0)
                            Text(MacroFormat.value(m))
                                .font(.caption2.weight(.heavy)).monospacedDigit()
                                .foregroundStyle(Palette.text)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(Palette.surfaceElevated, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
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
        let inner = Button { present() } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Palette.blue.opacity(0.16))
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.blue)
                }
                .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Macro Intelligence")
                        .font(.callout.weight(.semibold)).foregroundStyle(Palette.text)
                    Text("Track global markets, economic indicators and macro conditions.")
                        .font(.caption).foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold)).foregroundStyle(Palette.faint)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        Group {
            if boxed { Card { inner } } else { inner }
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $open) { MacroPulseView() }
        #endif
    }

    private func present() {
        #if os(macOS)
        // The Mac hands it to MainView, which gives it the whole content area.
        // A fixed-size sheet was the reason it looked clipped and half-finished.
        withAnimation(.knNormal) { UISignals.shared.openMacro = true }
        #else
        open = true
        #endif
    }
}
