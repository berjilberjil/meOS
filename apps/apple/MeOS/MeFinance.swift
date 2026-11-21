import SwiftUI

// MARK: - Finance destinations

enum FinDestination: String, CaseIterable, Identifiable, Hashable {
    case overview, transactions, accounts, income, expenses, transfers
    case budgets, investments, liabilities, netWorth, timeline, goals
    case recurring, statements, reports, tax, audit, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .transactions: "Transactions"
        case .accounts: "Accounts"
        case .income: "Income"
        case .expenses: "Expenses"
        case .transfers: "Transfers"
        case .budgets: "Budgets"
        case .investments: "Investments"
        case .liabilities: "Liabilities"
        case .netWorth: "Net Worth"
        case .timeline: "Financial Timeline"
        case .goals: "Goals"
        case .recurring: "Recurring Payments"
        case .statements: "Statements & Imports"
        case .reports: "Reports"
        case .tax: "Tax Centre"
        case .audit: "Audit & Reconciliation"
        case .settings: "Finance Settings"
        }
    }

    var icon: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .transactions: "list.bullet.rectangle"
        case .accounts: "building.columns"
        case .income: "arrow.down.left"
        case .expenses: "arrow.up.right"
        case .transfers: "arrow.left.arrow.right"
        case .budgets: "chart.pie"
        case .investments: "chart.line.uptrend.xyaxis"
        case .liabilities: "creditcard"
        case .netWorth: "chart.xyaxis.line"
        case .timeline: "clock.arrow.circlepath"
        case .goals: "target"
        case .recurring: "repeat"
        case .statements: "doc.badge.arrow.up"
        case .reports: "doc.text.magnifyingglass"
        case .tax: "percent"
        case .audit: "checkmark.shield"
        case .settings: "slider.horizontal.3"
        }
    }

    var group: String {
        switch self {
        case .overview: "Command centre"
        case .transactions, .accounts, .income, .expenses, .transfers: "Money in motion"
        case .budgets, .goals, .recurring: "Planning"
        case .investments, .liabilities, .netWorth, .timeline: "Wealth"
        case .statements, .reports, .tax, .audit: "Records"
        case .settings: "System"
        }
    }

    var subtitle: String {
        switch self {
        case .overview: "Your complete financial position"
        case .transactions: "Everything that moved, in one ledger"
        case .accounts: "Where the money sits"
        case .income: "Every rupee that came in"
        case .expenses: "Every rupee that went out"
        case .transfers: "Movement between your own accounts"
        case .budgets: "Planned versus actual"
        case .investments: "Capital, value and return"
        case .liabilities: "Debt, repayments and tenure"
        case .netWorth: "Assets minus liabilities over time"
        case .timeline: "The financial life, reconstructed"
        case .goals: "What the money is for"
        case .recurring: "Commitments that repeat"
        case .statements: "The import pipeline, ready for statements"
        case .reports: "Answer a specific money question"
        case .tax: "Indian tax-year records, no guesses"
        case .audit: "Every correction, and every mismatch"
        case .settings: "Preferences, taxonomy and demo data"
        }
    }

    static let groups: [(String, [FinDestination])] = [
        ("Command centre", [.overview]),
        ("Money in motion", [.transactions, .accounts, .income, .expenses, .transfers]),
        ("Planning", [.budgets, .goals, .recurring]),
        ("Wealth", [.investments, .liabilities, .netWorth, .timeline]),
        ("Records", [.statements, .reports, .tax, .audit]),
        ("System", [.settings]),
    ]
}

// MARK: - Shared UI signals

@MainActor
final class FinanceSignals: ObservableObject {
    static let shared = FinanceSignals()
    @Published var newTransaction = false
    @Published var search = false
    @Published var ask = false
    @Published var openTransactionID: String?
    @Published var navigate: FinDestination?
    @Published var quickAddAccount = false
    @Published var quickAddInvestment = false
}

struct FinIDBox: Identifiable {
    let id: String
}

// MARK: - Finance root

struct MeFinance: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var signals = FinanceSignals.shared
    @State private var selection: FinDestination = .overview
    @State private var destinationsOpen = false

    var body: some View {
        Group {
            #if os(macOS)
            HStack(spacing: 0) {
                sidebar
                    .frame(width: 206)
                Rectangle().fill(FinStyle.border).frame(width: 1).ignoresSafeArea()
                content
            }
            #else
            content
            #endif
        }
        .background(Palette.background)
        .toolbar {
            #if os(iOS)
            ToolbarItemGroup(placement: .primaryAction) {
                Button { signals.search = true } label: { Image(systemName: "magnifyingglass") }
                    .accessibilityLabel("Search finance")
                Button { signals.newTransaction = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("New transaction")
                Button { destinationsOpen = true } label: { Image(systemName: "square.grid.2x2") }
                    .accessibilityLabel("All finance screens")
            }
            #endif
        }
        .meActions {
            #if os(macOS)
            Button { signals.search = true } label: { Image(systemName: "magnifyingglass") }
                .help("Search finance  ⌘K")
                .accessibilityLabel("Search finance")
            Button { signals.newTransaction = true } label: { Image(systemName: "plus") }
                .help("New transaction  ⌘N")
                .accessibilityLabel("New transaction")
            Button { destinationsOpen = true } label: { Image(systemName: "square.grid.2x2") }
                .help("All finance screens")
                .accessibilityLabel("All finance screens")
            #endif
        }
        .task {
            state.financePrepare()
            if selection == .overview, signals.navigate != nil {
                selection = signals.navigate ?? .overview
                signals.navigate = nil
            }
        }
        .onChange(of: signals.navigate) { _, dest in
            guard let dest else { return }
            selection = dest
            signals.navigate = nil
        }
        .sheet(isPresented: $signals.newTransaction) {
            FinTransactionEditor(transaction: nil)
                .environmentObject(state)
        }
        .sheet(isPresented: $signals.quickAddAccount) {
            FinAccountEditor(account: nil)
                .environmentObject(state)
        }
        .sheet(isPresented: $signals.quickAddInvestment) {
            FinInvestmentEditor(investment: nil)
                .environmentObject(state)
        }
        .sheet(isPresented: $signals.search) {
            NavigationStack {
                FinGlobalSearch()
                    .environmentObject(state)
            }
            #if os(macOS)
            .frame(minWidth: 640, minHeight: 580)
            #endif
        }
        .sheet(isPresented: $signals.ask) {
            NavigationStack {
                MeAssistant()
                    .environmentObject(state)
            }
            #if os(macOS)
            .frame(minWidth: 760, minHeight: 640)
            #endif
        }
        .sheet(item: Binding(get: { signals.openTransactionID.map(FinIDBox.init) },
                             set: { signals.openTransactionID = $0?.id })) { box in
            FinTransactionDetailSheet(id: box.id)
                .environmentObject(state)
        }
        .sheet(isPresented: $destinationsOpen) {
            FinDestinationSheet(selection: $selection) { dest in
                selection = dest
                destinationsOpen = false
            }
            .environmentObject(state)
        }
        .background {
            // Invisible command buttons: the shortcuts only exist while Finance
            // is on screen, and never collide with a text field's own editing keys.
            VStack {
                Button("Search finance") { signals.search = true }
                    .keyboardShortcut("k", modifiers: .command)
                Button("New transaction") { signals.newTransaction = true }
                    .keyboardShortcut("n", modifiers: .command)
                Button("Ask about money") { signals.ask = true }
                    .keyboardShortcut("j", modifiers: [.command, .shift])
            }
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder private var content: some View {
        #if os(macOS)
        FinDestinationScreen(destination: selection, selection: $selection)
            .frame(maxWidth: .infinity)
            .id(selection)
        #else
        FinDestinationScreen(destination: .overview, selection: $selection)
            .navigationDestination(for: FinDestination.self) { dest in
                FinDestinationScreen(destination: dest, selection: $selection)
            }
        #endif
    }

    #if os(macOS)
    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 7) {
                        Image(systemName: "indianrupeesign.circle.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Palette.green)
                        Text("FINANCE")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1.2)
                            .foregroundStyle(Palette.muted)
                        Spacer()
                        if state.finance.settings.demoMode {
                            FinBadge(text: "demo", tint: Palette.orange)
                        }
                    }
                    let nw = FinanceEngine.netWorth(state.finance)
                    Group {
                        if state.finance.settings.hideBalances {
                            Text("₹ ••••••")
                        } else {
                            Text(FinanceFormat.inr(nw.paise))
                        }
                    }
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(FinStyle.moneyColor(nw.paise))
                    Text("net worth · \(nw.certainty.label.lowercased())")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(Palette.faint)
                }
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 16)

                ForEach(FinDestination.groups, id: \.0) { group in
                    Text(group.0.uppercased())
                        .font(.system(size: 8.5, weight: .bold))
                        .tracking(1.0)
                        .foregroundStyle(Palette.faint)
                        .padding(.horizontal, 10)
                        .padding(.top, 12)
                        .padding(.bottom, 4)
                    ForEach(group.1) { dest in
                        sidebarRow(dest)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(Palette.surface)
    }

    private func sidebarRow(_ dest: FinDestination) -> some View {
        let on = selection == dest
        return Button {
            withAnimation(DS.spring) { selection = dest }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: dest.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 18)
                    .foregroundStyle(on ? Palette.background : (dest == .audit ? Palette.orange : Palette.muted))
                Text(dest.title)
                    .font(.system(size: 12.5, weight: on ? .semibold : .medium))
                    .lineLimit(1)
                Spacer(minLength: 2)
                if dest == .audit {
                    let count = FinanceEngine.integrityIssues(state.finance).filter { $0.severity > 0 }.count
                    if count > 0 {
                        Text("\(count)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(on ? Palette.background : Palette.orange)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(on ? Palette.background.opacity(0.15) : Palette.orange.opacity(0.12), in: Capsule())
                    }
                }
            }
            .foregroundStyle(on ? Palette.background : Palette.text)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(on ? Palette.text : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(FinSidebarStyle())
    }
    #endif
}

private struct FinSidebarStyle: ButtonStyle {
    @State private var hover = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.white.opacity(hover ? 0.04 : 0), in: RoundedRectangle(cornerRadius: 8))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .onHover { h in withAnimation(.easeOut(duration: 0.1)) { hover = h } }
    }
}

/// Routes one finance screen. On iPhone only the overview is hosted here;
/// everything else arrives through the same view via NavigationLink.
struct FinDestinationScreen: View {
    @EnvironmentObject var state: AppState
    let destination: FinDestination
    @Binding var selection: FinDestination

    var body: some View {
        switch destination {
        case .overview:     MeFinanceOverview(selection: $selection)
        case .transactions: MeFinanceTransactions()
        case .accounts:     MeFinanceAccounts()
        case .income:       MeFinanceFlow(kind: .income, selection: $selection)
        case .expenses:     MeFinanceFlow(kind: .expense, selection: $selection)
        case .transfers:    MeFinanceTransfers()
        case .budgets:      MeFinanceBudgets()
        case .investments:  MeFinanceInvestments()
        case .liabilities:  MeFinanceLiabilities()
        case .netWorth:     MeFinanceNetWorth()
        case .timeline:     MeFinanceTimeline()
        case .goals:        MeFinanceGoals()
        case .recurring:    MeFinanceRecurring()
        case .statements:   MeFinanceStatements()
        case .reports:      MeFinanceReports()
        case .tax:          MeFinanceTax()
        case .audit:        MeFinanceAudit(selection: $selection)
        case .settings:     MeFinanceSettings()
        }
    }
}

struct FinDestinationSheet: View {
    @Binding var selection: FinDestination
    let choose: (FinDestination) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(FinDestination.groups, id: \.0) { group in
                    Section(group.0) {
                        ForEach(group.1) { dest in
                            #if os(iOS)
                            NavigationLink {
                                FinDestinationScreen(destination: dest, selection: $selection)
                            } label: {
                                row(dest)
                            }
                            #else
                            Button { choose(dest) } label: { row(dest) }
                                .buttonStyle(.plain)
                            #endif
                        }
                    }
                }
            }
            .navigationTitle("Finance")
            .navigationDestination(for: FinDestination.self) { dest in
                FinDestinationScreen(destination: dest, selection: $selection)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    private func row(_ dest: FinDestination) -> some View {
        HStack(spacing: 12) {
            Image(systemName: dest.icon)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 24)
                .foregroundStyle(Palette.muted)
            VStack(alignment: .leading, spacing: 2) {
                Text(dest.title).font(.system(size: 14, weight: .semibold))
                Text(dest.subtitle).font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
            Spacer()
        }
        .contentShape(.rect)
    }
}

/// A destination link that behaves like a push on iPhone and selects the
/// finance sidebar row on the Mac.
struct FinDestinationLink<Label: View>: View {
    let destination: FinDestination
    @Binding var selection: FinDestination
    @ViewBuilder var label: Label

    var body: some View {
        #if os(macOS)
        Button { withAnimation(DS.spring) { selection = destination } } label: { label }
            .buttonStyle(.plain)
        #else
        NavigationLink(value: destination) { label }
            .buttonStyle(.plain)
        #endif
    }
}

// MARK: - Overview

struct MeFinanceOverview: View {
    @EnvironmentObject var state: AppState
    @Binding var selection: FinDestination
    @ObservedObject private var signals = FinanceSignals.shared
    @State private var range: FinRangePreset = .y1
    @State private var demoReset = false

    private var doc: FinanceDocument { state.finance }
    private var today: String { FinanceCal.today() }

    var body: some View {
        let comparisons = FinanceEngine.periodComparisons(doc, asOf: today)
        let current = comparisons.month
        let previous = comparisons.prevMonth
        let nw = FinanceEngine.netWorth(doc)
        let assets = FinanceEngine.totalAssets(doc)
        let liabilities = FinanceEngine.totalLiabilities(doc)
        let portfolio = FinanceEngine.portfolio(doc)
        let cash = FinanceEngine.liquidAssets(doc)
        let history = FinanceEngine.netWorthHistory(doc,
                                                   from: FinanceEngine.rangeStart(range, doc: doc, asOf: today) ?? FinanceCal.addMonths(-12, to: today),
                                                   through: today)
        let nwDelta: Double? = {
            guard history.count >= 2, let last = history.last, let prev = history.dropLast().last else { return nil }
            return FinanceEngine.comparison(last.netPaise, prev.netPaise)
        }()
        let accounts = FinanceEngine.accountSummaries(doc, asOf: today)
        let spends = FinanceEngine.expenseByCategory(doc, from: FinanceCal.monthStart(today), through: FinanceCal.monthEnd(today))
        let upcoming = FinanceEngine.upcomingPayments(doc, days: 45, asOf: today)
        let goals = FinanceEngine.goalStatuses(doc, asOf: today)
        let insights = FinanceEngine.insights(doc, asOf: today)
        let monthsBack = min(max(range.months ?? 12, 6), 18)
        let cashflow = FinanceEngine.monthlyCashflow(doc, months: FinanceCal.monthsBack(monthsBack))
        let quarterStart = FinanceCal.addMonths(-2, to: FinanceCal.monthStart(today))
        let currentQuarter = FinanceEngine.totals(doc, from: quarterStart, through: FinanceCal.monthEnd(today))
        let prevQuarterStart = FinanceCal.addMonths(-5, to: FinanceCal.monthStart(today))
        let prevQuarter = FinanceEngine.totals(doc, from: prevQuarterStart, through: FinanceCal.addDays(-1, to: quarterStart))
        let currentYear = FinanceEngine.totals(doc, from: FinanceCal.yearStart(today), through: today)
        let prevYear = FinanceEngine.totals(doc,
                                           from: FinanceCal.addYears(-1, to: FinanceCal.yearStart(today)),
                                           through: FinanceCal.addYears(-1, to: today))
        let hide = doc.settings.hideBalances

        FinPage(title: "Finance",
                sub: doc.isEmpty ? "A complete record of your money, from the first rupee." : "Your financial position, calculated from \(doc.transactions.count) recorded transactions.",
                badge: doc.settings.demoMode ? "Demo data" : nil) {

            if doc.hasDemoRecords {
                demoBanner
            }

            if let syncError = state.lastSyncError ?? state.lastHydrateError {
                FinCard {
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: "exclamationmark.icloud").foregroundStyle(Palette.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Not syncing").font(.system(size: 12, weight: .semibold))
                            Text(syncError).font(.system(size: 10.5)).foregroundStyle(Palette.muted)
                            Text("Changes remain on this device and will retry. Nothing has been discarded.")
                                .font(.system(size: 9.5)).foregroundStyle(Palette.faint)
                        }
                        Spacer()
                        Button { Task { await state.syncNow() } } label: {
                            Text("Retry").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.orange)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if doc.isEmpty {
                onboarding
            }

            // Hero: net worth and the chart that explains it.
            FinCard {
                #if os(macOS)
                HStack(alignment: .top, spacing: 16) {
                    heroNumbers(nw: nw, nwDelta: nwDelta, hide: hide)
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 6) {
                        FinRangeBar(selection: $range)
                        HStack(spacing: 10) {
                            legendDot(Palette.green, "Assets")
                            legendDot(Palette.negative, "Liabilities")
                        }
                    }
                }
                #else
                VStack(alignment: .leading, spacing: 10) {
                    heroNumbers(nw: nw, nwDelta: nwDelta, hide: hide)
                    HStack {
                        FinRangeBar(selection: $range)
                        Spacer()
                        legendDot(Palette.green, "Assets")
                        legendDot(Palette.negative, "Liabilities")
                    }
                }
                #endif

                FinNetWorthChart(points: history, height: 210)

                HStack(spacing: 18) {
                    miniMetric("Assets", FinanceFormat.inr(assets.paise), assets.certainty)
                    miniMetric("Liabilities", FinanceFormat.inr(liabilities), .calculated)
                    miniMetric("Portfolio", FinanceFormat.inr(portfolio.value), portfolio.certainty)
                    Spacer()
                    if history.count >= 2 {
                        Text("\(history.count) month-end points")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(Palette.faint)
                    }
                }
            }

            // Current month position, with the comparisons the brief asks for.
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 185), spacing: 12)], spacing: 12) {
                FinStatTile(label: "Assets", value: hide ? "₹ ••••" : FinanceFormat.inr(assets.paise),
                            sub: assets.certainty.label, icon: "building.columns")
                FinStatTile(label: "Liabilities", value: hide ? "₹ ••••" : FinanceFormat.inr(liabilities),
                            sub: liabilities > 0 ? "Outstanding principal" : "No debt recorded",
                            icon: "creditcard",
                            valueTint: liabilities > 0 ? Palette.negative : Palette.text)
                FinStatTile(label: "Cash & bank", value: hide ? "₹ ••••" : FinanceFormat.inr(cash),
                            sub: "Liquid", icon: "banknote")
                FinStatTile(label: "Investments", value: hide ? "₹ ••••" : FinanceFormat.inr(portfolio.value),
                            sub: portfolio.certainty.label, icon: "chart.line.uptrend.xyaxis")
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 205), spacing: 12)], spacing: 12) {
                FinStatTile(label: "Income · this month", value: hide ? "₹ ••••" : FinanceFormat.inr(current.incomePaise),
                            delta: FinanceEngine.comparison(current.incomePaise, previous.incomePaise),
                            deltaLabel: "vs last month", icon: "arrow.down.left")
                FinStatTile(label: "Expenses · this month", value: hide ? "₹ ••••" : FinanceFormat.inr(current.expensePaise),
                            delta: FinanceEngine.comparison(current.expensePaise, previous.expensePaise),
                            deltaLabel: "vs last month", icon: "arrow.up.right")
                FinStatTile(label: "Net savings · this month", value: hide ? "₹ ••••" : FinanceFormat.inr(current.netSavingsPaise),
                            delta: FinanceEngine.comparison(current.netSavingsPaise, previous.netSavingsPaise),
                            deltaLabel: "vs last month", icon: "banknote")
                FinStatTile(label: "Savings rate", value: current.savingsRate.map { FinanceFormat.percent($0) } ?? "—",
                            sub: current.incomePaise > 0 ? "Of this month's income" : "No income recorded", icon: "percent")
            }

            // Cash flow.
            FinCard {
                FinCardHeader("Cash flow", sub: "Income, expenses and what stays", icon: "chart.bar") {
                    FinDestinationLink(destination: .reports, selection: $selection) {
                        Text("Open reports").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.green)
                    }
                }
                FinCashflowChart(points: cashflow, height: 190)
                HStack(spacing: 18) {
                    miniMetric("Income", FinanceFormat.inr(cashflow.reduce(0) { $0 + $1.incomePaise }), .calculated)
                    miniMetric("Expenses", FinanceFormat.inr(cashflow.reduce(0) { $0 + $1.expensePaise }), .calculated)
                    miniMetric("Saved", FinanceFormat.inr(cashflow.reduce(0) { $0 + $1.netPaise }), .calculated)
                    Spacer()
                    Text("\(monthsBack) months").font(.system(size: 9.5)).foregroundStyle(Palette.faint)
                }
            }

            FinCard {
                FinCardHeader("Compared with", sub: "Same-length windows, from recorded transactions", icon: "arrow.left.arrow.right")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 16)], spacing: 10) {
                    comparisonColumn("This month", current: current, previous: previous, previousLabel: "last month")
                    comparisonColumn("This quarter", current: currentQuarter, previous: prevQuarter, previousLabel: "previous quarter")
                    comparisonColumn("Year to date", current: currentYear, previous: prevYear, previousLabel: "same period last year")
                }
            }

            // Spending + accounts.
            #if os(macOS)
            HStack(alignment: .top, spacing: 12) {
                spendingCard(spends, hide: hide).frame(maxWidth: .infinity)
                accountsCard(accounts, hide: hide).frame(maxWidth: .infinity)
            }
            #else
            spendingCard(spends, hide: hide)
            accountsCard(accounts, hide: hide)
            #endif

            // Investments + upcoming.
            #if os(macOS)
            HStack(alignment: .top, spacing: 12) {
                investmentsCard(hide: hide).frame(maxWidth: .infinity)
                upcomingCard(upcoming, hide: hide).frame(maxWidth: .infinity)
            }
            #else
            investmentsCard(hide: hide)
            upcomingCard(upcoming, hide: hide)
            #endif

            // Goals + insights.
            #if os(macOS)
            HStack(alignment: .top, spacing: 12) {
                goalsCard(goals).frame(maxWidth: .infinity)
                insightsCard(insights).frame(maxWidth: .infinity)
            }
            #else
            goalsCard(goals)
            insightsCard(insights)
            #endif

            FinCard {
                FinCardHeader("Ask about your money", sub: "Answers come from the ledger, with the records to back them", icon: "sparkles")
                HStack(spacing: 6) {
                    ForEach(["How much did I spend on food this year?",
                             "What is my net worth?",
                             "How much have I invested?",
                             "What was my largest expense?"], id: \.self) { q in
                        Button { askQuestion(q) } label: {
                            Text(q)
                                .font(.system(size: 10, weight: .medium))
                                .lineLimit(1)
                                .padding(.horizontal, 9).frame(height: 28)
                                .background(FinStyle.elevated, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
            }

            FinCard {
                FinCardHeader("Do something", icon: "bolt")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 8)], spacing: 8) {
                    quickAction("Add transaction", "plus", .transactions) { signals.newTransaction = true }
                    quickAction("Add account", "building.columns", .accounts) { signals.quickAddAccount = true }
                    quickAction("Add investment", "chart.line.uptrend.xyaxis", .investments) { signals.quickAddInvestment = true }
                    quickAction("Queue statement", "doc.badge.arrow.up", .statements) {}
                    quickAction("Reconcile", "checkmark.shield", .audit) {}
                    quickAction("Ask about money", "sparkles", .overview) { signals.ask = true }
                }
            }

            Text("All figures are INR, calculated in Asia/Kolkata. Nothing here is a forecast.")
                .font(.system(size: 9.5))
                .foregroundStyle(Palette.faint)
                .padding(.top, 2)
        }
        .confirmationDialog("Remove all demo records?", isPresented: $demoReset, titleVisibility: .visible) {
            Button("Remove demo data", role: .destructive) { state.financeResetDemo() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Only rows marked as demo are removed. Anything you recorded yourself is kept.")
        }
    }

    // MARK: Overview pieces

    private var demoBanner: some View {
        FinCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "testtube.2")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Palette.orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Demo data only").font(.system(size: 13, weight: .bold))
                    Text("These accounts, transactions and valuations are fictional. Reset before recording real money. Demo rows never touch production records.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 8)
                Button { demoReset = true } label: {
                    Text("Remove demo").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.orange)
                }
                .buttonStyle(.plain)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: FinStyle.radius).strokeBorder(Palette.orange.opacity(0.22), lineWidth: 1)
        }
    }

    private var onboarding: some View {
        FinCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: "indianrupeesign.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(Palette.green)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Start the ledger").font(.system(size: 19, weight: .bold))
                        Text("Nothing is assumed. Create the first account, or explore with a labelled demo.")
                            .font(.system(size: 12)).foregroundStyle(Palette.muted)
                    }
                }
                HStack(spacing: 10) {
                    FinDestinationLink(destination: .accounts, selection: $selection) {
                        finButtonLabel("Add first account", icon: "plus")
                    }
                    Button { state.financeLoadDemo() } label: { finButtonLabel("Load demo data", icon: "testtube.2", filled: false) }
                        .buttonStyle(.plain)
                    Button { signals.ask = true } label: { finButtonLabel("Ask a question", icon: "sparkles", filled: false) }
                        .buttonStyle(.plain)
                }
                HStack(spacing: 16) {
                    onboardingPoint("ledger", "Every transaction, searchable")
                    onboardingPoint("checkmark.shield", "Corrections are audited")
                    onboardingPoint("arrow.left.arrow.right", "Transfers never inflate income")
                }
            }
        }
    }

    private func finButtonLabel(_ title: String, icon: String, filled: Bool = true) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon).font(.system(size: 11, weight: .semibold))
            Text(title).font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(filled ? Palette.background : Palette.text)
        .padding(.horizontal, 14).frame(height: 36)
        .background(filled ? Palette.text : FinStyle.elevated, in: Capsule())
        .overlay { if !filled { Capsule().strokeBorder(FinStyle.border) } }
    }

    private func onboardingPoint(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 9)).foregroundStyle(Palette.green)
            Text(text).font(.system(size: 9.5)).foregroundStyle(Palette.faint)
        }
    }

    private func spendingCard(_ slices: [FinCategorySlice], hide: Bool) -> some View {
        FinCard {
            FinCardHeader("Spending breakdown", sub: "This month", icon: "chart.pie") {
                FinDestinationLink(destination: .expenses, selection: $selection) {
                    Text("All expenses").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.green)
                }
            }
            if slices.isEmpty {
                FinEmptyState(icon: "chart.pie", title: "No spending this month",
                              detail: "Record an expense and it will be classified here.")
                    .frame(height: 180)
            } else {
                HStack(alignment: .center, spacing: 14) {
                    FinDonutChart(slices: slices, height: 160).frame(width: 160)
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(Array(slices.prefix(5).enumerated()), id: \.element.id) { i, s in
                            HStack(spacing: 6) {
                                Circle().fill(FinStyle.sliceColor(i)).frame(width: 6, height: 6)
                                Text(s.name).font(.system(size: 11, weight: .medium)).lineLimit(1)
                                Spacer(minLength: 4)
                                Text(hide ? "•••" : FinanceFormat.compact(s.paise))
                                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(Palette.muted)
                                Text(FinanceFormat.percent(s.share, decimals: 0))
                                    .font(.system(size: 9)).foregroundStyle(Palette.faint)
                                    .frame(width: 28, alignment: .trailing)
                            }
                        }
                    }
                }
            }
        }
    }

    private func accountsCard(_ summaries: [FinAccountSummary], hide: Bool) -> some View {
        let top = Array(summaries.prefix(5))
        return FinCard {
            FinCardHeader("Accounts", sub: "\(summaries.count) open", icon: "building.columns") {
                FinDestinationLink(destination: .accounts, selection: $selection) {
                    Text("Manage").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.green)
                }
            }
            if top.isEmpty {
                FinDestinationLink(destination: .accounts, selection: $selection) {
                    FinEmptyState(icon: "building.columns", title: "No accounts yet",
                                  detail: "Add a bank account, cash wallet or credit card to start the ledger.")
                }
            } else {
                VStack(spacing: 10) {
                    ForEach(top) { s in
                        FinDestinationLink(destination: .accounts, selection: $selection) {
                            FinAccountLine(summary: hide ? hideSummary(s) : s)
                        }
                    }
                }
            }
        }
    }

    private func hideSummary(_ s: FinAccountSummary) -> FinAccountSummary {
        var copy = s
        copy.balance = FinAmount(paise: 0, certainty: s.balance.certainty)
        return copy
    }

    private func investmentsCard(hide: Bool) -> some View {
        let p = FinanceEngine.portfolio(doc)
        let summaries = FinanceEngine.investmentSummaries(doc).prefix(4)
        return FinCard {
            FinCardHeader("Investment snapshot", sub: "Manual valuations — no live market feed", icon: "chart.line.uptrend.xyaxis") {
                FinDestinationLink(destination: .investments, selection: $selection) {
                    Text("Portfolio").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.green)
                }
            }
            if summaries.isEmpty {
                FinDestinationLink(destination: .investments, selection: $selection) {
                    FinEmptyState(icon: "chart.line.uptrend.xyaxis", title: "No holdings recorded",
                                  detail: "Add a mutual fund, equity or deposit with its invested and current value.")
                }
            } else {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CURRENT VALUE").font(.system(size: 8.5, weight: .bold)).tracking(0.7).foregroundStyle(Palette.faint)
                        Text(hide ? "₹ ••••" : FinanceFormat.inr(p.value)).font(.system(size: 20, weight: .bold, design: .rounded)).monospacedDigit()
                        Text("Invested \(hide ? "•••" : FinanceFormat.inr(p.invested))")
                            .font(.system(size: 10)).foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(p.unrealised >= 0 ? "UNREALISED GAIN" : "UNREALISED LOSS")
                            .font(.system(size: 8.5, weight: .bold)).tracking(0.7).foregroundStyle(Palette.faint)
                        Text(hide ? "₹ ••••" : FinanceFormat.inr(p.unrealised, showSign: true))
                            .font(.system(size: 17, weight: .bold, design: .rounded)).monospacedDigit()
                            .foregroundStyle(FinStyle.moneyColor(p.unrealised))
                        if p.invested > 0 {
                            Text(FinanceFormat.signedPercent(Double(p.unrealised) / Double(p.invested) * 100))
                                .font(.system(size: 10, weight: .semibold)).foregroundStyle(FinStyle.moneyColor(p.unrealised))
                        }
                    }
                }
                if !p.allocation.isEmpty {
                    GeometryReader { geo in
                        HStack(spacing: 2) {
                            ForEach(Array(p.allocation.prefix(6).enumerated()), id: \.element.id) { i, slice in
                                Capsule()
                                    .fill(FinStyle.sliceColor(i))
                                    .frame(width: max(3, geo.size.width * CGFloat(slice.share) / 100), height: 5)
                            }
                        }
                    }
                    .frame(height: 5)
                    ForEach(Array(p.allocation.prefix(3).enumerated()), id: \.element.id) { i, slice in
                        HStack(spacing: 5) {
                            Circle().fill(FinStyle.sliceColor(i)).frame(width: 5, height: 5)
                            Text(slice.assetClass.shortLabel).font(.system(size: 9.5)).foregroundStyle(Palette.muted)
                            Spacer()
                            Text(FinanceFormat.percent(slice.share, decimals: 0))
                                .font(.system(size: 9)).foregroundStyle(Palette.faint)
                        }
                    }
                }
                ForEach(Array(summaries)) { s in
                    HStack(spacing: 8) {
                        Image(systemName: s.investment.assetClass.icon).font(.system(size: 9)).foregroundStyle(Palette.muted).frame(width: 14)
                        Text(s.investment.name).font(.system(size: 11, weight: .medium)).lineLimit(1)
                        Spacer()
                        Text(hide ? "•••" : FinanceFormat.compact(s.valuePaise))
                            .font(.system(size: 10.5, weight: .semibold)).monospacedDigit()
                        FinBadge(text: s.certainty.label, tint: FinStyle.certaintyColor(s.certainty))
                    }
                }
            }
        }
    }

    private func upcomingCard(_ items: [FinUpcomingPayment], hide: Bool) -> some View {
        FinCard {
            FinCardHeader("Upcoming payments", sub: "Next 45 days", icon: "calendar") {
                FinDestinationLink(destination: .recurring, selection: $selection) {
                    Text("Recurring").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.green)
                }
            }
            if items.isEmpty {
                FinEmptyState(icon: "calendar", title: "Nothing due",
                              detail: "EMIs, subscriptions and bills with a next date appear here.")
                    .frame(height: 160)
            } else {
                ForEach(items.prefix(6)) { p in
                    HStack(spacing: 9) {
                        Image(systemName: p.kind.icon).font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.muted).frame(width: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(p.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                            Text("\(FinanceCal.display(p.date)) · \(p.daysAway <= 0 ? "today" : "in \(p.daysAway)d")")
                                .font(.system(size: 9.5)).foregroundStyle(Palette.muted)
                        }
                        Spacer()
                        FinMoneyText(paise: hide ? 0 : p.amountPaise, size: 11.5)
                    }
                }
            }
        }
    }

    private func goalsCard(_ goals: [FinGoalStatus]) -> some View {
        FinCard {
            FinCardHeader("Goals", sub: "Allocations are planning figures, not extra assets", icon: "target") {
                FinDestinationLink(destination: .goals, selection: $selection) {
                    Text("All goals").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.green)
                }
            }
            if goals.isEmpty {
                FinEmptyState(icon: "target", title: "No goals yet",
                              detail: "An emergency fund is the usual first one.")
                    .frame(height: 150)
            } else {
                ForEach(goals.prefix(3)) { g in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(g.goal.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                            Spacer()
                            Text("\(FinanceFormat.percent(g.progress * 100, decimals: 0))")
                                .font(.system(size: 10.5, weight: .semibold)).monospacedDigit().foregroundStyle(Palette.muted)
                        }
                        FinProgressBar(progress: g.progress, tint: g.progress >= 1 ? Palette.green : Palette.blue)
                        HStack {
                            Text("\(FinanceFormat.compact(g.goal.currentPaise)) of \(FinanceFormat.compact(g.goal.targetPaise))")
                            Spacer()
                            if let m = g.monthsLeft { Text("\(m) months left") }
                        }
                        .font(.system(size: 9.5)).foregroundStyle(Palette.faint)
                    }
                }
            }
        }
    }

    private func insightsCard(_ insights: [FinInsight]) -> some View {
        FinCard {
            FinCardHeader("Insights", sub: "Only what the records support", icon: "sparkles")
            if insights.isEmpty {
                FinEmptyState(icon: "sparkles", title: "No insights yet",
                              detail: "Once there is a month of real records, patterns become visible.")
                    .frame(height: 150)
            } else {
                ForEach(insights.prefix(5)) { insight in
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: insight.symbol)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(FinStyle.toneColor(insight.tone))
                            .frame(width: 18, height: 18)
                            .background(FinStyle.toneColor(insight.tone).opacity(0.10), in: RoundedRectangle(cornerRadius: 5))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(insight.title).font(.system(size: 11.5, weight: .semibold))
                            Text(insight.detail).font(.system(size: 10.5)).foregroundStyle(Palette.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    private func askQuestion(_ question: String) {
        state.pendingChatPrompt = question
        signals.ask = true
    }

    private func quickAction(_ title: String, _ icon: String, _ dest: FinDestination, action: @escaping () -> Void) -> some View {        Button {
            if dest == .transactions && title == "Add transaction" { action() }
            else if title == "Add account" { action() }
            else if title == "Add investment" { action() }
            else if title == "Queue statement" { selection = .statements }
            else if title == "Reconcile" { selection = .audit }
            else { action() }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.muted)
                Text(title).font(.system(size: 11, weight: .medium)).lineLimit(1)
                Spacer(minLength: 2)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(FinStyle.elevated, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func heroNumbers(nw: FinAmount, nwDelta: Double?, hide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text("NET WORTH").font(.system(size: 9, weight: .bold)).tracking(1.0).foregroundStyle(Palette.faint)
                FinBadge(text: nw.certainty.label, tint: FinStyle.certaintyColor(nw.certainty), icon: nw.certainty.icon)
                if doc.hasDemoRecords { FinBadge(text: "demo", tint: Palette.orange) }
            }
            Text(hide ? "₹ ••••••" : FinanceFormat.inr(nw.paise, showSign: true))
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .tracking(-1.2)
                .monospacedDigit()
                .foregroundStyle(FinStyle.moneyColor(nw.paise))
                .contentTransition(.numericText())
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            HStack(spacing: 12) {
                if let nwDelta {
                    HStack(spacing: 3) {
                        Image(systemName: nwDelta >= 0 ? "arrow.up.right" : "arrow.down.right")
                        Text(FinanceFormat.signedPercent(nwDelta))
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(FinStyle.changeColor(nwDelta))
                    Text("since the previous month").font(.system(size: 11)).foregroundStyle(Palette.muted)
                } else {
                    Text("Add a second month of records to see the change.")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
            }
        }
    }

    private func comparisonColumn(_ title: String, current: FinPeriodTotals, previous: FinPeriodTotals, previousLabel: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased()).font(.system(size: 8.5, weight: .bold)).tracking(0.7).foregroundStyle(Palette.faint)
            comparisonLine("Income", current: current.incomePaise, previous: previous.incomePaise)
            comparisonLine("Expenses", current: current.expensePaise, previous: previous.expensePaise)
            comparisonLine("Net saved", current: current.netSavingsPaise, previous: previous.netSavingsPaise)
            Text("vs \(previousLabel)").font(.system(size: 8.5)).foregroundStyle(Palette.faint)
        }
    }

    private func comparisonLine(_ label: String, current: Int64, previous: Int64) -> some View {
        let delta = FinanceEngine.comparison(current, previous)
        return HStack(spacing: 5) {
            Text(label).font(.system(size: 10.5)).foregroundStyle(Palette.muted)
            Spacer()
            Text(FinanceFormat.compact(current)).font(.system(size: 10.5, weight: .semibold)).monospacedDigit()
            if let delta {
                Text(FinanceFormat.signedPercent(delta)).font(.system(size: 9, weight: .semibold)).foregroundStyle(FinStyle.changeColor(delta))
            } else {
                Text("—").font(.system(size: 9)).foregroundStyle(Palette.faint)
            }
        }
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(label).font(.system(size: 9)).foregroundStyle(Palette.faint)
        }
    }

    private func miniMetric(_ label: String, _ value: String, _ certainty: FinCertainty) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 3) {
                Text(label).font(.system(size: 9, weight: .semibold)).foregroundStyle(Palette.faint)
                Image(systemName: certainty.icon).font(.system(size: 7)).foregroundStyle(FinStyle.certaintyColor(certainty))
            }
            Text(value).font(.system(size: 12.5, weight: .semibold, design: .rounded)).monospacedDigit()
        }
    }
}
