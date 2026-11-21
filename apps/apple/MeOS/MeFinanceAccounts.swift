import SwiftUI
import Charts

// MARK: - Accounts

struct MeFinanceAccounts: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var signals = FinanceSignals.shared
    @State private var search = ""
    @State private var showArchived = false
    @State private var filterType: FinAccountType?
    @State private var adding = false
    @State private var editing: FinAccount?
    @State private var detailID: String?

    private var doc: FinanceDocument { state.finance }
    private var summaries: [FinAccountSummary] {
        let all = FinanceEngine.accountSummaries(doc)
        let q = search.lowercased()
        return all.filter { s in
            if !showArchived && s.account.status != .active { return false }
            if let filterType, s.account.type != filterType { return false }
            if q.isEmpty { return true }
            return [s.account.name, s.account.institution, s.account.type.label, s.account.notes]
                .joined(separator: " ").lowercased().contains(q)
        }
    }

    private var grouped: [(FinAccountType, [FinAccountSummary])] {
        let dict = Dictionary(grouping: summaries, by: \.account.type)
        return dict.keys.sorted { $0.label < $1.label }.map { ($0, dict[$0]!.sorted { $0.account.name < $1.account.name }) }
    }

    private var accountFilterMenu: some View {
        Menu {
            Button("All types") { filterType = nil }
            Divider()
            ForEach(FinAccountType.allCases) { t in
                Button { filterType = t } label: {
                    if filterType == t { Label(t.label, systemImage: "checkmark") } else { Text(t.label) }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "line.3.horizontal.decrease")
                Text(filterType?.label ?? "Type")
            }
            .font(.system(size: 11.5, weight: .semibold))
            .padding(.horizontal, 11).frame(height: 34)
            .background(FinStyle.elevated, in: Capsule())
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
    }

    private var archiveToggle: some View {
        Button { showArchived.toggle() } label: {
            Text(showArchived ? "Hide archived" : "Show archived")
                .font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.muted)
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        let assets = FinanceEngine.totalAssets(doc)
        let liabilities = FinanceEngine.totalLiabilities(doc)
        let cash = FinanceEngine.liquidAssets(doc)
        let deposits = doc.accounts.filter { $0.type.isDeposit }.reduce(Int64(0)) { $0 + FinanceEngine.accountBalance(doc, account: $1).paise }
        let hide = doc.settings.hideBalances

        FinPage(title: "Accounts",
                sub: "\(doc.accounts.filter { $0.status == .active }.count) open · account numbers are never stored",
                badge: doc.settings.demoMode ? "Demo data" : nil) {

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 175), spacing: 12)], spacing: 12) {
                FinStatTile(label: "Total assets", value: hide ? "₹ ••••" : FinanceFormat.inr(assets.paise), sub: assets.certainty.label, icon: "building.columns")
                FinStatTile(label: "Liabilities", value: hide ? "₹ ••••" : FinanceFormat.inr(liabilities), sub: "Credit cards & loans", icon: "creditcard")
                FinStatTile(label: "Liquid cash", value: hide ? "₹ ••••" : FinanceFormat.inr(cash), sub: "Cash-like accounts", icon: "banknote")
                FinStatTile(label: "Deposits", value: hide ? "₹ ••••" : FinanceFormat.inr(deposits), sub: "FD & RD balances", icon: "lock.square")
            }

            #if os(macOS)
            HStack(spacing: 8) {
                FinSearchBar(text: $search, placeholder: "Search accounts")
                accountFilterMenu
                archiveToggle
                Spacer()
                FinPrimaryButton(title: "Add account", icon: "plus") { adding = true }
            }
            #else
            VStack(alignment: .leading, spacing: 8) {
                FinSearchBar(text: $search, placeholder: "Search accounts")
                HStack(spacing: 8) {
                    accountFilterMenu
                    archiveToggle
                    Spacer()
                    FinPrimaryButton(title: "Add", icon: "plus") { adding = true }
                }
            }
            #endif

            if summaries.isEmpty {
                FinCard {
                    FinEmptyState(icon: "building.columns", title: "No accounts to show",
                                  detail: "An account is the container every transaction belongs to. Start with the bank account you actually use.") {
                        FinPrimaryButton(title: "Add account", icon: "plus") { adding = true }
                    }
                }
            } else {
                ForEach(grouped, id: \.0) { type, list in
                    VStack(alignment: .leading, spacing: 8) {
                        FinSectionTitle(text: type.label, detail: "\(list.count)")
                        VStack(spacing: 0) {
                            ForEach(Array(list.enumerated()), id: \.element.id) { index, s in
                                Button {
                                    detailID = s.id
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: s.account.type.icon)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(s.account.type.isLiability ? Palette.negative : Palette.muted)
                                            .frame(width: 30, height: 30)
                                            .background(FinStyle.elevated, in: RoundedRectangle(cornerRadius: 8))
                                        VStack(alignment: .leading, spacing: 2) {
                                            HStack(spacing: 6) {
                                                Text(s.account.name).font(.system(size: 13, weight: .semibold))
                                                if s.account.isDemo { FinBadge(text: "demo", tint: Palette.orange) }
                                                if s.account.status != .active { FinBadge(text: s.account.status.label, tint: Palette.muted) }
                                            }
                                            Text([s.account.institution, s.transactionCount == 1 ? "1 transaction" : "\(s.transactionCount) transactions", s.lastActivity.map { "last \(FinanceFormat.date($0))" }]
                                                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                                                .font(.system(size: 10)).foregroundStyle(Palette.muted).lineLimit(1)
                                        }
                                        Spacer(minLength: 6)
                                        VStack(alignment: .trailing, spacing: 2) {
                                            FinMoneyText(paise: hide ? 0 : s.balance.paise, size: 13)
                                            HStack(spacing: 3) {
                                                Image(systemName: s.balance.certainty.icon).font(.system(size: 7))
                                                Text(s.balance.certainty.label)
                                            }
                                            .font(.system(size: 8.5)).foregroundStyle(FinStyle.certaintyColor(s.balance.certainty))
                                        }
                                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(Palette.faint)
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 11)
                                    .contentShape(.rect)
                                }
                                .buttonStyle(.plain)
                                if index < list.count - 1 {
                                    Rectangle().fill(FinStyle.border).frame(height: 1).padding(.leading, 56)
                                }
                            }
                        }
                        .background(FinStyle.surface, in: RoundedRectangle(cornerRadius: FinStyle.radius))
                        .overlay { RoundedRectangle(cornerRadius: FinStyle.radius).strokeBorder(FinStyle.border) }
                    }
                }
            }

            FinCard {
                FinCardHeader("Privacy", icon: "lock.shield")
                Text("MeOS stores an account name, institution and type. It does not store card or bank account numbers, CVV, PINs or net-banking credentials.")
                    .font(.system(size: 10.5)).foregroundStyle(Palette.muted)
            }
        }
        .sheet(isPresented: $adding) {
            FinAccountEditor(account: nil).environmentObject(state)
        }
        .sheet(item: $editing) { a in
            FinAccountEditor(account: a).environmentObject(state)
        }
        .sheet(item: Binding(get: { detailID.map(FinIDBox.init) }, set: { detailID = $0?.id })) { box in
            NavigationStack { FinAccountDetail(accountID: box.id).environmentObject(state) }
                #if os(macOS)
                .frame(minWidth: 720, minHeight: 680)
                #endif
        }
        .onAppear { if signals.quickAddAccount { signals.quickAddAccount = false; adding = true } }
    }
}

// MARK: - Account editor

struct FinAccountEditor: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let account: FinAccount?

    @State private var name = ""
    @State private var institution = ""
    @State private var type: FinAccountType = .savings
    @State private var currency = FinanceSchema.currency
    @State private var openingDate = Date.now
    @State private var openingText = ""
    @State private var creditLimitText = ""
    @State private var status: FinAccountStatus = .active
    @State private var notes = ""
    @State private var hasStatement = false
    @State private var statementText = ""
    @State private var statementDate = Date.now

    private var isEditing: Bool { account != nil }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            FinSheetHeader(title: isEditing ? "Edit account" : "New account",
                           sub: isEditing ? "Changes are audited" : "No account numbers, ever",
                           canSave: canSave) { save() }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    FinCard {
                        FinCardHeader("Identity", icon: "building.columns")
                        FinField(label: "Account name", placeholder: "Everyday salary", text: $name)
                        FinField(label: "Institution", placeholder: "Bank, broker or wallet", text: $institution)
                        FinPickerCard(label: "Type") {
                            Picker("Type", selection: $type) {
                                ForEach(FinAccountType.allCases) { t in Text(t.label).tag(t) }
                            }
                            .labelsHidden().pickerStyle(.menu)
                        }
                        if type.isLiability {
                            Text("A credit card is a liability. Purchases increase debt; paying the bill is a transfer, not an expense.")
                                .font(.system(size: 9.5)).foregroundStyle(Palette.muted)
                        }
                    }
                    FinCard {
                        FinCardHeader("Opening position", icon: "calendar")
                        HStack(spacing: 10) {
                            FinField(label: type.isLiability ? "Amount owed (₹)" : "Opening balance (₹)",
                                     placeholder: "0", text: $openingText, keyboard: .decimalPad)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("OPENING DATE").font(.system(size: 9, weight: .bold)).tracking(0.8).foregroundStyle(Palette.faint)
                                DatePicker("", selection: $openingDate, displayedComponents: .date)
                                    .labelsHidden()
                                    .padding(.horizontal, 10).frame(height: 40)
                                    .background(FinStyle.elevated, in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                        if type == .creditCard {
                            FinField(label: "Credit limit (₹, optional)", placeholder: "200000", text: $creditLimitText, keyboard: .decimalPad)
                        }
                        Text("This is the anchor the ledger counts from. It is recorded as entered, not inferred.")
                            .font(.system(size: 9.5)).foregroundStyle(Palette.faint)
                    }
                    FinCard {
                        FinCardHeader("State", icon: "slider.horizontal.3")
                        FinPickerCard(label: "Status") {
                            Picker("Status", selection: $status) {
                                ForEach(FinAccountStatus.allCases) { s in Text(s.label).tag(s) }
                            }
                            .labelsHidden().pickerStyle(.menu)
                        }
                        FinField(label: "Notes", placeholder: "What this account is for", text: $notes, multiline: true)
                    }
                    FinCard {
                        FinCardHeader("Statement anchor (optional)", sub: "A verified closing balance", icon: "checkmark.seal")
                        FinToggleRow(label: "I have a statement balance", isOn: $hasStatement)
                        if hasStatement {
                            HStack(spacing: 10) {
                                FinField(label: "Closing balance (₹)", placeholder: "0", text: $statementText, keyboard: .decimalPad)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("AS OF").font(.system(size: 9, weight: .bold)).tracking(0.8).foregroundStyle(Palette.faint)
                                    DatePicker("", selection: $statementDate, displayedComponents: .date)
                                        .labelsHidden()
                                        .padding(.horizontal, 10).frame(height: 40)
                                        .background(FinStyle.elevated, in: RoundedRectangle(cornerRadius: 10))
                                }
                            }
                            Text("Transactions after this date are added on top. This is how a reconciled statement becomes the source of truth.")
                                .font(.system(size: 9.5)).foregroundStyle(Palette.faint)
                        }
                    }
                    if let a = account {
                        FinCard {
                            FinCardHeader("History", icon: "clock")
                            Text("Created \(a.createdAt)").font(.system(size: 10)).foregroundStyle(Palette.muted)
                            Text("Updated \(a.updatedAt)").font(.system(size: 10)).foregroundStyle(Palette.muted)
                        }
                    }
                }
                .padding(18)
            }
        }
        .background(Palette.background)
        #if os(macOS)
        .frame(minWidth: 540, minHeight: 640)
        #endif
        .onAppear(perform: load)
    }

    private func load() {
        guard let a = account else { return }
        name = a.name
        institution = a.institution
        type = a.type
        currency = a.currency
        openingDate = FinanceCal.date(a.openingDate) ?? .now
        openingText = String(format: "%.2f", Double(a.openingBalancePaise) / 100)
        creditLimitText = a.creditLimitPaise.map { String(format: "%.2f", Double($0) / 100) } ?? ""
        status = a.status
        notes = a.notes
        if let b = a.statementBalancePaise, let d = a.statementBalanceOn {
            hasStatement = true
            statementText = String(format: "%.2f", Double(b) / 100)
            statementDate = FinanceCal.date(d) ?? .now
        }
    }

    private func save() {
        let opening = FinanceFormat.parsePaise(openingText) ?? 0
        let limit = FinanceFormat.parsePaise(creditLimitText)
        var next = account ?? FinAccount(name: name, institution: institution, type: type)
        next.name = name.trimmingCharacters(in: .whitespaces)
        next.institution = institution.trimmingCharacters(in: .whitespaces)
        next.type = type
        next.currency = currency
        next.openingDate = FinanceCal.key(openingDate)
        next.openingBalancePaise = opening
        next.creditLimitPaise = type == .creditCard ? limit : nil
        next.status = status
        next.notes = notes
        if hasStatement, let value = FinanceFormat.parsePaise(statementText) {
            next.statementBalancePaise = value
            next.statementBalanceOn = FinanceCal.key(statementDate)
            next.statementBalanceSource = .verified
        } else {
            next.statementBalancePaise = nil
            next.statementBalanceOn = nil
        }
        if isEditing {
            state.financeUpdateAccount(next)
        } else {
            state.financeAddAccount(next)
        }
        dismiss()
    }
}

// MARK: - Account detail

struct FinAccountDetail: View {
    @EnvironmentObject var state: AppState
    let accountID: String
    @State private var edit = false
    @State private var reconcile = false
    @State private var showAllTransactions = false
    @State private var detailID: String?
    @State private var confirmArchive = false

    private var doc: FinanceDocument { state.finance }
    private var account: FinAccount? { doc.account(accountID) }

    var body: some View {
        if let account {
            let balance = FinanceEngine.accountBalance(doc, account: account)
            let txns = FinanceEngine.accountTransactions(doc, accountID: accountID)
            let recent = Array(txns.prefix(showAllTransactions ? 200 : 30))
            let totalIn = txns.filter { $0.direction == .inflow && $0.accountID == accountID }.reduce(Int64(0)) { $0 + $1.amountPaise }
            let totalOut = txns.filter { $0.direction == .outflow && $0.accountID == accountID }.reduce(Int64(0)) { $0 + $1.amountPaise }
            let history = balanceHistory(account)
            let statements = doc.statements.filter { $0.accountID == accountID }
            let reconciliations = doc.reconciliations.filter { $0.accountID == accountID }.sorted { $0.periodEnd > $1.periodEnd }
            let hide = doc.settings.hideBalances

            FinPage(title: account.name,
                    sub: [account.institution, account.type.label, account.status.label].filter { !$0.isEmpty }.joined(separator: " · "),
                    badge: account.isDemo ? "Demo data" : nil) {

                FinCard {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(account.type.isLiability ? "OUTSTANDING" : "BALANCE")
                                .font(.system(size: 9, weight: .bold)).tracking(0.9).foregroundStyle(Palette.faint)
                            Text(hide ? "₹ ••••••" : FinanceFormat.inr(account.type.isLiability ? abs(balance.paise) : balance.paise,
                                                                       showSign: !account.type.isLiability))
                                .font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit()
                                .foregroundStyle(balance.paise < 0 ? Palette.negative : FinStyle.moneyColor(balance.paise))
                            HStack(spacing: 5) {
                                FinBadge(text: balance.certainty.label, tint: FinStyle.certaintyColor(balance.certainty), icon: balance.certainty.icon)
                                Text("as of \(FinanceFormat.date(FinanceCal.today()))")
                                    .font(.system(size: 9.5)).foregroundStyle(Palette.faint)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 8) {
                            if let available = available(account) {
                                VStack(alignment: .trailing, spacing: 1) {
                                    Text("AVAILABLE").font(.system(size: 8, weight: .bold)).tracking(0.8).foregroundStyle(Palette.faint)
                                    Text(FinanceFormat.inr(available)).font(.system(size: 15, weight: .semibold, design: .rounded)).monospacedDigit()
                                }
                            }
                            #if os(macOS)
                            HStack(spacing: 6) {
                                FinPrimaryButton(title: "Edit", icon: "pencil") { edit = true }
                                FinPrimaryButton(title: "Reconcile", icon: "checkmark.seal") { reconcile = true }
                            }
                            #endif
                        }
                    }
                    #if os(iOS)
                    HStack(spacing: 8) {
                        FinPrimaryButton(title: "Edit account", icon: "pencil") { edit = true }
                        FinPrimaryButton(title: "Reconcile", icon: "checkmark.seal") { reconcile = true }
                        Spacer()
                    }
                    #endif
                    HStack(spacing: 18) {
                        mini("Inflow", FinanceFormat.inr(totalIn), Palette.green)
                        mini("Outflow", FinanceFormat.inr(totalOut), Palette.negative)
                        mini("Transactions", "\(txns.count)", Palette.muted)
                        Spacer()
                        Text(account.lastReconciledOn.map { "Last reconciled \(FinanceFormat.date($0))" } ?? "Never reconciled")
                            .font(.system(size: 9.5)).foregroundStyle(Palette.faint)
                    }
                }

                FinCard {
                    FinCardHeader("Balance history", sub: "Calculated from the opening position and every recorded movement", icon: "chart.xyaxis.line")
                    if history.count < 2 {
                        Text("Not enough dated records yet.").font(.system(size: 11)).foregroundStyle(Palette.muted)
                    } else {
                        Chart(Array(history.enumerated()), id: \.offset) { i, v in
                            AreaMark(x: .value("i", i), y: .value("Balance", Double(v) / 100))
                                .foregroundStyle(LinearGradient(colors: [Palette.green.opacity(0.16), Color.clear],
                                                                startPoint: .top, endPoint: .bottom))
                            LineMark(x: .value("i", i), y: .value("Balance", Double(v) / 100))
                                .foregroundStyle(Palette.green)
                                .lineStyle(StrokeStyle(lineWidth: 2))
                        }
                        .chartXAxis(.hidden)
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
                        .frame(height: 150)
                        HStack {
                            Text(monthLabels(account).first ?? "").font(.system(size: 9)).foregroundStyle(Palette.faint)
                            Spacer()
                            Text(monthLabels(account).last ?? "").font(.system(size: 9)).foregroundStyle(Palette.faint)
                        }
                    }
                }

                FinCard {
                    FinCardHeader("Monthly flow", sub: "Last 12 months", icon: "chart.bar")
                    FinAccountFlowChart(doc: doc, accountID: accountID)
                        .frame(height: 150)
                }

                FinSectionTitle(text: "Transactions", detail: "\(txns.count)")
                FinCard(padding: 0) {
                    if recent.isEmpty {
                        FinEmptyState(icon: "list.bullet.rectangle", title: "No transactions",
                                      detail: "This account has an opening position but no recorded movements.")
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(recent.enumerated()), id: \.element.id) { index, t in
                                Button { detailID = t.id } label: {
                                    HStack(spacing: 9) {
                                        Image(systemName: t.type.icon).font(.system(size: 9, weight: .semibold))
                                            .foregroundStyle(Palette.muted).frame(width: 16)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(t.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                            Text("\(FinanceFormat.date(t.date)) · \(doc.category(t.categoryID)?.name ?? t.type.label)")
                                                .font(.system(size: 9.5)).foregroundStyle(Palette.muted).lineLimit(1)
                                        }
                                        Spacer()
                                        FinMoneyText(paise: t.direction == .inflow ? t.amountPaise : -t.amountPaise, showSign: true, size: 11.5)
                                    }
                                    .padding(.horizontal, 12).padding(.vertical, 9)
                                    .contentShape(.rect)
                                }
                                .buttonStyle(.plain)
                                if index < recent.count - 1 {
                                    Rectangle().fill(FinStyle.border).frame(height: 1).padding(.leading, 37)
                                }
                            }
                        }
                    }
                    if txns.count > recent.count {
                        Button { showAllTransactions = true } label: {
                            Text("Show more").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.green)
                                .frame(maxWidth: .infinity).frame(height: 34)
                        }
                        .buttonStyle(.plain)
                    }
                }

                #if os(macOS)
                HStack(alignment: .top, spacing: 12) {
                    statementsCard(statements).frame(maxWidth: .infinity)
                    reconciliationCard(reconciliations).frame(maxWidth: .infinity)
                }
                #else
                statementsCard(statements)
                reconciliationCard(reconciliations)
                #endif

                HStack(spacing: 8) {
                    if account.status == .active {
                        Button { confirmArchive = true } label: {
                            Text("Archive account").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Palette.muted)
                                .padding(.horizontal, 14).frame(height: 34)
                                .background(FinStyle.elevated, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        Button { state.financeSetAccountStatus(accountID, status: .closed) } label: {
                            Text("Close account").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Palette.negative)
                                .padding(.horizontal, 14).frame(height: 34)
                                .background(Palette.negative.opacity(0.08), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    } else if account.status == .archived {
                        Button { state.financeSetAccountStatus(accountID, status: .active) } label: {
                            Text("Restore account").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Palette.green)
                                .padding(.horizontal, 14).frame(height: 34)
                                .background(FinStyle.elevated, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    } else if account.status == .closed {
                        Button { state.financeSetAccountStatus(accountID, status: .active) } label: {
                            Text("Reopen account").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Palette.green)
                                .padding(.horizontal, 14).frame(height: 34)
                                .background(FinStyle.elevated, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    if txns.isEmpty {
                        Button {
                            state.financeDeleteAccount(accountID)
                        } label: {
                            Text("Delete empty account").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Palette.negative)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
            }
            .sheet(isPresented: $edit) { FinAccountEditor(account: account).environmentObject(state) }
            .sheet(isPresented: $reconcile) { FinReconcileSheet(accountID: accountID).environmentObject(state) }
            .sheet(item: Binding(get: { detailID.map(FinIDBox.init) }, set: { detailID = $0?.id })) { box in
                FinTransactionDetailSheet(id: box.id).environmentObject(state)
            }
            .confirmationDialog("Archive \(account.name)?", isPresented: $confirmArchive, titleVisibility: .visible) {
                Button("Archive", role: .destructive) { state.financeSetAccountStatus(accountID, status: .archived) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The history is kept. Archived accounts stop appearing in the active list but still contribute to net worth until closed.")
            }
        } else {
            FinPage(title: "Account") {
                FinEmptyState(icon: "questionmark.folder", title: "Account not found",
                              detail: "It may have been removed on another device.")
            }
        }
    }

    private func mini(_ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased()).font(.system(size: 8, weight: .bold)).tracking(0.6).foregroundStyle(Palette.faint)
            Text(value).font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(tint)
        }
    }

    private func available(_ account: FinAccount) -> Int64? {
        guard let limit = account.creditLimitPaise else { return nil }
        let balance = FinanceEngine.accountBalance(doc, account: account)
        return max(0, limit - max(0, -balance.paise))
    }

    private func balanceHistory(_ account: FinAccount) -> [Int64] {
        let start = max(account.openingDate, FinanceCal.addMonths(-18, to: FinanceCal.today()))
        let ends = FinanceCal.months(from: start, through: FinanceCal.today()).map { FinanceCal.monthEnd($0) }
        return ends.map { FinanceEngine.accountBalance(doc, account: account, asOf: $0).paise }
    }

    private func monthLabels(_ account: FinAccount) -> [String] {
        let start = max(account.openingDate, FinanceCal.addMonths(-18, to: FinanceCal.today()))
        return FinanceCal.months(from: start, through: FinanceCal.today()).map { FinanceCal.monthLabel(FinanceCal.monthEnd($0)) }
    }

    private func statementsCard(_ statements: [FinStatement]) -> some View {
        FinCard {
            FinCardHeader("Statements", sub: "\(statements.count)", icon: "doc.text")
            if statements.isEmpty {
                Text("No statement recorded for this account.").font(.system(size: 11)).foregroundStyle(Palette.muted)
            } else {
                ForEach(statements) { s in
                    HStack(spacing: 8) {
                        Image(systemName: s.fileType.lowercased().contains("pdf") ? "doc.richtext" : "doc.text").font(.system(size: 10)).foregroundStyle(Palette.muted)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(s.fileName).font(.system(size: 11, weight: .medium)).lineLimit(1)
                            Text("\(s.status.label) · \(s.fileSize.formatted()) bytes").font(.system(size: 9)).foregroundStyle(Palette.faint)
                        }
                        Spacer()
                        FinBadge(text: s.status.label, tint: s.status == .parsed ? Palette.green : Palette.orange)
                    }
                }
            }
        }
    }

    private func reconciliationCard(_ reconciliations: [FinReconciliation]) -> some View {
        FinCard {
            FinCardHeader("Reconciliation", sub: "\(reconciliations.count) periods", icon: "checkmark.shield")
            if reconciliations.isEmpty {
                Text("Not reconciled. Add a statement closing balance to prove the ledger against the bank.")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
            } else {
                ForEach(reconciliations.prefix(6)) { r in
                    HStack(spacing: 8) {
                        Image(systemName: r.status == .matched ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(r.status == .matched ? Palette.green : Palette.orange)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(FinanceFormat.date(r.periodStart)) – \(FinanceFormat.date(r.periodEnd))")
                                .font(.system(size: 10.5, weight: .medium))
                            Text("Counted \(FinanceFormat.inr(r.computedClosingPaise)) · statement \(FinanceFormat.inr(r.closingPaise))")
                                .font(.system(size: 9)).foregroundStyle(Palette.faint)
                        }
                        Spacer()
                        FinBadge(text: r.status.label, tint: r.status == .matched ? Palette.green : Palette.orange)
                    }
                }
            }
        }
    }
}

struct FinAccountFlowChart: View {
    let doc: FinanceDocument
    let accountID: String

    var body: some View {
        let ends = FinanceCal.monthsBack(12)
        let points: [(String, Int64, Int64)] = ends.map { end in
            let t = FinanceEngine.totals(doc, from: FinanceCal.monthStart(end), through: FinanceCal.monthEnd(end), accountID: accountID)
            return (FinanceCal.shortMonth(end), t.incomePaise + t.refundPaise + t.transferPaise, t.expensePaise + t.investmentPaise)
        }
        if points.allSatisfy({ $0.1 == 0 && $0.2 == 0 }) {
            Text("No flows recorded.").font(.system(size: 11)).foregroundStyle(Palette.muted)
                .frame(maxWidth: .infinity, minHeight: 120)
        } else {
            Chart {
                ForEach(Array(points.enumerated()), id: \.offset) { _, p in
                    BarMark(x: .value("Month", p.0), y: .value("In", Double(p.1) / 100))
                        .foregroundStyle(Palette.green).cornerRadius(2)
                    BarMark(x: .value("Month", p.0), y: .value("Out", -Double(p.2) / 100))
                        .foregroundStyle(Palette.orange).cornerRadius(2)
                }
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
        }
    }
}

// MARK: - Reconciliation

struct FinReconcileSheet: View {
    @EnvironmentObject var state: AppState
    let accountID: String
    @Environment(\.dismiss) private var dismiss
    @State private var periodEnd = Date.now
    @State private var periodStart = FinanceCal.date(FinanceCal.monthStart(FinanceCal.today())) ?? .now
    @State private var closingText = ""
    @State private var openingText = ""
    @State private var note = ""
    @State private var statementID = ""
    @State private var result: FinReconciliation?

    private var account: FinAccount? { state.finance.account(accountID) }
    private var computed: Int64 {
        guard let account else { return 0 }
        let opening = FinanceFormat.parsePaise(openingText)
            ?? FinanceEngine.statementBalance(state.finance, account: account,
                                              asOf: FinanceCal.addDays(-1, to: FinanceCal.key(periodStart)))
        return FinanceEngine.statementClosing(state.finance, account: account,
                                              periodStart: FinanceCal.key(periodStart),
                                              periodEnd: FinanceCal.key(periodEnd),
                                              openingPaise: opening)
    }
    private var closing: Int64 { FinanceFormat.parsePaise(closingText) ?? 0 }
    private var matches: Bool { computed == closing }

    var body: some View {
        VStack(spacing: 0) {
            FinSheetHeader(title: "Reconcile account", sub: account?.name, saveTitle: "Record", canSave: !closingText.isEmpty) {
                let r = state.financeAddReconciliation(accountID: accountID,
                                                       periodStart: FinanceCal.key(periodStart),
                                                       periodEnd: FinanceCal.key(periodEnd),
                                                       closingPaise: closing,
                                                       statementID: statementID.isEmpty ? nil : statementID,
                                                       openingPaise: FinanceFormat.parsePaise(openingText),
                                                       note: note)
                result = r
                if r?.status == .matched { dismiss() }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    FinCard {
                        FinCardHeader("Statement closing", sub: "The bank's number, not ours", icon: "building.columns")
                        HStack(spacing: 10) {
                            FinField(label: "Opening balance (₹)", placeholder: "From the statement", text: $openingText, keyboard: .decimalPad)
                            FinField(label: "Closing balance (₹)", placeholder: "0", text: $closingText, keyboard: .decimalPad)
                        }
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("PERIOD START").font(.system(size: 9, weight: .bold)).tracking(0.8).foregroundStyle(Palette.faint)
                                DatePicker("", selection: $periodStart, displayedComponents: .date)
                                    .labelsHidden().padding(.horizontal, 10).frame(height: 40)
                                    .background(FinStyle.elevated, in: RoundedRectangle(cornerRadius: 10))
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                Text("PERIOD END").font(.system(size: 9, weight: .bold)).tracking(0.8).foregroundStyle(Palette.faint)
                                DatePicker("", selection: $periodEnd, displayedComponents: .date)
                                    .labelsHidden().padding(.horizontal, 10).frame(height: 40)
                                    .background(FinStyle.elevated, in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                        if let account, !state.finance.statements.filter({ $0.accountID == accountID }).isEmpty {
                            FinPickerCard(label: "Statement (optional)") {
                                Picker("Statement", selection: $statementID) {
                                    Text("None").tag("")
                                    ForEach(state.finance.statements.filter { $0.accountID == accountID }) { s in
                                        Text(s.fileName).tag(s.id)
                                    }
                                }
                                .labelsHidden().pickerStyle(.menu)
                            }
                        }
                        FinField(label: "Note", placeholder: "Why this period", text: $note)
                    }
                    FinCard {
                        FinCardHeader("What the ledger says", icon: "function")
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("CALCULATED CLOSING").font(.system(size: 8.5, weight: .bold)).tracking(0.7).foregroundStyle(Palette.faint)
                                Text(FinanceFormat.inr(computed)).font(.system(size: 20, weight: .bold, design: .rounded)).monospacedDigit()
                            }
                            Spacer()
                            Image(systemName: closingText.isEmpty ? "minus" : matches ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(closingText.isEmpty ? Palette.faint : matches ? Palette.green : Palette.orange)
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("DIFFERENCE").font(.system(size: 8.5, weight: .bold)).tracking(0.7).foregroundStyle(Palette.faint)
                                Text(closingText.isEmpty ? "—" : FinanceFormat.inr(closing - computed, showSign: true))
                                    .font(.system(size: 20, weight: .bold, design: .rounded)).monospacedDigit()
                                    .foregroundStyle(closingText.isEmpty ? Palette.muted : matches ? Palette.green : Palette.orange)
                            }
                        }
                    }
                    if let result {
                        FinCard {
                            HStack(spacing: 8) {
                                Image(systemName: result.status == .matched ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                                    .foregroundStyle(result.status == .matched ? Palette.green : Palette.orange)
                                Text(result.status == .matched
                                     ? "Matched. The account anchor now uses the statement balance."
                                     : "Mismatch. The reconciliation is recorded for review; net worth keeps using the calculated balance.")
                                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
                            }
                        }
                    }
                    Text("Reconciliation never overwrites a transaction. A mismatch becomes an open item in Audit & Reconciliation.")
                        .font(.system(size: 9.5)).foregroundStyle(Palette.faint)
                }
                .padding(18)
            }
        }
        .background(Palette.background)
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 480)
        #endif
        .onAppear {
            if let account {
                openingText = String(format: "%.2f", Double(account.anchorBalancePaise) / 100)
            }
        }
    }
}
