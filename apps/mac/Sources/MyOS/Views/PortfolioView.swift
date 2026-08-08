import SwiftUI
import Charts

/// The Invest section of Finance. Drop a portfolio screenshot -> AI reads the
/// holdings -> a weekly snapshot tracks change, and a grounded read tells the user
/// what to actually do (obeying the gold-loan-first rule, server-side).
struct PortfolioView: View {
    @EnvironmentObject var state: AppState
    @State private var review: HoldingReviewPayload?
    @State private var editingSnapshot: PortfolioSnapshot?

    private let cols = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        Group {
            if let snap = state.portfolio.latest, !snap.holdings.isEmpty {
                tracked(snap)
            } else {
                emptyState
            }
        }
        .sheet(item: $review) { p in
            PortfolioReviewSheet(summary: p.summary, drafts: p.drafts)
        }
        .sheet(item: $editingSnapshot) { snap in SnapshotDetailSheet(snapshot: snap) }
    }

    // MARK: - Tracked

    @ViewBuilder private func tracked(_ snap: PortfolioSnapshot) -> some View {
        summaryCard(snap).knRise(2)
        if state.portfolio.snapshots.count >= 2 { trendCard.knRise(3) }
        holdingsTable(snap).knRise(4)
        allocationCard(snap).knRise(5)
        adviceCard.knRise(6)
        updateCard.knRise(7)
        if state.portfolio.snapshots.count > 1 { historyCard.knRise(8) }
    }

    // MARK: - Summary (Groww-style header)

    private func summaryCard(_ snap: PortfolioSnapshot) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("HOLDINGS (\(snap.holdings.count))")
                            .font(.system(size: 11, weight: .heavy, design: .rounded)).tracking(0.6).foregroundStyle(Palette.faint)
                        Text(Fmt.inr(snap.totalCurrent))
                            .font(.system(size: 30, weight: .bold)).monospacedDigit().foregroundStyle(Palette.text)
                    }
                    Spacer()
                    if let wc = state.portfolioWeekChange {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("SINCE LAST SNAPSHOT").font(.system(size: 9, weight: .heavy, design: .rounded)).tracking(0.5).foregroundStyle(Palette.faint)
                            Text("\(wc >= 0 ? "+" : "")\(Fmt.inr(wc))")
                                .font(.system(size: 15, weight: .heavy, design: .rounded)).monospacedDigit()
                                .foregroundStyle(wc >= 0 ? Palette.green : Palette.red)
                        }
                    }
                }
                Divider().overlay(Palette.border)
                HStack {
                    labelValue("Invested value", Fmt.inr(snap.totalInvested), Palette.text)
                    Spacer()
                    labelValue("Total returns",
                               "\(snap.pnl >= 0 ? "+" : "")\(Fmt.inr(snap.pnl)) (\(pctText(snap.returnPct)))",
                               snap.pnl >= 0 ? Palette.green : Palette.red, align: .trailing)
                }
            }
        }
    }

    private func labelValue(_ label: String, _ value: String, _ color: Color, align: HorizontalAlignment = .leading) -> some View {
        VStack(alignment: align, spacing: 3) {
            Text(label).font(.system(size: 11)).foregroundStyle(Palette.muted)
            Text(value).font(.system(size: 14, weight: .semibold)).monospacedDigit().foregroundStyle(color)
        }
    }

    // MARK: - Trend (current vs invested across snapshots)

    private var trendCard: some View {
        // Snapshots are newest-first; chronological for the chart.
        let snaps = state.portfolio.snapshots.reversed().map { $0 }
        return Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionTitle(text: "Current vs invested")
                    Spacer()
                    HStack(spacing: 12) {
                        legendDot("Current", Palette.blue)
                        legendDot("Invested", Palette.muted)
                    }
                }
                Chart {
                    ForEach(snaps) { s in
                        LineMark(x: .value("Date", s.date), y: .value("Value", s.totalCurrent), series: .value("s", "Current"))
                            .foregroundStyle(Palette.blue).interpolationMethod(.catmullRom)
                        LineMark(x: .value("Date", s.date), y: .value("Value", s.totalInvested), series: .value("s", "Invested"))
                            .foregroundStyle(Palette.muted).interpolationMethod(.catmullRom)
                    }
                }
                .chartForegroundStyleScale(["Current": Palette.blue, "Invested": Palette.muted])
                .chartLegend(.hidden)
                .chartXAxis { AxisMarks { _ in AxisGridLine().foregroundStyle(Palette.border.opacity(0.4)) } }
                .chartYAxis {
                    AxisMarks { v in
                        AxisGridLine().foregroundStyle(Palette.border.opacity(0.4))
                        AxisValueLabel {
                            if let d = v.as(Double.self) { Text(Fmt.inrShort(d)).font(.system(size: 9)).foregroundStyle(Palette.faint) }
                        }
                    }
                }
                .frame(height: 180)
            }
        }
    }

    private func legendDot(_ label: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.muted)
        }
    }

    // MARK: - Holdings table (Groww-style)

    private func holdingsTable(_ snap: PortfolioSnapshot) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    SectionTitle(text: "Holdings · \(snap.holdings.count)")
                    Spacer()
                    Button { Task { await state.refreshLivePrices() } } label: {
                        HStack(spacing: 5) {
                            if state.growwBusy { ProgressView().controlSize(.small) }
                            Label("Live prices", systemImage: "dot.radiowaves.left.and.right")
                        }
                    }
                    .buttonStyle(KGhostButtonStyle(color: Palette.green))
                    .disabled(state.growwBusy)
                    .help("Pull live prices from Yahoo Finance for holdings with a ticker set")
                    Button { editingSnapshot = snap } label: { Label("Edit", systemImage: "pencil") }
                        .buttonStyle(KGhostButtonStyle())
                        .help("Edit quantities, amounts, symbols, or remove holdings")
                }
                if let err = state.growwError {
                    Label(err, systemImage: "exclamationmark.triangle.fill").font(.system(size: 11)).foregroundStyle(Palette.amber)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let ts = state.growwLastRefresh {
                    Text("Live prices updated \(Fmt.day(ts))").font(.system(size: 10)).foregroundStyle(Palette.green)
                }
                // Column header
                HStack {
                    Text("COMPANY").font(.system(size: 9, weight: .heavy)).foregroundStyle(Palette.faint)
                    Spacer()
                    Text("LTP").font(.system(size: 9, weight: .heavy)).foregroundStyle(Palette.faint).frame(width: 84, alignment: .trailing)
                    Text("RETURNS").font(.system(size: 9, weight: .heavy)).foregroundStyle(Palette.faint).frame(width: 74, alignment: .trailing)
                    Text("CURRENT").font(.system(size: 9, weight: .heavy)).foregroundStyle(Palette.faint).frame(width: 90, alignment: .trailing)
                }
                .padding(.horizontal, 4)
                ForEach(Array(snap.holdings.enumerated()), id: \.element.id) { idx, h in
                    holdingRow(h)
                    if idx < snap.holdings.count - 1 { Divider().overlay(Palette.border) }
                }
            }
        }
    }

    private func holdingRow(_ h: Holding) -> some View {
        let units = h.units ?? 0
        let ltp = units > 0 ? h.currentInr / units : 0
        let avg = units > 0 ? h.investedInr / units : 0
        return HStack(alignment: .center, spacing: 8) {
            Image(systemName: h.type.icon).font(.system(size: 12, weight: .bold)).foregroundStyle(h.type.color)
                .frame(width: 28, height: 28)
                .background(h.type.color.opacity(0.15), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(h.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.text).lineLimit(1)
                Text(units > 0 ? "\(Fmt.trimKg(units)) shares · avg \(Fmt.inr(avg))" : h.type.label)
                    .font(.system(size: 10)).foregroundStyle(Palette.faint).lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(units > 0 ? Fmt.inr(ltp) : "—")
                .font(.system(size: 12, weight: .semibold)).monospacedDigit().foregroundStyle(Palette.text)
                .frame(width: 84, alignment: .trailing)
            Text(h.investedInr > 0 ? "\(h.pnl >= 0 ? "+" : "")\(pctText(h.returnPct))" : "—")
                .font(.system(size: 12, weight: .heavy, design: .rounded)).monospacedDigit()
                .foregroundStyle(h.pnl >= 0 ? Palette.green : Palette.red)
                .frame(width: 74, alignment: .trailing)
            VStack(alignment: .trailing, spacing: 1) {
                Text(Fmt.inr(h.currentInr)).font(.system(size: 12, weight: .semibold)).monospacedDigit().foregroundStyle(Palette.text)
                Text(Fmt.inr(h.investedInr)).font(.system(size: 10)).monospacedDigit().foregroundStyle(Palette.faint)
            }
            .frame(width: 90, alignment: .trailing)
        }
        .padding(.horizontal, 4).padding(.vertical, 5)
        .contentShape(Rectangle())
    }

    // MARK: - Asset allocation (donut by holding type)

    private func allocationCard(_ snap: PortfolioSnapshot) -> some View {
        let byType = Dictionary(grouping: snap.holdings, by: { $0.type })
            .map { (type: $0.key, value: $0.value.reduce(0) { $0 + $1.currentInr }) }
            .filter { $0.value > 0 }
            .sorted { $0.value > $1.value }
        let total = max(1, byType.reduce(0) { $0 + $1.value })
        return Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(text: "Asset allocation")
                HStack(alignment: .center, spacing: 20) {
                    Chart(byType, id: \.type) { seg in
                        SectorMark(angle: .value("Value", seg.value), innerRadius: .ratio(0.62), angularInset: 2)
                            .foregroundStyle(seg.type.color)
                            .cornerRadius(3)
                    }
                    .chartLegend(.hidden)
                    .frame(width: 150, height: 150)

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(byType, id: \.type) { seg in
                            HStack(spacing: 8) {
                                Circle().fill(seg.type.color).frame(width: 9, height: 9)
                                Text(seg.type.label).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.text)
                                Spacer()
                                Text("\(Int((seg.value / total * 100).rounded()))%")
                                    .font(.system(size: 11)).foregroundStyle(Palette.faint)
                                Text(Fmt.inrShort(seg.value)).font(.system(size: 12, weight: .semibold)).monospacedDigit()
                                    .foregroundStyle(Palette.muted).frame(minWidth: 56, alignment: .trailing)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var adviceCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionTitle(text: "This week's read")
                    Spacer()
                    Button {
                        Task { await state.requestPortfolioReview() }
                    } label: {
                        HStack(spacing: 6) {
                            if state.adviceBusy { ProgressView().controlSize(.small).tint(.white) }
                            Text(state.portfolio.advice == nil ? "Get read" : "Refresh")
                        }
                    }
                    .buttonStyle(KPrimaryButtonStyle())
                    .disabled(state.adviceBusy)
                }

                if let err = state.adviceError {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12)).foregroundStyle(Palette.amber)
                }

                if let a = state.portfolio.advice {
                    Text(a.verdict).font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundStyle(Palette.text)
                    adviceBlock("Allocation", a.allocation)
                    adviceBlock("Diversification", a.diversification)
                    if !a.actions.isEmpty { adviceList("Do next", a.actions, numbered: true, tint: Palette.brand) }
                    if !a.ideas.isEmpty { adviceList("Ideas", a.ideas, numbered: false, tint: Palette.blue) }
                    if !a.date.isEmpty {
                        Text("As of \(Fmt.day(a.date))").font(.system(size: 11)).foregroundStyle(Palette.faint)
                    }
                } else if !state.adviceBusy {
                    Text("Get an honest read on your allocation, diversification and what to do — grounded in your loan and income, not generic advice.")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                }
            }
        }
    }

    private func adviceBlock(_ title: String, _ body: String) -> some View {
        Group {
            if !body.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title.uppercased()).font(.system(size: 10, weight: .heavy, design: .rounded))
                        .tracking(0.7).foregroundStyle(Palette.faint)
                    Text(body).font(.system(size: 13)).foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func adviceList(_ title: String, _ items: [String], numbered: Bool, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.system(size: 10, weight: .heavy, design: .rounded))
                .tracking(0.7).foregroundStyle(Palette.faint)
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                HStack(alignment: .top, spacing: 8) {
                    if numbered {
                        Text("\(i + 1)").font(.system(size: 11, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                            .frame(width: 18, height: 18).background(tint, in: Circle())
                    } else {
                        Image(systemName: "sparkle").font(.system(size: 10, weight: .bold)).foregroundStyle(tint)
                            .frame(width: 18, height: 18)
                    }
                    Text(item).font(.system(size: 13)).foregroundStyle(Palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var updateCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(text: "Update — new screenshot")
                portfolioDropZone
            }
        }
    }

    private var historyCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                SectionTitle(text: "History")
                Text("Tap a snapshot to edit its holdings.")
                    .font(.system(size: 11)).foregroundStyle(Palette.faint)
                ForEach(Array(state.portfolio.snapshots.enumerated()), id: \.element.id) { idx, s in
                    SnapshotHistoryRow(snapshot: s,
                                       openEdit: { editingSnapshot = s },
                                       delete: { state.deleteSnapshot(s.id) })
                    if idx < state.portfolio.snapshots.count - 1 { Divider().overlay(Palette.border) }
                }
            }
        }
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 14) {
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    SectionTitle(text: "Track your portfolio")
                    Text("Drop a screenshot from Groww, Zerodha, Kuvera or your broker. AI reads your holdings, tracks them week to week, and gives you an honest read — grounded in your loan and income, not generic tips.")
                        .font(.system(size: 13)).foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    portfolioDropZone
                }
            }
            .knRise(2)
        }
    }

    private var portfolioDropZone: some View {
        VStack(alignment: .leading, spacing: 8) {
            ImageDropZone(
                title: "Drop your portfolio screenshot",
                subtitle: "One or more screens of your holdings. You confirm what's read before it's saved.",
                tint: Palette.blue,
                busy: state.imageBusy
            ) { imgs, mt in
                Task { @MainActor in
                    let r = await state.analyzePortfolio(imagesBase64: imgs, mediaType: mt)
                    if state.imageError == nil {
                        review = HoldingReviewPayload(summary: r.summary, drafts: r.drafts)
                    }
                }
            }
            if let err = state.imageError {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12)).foregroundStyle(Palette.amber)
            }
        }
    }

    private var weekChangeText: String? {
        guard let c = state.portfolioWeekChange else { return nil }
        return "\(c >= 0 ? "+" : "")\(Fmt.inrShort(c)) this week"
    }

    private func pctText(_ p: Double) -> String {
        String(format: "%@%.1f%%", p >= 0 ? "" : "-", abs(p * 100))
    }
}

/// Payload for the holdings review sheet.
struct HoldingReviewPayload: Identifiable {
    let id = UUID()
    let summary: String
    let drafts: [DraftHolding]
}

/// Review extracted holdings before they become a snapshot.
struct PortfolioReviewSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    let summary: String
    @State var drafts: [DraftHolding]

    private var included: [DraftHolding] { drafts.filter { $0.include } }
    private var includedCurrent: Double { included.reduce(0) { $0 + $1.currentInr } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Review \(drafts.count) \(drafts.count == 1 ? "holding" : "holdings")")
                    .font(.system(size: 18, weight: .heavy, design: .rounded)).foregroundStyle(Palette.text)
                if !summary.isEmpty {
                    Text(summary).font(.system(size: 12)).foregroundStyle(Palette.muted)
                }
            }
            .padding(20)

            Divider().overlay(Palette.border)

            if drafts.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "chart.pie").font(.system(size: 26)).foregroundStyle(Palette.faint)
                    Text("Couldn't read any holdings from that image.")
                        .font(.system(size: 13)).foregroundStyle(Palette.muted)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 40)
            } else {
                ScrollView {
                    VStack(spacing: 8) { ForEach($drafts) { $d in HoldingRow(draft: $d) } }
                        .padding(16)
                }
                .frame(maxHeight: 420)
            }

            Divider().overlay(Palette.border)

            HStack(spacing: 12) {
                Text("\(included.count) selected · \(Fmt.inr(includedCurrent))")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.muted)
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(KGhostButtonStyle())
                Button("Save snapshot") {
                    let holdings = included.map {
                        Holding(name: $0.name, type: $0.type, investedInr: $0.investedInr,
                                currentInr: $0.currentInr, units: $0.units, note: $0.note, symbol: $0.symbol)
                    }
                    state.addSnapshot(holdings)
                    dismiss()
                }
                .buttonStyle(KPrimaryButtonStyle())
                .disabled(included.isEmpty)
                .opacity(included.isEmpty ? 0.5 : 1)
            }
            .padding(20)
        }
        .frame(width: 600)
        .background(Palette.elevated)
    }
}

private struct HoldingRow: View {
    @Binding var draft: DraftHolding

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Button { draft.include.toggle() } label: {
                    Image(systemName: draft.include ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18)).foregroundStyle(draft.include ? Palette.green : Palette.faint)
                }
                .buttonStyle(KPressStyle())

                TextField("Name", text: $draft.name)
                    .textFieldStyle(.plain).font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.text).frame(maxWidth: .infinity, alignment: .leading)

                HoldingTypeMenu(type: $draft.type)
            }
            HStack(spacing: 8) {
                HoldingQtyField(label: "Qty", value: $draft.units)
                HoldingMoneyField(label: "Invested", value: $draft.investedInr)
                HoldingMoneyField(label: "Now", value: $draft.currentInr)
                Spacer(minLength: 0)
            }
        }
        .padding(11)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(Palette.border, lineWidth: 1))
        .opacity(draft.include ? 1 : 0.55)
    }
}

// MARK: - Shared holding fields + menu

/// Holding type dropdown over a `Binding<HoldingType>`.
struct HoldingTypeMenu: View {
    @Binding var type: HoldingType
    var body: some View {
        Menu {
            ForEach(HoldingType.allCases, id: \.self) { t in
                Button { type = t } label: { Label(t.label, systemImage: t.icon) }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: type.icon).font(.system(size: 10, weight: .bold)).foregroundStyle(type.color)
                Text(type.label).font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.text)
            }
            .padding(.horizontal, 9).padding(.vertical, 7)
            .background(Palette.surface2.opacity(0.6), in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
    }
}

/// ₹ money field over a non-optional Double.
struct HoldingMoneyField: View {
    let label: String
    @Binding var value: Double
    var body: some View {
        HStack(spacing: 4) {
            Text(label).font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.faint)
            Text("₹").font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.faint)
            TextField("0", value: $value, format: .number)
                .textFieldStyle(.plain).monospacedDigit()
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.text).frame(width: 62)
        }
        .padding(.horizontal, 8).padding(.vertical, 7)
        .background(Palette.bg, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
    }
}

/// Quantity (units) field over an optional Double — empty clears to nil.
struct HoldingQtyField: View {
    let label: String
    @Binding var value: Double?
    var body: some View {
        HStack(spacing: 4) {
            Text(label).font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.faint)
            TextField("—", text: Binding(
                get: { value.map { KLabeledNumberField.format($0, decimals: 2) } ?? "" },
                set: { value = KLabeledNumberField.parse($0) }))
                .textFieldStyle(.plain).monospacedDigit()
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.text).frame(width: 46)
        }
        .padding(.horizontal, 8).padding(.vertical, 7)
        .background(Palette.bg, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
    }
}

// MARK: - History row (tap to edit, hold-to-confirm delete)

private struct SnapshotHistoryRow: View {
    let snapshot: PortfolioSnapshot
    let openEdit: () -> Void
    let delete: () -> Void
    @State private var hover = false
    @State private var showConfirm = false

    var body: some View {
        HStack(spacing: 10) {
            Text(Fmt.day(snapshot.date)).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.text)
            Text("· \(snapshot.holdings.count)").font(.system(size: 11)).foregroundStyle(Palette.faint)
            Spacer()
            Text(Fmt.inr(snapshot.totalCurrent)).font(.system(size: 12, weight: .semibold)).monospacedDigit()
                .foregroundStyle(Palette.muted)
            Button { openEdit() } label: {
                Image(systemName: "pencil").font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(KIconButtonStyle(size: 20))
            .opacity(hover ? 1 : 0)
            Button { showConfirm = true } label: {
                Image(systemName: "trash").font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(KIconButtonStyle(size: 20, color: Palette.red))
            .opacity(hover ? 1 : 0)
            .holdToDelete(isPresented: $showConfirm,
                          title: "Delete this snapshot?",
                          message: "The whole \(Fmt.day(snapshot.date)) snapshot (\(snapshot.holdings.count) holdings) — this can't be undone.") {
                delete()
            }
        }
        .padding(.vertical, 4).padding(.horizontal, 4)
        .background(hover ? Palette.surface2.opacity(0.4) : .clear,
                    in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { openEdit() }
        .onHover { h in hover = h }
        .animation(.knFast, value: hover)
    }
}

// MARK: - Snapshot edit sheet (edit any snapshot's holdings)

/// Edit every holding in a snapshot — name, type, quantity, invested, current —
/// or remove holdings. Save writes the whole set; removing them all deletes the
/// snapshot.
struct SnapshotDetailSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    private let snapshotID: String
    private let date: String
    @State private var holdings: [Holding]

    init(snapshot: PortfolioSnapshot) {
        snapshotID = snapshot.id
        date = snapshot.date
        _holdings = State(initialValue: snapshot.holdings)
    }

    private var totalCurrent: Double { holdings.reduce(0) { $0 + $1.currentInr } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Edit snapshot · \(Fmt.day(date))")
                    .font(.system(size: 18, weight: .heavy, design: .rounded)).foregroundStyle(Palette.text)
                Text("Fix quantities or amounts, or remove a holding.")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
            }
            .padding(20)

            Divider().overlay(Palette.border)

            if holdings.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "chart.pie").font(.system(size: 26)).foregroundStyle(Palette.faint)
                    Text("No holdings left — saving will delete this snapshot.")
                        .font(.system(size: 13)).foregroundStyle(Palette.muted)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 40)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach($holdings) { $h in
                            EditableHoldingRow(holding: $h) {
                                holdings.removeAll { $0.id == h.id }
                            }
                        }
                    }
                    .padding(16)
                }
                .frame(maxHeight: 440)
            }

            Divider().overlay(Palette.border)

            HStack(spacing: 12) {
                Text("\(holdings.count) holdings · \(Fmt.inr(totalCurrent))")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.muted)
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(KGhostButtonStyle())
                Button("Save changes") {
                    if holdings.isEmpty { state.deleteSnapshot(snapshotID) }
                    else { state.updateSnapshotHoldings(snapshotID, holdings: holdings) }
                    dismiss()
                }
                .buttonStyle(KPrimaryButtonStyle())
            }
            .padding(20)
        }
        .frame(width: 640)
        .background(Palette.elevated)
    }
}

/// One editable saved holding — with a hold-to-confirm remove (removes from the
/// draft; the delete persists on Save).
private struct EditableHoldingRow: View {
    @Binding var holding: Holding
    let remove: () -> Void
    @State private var showConfirm = false

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                TextField("Name", text: $holding.name)
                    .textFieldStyle(.plain).font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.text).frame(maxWidth: .infinity, alignment: .leading)
                // Yahoo ticker for live prices (e.g. ITC.NS, TCS.BO, AAPL)
                TextField("ITC.NS", text: Binding(get: { holding.symbol ?? "" },
                                                  set: { holding.symbol = $0.isEmpty ? nil : $0.uppercased() }))
                    .textFieldStyle(.plain).font(.system(size: 12, weight: .semibold)).monospaced()
                    .foregroundStyle(Palette.text).frame(width: 96)
                    .padding(.horizontal, 8).padding(.vertical, 7)
                    .background(Palette.bg, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
                    .help("Yahoo ticker for live prices — ITC.NS (NSE), TCS.BO (BSE), AAPL (US)")
                HoldingTypeMenu(type: $holding.type)
                Button { showConfirm = true } label: {
                    Image(systemName: "trash").font(.system(size: 11, weight: .bold))
                }
                .buttonStyle(KIconButtonStyle(size: 24, color: Palette.red))
                .holdToDelete(isPresented: $showConfirm,
                              title: "Remove this holding?",
                              message: "\(holding.name.isEmpty ? "This holding" : holding.name) — removed when you save.",
                              confirmLabel: "Hold to remove") {
                    remove()
                }
            }
            HStack(spacing: 8) {
                HoldingQtyField(label: "Qty", value: $holding.units)
                HoldingMoneyField(label: "Invested", value: $holding.investedInr)
                HoldingMoneyField(label: "Now", value: $holding.currentInr)
                Spacer(minLength: 0)
                if holding.investedInr > 0 {
                    Text("\(holding.pnl >= 0 ? "+" : "")\(String(format: "%.1f%%", holding.returnPct * 100))")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundStyle(holding.pnl >= 0 ? Palette.green : Palette.red)
                }
            }
        }
        .padding(11)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(Palette.border, lineWidth: 1))
    }
}
