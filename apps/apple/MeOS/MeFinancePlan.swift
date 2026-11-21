import SwiftUI
import Charts

// MARK: - Income and expenses

struct MeFinanceFlow: View {
    @EnvironmentObject var state: AppState
    let kind: FinCategoryKind
    @Binding var selection: FinDestination

    @State private var preset: FinRangePreset = .y1
    @State private var customStart = FinanceCal.date(FinanceCal.addMonths(-12, to: FinanceCal.today())) ?? .now
    @State private var customEnd = Date.now
    @State private var adding = false
    @State private var detailID: String?
    @State private var addingCategory = false
    @State private var limit = 120

    private var doc: FinanceDocument { state.finance }
    private var isIncome: Bool { kind == .income }
    private var start: String {
        if preset == .custom { return FinanceCal.key(customStart) }
        return FinanceEngine.rangeStart(preset, doc: doc) ?? FinanceCal.addYears(-10, to: FinanceCal.today())
    }
    private var end: String { preset == .custom ? FinanceCal.key(customEnd) : FinanceCal.today() }
    private var totals: FinPeriodTotals { FinanceEngine.totals(doc, from: start, through: end) }

    private var records: [FinTransaction] {
        doc.transactions.filter { t in
            guard t.date >= start && t.date <= end else { return false }
            if isIncome { return FinanceEngine.isIncome(t) }
            return FinanceEngine.isExpense(t) || FinanceEngine.isRefund(t)
        }.sorted { $0.date > $1.date }
    }

    private var visible: [FinTransaction] { Array(records.prefix(limit)) }

    private var slices: [FinCategorySlice] {
        isIncome ? FinanceEngine.incomeByCategory(doc, from: start, through: end)
                 : FinanceEngine.expenseByCategory(doc, from: start, through: end)
    }

    private var months: [FinMonthPoint] {
        let ends = preset == .all
            ? FinanceCal.months(from: FinanceCal.monthStart(start), through: end).suffix(18).map { FinanceCal.monthEnd($0) }
            : FinanceCal.monthsBack(min(max(preset.months ?? 12, 3), 24))
        return FinanceEngine.monthlyCashflow(doc, months: Array(ends))
    }

    var body: some View {
        let total = isIncome ? totals.incomePaise : totals.expensePaise
        let activeMonths = max(1, months.filter { $0.incomePaise > 0 || $0.expensePaise > 0 }.count)
        let average = total / Int64(activeMonths)
        let top = slices.first
        let budgets = FinanceEngine.budgetStatuses(doc)

        FinPage(title: kind == .income ? "Income" : "Expenses",
                sub: kind == .income
                    ? "Inflows classified as income, interest or dividend. Transfers and refunds are excluded."
                    : "Ordinary spending, fees, tax and loan interest, net of refunds.",
                badge: doc.settings.demoMode ? "Demo data" : nil) {

            #if os(macOS)
            HStack(spacing: 8) {
                FinRangeBar(selection: $preset, presets: [.m1, .m3, .m6, .y1, .all, .custom])
                Spacer()
                if preset == .custom { customDates }
                categoryAddButton
                FinPrimaryButton(title: "Add \(isIncome ? "income" : "expense")", icon: "plus") { adding = true }
            }
            #else
            VStack(alignment: .leading, spacing: 8) {
                ScrollView(.horizontal) {
                    FinRangeBar(selection: $preset, presets: [.m1, .m3, .m6, .y1, .all, .custom])
                }
                .scrollIndicators(.hidden)
                HStack(spacing: 8) {
                    if preset == .custom { customDates }
                    Spacer()
                    categoryAddButton
                    FinPrimaryButton(title: "Add", icon: "plus") { adding = true }
                }
            }
            #endif

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 175), spacing: 12)], spacing: 12) {
                FinStatTile(label: isIncome ? "Total income" : "Total spent",
                            value: FinanceFormat.inr(total),
                            sub: "\(FinanceFormat.date(start)) – \(FinanceFormat.date(end))",
                            icon: isIncome ? "arrow.down.left" : "arrow.up.right")
                FinStatTile(label: "Monthly average", value: FinanceFormat.inr(average),
                            sub: "Across \(activeMonths) active months", icon: "calendar")
                FinStatTile(label: "Transactions", value: "\(records.count)",
                            sub: top.map { "Top: \($0.name)" } ?? "No category yet", icon: "list.bullet")
                if isIncome {
                    let rate = totals.savingsRate
                    FinStatTile(label: "Savings rate", value: rate.map { FinanceFormat.percent($0) } ?? "—",
                                sub: "Income minus expenses", icon: "percent")
                } else {
                    let planned = budgets.reduce(Int64(0)) { $0 + $1.budget.plannedPaise }
                    let actual = budgets.reduce(Int64(0)) { $0 + $1.actualPaise }
                    FinStatTile(label: "Budget use", value: planned > 0 ? FinanceFormat.percent(Double(actual) / Double(planned) * 100) : "—",
                                sub: planned > 0 ? "\(FinanceFormat.inr(actual)) of \(FinanceFormat.inr(planned))" : "No budgets set", icon: "chart.pie")
                }
            }

            #if os(macOS)
            HStack(alignment: .top, spacing: 12) {
                categoryCard(slices, total: total).frame(maxWidth: .infinity)
                trendCard(months, isIncome: isIncome).frame(maxWidth: .infinity)
            }
            #else
            categoryCard(slices, total: total)
            trendCard(months, isIncome: isIncome)
            #endif

            if !isIncome && !budgets.isEmpty {
                FinCard {
                    FinCardHeader("Budget pressure", sub: "Current period", icon: "chart.pie") {
                        FinDestinationLink(destination: .budgets, selection: $selection) {
                            Text("Budgets").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.green)
                        }
                    }
                    ForEach(budgets.prefix(5)) { b in
                        HStack(spacing: 8) {
                            Text(b.categoryName).font(.system(size: 11.5, weight: .medium)).lineLimit(1).frame(width: 150, alignment: .leading)
                            FinProgressBar(progress: b.progress, tint: b.progress > 1 ? Palette.negative : b.progress > 0.85 ? Palette.orange : Palette.green)
                            Text("\(FinanceFormat.percent(b.progress * 100, decimals: 0))")
                                .font(.system(size: 10, weight: .semibold)).monospacedDigit().frame(width: 42, alignment: .trailing)
                        }
                    }
                }
            }

            FinSectionTitle(text: isIncome ? "Income records" : "Expense records", detail: "\(records.count)")
            FinCard(padding: 0) {
                if visible.isEmpty {
                    FinEmptyState(icon: isIncome ? "arrow.down.left" : "arrow.up.right",
                                  title: isIncome ? "No income in this range" : "No expenses in this range",
                                  detail: isIncome
                                    ? "Salary, freelance payments and interest appear here once recorded."
                                    : "Ordinary spending appears here. Investments and transfers do not.") {
                        FinPrimaryButton(title: "Add \(isIncome ? "income" : "expense")", icon: "plus") { adding = true }
                    }
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(visible.enumerated()), id: \.element.id) { index, t in
                            Button { detailID = t.id } label: {
                                HStack(spacing: 9) {
                                    Image(systemName: t.type.icon)
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(FinanceEngine.isRefund(t) ? Palette.green : Palette.muted)
                                        .frame(width: 18)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(t.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                        Text("\(FinanceFormat.date(t.date)) · \(doc.category(t.categoryID)?.name ?? t.type.label) · \(doc.account(t.accountID)?.name ?? "—")")
                                            .font(.system(size: 9.5)).foregroundStyle(Palette.muted).lineLimit(1)
                                    }
                                    Spacer()
                                    if t.isDemo { FinBadge(text: "demo", tint: Palette.orange) }
                                    FinMoneyText(paise: displayed(t), showSign: true, size: 12)
                                }
                                .padding(.horizontal, 12).padding(.vertical, 9)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            if index < visible.count - 1 {
                                Rectangle().fill(FinStyle.border).frame(height: 1).padding(.leading, 39)
                            }
                        }
                    }
                }
            }
            if records.count > visible.count {
                HStack {
                    Spacer()
                    Button { limit += 120 } label: {
                        Text("Show 120 more").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.muted)
                            .padding(.horizontal, 14).frame(height: 32).background(FinStyle.elevated, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
            }
            Text(isIncome
                 ? "Refunds reduce spending; they are never counted as income. Investment sales return capital and are excluded."
                 : "Transfers between your accounts, credit-card bill payments and investment purchases are not expenses.")
                .font(.system(size: 9.5)).foregroundStyle(Palette.faint)
        }
        .sheet(isPresented: $adding) {
            FinTransactionEditor(transaction: nil, initialType: isIncome ? .income : .expense)
                .environmentObject(state)
        }
        .sheet(isPresented: $addingCategory) {
            FinCategoryEditor(kind: kind).environmentObject(state)
        }
        .sheet(item: Binding(get: { detailID.map(FinIDBox.init) }, set: { detailID = $0?.id })) { box in
            FinTransactionDetailSheet(id: box.id).environmentObject(state)
        }
    }

    private func displayed(_ t: FinTransaction) -> Int64 {
        FinanceEngine.isRefund(t) ? t.amountPaise : (t.direction == .inflow ? t.amountPaise : -t.amountPaise)
    }

    @ViewBuilder
    private var customDates: some View {
        DatePicker("", selection: $customStart, displayedComponents: .date).labelsHidden()
        Text("to").font(.system(size: 10)).foregroundStyle(Palette.faint)
        DatePicker("", selection: $customEnd, displayedComponents: .date).labelsHidden()
    }

    private var categoryAddButton: some View {
        Button { addingCategory = true } label: {
            Image(systemName: "folder.badge.plus").font(.system(size: 12, weight: .semibold))
                .frame(width: 34, height: 34).background(FinStyle.elevated, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("New category")
    }

    private func categoryCard(_ slices: [FinCategorySlice], total: Int64) -> some View {
        FinCard {
            FinCardHeader(isIncome ? "Income sources" : "Where it went", sub: "\(slices.count) categories", icon: "chart.pie")
            if slices.isEmpty {
                FinEmptyState(icon: "chart.pie", title: "Nothing classified",
                              detail: "No records in this range.")
                    .frame(height: 180)
            } else {
                HStack(alignment: .center, spacing: 14) {
                    FinDonutChart(slices: slices, height: 155).frame(width: 155)
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(slices.prefix(7).enumerated()), id: \.element.id) { i, s in
                            HStack(spacing: 6) {
                                Circle().fill(FinStyle.sliceColor(i)).frame(width: 5, height: 5)
                                Text(s.name).font(.system(size: 10.5)).lineLimit(1)
                                Spacer(minLength: 4)
                                Text(FinanceFormat.compact(s.paise)).font(.system(size: 10, weight: .semibold)).monospacedDigit()
                                Text(FinanceFormat.percent(s.share, decimals: 0)).font(.system(size: 8.5)).foregroundStyle(Palette.faint).frame(width: 26, alignment: .trailing)
                            }
                        }
                    }
                }
                if let top = slices.first, total > 0 {
                    Text("\(top.name) accounts for \(FinanceFormat.percent(top.share)) of the total.")
                        .font(.system(size: 9.5)).foregroundStyle(Palette.faint)
                }
            }
        }
    }

    private func trendCard(_ points: [FinMonthPoint], isIncome: Bool) -> some View {
        FinCard {
            FinCardHeader(isIncome ? "Income trend" : "Spending trend", sub: "Monthly", icon: "chart.bar")
            let values = points.map { isIncome ? $0.incomePaise : $0.expensePaise }
            if values.allSatisfy({ $0 == 0 }) {
                FinEmptyState(icon: "chart.bar", title: "No monthly history", detail: "Trends need at least one month of records.")
                    .frame(height: 180)
            } else {
                Chart(Array(points.enumerated()), id: \.offset) { _, p in
                    BarMark(x: .value("Month", FinanceCal.shortMonth(p.month)),
                            y: .value("Amount", Double(isIncome ? p.incomePaise : p.expensePaise) / 100))
                        .foregroundStyle(isIncome ? Palette.green : Palette.orange)
                        .cornerRadius(3)
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine().foregroundStyle(Palette.text.opacity(0.05))
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(FinanceFormat.compact(Int64(v * 100))).font(.system(size: 8.5)).foregroundStyle(Palette.faint)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let s = value.as(String.self) { Text(s).font(.system(size: 8.5)).foregroundStyle(Palette.faint) }
                        }
                    }
                }
                .frame(height: 180)
            }
        }
    }
}

// MARK: - Category editor

struct FinCategoryEditor: View {
    @EnvironmentObject var state: AppState
    var kind: FinCategoryKind? = nil
    let editing: FinCategory?
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var group = ""
    @State private var selectedKind: FinCategoryKind = .expense
    @State private var icon = "tag"
    @State private var parentID = ""

    init(kind: FinCategoryKind? = nil, editing: FinCategory? = nil) {
        self.kind = kind
        self.editing = editing
        _selectedKind = State(initialValue: kind ?? editing?.kind ?? .expense)
        _name = State(initialValue: editing?.name ?? "")
        _group = State(initialValue: editing?.group ?? "")
        _icon = State(initialValue: editing?.icon ?? "tag")
        _parentID = State(initialValue: editing?.parentID ?? "")
    }

    private let icons = ["tag", "cart", "fork.knife", "car", "house", "bolt", "bag", "ticket", "airplane",
                         "repeat", "shield", "percent", "doc.text", "creditcard", "camera", "film", "megaphone",
                         "briefcase", "laptopcomputer", "gift", "chart.line.uptrend.xyaxis", "banknote"]

    var body: some View {
        VStack(spacing: 0) {
            FinSheetHeader(title: editing == nil ? "New category" : "Edit category",
                           sub: "Custom taxonomy",
                           canSave: !name.trimmingCharacters(in: .whitespaces).isEmpty) { save() }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    FinCard {
                        FinField(label: "Name", placeholder: "Groceries", text: $name)
                        if kind == nil {
                            FinPickerCard(label: "Kind") {
                                Picker("Kind", selection: $selectedKind) {
                                    ForEach(FinCategoryKind.allCases) { k in Text(k.label).tag(k) }
                                }
                                .labelsHidden().pickerStyle(.segmented)
                            }
                        }
                        FinField(label: "Group", placeholder: "Living, Lifestyle, Business…", text: $group)
                        FinPickerCard(label: "Parent category (optional)") {
                            Picker("Parent", selection: $parentID) {
                                Text("None").tag("")
                                ForEach(state.finance.categories.filter { $0.kind == selectedKind && $0.parentID == nil && $0.id != editing?.id }) { c in
                                    Text(c.displayName).tag(c.id)
                                }
                            }
                            .labelsHidden().pickerStyle(.menu)
                        }
                    }
                    FinCard {
                        FinCardHeader("Icon", icon: icon)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 8) {
                            ForEach(icons, id: \.self) { i in
                                Button { icon = i } label: {
                                    Image(systemName: i)
                                        .font(.system(size: 13, weight: .semibold))
                                        .frame(width: 32, height: 32)
                                        .foregroundStyle(icon == i ? Palette.background : Palette.muted)
                                        .background(icon == i ? Palette.text : FinStyle.elevated, in: RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    if let editing, editing.isSystem {
                        Text("This is a seeded category. It can be renamed or archived, and existing transactions keep their reference.")
                            .font(.system(size: 9.5)).foregroundStyle(Palette.faint)
                    }
                }
                .padding(18)
            }
        }
        .background(Palette.background)
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 480)
        #endif
    }

    private func save() {
        if let editing {
            var next = editing
            next.name = name
            next.group = group.isEmpty ? "Other" : group
            next.icon = icon
            next.parentID = parentID.isEmpty ? nil : parentID
            state.financeUpdateCategory(next)
        } else {
            _ = state.financeAddCategory(name: name, kind: selectedKind,
                                         group: group.isEmpty ? "Other" : group,
                                         icon: icon, parentID: parentID.isEmpty ? nil : parentID)
        }
        dismiss()
    }
}

// MARK: - Transfers

struct MeFinanceTransfers: View {
    @EnvironmentObject var state: AppState
    @State private var adding = false
    @State private var detailID: String?
    @State private var confirm: FinTransfer?

    private var doc: FinanceDocument { state.finance }
    private var candidates: [FinTransferCandidate] { FinanceEngine.transferCandidates(doc) }
    private var unmatched: [FinTransaction] {
        doc.transactions.filter { $0.type == .transfer && $0.transferID == nil }
    }

    var body: some View {
        let total = doc.transfers.reduce(Int64(0)) { $0 + $1.amountPaise }
        let fees = doc.transfers.reduce(Int64(0)) { $0 + $1.feePaise }
        let sorted = doc.transfers.sorted { $0.date > $1.date }

        FinPage(title: "Transfers",
                sub: "Movement between your own accounts. Never income, never spending.",
                badge: doc.settings.demoMode ? "Demo data" : nil) {

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 185), spacing: 12)], spacing: 12) {
                FinStatTile(label: "Moved internally", value: FinanceFormat.inr(total), sub: "\(sorted.count) linked transfers", icon: "arrow.left.arrow.right")
                FinStatTile(label: "Transfer fees", value: FinanceFormat.inr(fees), sub: "Recorded as an expense", icon: "percent")
                FinStatTile(label: "To review", value: "\(candidates.count + unmatched.count)", sub: "Possible matches", icon: "exclamationmark.triangle")
            }

            HStack {
                FinPrimaryButton(title: "New transfer", icon: "plus") { adding = true }
                Spacer()
                Text("A transfer creates two linked entries: one out, one in.")
                    .font(.system(size: 10)).foregroundStyle(Palette.faint)
            }

            if !candidates.isEmpty {
                FinCard {
                    FinCardHeader("Possible transfers", sub: "Same amount, opposite directions, within 3 days", icon: "sparkles")
                    ForEach(candidates.prefix(8)) { c in
                        HStack(spacing: 9) {
                            Image(systemName: "arrow.left.arrow.right").font(.system(size: 10)).foregroundStyle(Palette.blue).frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(doc.account(c.from.accountID)?.name ?? "—") → \(doc.account(c.to.accountID)?.name ?? "—")")
                                    .font(.system(size: 11.5, weight: .medium))
                                Text("\(FinanceFormat.date(c.from.date)) · \(c.from.title) / \(c.to.title)")
                                    .font(.system(size: 9.5)).foregroundStyle(Palette.muted).lineLimit(1)
                            }
                            Spacer()
                            FinMoneyText(paise: c.from.amountPaise, size: 11.5)
                            FinPrimaryButton(title: "Match", icon: "link") { state.financeMatchTransfer(c) }
                        }
                    }
                }
            }

            if !unmatched.isEmpty {
                FinCard {
                    FinCardHeader("Unlinked transfer entries", sub: "Created before their counterpart", icon: "exclamationmark.triangle")
                    ForEach(unmatched) { t in
                        Button { detailID = t.id } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(t.title).font(.system(size: 11.5, weight: .medium))
                                    Text("\(FinanceFormat.date(t.date)) · \(doc.account(t.accountID)?.name ?? "—")")
                                        .font(.system(size: 9.5)).foregroundStyle(Palette.muted)
                                }
                                Spacer()
                                FinMoneyText(paise: t.direction == .inflow ? t.amountPaise : -t.amountPaise, showSign: true, size: 11.5)
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            FinSectionTitle(text: "Transfer register", detail: "\(sorted.count)")
            FinCard(padding: 0) {
                if sorted.isEmpty {
                    FinEmptyState(icon: "arrow.left.arrow.right", title: "No transfers yet",
                                  detail: "Moving money between your own accounts should be recorded here so it never inflates income or spending.")
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(sorted.enumerated()), id: \.element.id) { index, t in
                            HStack(spacing: 10) {
                                Image(systemName: "arrow.left.arrow.right")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Palette.blue)
                                    .frame(width: 22, height: 22)
                                    .background(Palette.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(doc.account(t.fromAccountID)?.name ?? "—") → \(doc.account(t.toAccountID)?.name ?? "—")")
                                        .font(.system(size: 12, weight: .medium))
                                    HStack(spacing: 5) {
                                        Text(FinanceFormat.date(t.date))
                                        if t.feePaise > 0 { Text("· fee \(FinanceFormat.inr(t.feePaise))") }
                                        if !t.reference.isEmpty { Text("· \(t.reference)") }
                                        if t.isDemo { Text("· demo") }
                                    }
                                    .font(.system(size: 9.5)).foregroundStyle(Palette.muted)
                                }
                                Spacer()
                                FinMoneyText(paise: t.amountPaise, size: 12)
                                FinBadge(text: t.reconciled ? "Reconciled" : "Review",
                                         tint: t.reconciled ? Palette.green : Palette.orange)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 10)
                            .contentShape(.rect)
                            .contextMenu {
                                Button(t.reconciled ? "Mark unreconciled" : "Mark reconciled") {
                                    state.financeSetTransferReconciled(t.id, reconciled: !t.reconciled)
                                }
                                if let fid = t.fromTransactionID {
                                    Button("Open outgoing entry") { detailID = fid }
                                }
                            }
                            if index < sorted.count - 1 {
                                Rectangle().fill(FinStyle.border).frame(height: 1).padding(.leading, 44)
                            }
                        }
                    }
                }
            }
            Text("A credit-card payment is a transfer to the card account. The original purchase is the expense; paying the bill is not.")
                .font(.system(size: 9.5)).foregroundStyle(Palette.faint)
        }
        .sheet(isPresented: $adding) { FinTransferEditor().environmentObject(state) }
        .sheet(item: Binding(get: { detailID.map(FinIDBox.init) }, set: { detailID = $0?.id })) { box in
            FinTransactionDetailSheet(id: box.id).environmentObject(state)
        }
    }
}

struct FinTransferEditor: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var from = ""
    @State private var to = ""
    @State private var amountText = ""
    @State private var date = Date.now
    @State private var feeText = ""
    @State private var reference = ""
    @State private var note = ""

    private var accounts: [FinAccount] { state.finance.accounts.filter { $0.status == .active } }
    private var canSave: Bool {
        !from.isEmpty && !to.isEmpty && from != to && (FinanceFormat.parsePaise(amountText) ?? 0) > 0
    }

    var body: some View {
        VStack(spacing: 0) {
            FinSheetHeader(title: "New transfer", sub: "Two linked entries, no double counting", canSave: canSave) {
                let ok = state.financeCreateTransfer(fromAccountID: from, toAccountID: to,
                                                     amountPaise: FinanceFormat.parsePaise(amountText) ?? 0,
                                                     date: FinanceCal.key(date),
                                                     feePaise: FinanceFormat.parsePaise(feeText) ?? 0,
                                                     reference: reference, note: note)
                if ok { dismiss() }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    FinCard {
                        FinPickerCard(label: "From") {
                            Picker("From", selection: $from) {
                                Text("Choose").tag("")
                                ForEach(accounts) { a in Text(a.name).tag(a.id) }
                            }
                            .labelsHidden().pickerStyle(.menu)
                        }
                        FinPickerCard(label: "To") {
                            Picker("To", selection: $to) {
                                Text("Choose").tag("")
                                ForEach(accounts.filter { $0.id != from }) { a in Text(a.name).tag(a.id) }
                            }
                            .labelsHidden().pickerStyle(.menu)
                        }
                        HStack(spacing: 10) {
                            FinField(label: "Amount (₹)", placeholder: "0", text: $amountText, keyboard: .decimalPad)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("DATE").font(.system(size: 9, weight: .bold)).tracking(0.8).foregroundStyle(Palette.faint)
                                DatePicker("", selection: $date, displayedComponents: .date)
                                    .labelsHidden().padding(.horizontal, 10).frame(height: 40)
                                    .background(FinStyle.elevated, in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                        FinField(label: "Fee (₹, optional)", placeholder: "0", text: $feeText, keyboard: .decimalPad)
                        FinField(label: "Reference", placeholder: "UPI / NEFT reference", text: $reference)
                        FinField(label: "Note", placeholder: "Why the money moved", text: $note, multiline: true)
                    }
                    Text("The fee is booked separately as an expense. The transfer itself is excluded from income and spending.")
                        .font(.system(size: 9.5)).foregroundStyle(Palette.faint)
                }
                .padding(18)
            }
        }
        .background(Palette.background)
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 500)
        #endif
    }
}

// MARK: - Budgets

struct MeFinanceBudgets: View {
    @EnvironmentObject var state: AppState
    @State private var adding = false
    @State private var editing: FinBudget?
    @State private var pendingDelete: FinBudget?
    @State private var month = Date.now

    private var doc: FinanceDocument { state.finance }
    private var statuses: [FinBudgetStatus] { FinanceEngine.budgetStatuses(doc, on: FinanceCal.key(month)) }
    private var planned: Int64 { statuses.reduce(0) { $0 + $1.budget.plannedPaise } }
    private var actual: Int64 { statuses.reduce(0) { $0 + $1.actualPaise } }

    var body: some View {
        FinPage(title: "Budgets",
                sub: "Planned versus actual, by category and period",
                badge: doc.settings.demoMode ? "Demo data" : nil) {

            HStack(spacing: 8) {
                Button { month = FinanceCal.date(FinanceCal.addMonths(-1, to: FinanceCal.key(month))) ?? month } label: {
                    Image(systemName: "chevron.left").font(.system(size: 10, weight: .bold)).frame(width: 30, height: 30).background(FinStyle.elevated, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Previous month")
                Text(FinanceCal.monthLabel(FinanceCal.key(month))).font(.system(size: 13, weight: .semibold)).frame(minWidth: 90)
                Button { month = FinanceCal.date(FinanceCal.addMonths(1, to: FinanceCal.key(month))) ?? month } label: {
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).frame(width: 30, height: 30).background(FinStyle.elevated, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Next month")
                Spacer()
                FinPrimaryButton(title: "New budget", icon: "plus") { adding = true }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 185), spacing: 12)], spacing: 12) {
                FinStatTile(label: "Planned", value: FinanceFormat.inr(planned), sub: "\(statuses.count) budgets", icon: "target")
                FinStatTile(label: "Actual", value: FinanceFormat.inr(actual), sub: "Net of refunds", icon: "chart.bar")
                FinStatTile(label: "Remaining", value: FinanceFormat.inr(planned - actual),
                            sub: planned >= actual ? "Within plan" : "Over plan", icon: "equal.circle")
                FinStatTile(label: "Use", value: planned > 0 ? FinanceFormat.percent(Double(actual) / Double(planned) * 100) : "—",
                            sub: "Across all budgets", icon: "percent")
            }

            if statuses.isEmpty {
                FinCard {
                    FinEmptyState(icon: "chart.pie", title: "No budgets",
                                  detail: "A budget is a plan for a category or for all spending in a period. It never changes a transaction.") {
                        FinPrimaryButton(title: "Create a budget", icon: "plus") { adding = true }
                    }
                }
            } else {
                ForEach(statuses) { s in
                    FinCard {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(s.budget.name.isEmpty ? s.categoryName : s.budget.name)
                                        .font(.system(size: 14, weight: .semibold))
                                    FinBadge(text: s.budget.period.label, tint: Palette.blue)
                                }
                                Text("\(s.categoryName) · \(FinanceFormat.date(s.range.start)) – \(FinanceFormat.date(s.range.end))")
                                    .font(.system(size: 10)).foregroundStyle(Palette.muted)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(FinanceFormat.inr(s.actualPaise)).font(.system(size: 17, weight: .bold, design: .rounded)).monospacedDigit()
                                Text("of \(FinanceFormat.inr(s.budget.plannedPaise))").font(.system(size: 9.5)).foregroundStyle(Palette.muted)
                            }
                        }
                        FinProgressBar(progress: s.progress,
                                       tint: s.progress > 1 ? Palette.negative : s.progress > 0.85 ? Palette.orange : Palette.green,
                                       height: 8)
                        HStack {
                            Text(s.remainingPaise >= 0
                                 ? "\(FinanceFormat.inr(s.remainingPaise)) left"
                                 : "\(FinanceFormat.inr(-s.remainingPaise)) over")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(s.remainingPaise >= 0 ? Palette.green : Palette.negative)
                            Spacer()
                            Text(FinanceFormat.percent(s.progress * 100, decimals: 0))
                                .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Palette.muted)
                            Menu {
                                Button("Edit") { editing = s.budget }
                                Button("Delete", role: .destructive) { pendingDelete = s.budget }
                            } label: {
                                Image(systemName: "ellipsis").font(.system(size: 11)).frame(width: 28, height: 24)
                            }
                            .menuIndicator(.hidden)
                        }
                    }
                }
            }
            Text("Budget actuals use the same expense definitions as reports: transfers and investments are excluded, and refunds reduce the total.")
                .font(.system(size: 9.5)).foregroundStyle(Palette.faint)
        }
        .sheet(isPresented: $adding) { FinBudgetEditor(budget: nil).environmentObject(state) }
        .sheet(item: $editing) { b in FinBudgetEditor(budget: b).environmentObject(state) }
        .confirmationDialog("Delete this budget?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
            if let b = pendingDelete {
                Button("Delete", role: .destructive) { state.financeDeleteBudget(b.id); pendingDelete = nil }
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("Spending history is untouched. Only the plan is removed, and the deletion is written to the audit log.")
        }
    }
}

struct FinBudgetEditor: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let budget: FinBudget?
    @State private var name = ""
    @State private var categoryID = ""
    @State private var period: FinBudgetPeriod = .monthly
    @State private var start = Date.now
    @State private var end = Date.now
    @State private var plannedText = ""
    @State private var note = ""

    private var canSave: Bool { (FinanceFormat.parsePaise(plannedText) ?? 0) > 0 }

    var body: some View {
        VStack(spacing: 0) {
            FinSheetHeader(title: budget == nil ? "New budget" : "Edit budget", canSave: canSave) { save() }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    FinCard {
                        FinField(label: "Name", placeholder: "Food & cafés", text: $name)
                        FinPickerCard(label: "Category") {
                            Picker("Category", selection: $categoryID) {
                                Text("All spending").tag("")
                                ForEach(state.finance.categories.filter { !$0.archived && $0.kind == .expense && $0.parentID == nil }) { c in
                                    Text(c.displayName).tag(c.id)
                                }
                            }
                            .labelsHidden().pickerStyle(.menu)
                        }
                        FinPickerCard(label: "Period") {
                            Picker("Period", selection: $period) {
                                ForEach(FinBudgetPeriod.allCases) { p in Text(p.label).tag(p) }
                            }
                            .labelsHidden().pickerStyle(.segmented)
                        }
                        FinField(label: "Planned amount (₹)", placeholder: "0", text: $plannedText, keyboard: .decimalPad)
                        if period == .custom {
                            HStack(spacing: 10) {
                                DatePicker("Start", selection: $start, displayedComponents: .date)
                                DatePicker("End", selection: $end, displayedComponents: .date)
                            }
                            .font(.system(size: 11))
                        }
                        FinField(label: "Note", placeholder: "What this plan protects", text: $note, multiline: true)
                    }
                    Text("A budget is a plan, not a transaction. Deleting it never touches spending history.")
                        .font(.system(size: 9.5)).foregroundStyle(Palette.faint)
                }
                .padding(18)
            }
        }
        .background(Palette.background)
        #if os(macOS)
        .frame(minWidth: 470, minHeight: 480)
        #endif
        .onAppear {
            guard let b = budget else { return }
            name = b.name
            categoryID = b.categoryID ?? ""
            period = b.period
            start = FinanceCal.date(b.startDate) ?? .now
            end = b.endDate.flatMap(FinanceCal.date) ?? .now
            plannedText = String(format: "%.2f", Double(b.plannedPaise) / 100)
            note = b.note
        }
    }

    private func save() {
        var next = budget ?? FinBudget()
        next.name = name.trimmingCharacters(in: .whitespaces)
        next.categoryID = categoryID.isEmpty ? nil : categoryID
        next.period = period
        next.startDate = FinanceCal.key(start)
        next.endDate = period == .custom ? FinanceCal.key(end) : nil
        next.plannedPaise = FinanceFormat.parsePaise(plannedText) ?? 0
        next.note = note
        if budget == nil { state.financeAddBudget(next) } else { state.financeUpdateBudget(next) }
        dismiss()
    }
}

// MARK: - Goals

struct MeFinanceGoals: View {
    @EnvironmentObject var state: AppState
    @State private var adding = false
    @State private var editing: FinGoal?
    @State private var contributing: FinGoal?
    @State private var pendingDelete: FinGoal?

    private var doc: FinanceDocument { state.finance }
    private var statuses: [FinGoalStatus] { FinanceEngine.goalStatuses(doc) }

    var body: some View {
        let target = doc.goals.reduce(Int64(0)) { $0 + $1.targetPaise }
        let current = doc.goals.reduce(Int64(0)) { $0 + $1.currentPaise }
        let onTrack = statuses.filter { $0.onTrack == true }.count

        FinPage(title: "Goals",
                sub: "What the money is for. An allocation is a plan, not a separate asset.",
                badge: doc.settings.demoMode ? "Demo data" : nil) {

            HStack {
                Spacer()
                FinPrimaryButton(title: "New goal", icon: "plus") { adding = true }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 185), spacing: 12)], spacing: 12) {
                FinStatTile(label: "Targets", value: FinanceFormat.inr(target), sub: "\(doc.goals.count) goals", icon: "target")
                FinStatTile(label: "Allocated", value: FinanceFormat.inr(current), sub: "Planning figure", icon: "banknote")
                FinStatTile(label: "Progress", value: target > 0 ? FinanceFormat.percent(Double(current) / Double(target) * 100) : "—", sub: "Across all goals", icon: "chart.pie")
                FinStatTile(label: "On track", value: "\(onTrack)", sub: "Based on stated contributions", icon: "checkmark.circle")
            }

            if statuses.isEmpty {
                FinCard {
                    FinEmptyState(icon: "target", title: "No goals",
                                  detail: "Start with an emergency fund target — usually three to six months of essential spending.") {
                        FinPrimaryButton(title: "Create a goal", icon: "plus") { adding = true }
                    }
                }
            } else {
                ForEach(statuses) { s in
                    FinCard {
                        HStack(alignment: .top) {
                            HStack(spacing: 10) {
                                Image(systemName: s.goal.kind.icon)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Palette.green)
                                    .frame(width: 32, height: 32)
                                    .background(Palette.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(s.goal.name).font(.system(size: 14, weight: .semibold))
                                    Text("\(FinanceFormat.inr(s.goal.currentPaise)) of \(FinanceFormat.inr(s.goal.targetPaise))")
                                        .font(.system(size: 10)).foregroundStyle(Palette.muted)
                                }
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(FinanceFormat.percent(s.progress * 100, decimals: 0))
                                    .font(.system(size: 18, weight: .bold, design: .rounded)).monospacedDigit()
                                if let d = s.goal.deadline {
                                    Text("by \(FinanceFormat.date(d))").font(.system(size: 9)).foregroundStyle(Palette.faint)
                                }
                            }
                        }
                        FinProgressBar(progress: s.progress, tint: s.progress >= 1 ? Palette.green : Palette.blue, height: 8)
                        HStack(spacing: 12) {
                            if let months = s.monthsLeft { Text("\(months) months left") }
                            if let req = s.requiredMonthlyPaise { Text("needs \(FinanceFormat.inr(req))/mo") }
                            if let track = s.onTrack {
                                Text(track ? "on track" : "behind")
                                    .foregroundStyle(track ? Palette.green : Palette.orange)
                            }
                            Spacer()
                            FinPrimaryButton(title: "Contribute", icon: "plus") { contributing = s.goal }
                            Menu {
                                Button("Edit") { editing = s.goal }
                                Button("Delete", role: .destructive) { pendingDelete = s.goal }
                            } label: {
                                Image(systemName: "ellipsis").font(.system(size: 11)).frame(width: 28, height: 24)
                            }
                            .menuIndicator(.hidden)
                        }
                        .font(.system(size: 10)).foregroundStyle(Palette.muted)
                        if !s.goal.note.isEmpty {
                            Text(s.goal.note).font(.system(size: 9.5)).foregroundStyle(Palette.faint)
                        }
                    }
                }
            }
            FinCard {
                FinCardHeader("Honest accounting", icon: "info.circle")
                Text("A goal's current amount is a planning allocation. It does not create a new asset, and it is not added to net worth. If the money sits in an account, that account already counts.")
                    .font(.system(size: 10.5)).foregroundStyle(Palette.muted)
            }
        }
        .sheet(isPresented: $adding) { FinGoalEditor(goal: nil).environmentObject(state) }
        .sheet(item: $editing) { g in FinGoalEditor(goal: g).environmentObject(state) }
        .sheet(item: $contributing) { g in FinGoalContributeSheet(goal: g).environmentObject(state) }
        .confirmationDialog("Delete this goal?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
            if let g = pendingDelete {
                Button("Delete", role: .destructive) { state.financeDeleteGoal(g.id); pendingDelete = nil }
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("The allocation disappears. No account balance or transaction is changed.")
        }
    }
}

struct FinGoalEditor: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let goal: FinGoal?
    @State private var name = ""
    @State private var kind: FinGoalKind = .savings
    @State private var targetText = ""
    @State private var currentText = ""
    @State private var deadline = Date.now
    @State private var hasDeadline = false
    @State private var monthlyText = ""
    @State private var accountID = ""
    @State private var note = ""

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && (FinanceFormat.parsePaise(targetText) ?? 0) > 0
    }

    var body: some View {
        VStack(spacing: 0) {
            FinSheetHeader(title: goal == nil ? "New goal" : "Edit goal", canSave: canSave) { save() }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    FinCard {
                        FinField(label: "Name", placeholder: "Emergency fund", text: $name)
                        FinPickerCard(label: "Kind") {
                            Picker("Kind", selection: $kind) {
                                ForEach(FinGoalKind.allCases) { k in Text(k.label).tag(k) }
                            }
                            .labelsHidden().pickerStyle(.menu)
                        }
                        HStack(spacing: 10) {
                            FinField(label: "Target (₹)", placeholder: "0", text: $targetText, keyboard: .decimalPad)
                            FinField(label: "Already allocated (₹)", placeholder: "0", text: $currentText, keyboard: .decimalPad)
                        }
                        FinField(label: "Monthly contribution (₹)", placeholder: "0", text: $monthlyText, keyboard: .decimalPad)
                        FinToggleRow(label: "Has a deadline", isOn: $hasDeadline)
                        if hasDeadline {
                            DatePicker("Deadline", selection: $deadline, displayedComponents: .date).font(.system(size: 11))
                        }
                        FinPickerCard(label: "Linked account (reference only)") {
                            Picker("Account", selection: $accountID) {
                                Text("None").tag("")
                                ForEach(state.finance.accounts.filter { !$0.type.isLiability }) { a in Text(a.name).tag(a.id) }
                            }
                            .labelsHidden().pickerStyle(.menu)
                        }
                        FinField(label: "Note", placeholder: "What this is for", text: $note, multiline: true)
                    }
                }
                .padding(18)
            }
        }
        .background(Palette.background)
        #if os(macOS)
        .frame(minWidth: 470, minHeight: 520)
        #endif
        .onAppear {
            guard let g = goal else { return }
            name = g.name; kind = g.kind
            targetText = String(format: "%.2f", Double(g.targetPaise) / 100)
            currentText = String(format: "%.2f", Double(g.currentPaise) / 100)
            monthlyText = String(format: "%.2f", Double(g.monthlyContributionPaise) / 100)
            if let d = g.deadline { hasDeadline = true; deadline = FinanceCal.date(d) ?? .now }
            accountID = g.accountID ?? ""
            note = g.note
        }
    }

    private func save() {
        var next = goal ?? FinGoal(name: name)
        next.name = name
        next.kind = kind
        next.targetPaise = FinanceFormat.parsePaise(targetText) ?? 0
        next.currentPaise = FinanceFormat.parsePaise(currentText) ?? 0
        next.monthlyContributionPaise = FinanceFormat.parsePaise(monthlyText) ?? 0
        next.deadline = hasDeadline ? FinanceCal.key(deadline) : nil
        next.accountID = accountID.isEmpty ? nil : accountID
        next.note = note
        next.achieved = next.targetPaise > 0 && next.currentPaise >= next.targetPaise
        if goal == nil { state.financeAddGoal(next) } else { state.financeUpdateGoal(next) }
        dismiss()
    }
}

struct FinGoalContributeSheet: View {
    @EnvironmentObject var state: AppState
    let goal: FinGoal
    @Environment(\.dismiss) private var dismiss
    @State private var amountText = ""
    @State private var fromAccountID = ""

    var body: some View {
        VStack(spacing: 0) {
            FinSheetHeader(title: "Contribute to goal", sub: goal.name,
                           canSave: (FinanceFormat.parsePaise(amountText) ?? 0) > 0) {
                state.financeContributeToGoal(goal.id,
                                              amountPaise: FinanceFormat.parsePaise(amountText) ?? 0,
                                              fromAccountID: fromAccountID.isEmpty ? nil : fromAccountID)
                dismiss()
            }
            VStack(alignment: .leading, spacing: 14) {
                FinField(label: "Amount (₹)", placeholder: "0", text: $amountText, keyboard: .decimalPad)
                FinPickerCard(label: "Reference account") {
                    Picker("Account", selection: $fromAccountID) {
                        Text("None").tag("")
                        ForEach(state.finance.accounts.filter { !$0.type.isLiability }) { a in Text(a.name).tag(a.id) }
                    }
                    .labelsHidden().pickerStyle(.menu)
                }
                Text("This updates the goal's allocated amount. It does not move money. Record a transfer separately if the cash actually moved.")
                    .font(.system(size: 10)).foregroundStyle(Palette.muted)
                Spacer()
            }
            .padding(18)
        }
        .background(Palette.background)
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 300)
        #endif
    }
}

// MARK: - Recurring

struct MeFinanceRecurring: View {
    @EnvironmentObject var state: AppState
    @State private var adding = false
    @State private var editing: FinRecurring?
    @State private var logItem: FinRecurring?
    @State private var pendingDelete: FinRecurring?
    @State private var logDate = Date.now

    private var doc: FinanceDocument { state.finance }
    private var items: [FinRecurring] { doc.recurring.sorted { $0.active && !$1.active ? true : $0.nextDate < $1.nextDate } }
    private var upcoming: [FinUpcomingPayment] { FinanceEngine.upcomingPayments(doc, days: 45) }

    var body: some View {
        let monthly = FinanceEngine.monthlyRecurringCommitment(doc)
        let annual = FinanceEngine.annualRecurringCommitment(doc)
        let active = doc.recurring.filter(\.active).count

        FinPage(title: "Recurring payments",
                sub: "Subscriptions, rent, EMIs, bills and SIPs",
                badge: doc.settings.demoMode ? "Demo data" : nil) {

            HStack {
                Spacer()
                FinPrimaryButton(title: "New commitment", icon: "plus") { adding = true }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 185), spacing: 12)], spacing: 12) {
                FinStatTile(label: "Monthly commitment", value: FinanceFormat.inr(monthly), sub: "\(active) active", icon: "repeat")
                FinStatTile(label: "Annual commitment", value: FinanceFormat.inr(annual), sub: "If nothing changes", icon: "calendar")
                FinStatTile(label: "Due in 45 days", value: "\(upcoming.count)", sub: upcoming.first.map { FinanceFormat.date($0.date) } ?? "Nothing due", icon: "clock")
            }

            if !upcoming.isEmpty {
                FinCard {
                    FinCardHeader("Next up", sub: "Sorted by date", icon: "calendar")
                    ForEach(upcoming.prefix(8)) { p in
                        HStack(spacing: 9) {
                            Image(systemName: p.kind.icon).font(.system(size: 10)).foregroundStyle(Palette.muted).frame(width: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(p.title).font(.system(size: 12, weight: .medium))
                                Text("\(FinanceFormat.date(p.date)) · \(p.daysAway <= 0 ? "today" : "in \(p.daysAway) days") · \(p.certainty.label)")
                                    .font(.system(size: 9.5)).foregroundStyle(Palette.muted)
                            }
                            Spacer()
                            FinMoneyText(paise: p.amountPaise, size: 11.5)
                        }
                    }
                }
            }

            FinSectionTitle(text: "Commitments", detail: "\(items.count)")
            if items.isEmpty {
                FinCard {
                    FinEmptyState(icon: "repeat", title: "No recurring payments",
                                  detail: "Record a subscription, rent, EMI or SIP here so upcoming commitments are visible. A statement entry is never created automatically.") {
                        FinPrimaryButton(title: "Add commitment", icon: "plus") { adding = true }
                    }
                }
            } else {
                ForEach(items) { item in
                    FinCard {
                        HStack(alignment: .top) {
                            Image(systemName: item.kind.icon)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(item.active ? Palette.green : Palette.muted)
                                .frame(width: 30, height: 30)
                                .background(FinStyle.elevated, in: RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(item.name).font(.system(size: 13, weight: .semibold))
                                    FinBadge(text: item.kind.label, tint: Palette.blue)
                                    if !item.active { FinBadge(text: "paused", tint: Palette.orange) }
                                }
                                Text("\(FinanceFormat.inr(item.amountPaise)) · \(item.cadence.label.lowercased()) · next \(FinanceFormat.date(item.nextDate))")
                                    .font(.system(size: 10)).foregroundStyle(Palette.muted)
                                if let a = doc.account(item.accountID) {
                                    Text(a.name).font(.system(size: 9)).foregroundStyle(Palette.faint)
                                }
                            }
                            Spacer()
                            Toggle("", isOn: Binding(get: { item.active }, set: { _ in state.financeToggleRecurring(item.id) }))
                                .labelsHidden().tint(Palette.green)
                            Menu {
                                if [.subscription, .rent, .bill, .insurance, .other].contains(item.kind) {
                                    Button("Log this occurrence") { logItem = item; logDate = FinanceCal.date(item.nextDate) ?? .now }
                                }
                                if item.kind == .sip || item.kind == .recurringDeposit {
                                    Text("Record this through Investments so the holding's cost basis updates.")
                                }
                                if item.kind == .emi {
                                    Text("Record this through Liabilities so principal and interest stay separate.")
                                }
                                Button("Edit") { editing = item }
                                Button("Delete", role: .destructive) { pendingDelete = item }
                            } label: {
                                Image(systemName: "ellipsis").font(.system(size: 11)).frame(width: 28, height: 24)
                            }
                            .menuIndicator(.hidden)
                        }
                    }
                }
            }
            FinCard {
                FinCardHeader("No double counting", icon: "checkmark.shield")
                Text("MeOS never creates a transaction when a statement later contains the same payment. Tap “Log this occurrence” only when you want to record it yourself; otherwise the imported transaction is the single record.")
                    .font(.system(size: 10.5)).foregroundStyle(Palette.muted)
            }
        }
        .sheet(isPresented: $adding) { FinRecurringEditor(item: nil).environmentObject(state) }
        .sheet(item: $editing) { item in FinRecurringEditor(item: item).environmentObject(state) }
        .confirmationDialog("Delete this commitment?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
            if let r = pendingDelete {
                Button("Delete", role: .destructive) { state.financeDeleteRecurring(r.id); pendingDelete = nil }
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("Past transactions stay. Only the recurring schedule is removed.")
        }
        .sheet(item: $logItem) { item in
            VStack(spacing: 0) {
                FinSheetHeader(title: "Log occurrence", sub: item.name, saveTitle: "Log", canSave: item.accountID != nil) {
                    state.financeLogRecurring(item.id, date: FinanceCal.key(logDate))
                    dismissLog()
                }
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("AMOUNT").font(.system(size: 9, weight: .bold)).tracking(0.8).foregroundStyle(Palette.faint)
                            Text(FinanceFormat.inr(item.amountPaise))
                                .font(.system(size: 15, weight: .semibold, design: .rounded)).monospacedDigit()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12).frame(height: 40)
                                .background(FinStyle.elevated, in: RoundedRectangle(cornerRadius: 10))
                        }
                        DatePicker("Date", selection: $logDate, displayedComponents: .date)
                    }
                    Text("This records one real expense and moves the next date forward. The amount is fixed from the commitment; edit the commitment first if it changed.")
                        .font(.system(size: 10)).foregroundStyle(Palette.muted)
                    Spacer()
                }
                .padding(18)
            }
            .background(Palette.background)
            #if os(macOS)
            .frame(minWidth: 460, minHeight: 340)
            #endif
        }
    }

    private func dismissLog() { logItem = nil }
}

struct FinRecurringEditor: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let item: FinRecurring?
    @State private var name = ""
    @State private var kind: FinRecurringKind = .subscription
    @State private var amountText = ""
    @State private var cadence: FinRecurringCadence = .monthly
    @State private var nextDate = Date.now
    @State private var accountID = ""
    @State private var categoryID = ""
    @State private var vendor = ""
    @State private var note = ""
    @State private var active = true
    @State private var intervalText = "30"

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && (FinanceFormat.parsePaise(amountText) ?? 0) > 0
    }

    var body: some View {
        VStack(spacing: 0) {
            FinSheetHeader(title: item == nil ? "New commitment" : "Edit commitment", canSave: canSave) { save() }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    FinCard {
                        FinField(label: "Name", placeholder: "Streamly", text: $name)
                        FinPickerCard(label: "Kind") {
                            Picker("Kind", selection: $kind) {
                                ForEach(FinRecurringKind.allCases) { k in Text(k.label).tag(k) }
                            }
                            .labelsHidden().pickerStyle(.menu)
                        }
                        FinField(label: "Amount (₹)", placeholder: "0", text: $amountText, keyboard: .decimalPad)
                        FinPickerCard(label: "Cadence") {
                            Picker("Cadence", selection: $cadence) {
                                ForEach(FinRecurringCadence.allCases) { c in Text(c.label).tag(c) }
                            }
                            .labelsHidden().pickerStyle(.menu)
                        }
                        if cadence == .custom {
                            FinField(label: "Repeat every (days)", placeholder: "30", text: $intervalText, keyboard: .numberPad)
                        }
                        DatePicker("Next date", selection: $nextDate, displayedComponents: .date).font(.system(size: 11))
                        FinPickerCard(label: "Account") {
                            Picker("Account", selection: $accountID) {
                                Text("None").tag("")
                                ForEach(state.finance.accounts.filter { $0.status == .active }) { a in Text(a.name).tag(a.id) }
                            }
                            .labelsHidden().pickerStyle(.menu)
                        }
                        FinPickerCard(label: "Category") {
                            Picker("Category", selection: $categoryID) {
                                Text("Uncategorised").tag("")
                                ForEach(state.finance.categories.filter { !$0.archived && $0.kind == .expense }) { c in
                                    Text(c.displayName).tag(c.id)
                                }
                            }
                            .labelsHidden().pickerStyle(.menu)
                        }
                        FinField(label: "Vendor", placeholder: "Who charges it", text: $vendor)
                        FinField(label: "Note", placeholder: "Renewal terms, plan…", text: $note, multiline: true)
                        FinToggleRow(label: "Active", isOn: $active)
                    }
                }
                .padding(18)
            }
        }
        .background(Palette.background)
        #if os(macOS)
        .frame(minWidth: 470, minHeight: 580)
        #endif
        .onAppear {
            guard let r = item else { return }
            name = r.name; kind = r.kind
            amountText = String(format: "%.2f", Double(r.amountPaise) / 100)
            cadence = r.cadence
            nextDate = FinanceCal.date(r.nextDate) ?? .now
            accountID = r.accountID ?? ""
            categoryID = r.categoryID ?? ""
            vendor = r.vendor
            note = r.note
            active = r.active
            intervalText = String(r.intervalDays ?? 30)
        }
    }

    private func save() {
        var next = item ?? FinRecurring(name: name)
        next.name = name
        next.kind = kind
        next.amountPaise = FinanceFormat.parsePaise(amountText) ?? 0
        next.cadence = cadence
        next.intervalDays = cadence == .custom ? max(1, Int(intervalText) ?? 30) : nil
        next.nextDate = FinanceCal.key(nextDate)
        next.accountID = accountID.isEmpty ? nil : accountID
        next.categoryID = categoryID.isEmpty ? nil : categoryID
        next.vendor = vendor
        next.note = note
        next.active = active
        if item == nil { state.financeAddRecurring(next) } else { state.financeUpdateRecurring(next) }
        dismiss()
    }
}
