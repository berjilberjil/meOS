import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - Transaction filtering

struct FinTxnFilter: Equatable {
    var search = ""
    var start: String? = nil
    var end: String? = nil
    var accountID: String? = nil
    var categoryID: String? = nil
    var type: FinTxnType? = nil
    var direction: FinDirection? = nil
    var verification: FinVerification? = nil
    var source: FinSource? = nil
    var minPaise: Int64? = nil
    var maxPaise: Int64? = nil
    var tag: String? = nil

    var isActive: Bool {
        start != nil || end != nil || accountID != nil || categoryID != nil || type != nil
            || direction != nil || verification != nil || source != nil
            || minPaise != nil || maxPaise != nil || tag != nil
    }

    var activeCount: Int {
        var n = 0
        if start != nil || end != nil { n += 1 }
        if accountID != nil { n += 1 }
        if categoryID != nil { n += 1 }
        if type != nil { n += 1 }
        if direction != nil { n += 1 }
        if verification != nil { n += 1 }
        if source != nil { n += 1 }
        if minPaise != nil || maxPaise != nil { n += 1 }
        if tag != nil { n += 1 }
        return n
    }

    func apply(to transactions: [FinTransaction], doc: FinanceDocument) -> [FinTransaction] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return transactions.filter { t in
            if let start, t.date < start { return false }
            if let end, t.date > end { return false }
            if let accountID, t.accountID != accountID && t.transferAccountID != accountID { return false }
            if let categoryID, t.categoryID != categoryID { return false }
            if let type, t.type != type { return false }
            if let direction, t.direction != direction { return false }
            if let verification, t.verification != verification { return false }
            if let source, t.source != source { return false }
            if let minPaise, t.amountPaise < minPaise { return false }
            if let maxPaise, t.amountPaise > maxPaise { return false }
            if let tag, !t.tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) { return false }
            if q.isEmpty { return true }
            let category = doc.category(t.categoryID)?.displayName ?? ""
            let account = doc.account(t.accountID)?.name ?? ""
            let haystack = [t.merchant, t.note, t.reference, category, account, t.type.label, t.tags.joined(separator: " ")]
                .joined(separator: " ").lowercased()
            return haystack.contains(q)
        }
    }
}

enum FinTxnSort: String, CaseIterable, Identifiable {
    case dateDesc, dateAsc, amountDesc, amountAsc, merchant
    var id: String { rawValue }
    var label: String {
        switch self {
        case .dateDesc: "Newest first"
        case .dateAsc: "Oldest first"
        case .amountDesc: "Largest amount"
        case .amountAsc: "Smallest amount"
        case .merchant: "Payee A–Z"
        }
    }

    func sort(_ list: [FinTransaction]) -> [FinTransaction] {
        switch self {
        case .dateDesc: list.sorted { ($0.date, $0.createdAt) > ($1.date, $1.createdAt) }
        case .dateAsc: list.sorted { ($0.date, $0.createdAt) < ($1.date, $1.createdAt) }
        case .amountDesc: list.sorted { $0.amountPaise > $1.amountPaise }
        case .amountAsc: list.sorted { $0.amountPaise < $1.amountPaise }
        case .merchant: list.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
    }
}

// MARK: - Transaction manager

struct MeFinanceTransactions: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var signals = FinanceSignals.shared
    @State private var filter = FinTxnFilter()
    @State private var sort: FinTxnSort = .dateDesc
    @State private var limit = 200
    @State private var showFilters = false
    @State private var showAdd = false
    @State private var selecting = false
    @State private var selected = Set<String>()
    @State private var detailID: String?
    @State private var bulkCategory: String = ""
    @State private var bulkTag = ""
    @State private var export: FinURLBox?
    @State private var focusRequest = 0
    @State private var showBulk = false
    @FocusState private var tableFocused: Bool
    @State private var highlighted: String?

    private var doc: FinanceDocument { state.finance }
    private var filtered: [FinTransaction] {
        sort.sort(filter.apply(to: doc.transactions, doc: doc))
    }
    private var visible: [FinTransaction] { Array(filtered.prefix(limit)) }

    private var periodTotals: FinPeriodTotals {
        var out = FinPeriodTotals()
        for t in filtered {
            if FinanceEngine.isIncome(t) { out.incomePaise += t.amountPaise }
            else if FinanceEngine.isRefund(t) { out.refundPaise += t.amountPaise }
            else if FinanceEngine.isInternalTransfer(t) { out.transferPaise += t.amountPaise }
            else if FinanceEngine.isInvestmentFlow(t) { if t.direction == .outflow { out.investmentPaise += t.amountPaise } }
            else if t.type == .loanRepayment {
                out.debtPrincipalPaise += t.principalPaise ?? 0
                out.debtInterestPaise += t.interestPaise ?? 0
            } else if FinanceEngine.isExpense(t) { out.expensePaise += FinanceEngine.expenseAmount(t) }
        }
        out.expensePaise = max(0, out.expensePaise - out.refundPaise)
        out.transactionCount = filtered.count
        return out
    }

    var body: some View {
        FinPage(title: "Transactions",
                sub: "\(doc.transactions.count) records · every row is editable and audited",
                badge: doc.settings.demoMode ? "Demo data" : nil) {

            #if os(macOS)
            HStack(spacing: 8) {
                FinSearchBar(text: $filter.search, placeholder: "Search payee, note, reference, tag…", focusRequest: focusRequest)
                    .frame(maxWidth: 420)
                transactionControls
                Spacer(minLength: 4)
                FinPrimaryButton(title: "Add", icon: "plus") { showAdd = true }
            }
            #else
            VStack(alignment: .leading, spacing: 8) {
                FinSearchBar(text: $filter.search, placeholder: "Search payee, note, reference, tag…", focusRequest: focusRequest)
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        transactionControls
                        FinPrimaryButton(title: "Add", icon: "plus") { showAdd = true }
                    }
                }
                .scrollIndicators(.hidden)
            }
            #endif

            if filter.isActive {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        filterChip("All records") { filter = FinTxnFilter(search: filter.search) }
                        if let start = filter.start, let end = filter.end {
                            filterChip("\(FinanceFormat.date(start)) – \(FinanceFormat.date(end))") { filter.start = nil; filter.end = nil }
                        }
                        if let id = filter.accountID, let a = doc.account(id) {
                            filterChip(a.name) { filter.accountID = nil }
                        }
                        if let id = filter.categoryID, let c = doc.category(id) {
                            filterChip(c.displayName) { filter.categoryID = nil }
                        }
                        if let t = filter.type { filterChip(t.label) { filter.type = nil } }
                        if let d = filter.direction { filterChip(d.label) { filter.direction = nil } }
                        if let v = filter.verification { filterChip(v.label) { filter.verification = nil } }
                        if let s = filter.source { filterChip(s.label) { filter.source = nil } }
                        if filter.minPaise != nil || filter.maxPaise != nil { filterChip("Amount range") { filter.minPaise = nil; filter.maxPaise = nil } }
                        if let tag = filter.tag { filterChip("#\(tag)") { filter.tag = nil } }
                    }
                }
                .scrollIndicators(.hidden)
            }

            // Summary strip — what the current filter actually contains.
            HStack(spacing: 18) {
                summary("Records", "\(filtered.count)")
                summary("In", FinanceFormat.inr(periodTotals.incomePaise + periodTotals.refundPaise))
                summary("Out", FinanceFormat.inr(periodTotals.expensePaise))
                summary("Invested", FinanceFormat.inr(periodTotals.investmentPaise))
                summary("Transfers", FinanceFormat.inr(periodTotals.transferPaise))
                Spacer()
                if filtered.count > limit {
                    Text("Showing \(limit) of \(filtered.count)")
                        .font(.system(size: 9.5)).foregroundStyle(Palette.faint)
                }
            }

            if selecting && !selected.isEmpty {
                FinCard(padding: 10) {
                    HStack(spacing: 10) {
                        Text("\(selected.count) selected").font(.system(size: 11.5, weight: .semibold))
                        Spacer()
                        FinPrimaryButton(title: "Categorise", icon: "tag") { showBulk = true }
                        FinPrimaryButton(title: "Verify", icon: "checkmark.seal") {
                            state.financeBulkUpdate(ids: selected, verification: .verified, reason: "Bulk verified")
                            selected.removeAll()
                        }
                        Button { exportSelected() } label: {
                            Text("Export").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Palette.muted)
                        }
                        .buttonStyle(.plain)
                        Button { selected.removeAll() } label: {
                            Text("Clear").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Palette.muted)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            FinCard(padding: 0) {
                #if os(macOS)
                tableHeader
                #endif
                if visible.isEmpty {
                    FinEmptyState(icon: "list.bullet.rectangle",
                                  title: doc.transactions.isEmpty ? "No transactions yet" : "Nothing matches",
                                  detail: doc.transactions.isEmpty
                                    ? "Add the first transaction manually, or queue a statement for the import phase."
                                    : "Clear a filter or search for something else.")
                    .padding(.vertical, 16)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(visible.enumerated()), id: \.element.id) { index, t in
                            #if os(macOS)
                            transactionTableRow(t)
                            #else
                            transactionCardRow(t)
                            #endif
                            if index < visible.count - 1 {
                                Rectangle().fill(FinStyle.border).frame(height: 1).padding(.leading, 12)
                            }
                        }
                    }
                }
            }
            .focusable(true)
            .focused($tableFocused)
            .onKeyPress(.downArrow) {
                moveHighlight(1)
                return .handled
            }
            .onKeyPress(.upArrow) {
                moveHighlight(-1)
                return .handled
            }
            .onKeyPress(.return) {
                if let highlighted { detailID = highlighted; return .handled }
                return .ignored
            }

            if filtered.count > limit {
                HStack {
                    Spacer()
                    Button { limit += 200 } label: {
                        Text("Load 200 more").font(.system(size: 11.5, weight: .semibold))
                            .padding(.horizontal, 16).frame(height: 34)
                            .background(FinStyle.elevated, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
            }

            Text("Transfers and credit-card settlements are excluded from income and expenses. Refunds reduce spending. Investment purchases are capital, not consumption.")
                .font(.system(size: 9.5))
                .foregroundStyle(Palette.faint)
        }
        .sheet(isPresented: $showFilters) {
            FinTxnFilterSheet(filter: $filter)
                .environmentObject(state)
        }
        .sheet(isPresented: $showAdd) {
            FinTransactionEditor(transaction: nil)
                .environmentObject(state)
        }
        .sheet(isPresented: $showBulk) {
            FinBulkEditSheet(ids: selected, onDone: { selected.removeAll() })
                .environmentObject(state)
        }
        .sheet(item: Binding(get: { detailID.map(FinIDBox.init) }, set: { detailID = $0?.id })) { box in
            FinTransactionDetailSheet(id: box.id).environmentObject(state)
        }
        .sheet(item: $export) { box in
            FinShareSheet(url: box.url)
        }
        .background {
            VStack {
                Button("Find transaction") { focusRequest += 1 }
                    .keyboardShortcut("f", modifiers: .command)
                Button("Export transactions") { exportCSV() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
            }
            .frame(width: 0, height: 0).opacity(0).accessibilityHidden(true)
        }
        .onChange(of: filter) { _, _ in limit = 200 }
        .onAppear {
            if let id = signals.openTransactionID { detailID = id; signals.openTransactionID = nil }
        }
    }

    // MARK: Controls

    @ViewBuilder
    private var transactionControls: some View {
        Button { showFilters = true } label: {
            HStack(spacing: 5) {
                Image(systemName: "line.3.horizontal.decrease")
                Text("Filters")
                if filter.isActive {
                    Text("\(filter.activeCount)")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Palette.text, in: Capsule())
                        .foregroundStyle(Palette.background)
                }
            }
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(Palette.text)
            .padding(.horizontal, 11).frame(height: 34)
            .background(FinStyle.elevated, in: Capsule())
            .overlay { Capsule().strokeBorder(FinStyle.border) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Filter transactions")

        Menu {
            ForEach(FinTxnSort.allCases) { s in
                Button { sort = s } label: {
                    if s == sort { Label(s.label, systemImage: "checkmark") } else { Text(s.label) }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 34, height: 34)
                .background(FinStyle.elevated, in: Circle())
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .accessibilityLabel("Sort transactions")

        Button { selecting.toggle(); if !selecting { selected.removeAll() } } label: {
            Image(systemName: selecting ? "checkmark.circle.fill" : "checkmark.circle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(selecting ? Palette.green : Palette.text)
                .frame(width: 34, height: 34)
                .background(FinStyle.elevated, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(selecting ? "Stop selecting" : "Select transactions")

        Button { exportCSV() } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 34, height: 34)
                .background(FinStyle.elevated, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Export filtered transactions")
    }

    // MARK: Table

    private var tableHeader: some View {
        HStack(spacing: 8) {
            if selecting { Color.clear.frame(width: 18) }
            Text("DATE").frame(width: 84, alignment: .leading)
            Text("PAYEE / DESCRIPTION").frame(maxWidth: .infinity, alignment: .leading)
            Text("CATEGORY").frame(width: 132, alignment: .leading)
            Text("ACCOUNT").frame(width: 118, alignment: .leading)
            Text("TYPE").frame(width: 92, alignment: .leading)
            Text("AMOUNT").frame(width: 104, alignment: .trailing)
        }
        .font(.system(size: 8.5, weight: .bold))
        .tracking(0.7)
        .foregroundStyle(Palette.faint)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Palette.surfaceElevated)
    }

    private func transactionTableRow(_ t: FinTransaction) -> some View {
        let isSelected = selected.contains(t.id)
        let isHighlighted = highlighted == t.id
        return Button {
            tableFocused = true
            highlighted = t.id
            if selecting {
                toggle(t.id)
            } else {
                #if os(macOS)
                if NSEvent.modifierFlags.contains(.shift) || NSEvent.modifierFlags.contains(.command) {
                    selecting = true; toggle(t.id); return
                }
                #endif
                detailID = t.id
            }
        } label: {
            HStack(spacing: 8) {
                if selecting {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .font(.system(size: 13))
                        .foregroundStyle(isSelected ? Palette.green : Palette.muted)
                        .frame(width: 18)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(FinanceFormat.dayMonth(t.date))
                        .font(.system(size: 11.5, weight: .semibold)).monospacedDigit()
                    Text(String(t.date.prefix(4)))
                        .font(.system(size: 8.5)).foregroundStyle(Palette.faint).monospacedDigit()
                }
                .frame(width: 84, alignment: .leading)

                HStack(spacing: 7) {
                    Image(systemName: t.type.icon)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(rowTint(t))
                        .frame(width: 16)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                        HStack(spacing: 4) {
                            if !t.note.isEmpty {
                                Text(t.note).lineLimit(1)
                            }
                            if t.isDemo { Text("demo") }
                            if t.source == .imported { Text("imported") }
                            if t.verification == .needsReview { Text("review") }
                            if !t.tags.isEmpty { Text(t.tags.prefix(2).map { "#\($0)" }.joined(separator: " ")) }
                        }
                        .font(.system(size: 9)).foregroundStyle(Palette.faint)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(doc.category(t.categoryID)?.name ?? "—")
                    .font(.system(size: 10.5))
                    .foregroundStyle(t.categoryID == nil ? Palette.faint : Palette.muted)
                    .lineLimit(1)
                    .frame(width: 132, alignment: .leading)

                Text(doc.account(t.accountID)?.name ?? "—")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
                    .frame(width: 118, alignment: .leading)

                FinBadge(text: t.type.shortLabel, tint: rowTint(t))
                    .frame(width: 92, alignment: .leading)

                FinMoneyText(paise: signed(t), showSign: true, size: 12)
                    .frame(width: 104, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHighlighted ? Palette.text.opacity(0.05) : isSelected ? Palette.green.opacity(0.06) : Color.clear)
            .contentShape(.rect)
        }
        .buttonStyle(FinRowHoverStyle())
        .contextMenu {
            if selecting {
                Button(isSelected ? "Deselect" : "Select") { toggle(t.id) }
            } else {
                Button("Open details") { detailID = t.id }
                Button("Edit") { detailID = t.id }
                if t.verification != .verified {
                    Button("Mark verified") { state.financeBulkUpdate(ids: [t.id], verification: .verified) }
                }
                Button("Duplicate", role: .destructive) { duplicate(t) }
            }
        }
    }

    private func transactionCardRow(_ t: FinTransaction) -> some View {
        Button {
            if selecting { toggle(t.id) } else { detailID = t.id }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                if selecting {
                    Image(systemName: selected.contains(t.id) ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 15))
                        .foregroundStyle(selected.contains(t.id) ? Palette.green : Palette.muted)
                        .padding(.top, 2)
                }
                Image(systemName: t.type.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(rowTint(t))
                    .frame(width: 26, height: 26)
                    .background(FinStyle.elevated, in: RoundedRectangle(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    Text("\(doc.category(t.categoryID)?.name ?? "Uncategorised") · \(doc.account(t.accountID)?.name ?? "—")")
                        .font(.system(size: 10)).foregroundStyle(Palette.muted).lineLimit(1)
                    HStack(spacing: 5) {
                        Text(FinanceFormat.date(t.date))
                        if t.verification == .needsReview { Text("· review") }
                        if t.isDemo { Text("· demo") }
                    }
                    .font(.system(size: 9)).foregroundStyle(Palette.faint)
                }
                Spacer(minLength: 4)
                FinMoneyText(paise: signed(t), showSign: true, size: 13)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func rowTint(_ t: FinTransaction) -> Color {
        if FinanceEngine.isIncome(t) { return Palette.green }
        if FinanceEngine.isInternalTransfer(t) { return Palette.blue }
        if FinanceEngine.isInvestmentFlow(t) { return Palette.blue }
        if t.type == .refund { return Palette.green }
        if t.type == .loanRepayment { return Palette.orange }
        if t.type == .fee || t.type == .tax { return Palette.orange }
        return Palette.muted
    }

    private func signed(_ t: FinTransaction) -> Int64 {
        if FinanceEngine.isInternalTransfer(t) { return t.direction == .inflow ? t.amountPaise : -t.amountPaise }
        return t.direction == .inflow ? t.amountPaise : -t.amountPaise
    }

    private func moveHighlight(_ delta: Int) {
        guard !visible.isEmpty else { return }
        guard let current = highlighted, let i = visible.firstIndex(where: { $0.id == current }) else {
            highlighted = delta > 0 ? visible.first?.id : visible.last?.id
            return
        }
        let next = max(0, min(visible.count - 1, i + delta))
        highlighted = visible[next].id
    }

    private func toggle(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func duplicate(_ t: FinTransaction) {
        guard t.type != .investmentSale && t.transferID == nil else { return }
        var copy = t
        copy.id = FinID.new()
        copy.date = FinanceCal.today()
        copy.createdAt = FinNow.stamp()
        copy.updatedAt = copy.createdAt
        copy.source = .manual
        copy.isDemo = false
        copy.verification = .verified
        copy.transferID = nil
        copy.linkedTransactionID = nil
        copy.note = (copy.note.isEmpty ? "" : copy.note + " ") + "Duplicated from \(t.id.prefix(8))"
        state.financeAddTransaction(copy, reason: "Duplicated transaction")
    }

    // MARK: Actions

    private func filterChip(_ label: String, clear: @escaping () -> Void) -> some View {
        Button(action: clear) {
            HStack(spacing: 4) {
                Text(label).font(.system(size: 10, weight: .medium))
                Image(systemName: "xmark").font(.system(size: 7, weight: .bold))
            }
            .foregroundStyle(Palette.muted)
            .padding(.horizontal, 8).frame(height: 24)
            .background(FinStyle.elevated, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func summary(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased()).font(.system(size: 8, weight: .bold)).tracking(0.6).foregroundStyle(Palette.faint)
            Text(value).font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
        }
    }

    private func exportCSV() {
        let csv = FinanceEngine.transactionsCSV(filtered, doc: doc)
        if let url = FinExport.write(csv, name: "meos-transactions") { export = FinURLBox(url: url) }
    }

    private func exportSelected() {
        let list = doc.transactions.filter { selected.contains($0.id) }
        let csv = FinanceEngine.transactionsCSV(list, doc: doc)
        if let url = FinExport.write(csv, name: "meos-selected-transactions") { export = FinURLBox(url: url) }
    }
}

private struct FinRowHoverStyle: ButtonStyle {
    @State private var hover = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.white.opacity(hover ? 0.025 : 0), in: Rectangle())
            .onHover { h in withAnimation(.easeOut(duration: 0.1)) { hover = h } }
    }
}

// MARK: - Filter sheet

struct FinTxnFilterSheet: View {
    @EnvironmentObject var state: AppState
    @Binding var filter: FinTxnFilter
    @Environment(\.dismiss) private var dismiss
    @State private var draft = FinTxnFilter()
    @State private var limitStart = false
    @State private var limitEnd = false
    @State private var startDate = Date.now
    @State private var endDate = Date.now
    @State private var minText = ""
    @State private var maxText = ""

    var body: some View {
        VStack(spacing: 0) {
            FinSheetHeader(title: "Filter transactions", sub: "\(filteredCount) match", saveTitle: "Apply", canSave: true) {
                var next = draft
                next.start = limitStart ? FinanceCal.key(startDate) : nil
                next.end = limitEnd ? FinanceCal.key(endDate) : nil
                next.minPaise = FinanceFormat.parsePaise(minText)
                next.maxPaise = FinanceFormat.parsePaise(maxText)
                filter = next
                dismiss()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    FinSearchBar(text: $draft.search, placeholder: "Search within the ledger")
                    FinCard {
                        FinCardHeader("Dates", icon: "calendar")
                        FinToggleRow(label: "From a date", isOn: $limitStart)
                        if limitStart {
                            DatePicker("Start", selection: $startDate, displayedComponents: .date)
                                .font(.system(size: 12))
                        }
                        FinToggleRow(label: "Through a date", isOn: $limitEnd)
                        if limitEnd {
                            DatePicker("End", selection: $endDate, displayedComponents: .date)
                                .font(.system(size: 12))
                        }
                        HStack(spacing: 6) {
                            quickRange("This month", monthsAgo: 0)
                            quickRange("Last 3 months", monthsAgo: 3)
                            quickRange("This year", monthsAgo: -1)
                            quickRange("All time", monthsAgo: -2)
                        }
                    }
                    FinCard {
                        FinCardHeader("Classification", icon: "tag")
                        FinPickerCard(label: "Account") {
                            Picker("Account", selection: $draft.accountID) {
                                Text("Any account").tag(String?.none)
                                ForEach(state.finance.accounts) { a in Text(a.name).tag(String?.some(a.id)) }
                            }
                            .labelsHidden().pickerStyle(.menu)
                        }
                        FinPickerCard(label: "Category") {
                            Picker("Category", selection: $draft.categoryID) {
                                Text("Any category").tag(String?.none)
                                ForEach(state.finance.categories.filter { !$0.archived }) { c in
                                    Text(c.displayName).tag(String?.some(c.id))
                                }
                            }
                            .labelsHidden().pickerStyle(.menu)
                        }
                        FinPickerCard(label: "Type") {
                            Picker("Type", selection: $draft.type) {
                                Text("Any type").tag(FinTxnType?.none)
                                ForEach(FinTxnType.allCases) { t in Text(t.label).tag(FinTxnType?.some(t)) }
                            }
                            .labelsHidden().pickerStyle(.menu)
                        }
                        FinPickerCard(label: "Direction") {
                            Picker("Direction", selection: $draft.direction) {
                                Text("Both").tag(FinDirection?.none)
                                ForEach(FinDirection.allCases) { d in Text(d.label).tag(FinDirection?.some(d)) }
                            }
                            .labelsHidden().pickerStyle(.menu)
                        }
                    }
                    FinCard {
                        FinCardHeader("Source & trust", icon: "checkmark.shield")
                        FinPickerCard(label: "Verification") {
                            Picker("Verification", selection: $draft.verification) {
                                Text("Any").tag(FinVerification?.none)
                                ForEach(FinVerification.allCases) { v in Text(v.label).tag(FinVerification?.some(v)) }
                            }
                            .labelsHidden().pickerStyle(.menu)
                        }
                        FinPickerCard(label: "Source") {
                            Picker("Source", selection: $draft.source) {
                                Text("Any").tag(FinSource?.none)
                                ForEach(FinSource.allCases) { s in Text(s.label).tag(FinSource?.some(s)) }
                            }
                            .labelsHidden().pickerStyle(.menu)
                        }
                    }
                    FinCard {
                        FinCardHeader("Amount", sub: "In rupees", icon: "indianrupeesign")
                        HStack(spacing: 10) {
                            FinField(label: "At least", placeholder: "0", text: $minText, keyboard: .numberPad)
                            FinField(label: "At most", placeholder: "Any", text: $maxText, keyboard: .numberPad)
                        }
                    }
                    Button {
                        filter = FinTxnFilter(search: filter.search)
                        dismiss()
                    } label: {
                        Text("Clear all filters").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.orange)
                            .frame(maxWidth: .infinity).frame(height: 38)
                    }
                    .buttonStyle(.plain)
                }
                .padding(18)
            }
        }
        .background(Palette.background)
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 620)
        #endif
        .onAppear {
            draft = filter
            if let s = filter.start, let d = FinanceCal.date(s) { startDate = d; limitStart = true }
            if let e = filter.end, let d = FinanceCal.date(e) { endDate = d; limitEnd = true }
            if let m = filter.minPaise { minText = String(m / 100) }
            if let m = filter.maxPaise { maxText = String(m / 100) }
        }
    }

    private var filteredCount: Int {
        var next = draft
        next.start = limitStart ? FinanceCal.key(startDate) : nil
        next.end = limitEnd ? FinanceCal.key(endDate) : nil
        next.minPaise = FinanceFormat.parsePaise(minText)
        next.maxPaise = FinanceFormat.parsePaise(maxText)
        return next.apply(to: state.finance.transactions, doc: state.finance).count
    }

    @ViewBuilder
    private func quickRange(_ title: String, monthsAgo: Int) -> some View {
        Button {
            let now = Date.now
            if monthsAgo == -2 {
                limitStart = false; limitEnd = false
            } else if monthsAgo == -1 {
                limitStart = true; limitEnd = true
                startDate = FinanceCal.date(FinanceCal.yearStart(FinanceCal.today())) ?? now
                endDate = now
            } else {
                limitStart = true; limitEnd = true
                startDate = FinanceCal.date(FinanceCal.addMonths(-monthsAgo, to: FinanceCal.today())) ?? now
                endDate = now
            }
        } label: {
            Text(title).font(.system(size: 10, weight: .medium))
                .foregroundStyle(Palette.muted)
                .padding(.horizontal, 9).frame(height: 26)
                .background(FinStyle.elevated, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Editor

struct FinTransactionEditor: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let transaction: FinTransaction?
    var initialType: FinTxnType? = nil

    @State private var type: FinTxnType = .expense
    @State private var direction: FinDirection = .outflow
    @State private var amountText = ""
    @State private var date = Date.now
    @State private var hasPostedDate = false
    @State private var postedDate = Date.now
    @State private var accountID = ""
    @State private var toAccountID = ""
    @State private var categoryID = ""
    @State private var merchant = ""
    @State private var paymentMethod: FinPaymentMethod = .upi
    @State private var reference = ""
    @State private var note = ""
    @State private var tagsText = ""
    @State private var verification: FinVerification = .verified
    @State private var liabilityID = ""
    @State private var principalText = ""
    @State private var interestText = ""
    @State private var investmentID = ""
    @State private var unitsText = ""
    @State private var feeText = ""
    @State private var showAccountEditor = false

    private var doc: FinanceDocument { state.finance }
    private var isEditing: Bool { transaction != nil }
    private var isTransfer: Bool { type == .transfer }
    private var isLoanPayment: Bool { type == .loanRepayment }
    private var isLoanDisbursement: Bool { type == .loanDisbursement }
    private var isInvestmentPurchase: Bool { type == .investmentPurchase }
    private var isIncomeSide: Bool {
        switch type {
        case .income, .dividend: return true
        case .interest: return direction == .inflow
        default: return false
        }
    }

    private var categories: [FinCategory] {
        doc.categories.filter { !$0.archived && $0.kind == (isIncomeSide ? .income : .expense) }
            .sorted { ($0.group, $0.parentID == nil ? 0 : 1, $0.name) < ($1.group, $1.parentID == nil ? 0 : 1, $1.name) }
    }

    private func categoryLabel(_ category: FinCategory) -> String {
        if let parent = doc.category(category.parentID) {
            return "\(parent.name) · \(category.name)"
        }
        return category.displayName
    }

    private var activeAccounts: [FinAccount] {
        doc.accounts.filter { $0.status == .active }
    }

    private var canSave: Bool {
        let amount = FinanceFormat.parsePaise(amountText) ?? 0
        guard amount > 0, FinanceCal.date(FinanceCal.key(date)) != nil else { return false }
        if isTransfer { return !accountID.isEmpty && !toAccountID.isEmpty && accountID != toAccountID }
        guard !accountID.isEmpty else { return false }
        if isLoanPayment {
            guard !liabilityID.isEmpty else { return false }
            let principal = FinanceFormat.parsePaise(principalText) ?? max(0, amount - (FinanceFormat.parsePaise(interestText) ?? 0))
            let interest = FinanceFormat.parsePaise(interestText) ?? 0
            return principal + interest == amount
        }
        if isLoanDisbursement { return !liabilityID.isEmpty }
        if isInvestmentPurchase { return !investmentID.isEmpty }
        return true
    }

    var body: some View {
        VStack(spacing: 0) {
            FinSheetHeader(title: isEditing ? "Edit transaction" : "New transaction",
                           sub: isEditing ? "Original values stay in the audit log" : "Manual entry",
                           saveTitle: isEditing ? "Save" : "Add",
                           canSave: canSave) { save() }
            if let transaction {
                HStack(spacing: 6) {
                    Text(transaction.source == .imported ? "Imported record" : "Existing record")
                        .font(.system(size: 10, weight: .semibold))
                    Text("·").foregroundStyle(Palette.faint)
                    Text("Corrections are versioned, never silent.")
                    Spacer()
                    FinBadge(text: transaction.source.label, tint: Palette.blue)
                }
                .font(.system(size: 10)).foregroundStyle(Palette.muted)
                .padding(.horizontal, 18).padding(.vertical, 8)
                .background(FinStyle.surface)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if activeAccounts.isEmpty {
                        FinEmptyState(icon: "building.columns", title: "No active account",
                                      detail: "A transaction needs an account. Create one first.") {
                            FinPrimaryButton(title: "Add account", icon: "plus") { showAccountEditor = true }
                        }
                    }
                    FinCard {
                        FinCardHeader("What happened", icon: "arrow.left.arrow.right")
                        FinPickerCard(label: "Type") {
                            Picker("Type", selection: $type) {
                                ForEach(FinTxnType.allCases.filter { !(isEditing && $0 == .transfer) }) { t in
                                    Text(t.label).tag(t)
                                }
                            }
                            .labelsHidden().pickerStyle(.menu)
                        }
                        HStack(spacing: 10) {
                            FinField(label: isTransfer ? "Amount transferred" : "Amount (₹)", placeholder: "0", text: $amountText, keyboard: .decimalPad)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("DATE").font(.system(size: 9, weight: .bold)).tracking(0.8).foregroundStyle(Palette.faint)
                                DatePicker("", selection: $date, displayedComponents: .date)
                                    .labelsHidden()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 10).frame(height: 40)
                                    .background(FinStyle.elevated, in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                        if !isTransfer {
                            FinToggleRow(label: "Has a separate posted date", isOn: $hasPostedDate)
                            if hasPostedDate {
                                DatePicker("Posted", selection: $postedDate, displayedComponents: .date)
                                    .font(.system(size: 11))
                            }
                            FinPickerCard(label: "Direction") {
                                Picker("Direction", selection: $direction) {
                                    ForEach(FinDirection.allCases) { d in Text(d.label).tag(d) }
                                }
                                .labelsHidden().pickerStyle(.segmented)
                            }
                        }
                        if isTransfer {
                            FinPickerCard(label: "From account") {
                                Picker("From", selection: $accountID) {
                                    Text("Choose").tag("")
                                    ForEach(activeAccounts) { a in Text(a.name).tag(a.id) }
                                }
                                .labelsHidden().pickerStyle(.menu)
                            }
                            FinPickerCard(label: "To account") {
                                Picker("To", selection: $toAccountID) {
                                    Text("Choose").tag("")
                                    ForEach(activeAccounts.filter { $0.id != accountID }) { a in Text(a.name).tag(a.id) }
                                }
                                .labelsHidden().pickerStyle(.menu)
                            }
                            FinField(label: "Transfer fee (₹)", placeholder: "0", text: $feeText, keyboard: .decimalPad)
                        } else {
                            FinPickerCard(label: "Account") {
                                Picker("Account", selection: $accountID) {
                                    Text("Choose").tag("")
                                    ForEach(activeAccounts) { a in Text(a.name).tag(a.id) }
                                }
                                .labelsHidden().pickerStyle(.menu)
                            }
                            if isLoanPayment {
                                FinPickerCard(label: "Liability") {
                                    Picker("Liability", selection: $liabilityID) {
                                        Text("Choose").tag("")
                                        ForEach(doc.liabilities) { l in Text(l.name).tag(l.id) }
                                    }
                                    .labelsHidden().pickerStyle(.menu)
                                }
                                HStack(spacing: 10) {
                                    FinField(label: "Principal (₹)", placeholder: "Reduces debt", text: $principalText, keyboard: .decimalPad)
                                    FinField(label: "Interest (₹)", placeholder: "Expense", text: $interestText, keyboard: .decimalPad)
                                }
                                if let amount = FinanceFormat.parsePaise(amountText), amount > 0 {
                                    let p = FinanceFormat.parsePaise(principalText) ?? max(0, amount - (FinanceFormat.parsePaise(interestText) ?? 0))
                                    let i = FinanceFormat.parsePaise(interestText) ?? 0
                                    Text(p + i == amount
                                         ? "Principal reduces the liability. Interest is the only part counted as an expense."
                                         : "Principal + interest must equal the amount paid.")
                                        .font(.system(size: 9.5))
                                        .foregroundStyle(p + i == amount ? Palette.faint : Palette.orange)
                                }
                            }
                            if isLoanDisbursement {
                                FinPickerCard(label: "Liability this loan belongs to") {
                                    Picker("Liability", selection: $liabilityID) {
                                        Text("Choose").tag("")
                                        ForEach(doc.liabilities) { l in Text(l.name).tag(l.id) }
                                    }
                                    .labelsHidden().pickerStyle(.menu)
                                }
                                Text("This records the cash received and links it to the debt. The liability's outstanding principal is entered in Liabilities; it is not increased twice here.")
                                    .font(.system(size: 9.5)).foregroundStyle(Palette.faint)
                            }
                            if isInvestmentPurchase {
                                FinPickerCard(label: "Investment") {
                                    Picker("Investment", selection: $investmentID) {
                                        Text("Choose").tag("")
                                        ForEach(doc.investments.filter { !$0.archived }) { inv in Text(inv.name).tag(inv.id) }
                                    }
                                    .labelsHidden().pickerStyle(.menu)
                                }
                                FinField(label: "Units (optional)", placeholder: "e.g. 12.5", text: $unitsText, keyboard: .decimalPad)
                                Text("A purchase increases invested capital. It is not spending.")
                                    .font(.system(size: 9.5)).foregroundStyle(Palette.faint)
                            }
                            if !isInvestmentPurchase && !isLoanPayment {
                                FinPickerCard(label: "Category") {
                                    Picker("Category", selection: $categoryID) {
                                        Text("Uncategorised").tag("")
                                        ForEach(categories) { c in Text(categoryLabel(c)).tag(c.id) }
                                    }
                                    .labelsHidden().pickerStyle(.menu)
                                }
                            }
                        }
                    }

                    if !isTransfer {
                        FinCard {
                            FinCardHeader("Details", icon: "text.alignleft")
                            FinField(label: "Merchant or payee", placeholder: "Who was it?", text: $merchant)
                            FinPickerCard(label: "Payment method") {
                                Picker("Payment", selection: $paymentMethod) {
                                    ForEach(FinPaymentMethod.allCases) { p in Text(p.label).tag(p) }
                                }
                                .labelsHidden().pickerStyle(.menu)
                            }
                            FinField(label: "Reference", placeholder: "UPI ref, cheque no., invoice", text: $reference)
                            FinField(label: "Note", placeholder: "Why this happened", text: $note, multiline: true)
                            FinField(label: "Tags", placeholder: "comma, separated", text: $tagsText)
                            FinPickerCard(label: "Verification") {
                                Picker("Verification", selection: $verification) {
                                    ForEach(FinVerification.allCases) { v in Text(v.label).tag(v) }
                                }
                                .labelsHidden().pickerStyle(.menu)
                            }
                        }
                    }
                    if let transaction {
                        FinCard {
                            FinCardHeader("Anchors", sub: "Read-only", icon: "link")
                            keyValue("Transaction ID", transaction.id)
                            keyValue("Source", transaction.source.label)
                            keyValue("Created", transaction.createdAt)
                            keyValue("Updated", transaction.updatedAt)
                            if let batch = transaction.importBatchID { keyValue("Import batch", batch) }
                            if let statement = transaction.statementID { keyValue("Statement", statement) }
                        }
                    }
                }
                .padding(18)
            }
        }
        .background(Palette.background)
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 680)
        #endif
        .sheet(isPresented: $showAccountEditor) {
            FinAccountEditor(account: nil).environmentObject(state)
        }
        .onAppear(perform: load)
        .onChange(of: type) { _, newType in
            switch newType {
            case .income, .interest, .dividend, .refund, .investmentSale, .loanDisbursement:
                direction = .inflow
            case .expense, .fee, .tax, .investmentPurchase, .loanRepayment:
                direction = .outflow
            case .transfer, .adjustment:
                break
            }
            if !isEditing { categoryID = "" }
            if newType == .transfer, accountID.isEmpty { accountID = activeAccounts.first?.id ?? "" }
        }
    }

    private func load() {
        guard let t = transaction else {
            accountID = activeAccounts.first?.id ?? ""
            if let initialType {
                type = initialType
                direction = (initialType == .income || initialType == .interest || initialType == .dividend) ? .inflow : .outflow
            }
            return
        }
        type = t.type
        direction = t.direction
        amountText = String(format: "%.2f", Double(t.amountPaise) / 100)
        date = FinanceCal.date(t.date) ?? .now
        if let posted = t.postedDate, let d = FinanceCal.date(posted) {
            hasPostedDate = true
            postedDate = d
        }
        accountID = t.accountID
        toAccountID = t.transferAccountID ?? ""
        categoryID = t.categoryID ?? ""
        merchant = t.merchant
        paymentMethod = t.paymentMethod
        reference = t.reference
        note = t.note
        tagsText = t.tags.joined(separator: ", ")
        verification = t.verification
        liabilityID = t.liabilityID ?? ""
        principalText = t.principalPaise.map { String(format: "%.2f", Double($0) / 100) } ?? ""
        interestText = t.interestPaise.map { String(format: "%.2f", Double($0) / 100) } ?? ""
        investmentID = t.investmentID ?? ""
    }

    private func save() {
        guard let amount = FinanceFormat.parsePaise(amountText), amount > 0 else { return }
        let key = FinanceCal.key(date)
        if isEditing, transaction?.transferID != nil {
            // A transfer is a linked pair. Editing one leg here would break the
            // pairing, so it is edited as a pair from the Transfers screen.
            return
        }
        let tags = tagsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if isTransfer, !isEditing {
            let ok = state.financeCreateTransfer(fromAccountID: accountID, toAccountID: toAccountID,
                                                 amountPaise: amount, date: key,
                                                 feePaise: FinanceFormat.parsePaise(feeText) ?? 0,
                                                 reference: reference, note: note)
            if ok { dismiss() }
            return
        }
        if isLoanPayment, !isEditing {
            let principal = FinanceFormat.parsePaise(principalText) ?? max(0, amount - (FinanceFormat.parsePaise(interestText) ?? 0))
            let interest = FinanceFormat.parsePaise(interestText) ?? 0
            guard principal + interest <= amount || interest == 0 else { return }
            let ok = state.financeRecordDebtPayment(liabilityID: liabilityID, accountID: accountID,
                                                    amountPaise: amount, principalPaise: principal,
                                                    interestPaise: interest, date: key, note: note)
            if ok { dismiss() }
            return
        }
        if isLoanDisbursement, !isEditing {
            var t = FinTransaction()
            t.date = key
            t.amountPaise = amount
            t.direction = .inflow
            t.type = .loanDisbursement
            t.accountID = accountID
            t.merchant = merchant
            t.note = note
            t.reference = reference
            t.liabilityID = liabilityID
            t.verification = verification
            state.financeAddTransaction(t, reason: "Loan disbursement")
            dismiss()
            return
        }
        if isInvestmentPurchase, !isEditing {
            let units = Double(unitsText.replacingOccurrences(of: ",", with: "."))
            let ok = state.financeRecordInvestmentPurchase(investmentID: investmentID,
                                                           accountID: accountID,
                                                           amountPaise: amount, date: key,
                                                           units: units, reference: reference, note: note)
            if ok { dismiss() }
            return
        }

        var t = transaction ?? FinTransaction()
        t.date = key
        t.postedDate = hasPostedDate ? FinanceCal.key(postedDate) : nil
        t.amountPaise = amount
        t.direction = direction
        t.type = type
        t.accountID = accountID
        t.transferAccountID = isTransfer ? toAccountID : nil
        t.categoryID = categoryID.isEmpty ? nil : categoryID
        t.merchant = merchant.trimmingCharacters(in: .whitespaces)
        t.paymentMethod = paymentMethod
        t.reference = reference.trimmingCharacters(in: .whitespaces)
        t.note = note
        t.tags = tags
        t.verification = verification
        t.liabilityID = (isLoanPayment || isLoanDisbursement) && !liabilityID.isEmpty ? liabilityID : nil
        t.principalPaise = isLoanPayment ? (FinanceFormat.parsePaise(principalText) ?? max(0, amount - (FinanceFormat.parsePaise(interestText) ?? 0))) : nil
        t.interestPaise = isLoanPayment ? (FinanceFormat.parsePaise(interestText) ?? 0) : nil
        t.investmentID = isInvestmentPurchase && !investmentID.isEmpty ? investmentID : nil
        if isEditing {
            state.financeUpdateTransaction(t)
        } else {
            t.source = .manual
            state.financeAddTransaction(t)
        }
        dismiss()
    }

    private func keyValue(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top) {
            Text(k).font(.system(size: 10.5)).foregroundStyle(Palette.muted).frame(width: 120, alignment: .leading)
            Text(v).font(.system(size: 10.5, design: .monospaced)).textSelection(.enabled)
            Spacer()
        }
    }
}

// MARK: - Detail

struct FinTransactionDetailSheet: View {
    @EnvironmentObject var state: AppState
    let id: String
    @Environment(\.dismiss) private var dismiss
    @State private var edit = false
    @State private var confirmDelete = false

    private var txn: FinTransaction? { state.finance.transaction(id) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .semibold))
                        .frame(width: 32, height: 32)
                        .background(FinStyle.elevated, in: Circle())
                }
                .buttonStyle(.plain)
                Spacer()
                Text("Transaction").font(.system(size: 14, weight: .semibold))
                Spacer()
                if txn != nil {
                    Menu {
                        Button("Edit", systemImage: "pencil") { edit = true }
                        Button("Verify", systemImage: "checkmark.seal") {
                            guard let t = txn else { return }
                            state.financeBulkUpdate(ids: [t.id], verification: .verified, reason: "Verified from details")
                        }
                        Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = true }
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 12, weight: .semibold))
                            .frame(width: 32, height: 32)
                            .background(FinStyle.elevated, in: Circle())
                    }
                    .menuIndicator(.hidden)
                }
            }
            .padding(14)
            .background(Palette.surface)
            .overlay(alignment: .bottom) { Rectangle().fill(FinStyle.border).frame(height: 1) }

            if let t = txn {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                FinBadge(text: t.type.label, tint: typeTint(t))
                                FinBadge(text: t.verification.label,
                                         tint: t.verification.isTrusted ? Palette.green : Palette.orange)
                                if t.isDemo { FinBadge(text: "demo", tint: Palette.orange) }
                                if t.source == .imported { FinBadge(text: "imported", tint: Palette.blue) }
                            }
                            Text(t.title).font(.system(size: 22, weight: .bold))
                            Text(FinanceFormat.inr(t.signedPaise, showSign: true))
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .minimumScaleFactor(0.6)
                                .lineLimit(1)
                                .foregroundStyle(FinanceEngine.isIncome(t) ? Palette.green : Palette.text)
                            Text("\(FinanceFormat.date(t.date)) · \(state.finance.account(t.accountID)?.name ?? "—")")
                                .font(.system(size: 11)).foregroundStyle(Palette.muted)
                        }

                        FinCard {
                            FinCardHeader("Record", icon: "list.bullet.rectangle")
                            detailRow("Direction", t.direction.label)
                            detailRow("Amount", FinanceFormat.inr(t.amountPaise))
                            detailRow("Currency", t.currency)
                            detailRow("Account", state.finance.account(t.accountID)?.name ?? "—")
                            if let other = t.transferAccountID {
                                detailRow("Other side", state.finance.account(other)?.name ?? other)
                            }
                            detailRow("Category", state.finance.category(t.categoryID)?.displayName ?? "Uncategorised")
                            if let inv = t.investmentID, let i = state.finance.investment(inv) {
                                detailRow("Investment", i.name)
                            }
                            if let liab = t.liabilityID, let l = state.finance.liability(liab) {
                                detailRow("Liability", l.name)
                                if let p = t.principalPaise { detailRow("Principal", FinanceFormat.inr(p)) }
                                if let i = t.interestPaise { detailRow("Interest", FinanceFormat.inr(i)) }
                            }
                            if t.type == .investmentSale {
                                if let c = t.costBasisPaise { detailRow("Cost basis", FinanceFormat.inr(c)) }
                                if let g = t.realisedGainPaise { detailRow("Realised gain", FinanceFormat.inr(g, showSign: true)) }
                            }
                            detailRow("Payment method", t.paymentMethod.label)
                            if !t.merchant.isEmpty { detailRow("Payee", t.merchant) }
                            if !t.reference.isEmpty { detailRow("Reference", t.reference) }
                            if !t.note.isEmpty { detailRow("Note", t.note) }
                            if !t.tags.isEmpty { detailRow("Tags", t.tags.map { "#\($0)" }.joined(separator: " ")) }
                        }

                        FinCard {
                            FinCardHeader("Provenance", icon: "checkmark.shield")
                            detailRow("Source", t.source.label)
                            detailRow("Verification", t.verification.label)
                            detailRow("Created", t.createdAt)
                            detailRow("Updated", t.updatedAt)
                            if let s = t.statementID {
                                detailRow("Statement", state.finance.statements.first { $0.id == s }?.fileName ?? s)
                            }
                            if let b = t.importBatchID { detailRow("Import batch", b) }
                            if let tr = t.transferID { detailRow("Transfer ID", tr) }
                            if let l = t.linkedTransactionID { detailRow("Linked entry", l) }
                        }

                        if let tr = t.transferID, let record = state.finance.transfers.first(where: { $0.id == tr }) {
                            FinCard {
                                FinCardHeader("Linked transfer", icon: "arrow.left.arrow.right")
                                detailRow("From", state.finance.account(record.fromAccountID)?.name ?? "—")
                                detailRow("To", state.finance.account(record.toAccountID)?.name ?? "—")
                                detailRow("Amount", FinanceFormat.inr(record.amountPaise))
                                detailRow("Fee", FinanceFormat.inr(record.feePaise))
                                detailRow("Reconciled", record.reconciled ? "Yes" : "No")
                            }
                        }

                        let audit = state.finance.audit.filter { $0.entityID == t.id }.sorted { $0.at > $1.at }
                        FinCard {
                            FinCardHeader("Audit history", sub: "\(audit.count) entries · immutable", icon: "clock.arrow.circlepath")
                            if audit.isEmpty {
                                Text("No corrections. This record has not been changed since it was created.")
                                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
                            } else {
                                ForEach(audit) { a in
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack {
                                            Text(a.action.label).font(.system(size: 10.5, weight: .semibold))
                                            if let f = a.field { Text("· \(f)").font(.system(size: 10)).foregroundStyle(Palette.muted) }
                                            Spacer()
                                            Text(a.at).font(.system(size: 8.5, design: .monospaced)).foregroundStyle(Palette.faint)
                                        }
                                        if let o = a.oldValue, let n = a.newValue {
                                            Text("\(o) → \(n)").font(.system(size: 10)).foregroundStyle(Palette.muted)
                                        }
                                        if !a.reason.isEmpty {
                                            Text(a.reason).font(.system(size: 9.5)).foregroundStyle(Palette.faint)
                                        }
                                    }
                                    .padding(.vertical, 3)
                                }
                            }
                        }

                        HStack(spacing: 8) {
                            if t.transferID == nil && t.type != .investmentSale {
                                FinPrimaryButton(title: "Edit record", icon: "pencil") { edit = true }
                            } else if t.type == .investmentSale {
                                Text("A sale is managed from its investment holding so cost basis and realised gain stay consistent.")
                                    .font(.system(size: 10)).foregroundStyle(Palette.muted)
                            } else {
                                Text("This entry is one leg of a linked transfer. Edit it from Transfers so both sides stay in step.")
                                    .font(.system(size: 10)).foregroundStyle(Palette.muted)
                            }
                            Button { confirmDelete = true } label: {
                                Text("Delete").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.negative)
                                    .padding(.horizontal, 14).frame(height: 36)
                                    .background(Palette.negative.opacity(0.08), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(18)
                }
            } else {
                FinEmptyState(icon: "questionmark.folder", title: "Record not found",
                              detail: "It may have been deleted on another device.")
            }
        }
        .background(Palette.background)
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 640)
        #endif
        .sheet(isPresented: $edit) {
            if let t = txn { FinTransactionEditor(transaction: t).environmentObject(state) }
        }
        .confirmationDialog("Delete this transaction?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                state.financeDeleteTransaction(id, reason: "Deleted from transaction details")
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The audit log keeps what was deleted, its values and the reason.")
        }
    }

    private func typeTint(_ t: FinTransaction) -> Color {
        if FinanceEngine.isIncome(t) { return Palette.green }
        if t.type == .transfer { return Palette.blue }
        if t.type == .refund { return Palette.green }
        if t.type == .fee || t.type == .tax || t.type == .loanRepayment { return Palette.orange }
        return Palette.muted
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label).font(.system(size: 10.5)).foregroundStyle(Palette.muted).frame(width: 108, alignment: .leading)
            Text(value).font(.system(size: 11.5)).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Bulk edit

struct FinBulkEditSheet: View {
    @EnvironmentObject var state: AppState
    let ids: Set<String>
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var categoryID = ""
    @State private var tags = ""
    @State private var verification: FinVerification?

    var body: some View {
        VStack(spacing: 0) {
            FinSheetHeader(title: "Edit \(ids.count) records", sub: "Recorded as one audited bulk change",
                           saveTitle: "Apply") {
                let list = tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                state.financeBulkUpdate(ids: ids,
                                        categoryID: categoryID.isEmpty ? nil : categoryID,
                                        addTags: list,
                                        verification: verification,
                                        reason: "Bulk edit of \(ids.count) transactions")
                onDone(); dismiss()
            }
            VStack(alignment: .leading, spacing: 14) {
                FinPickerCard(label: "Category") {
                    Picker("Category", selection: $categoryID) {
                        Text("Leave unchanged").tag("")
                        ForEach(state.finance.categories.filter { !$0.archived && $0.kind == .expense }) { c in
                            Text(c.displayName).tag(c.id)
                        }
                    }
                    .labelsHidden().pickerStyle(.menu)
                }
                FinField(label: "Add tags", placeholder: "comma, separated", text: $tags)
                FinPickerCard(label: "Verification") {
                    Picker("Verification", selection: $verification) {
                        Text("Leave unchanged").tag(FinVerification?.none)
                        ForEach(FinVerification.allCases) { v in Text(v.label).tag(FinVerification?.some(v)) }
                    }
                    .labelsHidden().pickerStyle(.menu)
                }
                Text("Bulk edits never change amounts or dates. Any field you set is written to the audit log for every affected record.")
                    .font(.system(size: 10)).foregroundStyle(Palette.faint)
                Spacer()
            }
            .padding(18)
        }
        .background(Palette.background)
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 360)
        #endif
    }
}

// MARK: - Global search

struct FinGlobalSearch: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var detailID: String?

    private var q: String { query.trimmingCharacters(in: .whitespaces).lowercased() }
    private var transactions: [FinTransaction] {
        guard !q.isEmpty else { return [] }
        return state.finance.transactions.filter {
            [$0.merchant, $0.note, $0.reference, $0.tags.joined(separator: " ")].joined(separator: " ").lowercased().contains(q)
        }.sorted { $0.date > $1.date }.prefix(20).map { $0 }
    }
    private var accounts: [FinAccount] {
        guard !q.isEmpty else { return [] }
        return state.finance.accounts.filter {
            [$0.name, $0.institution, $0.type.label, $0.notes].joined(separator: " ").lowercased().contains(q)
        }
    }
    private var investments: [FinInvestment] {
        guard !q.isEmpty else { return [] }
        return state.finance.investments.filter {
            [$0.name, $0.institution, $0.assetClass.label].joined(separator: " ").lowercased().contains(q)
        }
    }
    private var goals: [FinGoal] {
        guard !q.isEmpty else { return [] }
        return state.finance.goals.filter { [$0.name, $0.note].joined(separator: " ").lowercased().contains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted)
                TextField("Search transactions, accounts, investments, goals…", text: $query)
                    .font(.system(size: 16))
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                Button { dismiss() } label: {
                    Text("Esc").font(.system(size: 9, weight: .bold)).foregroundStyle(Palette.faint)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(FinStyle.elevated, in: RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
            }
            .padding(18)
            .background(Palette.surface)
            .overlay(alignment: .bottom) { Rectangle().fill(FinStyle.border).frame(height: 1) }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if q.isEmpty {
                        FinEmptyState(icon: "magnifyingglass", title: "Search the whole ledger",
                                      detail: "Cmd+K opens this from anywhere in Finance. Results are reads; nothing changes until you open a record.")
                    } else {
                        if !transactions.isEmpty {
                            resultGroup("Transactions", "\(transactions.count)") {
                                ForEach(transactions) { t in
                                    Button { detailID = t.id } label: {
                                        HStack(spacing: 9) {
                                            Image(systemName: t.type.icon).font(.system(size: 10)).foregroundStyle(Palette.muted).frame(width: 16)
                                            VStack(alignment: .leading, spacing: 1) {
                                                Text(t.title).font(.system(size: 12, weight: .medium))
                                                Text("\(FinanceFormat.date(t.date)) · \(state.finance.account(t.accountID)?.name ?? "—")")
                                                    .font(.system(size: 9.5)).foregroundStyle(Palette.muted)
                                            }
                                            Spacer()
                                            FinMoneyText(paise: t.signedPaise, showSign: true, size: 11.5)
                                        }
                                        .contentShape(.rect)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        if !accounts.isEmpty {
                            resultGroup("Accounts", "\(accounts.count)") {
                                ForEach(accounts) { a in
                                    NavigationLink {
                                        FinAccountDetail(accountID: a.id)
                                    } label: {
                                        HStack {
                                            Image(systemName: a.type.icon).font(.system(size: 10)).foregroundStyle(Palette.muted).frame(width: 16)
                                            Text(a.name).font(.system(size: 12, weight: .medium))
                                            Spacer()
                                            Text(a.type.label).font(.system(size: 9.5)).foregroundStyle(Palette.muted)
                                        }
                                        .contentShape(.rect)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        if !investments.isEmpty {
                            resultGroup("Investments", "\(investments.count)") {
                                ForEach(investments) { inv in
                                    NavigationLink { FinInvestmentDetail(investmentID: inv.id) } label: {
                                        HStack {
                                            Image(systemName: inv.assetClass.icon).font(.system(size: 10)).foregroundStyle(Palette.muted).frame(width: 16)
                                            Text(inv.name).font(.system(size: 12, weight: .medium))
                                            Spacer()
                                            Text(inv.assetClass.shortLabel).font(.system(size: 9.5)).foregroundStyle(Palette.muted)
                                        }
                                        .contentShape(.rect)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        if !goals.isEmpty {
                            resultGroup("Goals", "\(goals.count)") {
                                ForEach(goals) { g in
                                    HStack {
                                        Image(systemName: g.kind.icon).font(.system(size: 10)).foregroundStyle(Palette.muted).frame(width: 16)
                                        Text(g.name).font(.system(size: 12, weight: .medium))
                                        Spacer()
                                        Text(FinanceFormat.inr(g.targetPaise)).font(.system(size: 10)).foregroundStyle(Palette.muted)
                                    }
                                }
                            }
                        }
                        if transactions.isEmpty && accounts.isEmpty && investments.isEmpty && goals.isEmpty {
                            FinEmptyState(icon: "questionmark.folder", title: "Nothing found",
                                          detail: "Try a payee, a note, a reference number or an account name.")
                        }
                    }
                }
                .padding(18)
            }
        }
        .background(Palette.background)
        #if os(macOS)
        .frame(minWidth: 620, minHeight: 560)
        #endif
        .sheet(item: Binding(get: { detailID.map(FinIDBox.init) }, set: { detailID = $0?.id })) { box in
            FinTransactionDetailSheet(id: box.id).environmentObject(state)
        }
    }

    private func resultGroup<C: View>(_ title: String, _ count: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Text(title.uppercased()).font(.system(size: 9, weight: .bold)).tracking(0.9).foregroundStyle(Palette.faint)
                Spacer(); Text(count).font(.system(size: 9)).foregroundStyle(Palette.faint) }
            content()
        }
        .padding(12)
        .background(FinStyle.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(FinStyle.border) }
    }
}
