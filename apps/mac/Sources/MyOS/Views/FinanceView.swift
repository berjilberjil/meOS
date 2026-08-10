import SwiftUI

struct FinanceView: View {
    @EnvironmentObject var state: AppState

    enum Section: String, Hashable { case money, invest }
    @State private var section: Section = .money

    // Quick-add form
    @State private var amount = ""
    @State private var kind: TxnKind = .expense
    @State private var category = "food"
    @State private var quality: TxnQuality? = nil
    @State private var note = ""
    @FocusState private var amountFocused: Bool
    @FocusState private var noteFocused: Bool

    @State private var showMetaEditor = false
    @State private var showScan = false
    @State private var editing: Transaction?

    private let cols = [GridItem(.adaptive(minimum: 170), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                Text("Finance").font(.system(size: 24, weight: .semibold)).foregroundStyle(Palette.text)
                Spacer()
                if section == .money {
                    Button { showScan = true } label: {
                        Label("Scan", systemImage: "doc.viewfinder")
                    }
                    .buttonStyle(KGhostButtonStyle())
                    .help("Read a UPI screenshot or bank statement")
                    Button { showMetaEditor = true } label: {
                        Label("Edit targets", systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(KGhostButtonStyle())
                }
            }
            .knRise(0)

            Segmented(options: [(Section.money, "Money"), (Section.invest, "Invest")], selection: $section)
                .knRise(1)

            if section == .money { moneyContent } else { PortfolioView() }
        }
        .sheet(isPresented: $showMetaEditor) { MetaEditor() }
        .sheet(isPresented: $showScan) { ScanSheet() }
        .sheet(item: $editing) { txn in TxnEditSheet(txn: txn) }
    }

    // MARK: - Money

    @ViewBuilder private var moneyContent: some View {
        // Dashboard first — the detailed read on the month.
        LazyVGrid(columns: cols, spacing: 12) {
            StatTile(label: "This month in", value: Fmt.inrShort(state.monthIncome), accent: Palette.green)
            StatTile(label: "This month out", value: Fmt.inrShort(state.monthExpense), accent: Palette.red)
            StatTile(label: "Savings rate", value: "\(Int(state.savingsRate * 100))%",
                     sub: savingsSub, accent: Palette.brand)
            StatTile(label: "Wasted", value: Fmt.inrShort(state.monthWasted), accent: Palette.red)
        }
        .knRise(2)

        NetWorthCard().knRise(3)
        if state.monthExpense > 0 { qualityCard.knRise(4) }
        if !state.monthByCategory.isEmpty { breakdownCard.knRise(5) }
        goldLoanCard.knRise(6)
        emergencyCard.knRise(7)
        insuranceCard.knRise(8)
        // Adding a transaction lives just above the ledger — screenshot scanning is
        // the "Scan" icon in the header, not a giant drop zone on top.
        quickAddCard.knRise(9)
        transactionsList.knRise(10)
    }

    /// The savings-rate tile's subtitle: rupees kept + change vs last month.
    private var savingsSub: String {
        var s = "\(Fmt.inrShort(max(0, state.monthSaved))) kept"
        if let d = state.savingsRateDeltaPP, d != 0 { s += " · \(d > 0 ? "+" : "")\(d)pp" }
        return s
    }

    // Manual add-by-hand. (Screenshot scanning moved to the header "Scan" icon.)
    private var quickAddCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    SectionTitle(text: "Log a transaction")
                    Spacer()
                    Button { showScan = true } label: {
                        Label("Scan a screenshot", systemImage: "doc.viewfinder")
                    }
                    .buttonStyle(KGhostButtonStyle())
                }
                quickAdd
            }
        }
    }

    private var quickAdd: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                KindToggle(kind: $kind)
                HStack(spacing: 3) {
                    Text("₹").font(.system(size: 18, weight: .bold)).foregroundStyle(Palette.faint)
                    TextField("", text: $amount, prompt: Text("0").foregroundColor(Palette.faint))
                        .textFieldStyle(.plain).monospacedDigit()
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(Palette.text)
                        .focused($amountFocused)
                        .onSubmit(add)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.bg, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(amountFocused ? Palette.brand : Palette.border, lineWidth: 2))
                .animation(.knFast, value: amountFocused)

                Button("Add", action: add)
                    .buttonStyle(KPrimaryButtonStyle())
                    .disabled((Double(amount) ?? 0) <= 0)
                    .opacity((Double(amount) ?? 0) <= 0 ? 0.5 : 1)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(Categories.all, id: \.self) { catChip($0) }
                }
                .padding(.vertical, 1)
            }

            HStack(spacing: 10) {
                if kind == .expense { QualityPicker(quality: $quality) }
                TextField("", text: $note, prompt: Text("Note (optional)").foregroundColor(Palette.faint))
                    .textFieldStyle(.plain).font(.system(size: 13)).foregroundStyle(Palette.text)
                    .focused($noteFocused)
                    .knField(focused: noteFocused, radius: Radius.sm)
                    .onSubmit(add)
            }
        }
    }

    private func catChip(_ c: String) -> some View {
        let on = category == c
        return Button {
            category = c
            if Categories.income.contains(c) { kind = .income }
            else if kind == .income { kind = .expense }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: CatStyle.icon(c)).font(.system(size: 11, weight: .bold))
                Text(CatStyle.label(c)).font(.system(size: 12, weight: .heavy, design: .rounded))
            }
            .foregroundStyle(on ? .white : CatStyle.color(c))
            .padding(.horizontal, 11).padding(.vertical, 8)
            .background(on ? CatStyle.color(c) : CatStyle.color(c).opacity(0.14), in: Capsule())
        }
        .buttonStyle(KPressStyle())
    }

    // The useless / useful / investment read.
    private var qualityCard: some View {
        let segs = state.monthByQuality
        let untagged = state.monthUntagged
        let total = max(1, state.monthExpense)
        return Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionTitle(text: "Useless · useful · investment")
                    Spacer()
                    if state.monthWasted > 0 {
                        Text("\(Fmt.inr(state.monthWasted)) leaked")
                            .font(.system(size: 11, weight: .heavy, design: .rounded)).foregroundStyle(Palette.red)
                    }
                }
                // Stacked split bar
                Capsule().fill(Palette.surface2)
                    .frame(height: 16)
                    .overlay(
                        GeometryReader { geo in
                            HStack(spacing: 0) {
                                ForEach(segs, id: \.0) { q, amt in
                                    Rectangle().fill(q.color)
                                        .frame(width: CGFloat(amt / total) * geo.size.width)
                                }
                            }
                        }
                    )
                    .clipShape(Capsule())

                VStack(spacing: 8) {
                    ForEach(segs, id: \.0) { q, amt in
                        qualityLegendRow(color: q.color, icon: q.icon, label: q.label,
                                         amount: amt, pct: amt / total)
                    }
                    if untagged > 0 {
                        qualityLegendRow(color: Palette.faint, icon: "questionmark.circle.fill",
                                         label: "Untagged", amount: untagged, pct: untagged / total)
                    }
                }
            }
        }
    }

    private func qualityLegendRow(color: Color, icon: String, label: String, amount: Double, pct: Double) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon).font(.system(size: 12, weight: .bold)).foregroundStyle(color).frame(width: 16)
            Text(label).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.text)
            Spacer()
            Text("\(Int((pct * 100).rounded()))%").font(.system(size: 11)).foregroundStyle(Palette.faint)
            Text(Fmt.inr(amount)).font(.system(size: 13, weight: .semibold)).monospacedDigit()
                .foregroundStyle(Palette.muted).frame(minWidth: 62, alignment: .trailing)
        }
    }

    private var breakdownCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(text: "Where it went this month")
                ForEach(state.monthByCategory.prefix(9), id: \.0) { cat, total in
                    let frac = state.monthExpense > 0 ? total / state.monthExpense : 0
                    HStack(spacing: 11) {
                        CategoryBadge(category: cat, size: 30)
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(CatStyle.label(cat)).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.text)
                                Spacer()
                                Text(Fmt.inr(total)).font(.system(size: 12, weight: .semibold)).monospacedDigit()
                                    .foregroundStyle(Palette.muted)
                            }
                            MeterBar(fraction: frac, tint: CatStyle.color(cat), height: 6)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Goals (unchanged behaviour)

    private var goldLoanCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionTitle(text: "Gold loan")
                    Spacer()
                    Text("\(Int(state.goldLoanFraction * 100))% cleared")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.amber)
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(Fmt.inr(state.finance.meta.goldLoanOutstandingInr))
                        .font(.system(size: 30, weight: .semibold)).monospacedDigit().foregroundStyle(Palette.text)
                    Text("left of \(Fmt.inrShort(state.finance.meta.goldLoanStartInr)) @ \(Fmt.trimKg(state.finance.meta.goldLoanRatePct))%")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                }
                MeterBar(fraction: state.goldLoanFraction, tint: Palette.amber)
                Text("Paid so far: \(Fmt.inr(state.goldLoanPaid))")
                    .font(.system(size: 12)).foregroundStyle(Palette.green)
                HStack(spacing: 8) {
                    ForEach([5000.0, 10000.0, 25000.0], id: \.self) { amt in
                        Button {
                            state.addTransaction(kind: .expense, amountInr: amt, category: "loan",
                                                 note: "Gold loan payment", source: .manual)
                        } label: { Text("Pay \(Fmt.inrShort(amt))") }
                        .buttonStyle(KSoftButtonStyle(tint: Palette.amber))
                    }
                }
            }
        }
    }

    private var emergencyCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionTitle(text: "Emergency fund — protect yourself first")
                    Spacer()
                    Text("\(Fmt.inrShort(state.finance.meta.emergencyCurrentInr)) / \(Fmt.inrShort(state.finance.meta.emergencyTargetInr))")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.muted)
                }
                MeterBar(fraction: state.emergencyFraction, tint: Palette.blue)
                HStack(spacing: 8) {
                    ForEach([2000.0, 5000.0, 10000.0], id: \.self) { amt in
                        Button { state.addToEmergencyFund(amt) } label: { Text("+ \(Fmt.inrShort(amt))") }
                        .buttonStyle(KSoftButtonStyle(tint: Palette.blue))
                    }
                }
            }
        }
    }

    private var insuranceCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(text: "Insurance — buy this month")
                insuranceRow("Term insurance (₹75L–1Cr, ~₹1k/mo)", on: state.finance.meta.termInsuranceBought) {
                    var m = state.finance.meta; m.termInsuranceBought.toggle(); state.saveFinanceMeta(m)
                }
                insuranceRow("Own health insurance (₹5–10L, ~₹600/mo)", on: state.finance.meta.healthInsuranceBought) {
                    var m = state.finance.meta; m.healthInsuranceBought.toggle(); state.saveFinanceMeta(m)
                }
            }
        }
    }

    private func insuranceRow(_ label: String, on: Bool, toggle: @escaping () -> Void) -> some View {
        Button(action: toggle) {
            HStack(spacing: 10) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(on ? Palette.green : Palette.faint)
                Text(label).font(.system(size: 13)).foregroundStyle(on ? Palette.muted : Palette.text)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(KPressStyle())
        .animation(.knFast, value: on)
    }

    private var transactionsList: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                SectionTitle(text: "This month · \(state.monthTxns.count) entries")
                if state.monthTxns.isEmpty {
                    Text("No transactions yet. Drop a screenshot above, or add one by hand.")
                        .font(.system(size: 13)).foregroundStyle(Palette.faint).padding(.vertical, 6)
                }
                ForEach(Array(state.monthTxns.enumerated()), id: \.element.id) { idx, t in
                    TxnRow(txn: t, edit: { editing = t }, delete: { state.deleteTransaction(t.id) })
                    if idx < state.monthTxns.count - 1 { Divider().overlay(Palette.border) }
                }
            }
        }
    }

    private func add() {
        guard let amt = Double(amount), amt > 0 else { return }
        state.addTransaction(kind: kind, amountInr: amt, category: category,
                             quality: kind == .expense ? quality : nil,
                             note: note.isEmpty ? nil : note, source: .manual)
        amount = ""; note = ""; quality = nil
        amountFocused = true
    }
}

/// A single transaction row — tap to edit; trash asks for a hold-to-confirm before
/// deleting (sensitive finance data).
private struct TxnRow: View {
    let txn: Transaction
    let edit: () -> Void
    let delete: () -> Void
    @State private var hover = false
    @State private var showConfirm = false

    private var subtitle: String {
        let bits = [txn.merchant, txn.note?.isEmpty == false ? txn.note : nil].compactMap { $0 }
        return bits.isEmpty ? Fmt.day(txn.date) : bits.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 11) {
            CategoryBadge(category: txn.category, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(CatStyle.label(txn.category)).font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.text)
                    if let q = txn.quality { QualityTag(quality: q) }
                }
                Text(subtitle).font(.system(size: 11)).foregroundStyle(Palette.faint).lineLimit(1)
            }
            Spacer()
            Text((txn.kind == .income ? "+" : "-") + Fmt.inr(txn.amountInr))
                .font(.system(size: 13, weight: .semibold)).monospacedDigit()
                .foregroundStyle(txn.kind == .income ? Palette.green : Palette.text)
            Button { edit() } label: {
                Image(systemName: "pencil").font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(KIconButtonStyle(size: 22))
            .opacity(hover ? 1 : 0)
            .help("Edit")
            Button { showConfirm = true } label: {
                Image(systemName: "trash").font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(KIconButtonStyle(size: 22, color: Palette.red))
            .opacity(hover ? 1 : 0)
            .help("Delete")
            .holdToDelete(isPresented: $showConfirm,
                          title: "Delete this transaction?",
                          message: "\(CatStyle.label(txn.category)) · \(Fmt.inr(txn.amountInr)) — this can't be undone.") {
                delete()
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 7)
        .background(hover ? Palette.surface2.opacity(0.5) : .clear,
                    in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { edit() }
        .onHover { h in hover = h }
        .animation(.knFast, value: hover)
    }
}

/// Payload for the review sheet (Identifiable for `.sheet(item:)`).
struct ReviewPayload: Identifiable {
    let id = UUID()
    let summary: String
    let drafts: [DraftTxn]
}

/// The screenshot capture flow, now behind the header "Scan" icon. Drop an image
/// → AI reads it → the review appears in this same sheet (no sheet chaining).
private struct ScanSheet: View {
    @EnvironmentObject var state: AppState
    @State private var payload: ReviewPayload?

    var body: some View {
        Group {
            if let p = payload {
                TxnReviewSheet(summary: p.summary, source: .screenshot, drafts: p.drafts)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Scan a transaction")
                        .font(.system(size: 18, weight: .heavy, design: .rounded)).foregroundStyle(Palette.text)
                    ImageDropZone(
                        title: "Drop a UPI screenshot or bank statement",
                        subtitle: "GPay, PhonePe, bank SMS or a statement — AI reads every line, sorts and tags it. You confirm before it saves.",
                        tint: Palette.brand,
                        busy: state.imageBusy
                    ) { imgs, mt in
                        Task { @MainActor in
                            let r = await state.analyzeTransactions(imagesBase64: imgs, mediaType: mt)
                            if state.imageError == nil {
                                payload = ReviewPayload(summary: r.summary, drafts: r.drafts)
                            }
                        }
                    }
                    if let err = state.imageError {
                        Label(err, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 12)).foregroundStyle(Palette.amber)
                    }
                }
                .padding(24)
                .frame(width: 560)
                .background(Palette.elevated)
            }
        }
    }
}

// Edit financial targets (loan balance, rate, emergency target, monthly income).
private struct MetaEditor: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var m = FinanceMeta()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit targets").font(.system(size: 18, weight: .semibold)).foregroundStyle(Palette.text)
            VStack(spacing: 10) {
                row("Gold loan — starting amount", $m.goldLoanStartInr)
                row("Gold loan — outstanding now", $m.goldLoanOutstandingInr)
                row("Gold loan — interest rate %", $m.goldLoanRatePct)
                row("Emergency fund — target", $m.emergencyTargetInr)
                row("Emergency fund — current", $m.emergencyCurrentInr)
                row("Monthly income", $m.monthlyIncomeInr)
            }
            HStack(spacing: 10) {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(KGhostButtonStyle())
                Button("Save") { state.saveFinanceMeta(m); dismiss() }.buttonStyle(KPrimaryButtonStyle())
            }
        }
        .padding(24).frame(width: 400)
        .background(Palette.elevated)
        .onAppear { m = state.finance.meta }
    }

    private func row(_ label: String, _ value: Binding<Double>) -> some View {
        HStack {
            Text(label).font(.system(size: 13)).foregroundStyle(Palette.muted)
            Spacer()
            TextField("", value: value, format: .number)
                .textFieldStyle(.plain).frame(width: 110).multilineTextAlignment(.trailing)
                .foregroundStyle(Palette.text)
                .knField(radius: Radius.sm)
        }
    }
}

/// Edit a saved transaction — every field. Saves via `updateTransaction`.
private struct TxnEditSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Transaction
    @FocusState private var amountFocused: Bool

    init(txn: Transaction) { _draft = State(initialValue: txn) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit transaction")
                .font(.system(size: 18, weight: .heavy, design: .rounded)).foregroundStyle(Palette.text)

            HStack(spacing: 10) {
                KindToggle(kind: $draft.kind)
                HStack(spacing: 3) {
                    Text("₹").font(.system(size: 18, weight: .bold)).foregroundStyle(Palette.faint)
                    TextField("0", value: $draft.amountInr, format: .number)
                        .textFieldStyle(.plain).monospacedDigit()
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(Palette.text)
                        .focused($amountFocused)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.bg, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(amountFocused ? Palette.brand : Palette.border, lineWidth: 2))
                .animation(.knFast, value: amountFocused)
            }

            VStack(alignment: .leading, spacing: 6) {
                KFieldLabel(text: "Category")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) { ForEach(Categories.all, id: \.self) { catChip($0) } }
                        .padding(.vertical, 1)
                }
            }

            if draft.kind == .expense {
                VStack(alignment: .leading, spacing: 6) {
                    KFieldLabel(text: "Quality")
                    QualityPicker(quality: $draft.quality)
                }
            }

            KLabeledField(label: "Merchant", placeholder: "Who / where",
                          text: Binding(get: { draft.merchant ?? "" },
                                        set: { draft.merchant = $0.isEmpty ? nil : $0 }))
            KLabeledField(label: "Note", placeholder: "Optional",
                          text: Binding(get: { draft.note ?? "" },
                                        set: { draft.note = $0.isEmpty ? nil : $0 }))
            KLabeledField(label: "Date (yyyy-mm-dd)", placeholder: "2026-08-07", text: $draft.date)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(KGhostButtonStyle())
                Button("Save") { state.updateTransaction(draft); dismiss() }
                    .buttonStyle(KPrimaryButtonStyle())
                    .disabled(draft.amountInr <= 0)
                    .opacity(draft.amountInr <= 0 ? 0.5 : 1)
            }
        }
        .padding(24).frame(width: 440)
        .background(Palette.elevated)
    }

    private func catChip(_ c: String) -> some View {
        let on = draft.category == c
        return Button {
            draft.category = c
            if Categories.income.contains(c) { draft.kind = .income }
            else if draft.kind == .income { draft.kind = .expense }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: CatStyle.icon(c)).font(.system(size: 11, weight: .bold))
                Text(CatStyle.label(c)).font(.system(size: 12, weight: .heavy, design: .rounded))
            }
            .foregroundStyle(on ? .white : CatStyle.color(c))
            .padding(.horizontal, 11).padding(.vertical, 8)
            .background(on ? CatStyle.color(c) : CatStyle.color(c).opacity(0.14), in: Capsule())
        }
        .buttonStyle(KPressStyle())
    }
}
