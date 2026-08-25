import SwiftUI

/// Macro Pulse — the one screen. It answers "what changed, and what should I
/// care about", in about thirty seconds, and everything deeper is a tap away.
///
/// It is reached from Settings, not the sidebar: this is a module you go to on
/// purpose, not part of the daily-life OS.
struct MacroPulseView: View {
    /// Set when the screen is hosted rather than presented — the Mac renders it
    /// in the content area, so there is no sheet to dismiss.
    var onClose: (() -> Void)? = nil

    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var date = AppState.dateKey(Date())
    @State private var range: MacroRange = .d1
    @State private var detail: MacroMetric?
    @State private var showMethod = false

    private var snap: MacroSnapshot? { state.macro }
    private var isToday: Bool { date == state.todayKey }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Palette.border)

            ScrollView {
                VStack(alignment: .leading, spacing: Gap.screen) {
                    dateBar
                    if let err = state.macroError { errorNote(err) }

                    if let snap {
                        metricGrid(snap)
                        if !snap.regime.isEmpty { regimeBlock(snap) }
                        if let brief = snap.brief { briefBlock(brief) }
                        provenance(snap)
                    } else if state.macroBusy {
                        loading
                    } else {
                        empty
                    }
                }
                .padding(20)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .background(Palette.background)
        .task { await state.loadMacro(date: date) }
        .sheet(item: $detail) { m in
            MacroMetricDetail(metric: m, snapshot: snap)
                .environmentObject(state)
        }
        .sheet(isPresented: $showMethod) { MacroMethodSheet(regime: snap?.regime ?? []) }
    }

    // MARK: Chrome

    private var header: some View {
        HStack(spacing: 10) {
            Button { close() } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left").font(.caption2.weight(.bold))
                    Text("MyOS").font(.footnote.weight(.semibold))
                }
            }
            .buttonStyle(.borderless).tint(Palette.muted)

            Spacer(minLength: 0)

            VStack(spacing: 1) {
                Text("MACRO PULSE")
                    .font(.caption2.weight(.heavy)).tracking(1.2)
                    .foregroundStyle(Palette.action)
                if state.macroBusy {
                    Text("reading…")
                        .font(.caption2.weight(.heavy))
                        .foregroundStyle(Palette.faint)
                }
            }

            Spacer(minLength: 0)

            Button { showMethod = true } label: {
                Image(systemName: "info.circle").font(.footnote.weight(.semibold))
            }
            .buttonStyle(.borderless)
            .help("Where these numbers come from and how they are worked out")

            Button { Task { await state.loadMacro(date: date, refresh: true) } } label: {
                Image(systemName: "arrow.clockwise").font(.caption.weight(.bold))
            }
            .buttonStyle(.borderless)
            .disabled(state.macroBusy)
            .help("Fetch again now")
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .padding(.top, Self.topInset)
    }

    private var dateBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button { step(-1) } label: { Image(systemName: "chevron.left").font(.caption.weight(.bold)) }
                    .buttonStyle(.borderless)
                Text(Fmt.day(date))
                    .font(.body.weight(.bold))
                    .foregroundStyle(Palette.text)
                    .frame(minWidth: 120)
                Button { step(1) } label: { Image(systemName: "chevron.right").font(.caption.weight(.bold)) }
                    .buttonStyle(.borderless)
                    .disabled(isToday)
                    .opacity(isToday ? 0.35 : 1)
                Spacer(minLength: 0)
                if !isToday {
                    Button("Today") { go(state.todayKey) }
                        .buttonStyle(.bordered).tint(Palette.action)
                }
            }
            HStack(spacing: 6) {
                ForEach(MacroRange.allCases) { r in
                    Button { range = r } label: {
                        Text(r.rawValue)
                            .font(.caption2.weight(.heavy))
                            .foregroundStyle(r == range ? Brandmark.ink : Palette.muted)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(r == range ? Palette.action : Palette.surfaceElevated, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: Blocks

    private func metricGrid(_ snap: MacroSnapshot) -> some View {
        VStack(alignment: .leading, spacing: Gap.tight) {
            blockTitle("WHAT MATTERS NOW", "\(snap.pulse.count) indicators")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 168), spacing: 10)], spacing: 10) {
                ForEach(snap.pulse) { m in
                    Button { detail = m } label: { MacroMetricCard(metric: m, range: range) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private func regimeBlock(_ snap: MacroSnapshot) -> some View {
        VStack(alignment: .leading, spacing: Gap.tight) {
            HStack(spacing: 6) {
                blockTitle("MACRO REGIME", "OS reading, not advice")
                Button { showMethod = true } label: {
                    Image(systemName: "info.circle").font(.caption2.weight(.semibold))
                }
                .buttonStyle(.borderless).tint(Palette.faint)
                .help("How each score is worked out")
            }
            Card {
                VStack(spacing: 12) {
                    ForEach(snap.regime) { s in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 8) {
                                Text(s.label)
                                    .font(.footnote.weight(.semibold)).foregroundStyle(Palette.text)
                                Spacer(minLength: 0)
                                Text("\(s.score) / 100")
                                    .font(.footnote.weight(.heavy)).monospacedDigit()
                                    .foregroundStyle(s.tint)
                            }
                            ProgressView(value: Double(s.score) / 100).progressViewStyle(.linear).tint(s.tint)
                            if !s.inputs.isEmpty {
                                Text(s.inputs.joined(separator: "  ·  "))
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(Palette.faint)
                            }
                        }
                    }
                }
            }
        }
    }

    private func briefBlock(_ brief: MacroBrief) -> some View {
        VStack(alignment: .leading, spacing: Gap.tight) {
            blockTitle("CATHERINE'S BRIEF", brief.speculative ? "includes inference" : "from the numbers")
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    if !brief.changed.isEmpty {
                        section("WHAT CHANGED") {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(brief.changed, id: \.metric) { c in
                                    HStack(alignment: .top, spacing: 8) {
                                        Circle().fill(Palette.action).frame(width: 5, height: 5).padding(.top, 6)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(c.metric)
                                                .font(.footnote.weight(.semibold)).foregroundStyle(Palette.text)
                                            Text(c.move)
                                                .font(.footnote).foregroundStyle(Palette.muted)
                                        }
                                        Spacer(minLength: 0)
                                    }
                                }
                            }
                        }
                    }
                    section("WHY") { body(brief.why) }
                    section("WHY IT MATTERS") { body(brief.matters) }
                    if !brief.watch.isEmpty {
                        section("WATCH NEXT") {
                            HStack(spacing: 6) {
                                ForEach(brief.watch, id: \.self) { w in
                                    Text(w)
                                        .font(.caption2.weight(.heavy))
                                        .foregroundStyle(Palette.information)
                                        .padding(.horizontal, 8).padding(.vertical, 4)
                                        .background(Palette.information.opacity(0.14), in: Capsule())
                                }
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    if brief.speculative {
                        Text("The \"why\" here is inference from the numbers, not a reported cause.")
                            .font(.caption2).foregroundStyle(Palette.attention)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func provenance(_ snap: MacroSnapshot) -> some View {
        let verified = snap.metrics.filter { $0.grade == .verified }.count
        let estimated = snap.metrics.filter { $0.grade == .estimated }.count
        let missing = snap.metrics.filter { !$0.available }.count
        return VStack(alignment: .leading, spacing: 4) {
            Text("\(verified) verified · \(estimated) estimated · \(missing) unavailable")
                .font(.caption2.weight(.heavy))
                .foregroundStyle(Palette.faint)
            Text("Verified figures come from FRED's published series. Estimated ones are read off the web and carry their source — treat them as a reading, not a feed.")
                .font(.caption2).foregroundStyle(Palette.faint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
    }

    // MARK: Bits

    private func blockTitle(_ title: String, _ trailing: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption2.weight(.heavy)).tracking(0.8)
                .foregroundStyle(Palette.faint)
            Spacer(minLength: 0)
            Text(trailing)
                .font(.caption2.weight(.heavy))
                .foregroundStyle(Palette.faint)
        }
    }

    private func section<C: View>(_ label: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption2.weight(.heavy)).tracking(0.6)
                .foregroundStyle(Palette.faint)
            content()
        }
    }

    private func body(_ s: String) -> some View {
        Text(s).font(.footnote).foregroundStyle(Palette.text)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func errorNote(_ err: String) -> some View {
        Card(padding: 12) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(Palette.attention)
                Text(err).font(.caption).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
    }

    private var loading: some View {
        VStack(spacing: 10) {
            ProgressView().controlSize(.large).tint(Palette.action)
            Text("Reading the tape…")
                .font(.footnote.weight(.semibold)).foregroundStyle(Palette.muted)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 60)
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Text("Nothing for this date.")
                .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.text)
            Text("Verified series reconstruct for any past date. Estimated figures only exist for days MyOS has already snapshotted.")
                .font(.caption).foregroundStyle(Palette.faint)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 50).padding(.horizontal, 20)
    }

    private func step(_ days: Int) {
        let next = MacroFormat.shift(date, by: days)
        guard next <= state.todayKey else { return }
        go(next)
    }

    private func close() {
        if let onClose { onClose() } else { dismiss() }
    }

    private func go(_ key: String) {
        date = key
        Task { await state.loadMacro(date: key) }
    }

    private static var topInset: CGFloat {
        #if os(macOS)
        return 18
        #else
        return 0
        #endif
    }
}

/// One indicator. Value, where it went, and enough shape to read the trend
/// without opening it.
struct MacroMetricCard: View {
    let metric: MacroMetric
    var range: MacroRange = .d1

    private var delta: MacroDelta? { range.delta(metric) }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Text(metric.name)
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Circle().fill(metric.grade.tint).frame(width: 5, height: 5)
            }

            Text(MacroFormat.value(metric))
                .font(.title3.weight(.heavy)).monospacedDigit()
                .foregroundStyle(metric.available ? Palette.text : Palette.faint)
                .lineLimit(1).minimumScaleFactor(0.7)

            HStack(spacing: 5) {
                if metric.available, delta != nil {
                    Image(systemName: metric.direction >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.caption2.weight(.black))
                        .foregroundStyle(MacroFormat.tint(delta))
                }
                Text(metric.available ? MacroFormat.change(delta, isRate: metric.isRate) : "Data unavailable")
                    .font(.caption2.weight(.heavy)).monospacedDigit()
                    .foregroundStyle(metric.available ? MacroFormat.tint(delta) : Palette.faint)
                Spacer(minLength: 0)
                Sparkline(values: MacroFormat.series(metric.history, range: range).map(\.v),
                          color: MacroFormat.tint(delta))
                    .frame(width: 52, height: 18)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(Palette.border, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }
}
