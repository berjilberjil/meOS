import SwiftUI
import Charts
import UniformTypeIdentifiers

// MARK: - Statements & imports

struct MeFinanceStatements: View {
    @EnvironmentObject var state: AppState
    @State private var importing = false
    @State private var message: String?
    @State private var accountID = ""
    @State private var institution = ""
    @State private var confirmDelete: FinStatement?

    private var doc: FinanceDocument { state.finance }
    private var statements: [FinStatement] { doc.statements.sorted { $0.uploadedAt > $1.uploadedAt } }
    private var batches: [FinImportBatch] { doc.importBatches.sorted { $0.createdAt > $1.createdAt } }

    private var allowedTypes: [UTType] {
        var types: [UTType] = [.commaSeparatedText, .pdf, .plainText]
        if let xlsx = UTType(filenameExtension: "xlsx") { types.append(xlsx) }
        if let xls = UTType(filenameExtension: "xls") { types.append(xls) }
        return types
    }

    private let steps: [(Int, String, String)] = [
        (1, "Upload statement", "Choose a CSV, XLSX or PDF. Nothing is parsed in this phase."),
        (2, "Detect institution and account", "Match the file to an account you created."),
        (3, "Read statement structure", "Identify columns, date formats and balance lines."),
        (4, "Extract transactions", "One row per movement, with the raw source text kept."),
        (5, "Preview extracted data", "Nothing enters the ledger before you see it."),
        (6, "Validate dates, amounts, references", "Flag malformed rows rather than guessing."),
        (7, "Detect duplicates", "Compare against existing records, never overwrite them."),
        (8, "Identify transfers", "Pair opposite movements across your own accounts."),
        (9, "Review unknown transactions", "Categorise, tag or skip each unknown row."),
        (10, "Confirm import", "An explicit confirmation is required. There is no auto-import."),
        (11, "Reconcile closing balance", "Prove the extracted rows against the statement."),
        (12, "Save verified records + audit", "Preserve the original file and the import batch metadata."),
    ]

    var body: some View {
        FinPage(title: "Statements & imports",
                sub: "The complete import pipeline, ready for the next phase. No parser is installed yet.",
                badge: doc.settings.demoMode ? "Demo data" : nil) {

            FinCard {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "doc.badge.arrow.up")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Palette.blue)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Not enabled in this phase").font(.system(size: 13, weight: .bold))
                        Text("You can choose a file and record its metadata. MeOS will not read, parse, upload or import it yet, and it will not create a single transaction. The button says exactly what happened.")
                            .font(.system(size: 11)).foregroundStyle(Palette.muted)
                    }
                }
            }

            HStack(spacing: 8) {
                FinPrimaryButton(title: "Choose statement", icon: "doc.badge.plus") { importing = true }
                Spacer()
                if !doc.accounts.isEmpty {
                    Menu {
                        Button("No account") { accountID = "" }
                        ForEach(doc.accounts) { a in Button(a.name) { accountID = a.id } }
                    } label: {
                        Text(doc.account(accountID)?.name ?? "Link to account")
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 11).frame(height: 34)
                            .background(FinStyle.elevated, in: Capsule())
                    }
                    .menuIndicator(.hidden)
                }
            }

            if let message {
                FinCard {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle").foregroundStyle(Palette.blue)
                        Text(message).font(.system(size: 11)).foregroundStyle(Palette.muted)
                    }
                }
            }

            FinCard {
                FinCardHeader("Pipeline", sub: "12 stages · all deferred honestly", icon: "arrow.triangle.branch")
                ForEach(steps, id: \.0) { step in
                    HStack(alignment: .top, spacing: 9) {
                        Text("\(step.0)")
                            .font(.system(size: 9, weight: .bold)).monospacedDigit()
                            .foregroundStyle(Palette.faint)
                            .frame(width: 18, height: 18)
                            .background(FinStyle.elevated, in: Circle())
                        VStack(alignment: .leading, spacing: 1) {
                            Text(step.1).font(.system(size: 11.5, weight: .semibold))
                            Text(step.2).font(.system(size: 9.5)).foregroundStyle(Palette.muted)
                        }
                        Spacer()
                        FinBadge(text: step.0 <= 1 ? "UI ready" : "next phase",
                                 tint: step.0 <= 1 ? Palette.blue : Palette.muted)
                    }
                    .padding(.vertical, 2)
                }
            }

            FinSectionTitle(text: "Statements", detail: "\(statements.count)")
            FinCard(padding: 0) {
                if statements.isEmpty {
                    FinEmptyState(icon: "doc.text", title: "No statements yet",
                                  detail: "When importing is enabled, the original file will be preserved and every extracted row will stay linked to its statement and import batch.")
                } else {
                    ForEach(Array(statements.enumerated()), id: \.element.id) { index, s in
                        HStack(spacing: 10) {
                            Image(systemName: s.fileType.lowercased().contains("pdf") ? "doc.richtext" : "tablecells")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Palette.muted)
                                .frame(width: 28, height: 28)
                                .background(FinStyle.elevated, in: RoundedRectangle(cornerRadius: 7))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.fileName).font(.system(size: 11.5, weight: .medium)).lineLimit(1)
                                Text([doc.account(s.accountID)?.name, s.institution, "\(s.fileSize.formatted()) bytes", s.uploadedAt]
                                    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.system(size: 9)).foregroundStyle(Palette.muted).lineLimit(1)
                            }
                            Spacer()
                            FinBadge(text: s.status.label, tint: s.status == .parsed ? Palette.green : Palette.orange)
                            Menu {
                                Button("Remove statement", role: .destructive) { confirmDelete = s }
                            } label: {
                                Image(systemName: "ellipsis").font(.system(size: 11)).frame(width: 26, height: 22)
                            }
                            .menuIndicator(.hidden)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        if index < statements.count - 1 {
                            Rectangle().fill(FinStyle.border).frame(height: 1).padding(.leading, 50)
                        }
                    }
                }
            }

            if !batches.isEmpty {
                FinSectionTitle(text: "Import history", detail: "\(batches.count)")
                FinCard(padding: 0) {
                    ForEach(batches) { b in
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(doc.statements.first { $0.id == b.statementID }?.fileName ?? b.statementID)
                                    .font(.system(size: 11, weight: .medium))
                                Text("\(b.status.label) · \(b.rowCount) rows · \(b.duplicateCount) duplicates · \(b.errorCount) errors")
                                    .font(.system(size: 9)).foregroundStyle(Palette.muted)
                            }
                            Spacer()
                            FinBadge(text: b.status.label, tint: b.status == .confirmed ? Palette.green : Palette.orange)
                        }
                        .padding(12)
                    }
                }
            }

            FinCard {
                FinCardHeader("Safety rules already enforced", icon: "lock.shield")
                Text("• A statement is never imported without explicit confirmation.\n• Duplicate detection is a review queue, not an overwrite.\n• Every imported row keeps its statement and batch reference.\n• Imported values are preserved in the audit log when corrected.\n• A closing balance must reconcile before a statement is trusted.")
                    .font(.system(size: 10.5)).foregroundStyle(Palette.muted)
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: allowedTypes, allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                let scoped = url.startAccessingSecurityScopedResource()
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                if scoped { url.stopAccessingSecurityScopedResource() }
                _ = state.financeNoteStatement(fileName: url.lastPathComponent,
                                               fileSize: size,
                                               fileType: url.pathExtension.lowercased(),
                                               institution: institution,
                                               accountID: accountID.isEmpty ? nil : accountID)
                message = "“\(url.lastPathComponent)” was noted. No bytes were read, nothing was parsed, and no transaction was created. Extraction arrives in the import phase."
            case .failure(let error):
                message = "Could not open the file: \(error.localizedDescription)"
            }
        }
        .confirmationDialog("Remove this statement record?", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }), titleVisibility: .visible) {
            if let s = confirmDelete {
                Button("Remove", role: .destructive) { state.financeDeleteStatement(s.id); confirmDelete = nil }
            }
            Button("Cancel", role: .cancel) { confirmDelete = nil }
        } message: {
            Text("Its import batches and reconciliations are removed too. Transactions are never deleted by this action.")
        }
    }
}

// MARK: - Reports

enum FinReportKind: String, CaseIterable, Identifiable {
    case dailySpending, monthlySpending, annualSpending, lifetimeSpending
    case incomeTrend, incomeVsExpenses, savingsRate, netWorth
    case investmentReturns, categoryBreakdown, accountCashflow, merchantBreakdown
    case debtRepayment, recurringExpenditure

    var id: String { rawValue }
    var label: String {
        switch self {
        case .dailySpending: "Daily spending"
        case .monthlySpending: "Monthly spending"
        case .annualSpending: "Annual spending"
        case .lifetimeSpending: "Lifetime spending"
        case .incomeTrend: "Income trends"
        case .incomeVsExpenses: "Income vs expenses"
        case .savingsRate: "Savings rate"
        case .netWorth: "Net worth"
        case .investmentReturns: "Investment returns"
        case .categoryBreakdown: "Category breakdown"
        case .accountCashflow: "Account cash flow"
        case .merchantBreakdown: "Merchant breakdown"
        case .debtRepayment: "Debt repayment"
        case .recurringExpenditure: "Recurring expenditure"
        }
    }
    var icon: String {
        switch self {
        case .dailySpending, .monthlySpending, .annualSpending, .lifetimeSpending: "chart.bar"
        case .incomeTrend: "arrow.down.left"
        case .incomeVsExpenses: "arrow.left.arrow.right"
        case .savingsRate: "percent"
        case .netWorth: "chart.xyaxis.line"
        case .investmentReturns: "chart.line.uptrend.xyaxis"
        case .categoryBreakdown: "chart.pie"
        case .accountCashflow: "building.columns"
        case .merchantBreakdown: "storefront"
        case .debtRepayment: "creditcard"
        case .recurringExpenditure: "repeat"
        }
    }
    var definition: String {
        switch self {
        case .dailySpending: "Expenses by day, net of refunds, excluding transfers and investments."
        case .monthlySpending: "Expenses by calendar month in Asia/Kolkata."
        case .annualSpending: "Expenses by calendar year."
        case .lifetimeSpending: "Every recorded expense since the tracking start date."
        case .incomeTrend: "Income, interest and dividends by month."
        case .incomeVsExpenses: "Both flows side by side, with the monthly difference."
        case .savingsRate: "Net savings divided by income for each month. Months with no income show no rate."
        case .netWorth: "Month-end assets minus liabilities, with certainty labels."
        case .investmentReturns: "Current value versus invested capital. Unrealised until a sale is recorded."
        case .categoryBreakdown: "Expenses grouped by the category assigned to each transaction."
        case .accountCashflow: "Inflows and outflows per account for the selected range."
        case .merchantBreakdown: "Expenses grouped by payee text. Unnamed payees fall back to their category."
        case .debtRepayment: "Principal and interest recorded through loan repayments."
        case .recurringExpenditure: "Active commitments annualised at their stated cadence."
        }
    }
}

private struct FinSavingsRateRows: View {
    let points: [FinMonthPoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(points) { (p: FinMonthPoint) in
                if p.incomePaise > 0 {
                    HStack {
                        Text(FinanceCal.monthLabel(p.month)).font(.system(size: 10.5)).frame(width: 80, alignment: .leading)
                        Text(FinanceFormat.inr(p.netPaise)).font(.system(size: 10)).foregroundStyle(FinStyle.moneyColor(p.netPaise))
                        Spacer()
                        Text(FinanceFormat.percent(Double(p.netPaise) / Double(p.incomePaise) * 100))
                            .font(.system(size: 10.5, weight: .semibold)).monospacedDigit()
                    }
                    .padding(.vertical, 1)
                }
            }
        }
    }
}

struct MeFinanceReports: View {
    @EnvironmentObject var state: AppState
    @State private var kind: FinReportKind = .monthlySpending
    @State private var preset: FinRangePreset = .y1
    @State private var customStart = FinanceCal.date(FinanceCal.addMonths(-12, to: FinanceCal.today())) ?? .now
    @State private var customEnd = Date.now
    @State private var export: FinURLBox?

    private var doc: FinanceDocument { state.finance }
    private var start: String {
        preset == .custom ? FinanceCal.key(customStart) : (FinanceEngine.rangeStart(preset, doc: doc) ?? FinanceCal.addYears(-20, to: FinanceCal.today()))
    }
    private var end: String { preset == .custom ? FinanceCal.key(customEnd) : FinanceCal.today() }
    private var totals: FinPeriodTotals { FinanceEngine.totals(doc, from: start, through: end) }

    var body: some View {
        FinPage(title: "Reports",
                sub: "Every report reads the ledger. Nothing is sampled or projected.",
                badge: doc.settings.demoMode ? "Demo data" : nil) {

            #if os(macOS)
            HStack(spacing: 8) {
                reportMenu
                Spacer()
                FinRangeBar(selection: $preset, presets: [.m1, .m3, .m6, .y1, .y3, .all, .custom])
                exportButton
            }
            #else
            VStack(alignment: .leading, spacing: 8) {
                HStack { reportMenu; Spacer(); exportButton }
                ScrollView(.horizontal) {
                    FinRangeBar(selection: $preset, presets: [.m1, .m3, .m6, .y1, .y3, .all, .custom])
                }
                .scrollIndicators(.hidden)
            }
            #endif

            if preset == .custom {
                HStack(spacing: 8) {
                    DatePicker("From", selection: $customStart, displayedComponents: .date).font(.system(size: 11))
                    DatePicker("To", selection: $customEnd, displayedComponents: .date).font(.system(size: 11))
                    Spacer()
                }
            }

            HStack(spacing: 18) {
                summary("Income", FinanceFormat.inr(totals.incomePaise))
                summary("Expenses", FinanceFormat.inr(totals.expensePaise))
                summary("Net savings", FinanceFormat.inr(totals.netSavingsPaise))
                summary("Invested", FinanceFormat.inr(totals.investmentPaise))
                Spacer()
                Text("\(FinanceFormat.date(start)) – \(FinanceFormat.date(end))")
                    .font(.system(size: 9.5)).foregroundStyle(Palette.faint)
            }

            reportBody

            FinCard {
                FinCardHeader("Metric definitions", icon: "function")
                Text(kind.definition).font(.system(size: 11)).foregroundStyle(Palette.muted)
                Divider().overlay(FinStyle.border)
                FinDefinitionList()
            }
        }
        .sheet(item: $export) { box in FinShareSheet(url: box.url) }
    }

    private var reportMenu: some View {
        Menu {
            ForEach(FinReportKind.allCases) { r in
                Button { kind = r } label: {
                    if r == kind { Label(r.label, systemImage: "checkmark") } else { Label(r.label, systemImage: r.icon) }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: kind.icon).font(.system(size: 11, weight: .semibold))
                Text(kind.label).font(.system(size: 12.5, weight: .semibold))
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
            .padding(.horizontal, 12).frame(height: 34)
            .background(FinStyle.elevated, in: Capsule())
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
    }

    private var exportButton: some View {
        Button { exportReport() } label: {
            Image(systemName: "square.and.arrow.up").font(.system(size: 12, weight: .semibold))
                .frame(width: 34, height: 34).background(FinStyle.elevated, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Export report")
    }

    @ViewBuilder private var reportBody: some View {
        switch kind {
        case .dailySpending: dailySpending
        case .monthlySpending: monthlySpending
        case .annualSpending: annualSpending
        case .lifetimeSpending: lifetimeSpending
        case .incomeTrend: incomeTrend
        case .incomeVsExpenses: incomeVsExpenses
        case .savingsRate: savingsRate
        case .netWorth: netWorthReport
        case .investmentReturns: investmentReturns
        case .categoryBreakdown: categoryReport
        case .accountCashflow: accountCashflow
        case .merchantBreakdown: merchantReport
        case .debtRepayment: debtReport
        case .recurringExpenditure: recurringReport
        }
    }

    private var dailySpending: some View {
        let days = dayKeys()
        let values: [(String, Int64)] = days.map { d in
            let t = FinanceEngine.totals(doc, from: d, through: d)
            return (d, t.expensePaise)
        }
        let total = values.reduce(Int64(0)) { $0 + $1.1 }
        let active = values.filter { $0.1 > 0 }
        return VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 175), spacing: 12)], spacing: 12) {
                FinStatTile(label: "Total", value: FinanceFormat.inr(total), sub: "\(active.count) spending days", icon: "chart.bar")
                FinStatTile(label: "Daily average", value: FinanceFormat.inr(total / Int64(max(1, active.count))), sub: "Active days only", icon: "calendar")
                FinStatTile(label: "Biggest day", value: values.max { $0.1 < $1.1 }.map { FinanceFormat.inr($0.1) } ?? "—", sub: values.max { $0.1 < $1.1 }?.0 ?? "", icon: "arrow.up.right")
            }
            FinCard {
                FinCardHeader("Spending by day", icon: "chart.bar")
                Chart(Array(values.enumerated()), id: \.offset) { _, v in
                    BarMark(x: .value("Day", String(v.0.suffix(5))), y: .value("Spent", Double(v.1) / 100))
                        .foregroundStyle(Palette.orange).cornerRadius(2)
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 8)) { value in
                        AxisValueLabel {
                            if let s = value.as(String.self) { Text(s).font(.system(size: 8)).foregroundStyle(Palette.faint) }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine().foregroundStyle(Palette.text.opacity(0.05))
                        AxisValueLabel { if let v = value.as(Double.self) { Text(FinanceFormat.compact(Int64(v * 100))).font(.system(size: 8)).foregroundStyle(Palette.faint) } }
                    }
                }
                .frame(height: 220)
            }
        }
    }

    private var monthlySpending: some View {
        let points = FinanceEngine.monthlyCashflow(doc, months: monthEnds())
        return VStack(alignment: .leading, spacing: 12) {
            FinCard {
                FinCardHeader("Spending by month", sub: "Net of refunds", icon: "chart.bar")
                FinCashflowChart(points: points, height: 220)
            }
            FinCard(padding: 0) {
                ForEach(Array(points.reversed()), id: \.id) { p in
                    HStack {
                        Text(FinanceCal.monthLabel(p.month)).font(.system(size: 10.5, weight: .medium)).frame(width: 72, alignment: .leading)
                        Text(FinanceFormat.inr(p.incomePaise)).font(.system(size: 10)).monospacedDigit().foregroundStyle(Palette.green).frame(width: 80, alignment: .trailing)
                        Text(FinanceFormat.inr(p.expensePaise)).font(.system(size: 10)).monospacedDigit().foregroundStyle(Palette.orange).frame(width: 80, alignment: .trailing)
                        Spacer()
                        FinMoneyText(paise: p.netPaise, showSign: true, size: 11)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 7)
                }
            }
        }
    }

    private var annualSpending: some View {
        let years = Set(doc.transactions.map { String($0.date.prefix(4)) }).sorted()
        let values: [(String, Int64, Int64)] = years.map { y in
            let t = FinanceEngine.yearTotals(doc, year: Int(y) ?? 0)
            return (y, t.incomePaise, t.expensePaise)
        }
        return FinCard {
            FinCardHeader("Annual income and spending", icon: "chart.bar")
            if values.isEmpty {
                FinEmptyState(icon: "chart.bar", title: "No annual data", detail: "Record a transaction to start.")
            } else {
                Chart {
                    ForEach(Array(values.enumerated()), id: \.offset) { _, v in
                        BarMark(x: .value("Year", v.0), y: .value("Income", Double(v.1) / 100))
                            .foregroundStyle(Palette.green).cornerRadius(3)
                        BarMark(x: .value("Year", v.0), y: .value("Expenses", -Double(v.2) / 100))
                            .foregroundStyle(Palette.orange).cornerRadius(3)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine().foregroundStyle(Palette.text.opacity(0.05))
                        AxisValueLabel { if let v = value.as(Double.self) { Text(FinanceFormat.compact(Int64(v * 100))).font(.system(size: 8)).foregroundStyle(Palette.faint) } }
                    }
                }
                .frame(height: 220)
                ForEach(values, id: \.0) { v in
                    HStack {
                        Text(v.0).font(.system(size: 11, weight: .medium)).frame(width: 50, alignment: .leading)
                        Text(FinanceFormat.inr(v.1)).font(.system(size: 10.5)).foregroundStyle(Palette.green)
                        Text("in").font(.system(size: 9)).foregroundStyle(Palette.faint)
                        Spacer()
                        Text(FinanceFormat.inr(v.2)).font(.system(size: 10.5)).foregroundStyle(Palette.orange)
                        Text("out").font(.system(size: 9)).foregroundStyle(Palette.faint)
                    }
                }
            }
        }
    }

    private var lifetimeSpending: some View {
        let lifeStart = FinanceEngine.earliestRecordDate(doc) ?? start
        let lifetime = FinanceEngine.totals(doc, from: lifeStart, through: end)
        let expenses = doc.transactions.filter { FinanceEngine.isExpense($0) || FinanceEngine.isRefund($0) }
        let total = lifetime.expensePaise
        let income = lifetime.incomePaise
        let first = expenses.map(\.date).min()
        return VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 175), spacing: 12)], spacing: 12) {
                FinStatTile(label: "Lifetime spending", value: FinanceFormat.inr(total), sub: first.map { "since \(FinanceFormat.date($0))" } ?? "No records", icon: "chart.bar")
                FinStatTile(label: "Lifetime income", value: FinanceFormat.inr(income), sub: "Recorded only", icon: "arrow.down.left")
                FinStatTile(label: "Kept", value: income > 0 ? FinanceFormat.percent(Double(income - total) / Double(income) * 100) : "—", sub: "Of recorded income", icon: "percent")
            }
            FinCard {
                FinCardHeader("Lifetime ledger", icon: "tablecells")
                Text("This is the sum of every recorded expense, not an estimate of your life. Imported history will extend it without rewriting it.")
                    .font(.system(size: 10.5)).foregroundStyle(Palette.muted)
            }
        }
    }

    private var incomeTrend: some View {
        let points = FinanceEngine.monthlyCashflow(doc, months: monthEnds())
        return FinCard {
            FinCardHeader("Income by month", icon: "arrow.down.left")
            if points.allSatisfy({ $0.incomePaise == 0 }) {
                FinEmptyState(icon: "arrow.down.left", title: "No income recorded", detail: "Salary, freelance and interest will appear here.")
            } else {
                FinCashflowChart(points: points, height: 220)
            }
        }
    }

    private var incomeVsExpenses: some View {
        let points = FinanceEngine.monthlyCashflow(doc, months: monthEnds())
        return FinCard {
            FinCardHeader("Income vs expenses", sub: "Monthly net below the bars", icon: "arrow.left.arrow.right")
            FinCashflowChart(points: points, height: 230)
            ForEach(Array(points.reversed()), id: \.id) { p in
                HStack {
                    Text(FinanceCal.monthLabel(p.month)).font(.system(size: 10.5)).frame(width: 80, alignment: .leading)
                    Text(FinanceFormat.inr(p.incomePaise)).font(.system(size: 10)).foregroundStyle(Palette.green).frame(width: 90, alignment: .trailing)
                    Text("−").foregroundStyle(Palette.faint)
                    Text(FinanceFormat.inr(p.expensePaise)).font(.system(size: 10)).foregroundStyle(Palette.orange).frame(width: 90, alignment: .trailing)
                    Spacer()
                    FinMoneyText(paise: p.netPaise, showSign: true, size: 10.5)
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var savingsRate: some View {
        let points = FinanceEngine.monthlyCashflow(doc, months: monthEnds())
        let rates = points.map { p -> (String, Double?) in
            guard p.incomePaise > 0 else { return (p.month, nil) }
            return (p.month, Double(p.netPaise) / Double(p.incomePaise) * 100)
        }
        let valid = rates.compactMap(\.1)
        return FinCard {
            FinCardHeader("Savings rate", sub: "Net savings ÷ income", icon: "percent")
            if valid.isEmpty {
                FinEmptyState(icon: "percent", title: "No rate yet", detail: "A month needs recorded income before a rate is meaningful.")
            } else {
                Chart(Array(rates.enumerated()), id: \.offset) { _, r in
                    if let v = r.1 {
                        LineMark(x: .value("Month", FinanceCal.shortMonth(r.0)), y: .value("Rate", v))
                            .foregroundStyle(Palette.green)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                        PointMark(x: .value("Month", FinanceCal.shortMonth(r.0)), y: .value("Rate", v))
                            .foregroundStyle(Palette.green)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine().foregroundStyle(Palette.text.opacity(0.05))
                        AxisValueLabel { if let v = value.as(Double.self) { Text("\(Int(v))%").font(.system(size: 8)).foregroundStyle(Palette.faint) } }
                    }
                }
                .frame(height: 220)
                FinSavingsRateRows(points: points)
            }
        }
    }

    private var netWorthReport: some View {
        let points = FinanceEngine.netWorthHistory(doc, from: start, through: end)
        return FinCard {
            FinCardHeader("Net worth", sub: "Month-end, with provenance", icon: "chart.xyaxis.line")
            FinNetWorthChart(points: points, height: 240)
            ForEach(points.suffix(10)) { p in
                #if os(macOS)
                HStack {
                    Text(FinanceCal.monthLabel(p.date)).font(.system(size: 10.5)).frame(width: 80, alignment: .leading)
                    Text(FinanceFormat.inr(p.assetsPaise)).font(.system(size: 10)).foregroundStyle(Palette.green).frame(width: 90, alignment: .trailing)
                    Text(FinanceFormat.inr(p.liabilitiesPaise)).font(.system(size: 10)).foregroundStyle(Palette.negative).frame(width: 80, alignment: .trailing)
                    Spacer()
                    FinBadge(text: p.certainty.label, tint: FinStyle.certaintyColor(p.certainty))
                    Text(FinanceFormat.inr(p.netPaise)).font(.system(size: 10.5, weight: .semibold)).monospacedDigit().frame(width: 100, alignment: .trailing)
                }
                .padding(.vertical, 1)
                #else
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(FinanceCal.monthLabel(p.date)).font(.system(size: 10.5, weight: .medium))
                        Text("Assets \(FinanceFormat.compact(p.assetsPaise)) · debt \(FinanceFormat.compact(p.liabilitiesPaise))")
                            .font(.system(size: 8.5)).foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    FinBadge(text: p.certainty.label, tint: FinStyle.certaintyColor(p.certainty))
                    Text(FinanceFormat.compact(p.netPaise)).font(.system(size: 11, weight: .semibold)).monospacedDigit()
                }
                .padding(.vertical, 2)
                #endif
            }
        }
    }

    private var investmentReturns: some View {
        let p = FinanceEngine.portfolio(doc)
        let summaries = FinanceEngine.investmentSummaries(doc)
        return VStack(alignment: .leading, spacing: 12) {
            FinCard {
                FinCardHeader("Portfolio return", sub: "Unrealised unless sold", icon: "chart.line.uptrend.xyaxis")
                HStack(spacing: 18) {
                    summary("Value", FinanceFormat.inr(p.value))
                    summary("Invested", FinanceFormat.inr(p.invested))
                    summary("Gain", FinanceFormat.inr(p.unrealised, showSign: true))
                    summary("Return", p.invested > 0 ? FinanceFormat.signedPercent(Double(p.unrealised) / Double(p.invested) * 100) : "—")
                    Spacer()
                    FinBadge(text: p.certainty.label, tint: FinStyle.certaintyColor(p.certainty))
                }
                ForEach(summaries) { s in
                    HStack {
                        Text(s.investment.name).font(.system(size: 11, weight: .medium))
                        Spacer()
                        Text(FinanceFormat.inr(s.investedPaise)).font(.system(size: 10)).foregroundStyle(Palette.muted).frame(width: 90, alignment: .trailing)
                        Text(FinanceFormat.inr(s.valuePaise)).font(.system(size: 10)).frame(width: 90, alignment: .trailing)
                        Text(s.returnPercent.map { FinanceFormat.signedPercent($0) } ?? "—")
                            .font(.system(size: 10, weight: .semibold)).foregroundStyle(FinStyle.changeColor(s.returnPercent)).frame(width: 55, alignment: .trailing)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var categoryReport: some View {
        let slices = FinanceEngine.expenseByCategory(doc, from: start, through: end)
        return FinCard {
            FinCardHeader("Category breakdown", sub: "\(slices.count) categories", icon: "chart.pie")
            if slices.isEmpty {
                FinEmptyState(icon: "chart.pie", title: "No spending", detail: "No expenses in this range.")
            } else {
                HStack(alignment: .center, spacing: 16) {
                    FinDonutChart(slices: slices, height: 200).frame(width: 200)
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(slices.prefix(8).enumerated()), id: \.element.id) { i, s in
                            HStack {
                                Circle().fill(FinStyle.sliceColor(i)).frame(width: 5, height: 5)
                                Text(s.name).font(.system(size: 10.5)).lineLimit(1)
                                Spacer()
                                Text(FinanceFormat.inr(s.paise)).font(.system(size: 10, weight: .semibold)).monospacedDigit()
                                Text(FinanceFormat.percent(s.share, decimals: 0)).font(.system(size: 9)).foregroundStyle(Palette.faint).frame(width: 30, alignment: .trailing)
                            }
                        }
                    }
                }
            }
        }
    }

    private var accountCashflow: some View {
        let accounts = doc.accounts.filter { !$0.type.isLiability && $0.status != .closed }
        return FinCard {
            FinCardHeader("Account cash flow", sub: "Selected range", icon: "building.columns")
            ForEach(accounts) { a in
                let t = FinanceEngine.totals(doc, from: start, through: end, accountID: a.id)
                HStack {
                    Image(systemName: a.type.icon).font(.system(size: 10)).foregroundStyle(Palette.muted).frame(width: 16)
                    Text(a.name).font(.system(size: 11, weight: .medium))
                    Spacer()
                    Text(FinanceFormat.inr(t.incomePaise + t.refundPaise)).font(.system(size: 9.5)).foregroundStyle(Palette.green).frame(width: 72, alignment: .trailing)
                    Text(FinanceFormat.inr(t.expensePaise + t.investmentPaise)).font(.system(size: 9.5)).foregroundStyle(Palette.orange).frame(width: 72, alignment: .trailing)
                    FinMoneyText(paise: t.netSavingsPaise - t.investmentPaise, showSign: true, size: 10).frame(width: 84, alignment: .trailing)
                }
                .padding(.vertical, 3)
            }
        }
    }

    private var merchantReport: some View {
        let merchants = FinanceEngine.merchantBreakdown(doc, from: start, through: end)
        let total = merchants.reduce(Int64(0)) { $0 + $1.paise }
        return FinCard {
            FinCardHeader("Top payees", sub: "\(merchants.count) merchants", icon: "storefront")
            ForEach(Array(merchants.prefix(12).enumerated()), id: \.element.id) { i, m in
                HStack {
                    Text("\(i + 1)").font(.system(size: 9, weight: .bold)).foregroundStyle(Palette.faint).frame(width: 18)
                    Text(m.merchant).font(.system(size: 11, weight: .medium)).lineLimit(1)
                    Text("\(m.count)×").font(.system(size: 9)).foregroundStyle(Palette.faint)
                    Spacer()
                    Text(FinanceFormat.inr(m.paise)).font(.system(size: 10.5, weight: .semibold)).monospacedDigit()
                    Text(FinanceFormat.percent(total > 0 ? Double(m.paise) / Double(total) * 100 : 0, decimals: 0))
                        .font(.system(size: 9)).foregroundStyle(Palette.faint).frame(width: 30, alignment: .trailing)
                }
                .padding(.vertical, 3)
            }
        }
    }

    private var debtReport: some View {
        let summaries = FinanceEngine.liabilitySummaries(doc)
        let payments = doc.debtPayments.filter { $0.date >= start && $0.date <= end }
        let principal = payments.reduce(Int64(0)) { $0 + $1.principalPaise }
        let interest = payments.reduce(Int64(0)) { $0 + $1.interestPaise }
        return VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 175), spacing: 12)], spacing: 12) {
                FinStatTile(label: "Principal repaid", value: FinanceFormat.inr(principal), sub: "Reduces liabilities", icon: "arrow.down.right")
                FinStatTile(label: "Interest paid", value: FinanceFormat.inr(interest), sub: "Ordinary expense", icon: "percent")
                FinStatTile(label: "Outstanding", value: FinanceFormat.inr(FinanceEngine.totalLiabilities(doc)), sub: "\(summaries.count) debts", icon: "creditcard")
            }
            FinCard {
                FinCardHeader("By liability", icon: "creditcard")
                ForEach(summaries) { s in
                    HStack {
                        Text(s.liability.name).font(.system(size: 11, weight: .medium))
                        Spacer()
                        Text(FinanceFormat.percent(s.progress * 100, decimals: 0)).font(.system(size: 9.5)).foregroundStyle(Palette.muted)
                        Text(FinanceFormat.inr(s.outstandingPaise)).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Palette.negative).frame(width: 100, alignment: .trailing)
                    }
                    .padding(.vertical, 3)
                }
            }
        }
    }

    private var recurringReport: some View {
        let items = doc.recurring.filter(\.active)
        let annual = FinanceEngine.annualRecurringCommitment(doc)
        return FinCard {
            FinCardHeader("Recurring commitments", sub: "\(items.count) active", icon: "repeat")
            HStack(spacing: 18) {
                summary("Monthly", FinanceFormat.inr(annual / 12))
                summary("Annual", FinanceFormat.inr(annual))
                Spacer()
            }
            ForEach(items.sorted { $0.amountPaise * Int64($0.cadence.annualMultiplier) > $1.amountPaise * Int64($1.cadence.annualMultiplier) }) { item in
                HStack {
                    Image(systemName: item.kind.icon).font(.system(size: 10)).foregroundStyle(Palette.muted).frame(width: 16)
                    Text(item.name).font(.system(size: 11, weight: .medium))
                    Text(item.cadence.label).font(.system(size: 9)).foregroundStyle(Palette.faint)
                    Spacer()
                    Text(FinanceFormat.inr(item.amountPaise)).font(.system(size: 10.5)).monospacedDigit()
                    Text(FinanceFormat.inr(Int64(Double(item.amountPaise) * item.cadence.annualMultiplier)))
                        .font(.system(size: 10)).foregroundStyle(Palette.muted).frame(width: 100, alignment: .trailing)
                }
                .padding(.vertical, 3)
            }
        }
    }

    private func summary(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased()).font(.system(size: 8, weight: .bold)).tracking(0.6).foregroundStyle(Palette.faint)
            Text(value).font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit()
        }
    }

    private func monthEnds() -> [String] {
        preset == .all
            ? FinanceCal.months(from: FinanceCal.monthStart(start), through: end).suffix(24).map { FinanceCal.monthEnd($0) }
            : FinanceCal.monthsBack(min(max(preset.months ?? 12, 3), 36))
    }

    private func dayKeys() -> [String] {
        var out: [String] = []
        var cursor = max(start, FinanceCal.addDays(-90, to: end))
        var guardCount = 0
        while cursor <= end && guardCount < 370 {
            out.append(cursor)
            cursor = FinanceCal.addDays(1, to: cursor)
            guardCount += 1
        }
        return out
    }

    private func exportReport() {
        let csv: String
        switch kind {
        case .netWorth:
            let points = FinanceEngine.netWorthHistory(doc, from: start, through: end)
            let header = "date,assets_inr,liabilities_inr,net_worth_inr,certainty"
            csv = ([header] + points.map { p in
                "\(p.date),\(String(format: "%.2f", Double(p.assetsPaise) / 100)),\(String(format: "%.2f", Double(p.liabilitiesPaise) / 100)),\(String(format: "%.2f", Double(p.netPaise) / 100)),\(p.certainty.rawValue)"
            }).joined(separator: "\n")
        case .categoryBreakdown:
            let slices = FinanceEngine.expenseByCategory(doc, from: start, through: end)
            csv = (["category,group,amount_inr,share_percent,count"] + slices.map { s in
                "\"\(s.name)\",\"\(s.group)\",\(String(format: "%.2f", Double(s.paise) / 100)),\(String(format: "%.2f", s.share)),\(s.count)"
            }).joined(separator: "\n")
        case .accountCashflow:
            let header = "account,inflow_inr,outflow_inr,net_inr"
            let rows = doc.accounts.map { a -> String in
                let t = FinanceEngine.totals(doc, from: start, through: end, accountID: a.id)
                return "\"\(a.name)\",\(String(format: "%.2f", Double(t.incomePaise + t.refundPaise) / 100)),\(String(format: "%.2f", Double(t.expensePaise + t.investmentPaise) / 100)),\(String(format: "%.2f", Double(t.netSavingsPaise - t.investmentPaise) / 100))"
            }
            csv = ([header] + rows).joined(separator: "\n")
        default:
            let list = doc.transactions.filter { $0.date >= start && $0.date <= end }
            csv = FinanceEngine.transactionsCSV(list, doc: doc)
        }
        if let url = FinExport.write(csv, name: "meos-report-\(kind.rawValue)") { export = FinURLBox(url: url) }
    }
}

// MARK: - Tax centre

struct MeFinanceTax: View {
    @EnvironmentObject var state: AppState
    @State private var fyKey = FinanceCal.today()
    @State private var export: FinURLBox?

    private var doc: FinanceDocument { state.finance }
    private var summary: FinTaxSummary { FinanceEngine.taxSummary(doc, fyContaining: fyKey) }
    private var fys: [String] {
        let current = FinanceCal.financialYear(containing: FinanceCal.today())
        return (0..<5).map { FinanceCal.financialYear(containing: FinanceCal.addYears(-$0, to: current.start)).start }
    }

    var body: some View {
        let s = summary
        let related = doc.transactions.filter { t in
            t.date >= s.start && t.date <= s.end &&
            (t.type == .tax || t.type == .fee || t.type == .investmentSale)
        }.sorted { $0.date > $1.date }

        FinPage(title: "Tax centre",
                sub: "Indian financial-year records. No liability is calculated without actual tax rules and inputs.",
                badge: doc.settings.demoMode ? "Demo data" : nil) {

            HStack(spacing: 8) {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(fys, id: \.self) { f in
                            let label = "FY \(String(f.prefix(4)))–\(String((Int(f.prefix(4)) ?? 0) + 1).suffix(2))"
                            FinChipButton(text: label, on: FinanceCal.financialYear(containing: fyKey).start == f) {
                                fyKey = f
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
                Spacer(minLength: 4)
                Button { exportTax() } label: {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 12, weight: .semibold))
                        .frame(width: 34, height: 34).background(FinStyle.elevated, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Export tax-year CSV")
            }

            FinCard {
                FinCardHeader("\(s.fyLabel)", sub: "\(FinanceFormat.date(s.start)) – \(FinanceFormat.date(s.end))", icon: "doc.text")
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("RECORDED INCOME").font(.system(size: 8.5, weight: .bold)).tracking(0.7).foregroundStyle(Palette.faint)
                        Text(FinanceFormat.inr(s.totalIncomePaise)).font(.system(size: 28, weight: .bold, design: .rounded)).monospacedDigit()
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("CAPITAL GAINS RECORDED").font(.system(size: 8.5, weight: .bold)).tracking(0.7).foregroundStyle(Palette.faint)
                        Text(FinanceFormat.inr(s.capitalGainsPaise, showSign: true)).font(.system(size: 20, weight: .bold, design: .rounded)).monospacedDigit()
                            .foregroundStyle(FinStyle.moneyColor(s.capitalGainsPaise))
                        Text("from \(FinanceFormat.inr(s.recordedSaleProceedsPaise)) of recorded sales")
                            .font(.system(size: 9)).foregroundStyle(Palette.faint)
                    }
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 165), spacing: 12)], spacing: 12) {
                FinStatTile(label: "Salary", value: FinanceFormat.inr(s.salaryPaise), sub: "Category-based", icon: "briefcase")
                FinStatTile(label: "Freelance / consulting", value: FinanceFormat.inr(s.freelancePaise), sub: "Category-based", icon: "laptopcomputer")
                FinStatTile(label: "Business / creator", value: FinanceFormat.inr(s.businessPaise), sub: "Category-based", icon: "play.rectangle")
                FinStatTile(label: "Interest", value: FinanceFormat.inr(s.interestPaise), sub: "Recorded inflows", icon: "percent")
                FinStatTile(label: "Dividends", value: FinanceFormat.inr(s.dividendPaise), sub: "Recorded inflows", icon: "gift")
                FinStatTile(label: "Other income", value: FinanceFormat.inr(s.otherIncomePaise), sub: "Unclassified inflows", icon: "plus.circle")
                FinStatTile(label: "Tax / fees paid", value: FinanceFormat.inr(s.taxPaidPaise), sub: "Tax and fee entries", icon: "doc.text")
                FinStatTile(label: "Tax liability", value: "Not calculated", sub: "Rules and inputs not supplied", icon: "questionmark.circle")
            }

            FinSectionTitle(text: "Tax-relevant records", detail: "\(related.count)")
            FinCard(padding: 0) {
                if related.isEmpty {
                    FinEmptyState(icon: "doc.text", title: "Nothing recorded for this year",
                                  detail: "Tax, fee and investment-sale entries appear here with their references.")
                } else {
                    ForEach(related) { t in
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(t.title).font(.system(size: 11, weight: .medium))
                                Text("\(FinanceFormat.date(t.date)) · \(t.type.label)\(t.reference.isEmpty ? "" : " · \(t.reference)")")
                                    .font(.system(size: 9)).foregroundStyle(Palette.muted)
                            }
                            Spacer()
                            FinMoneyText(paise: t.amountPaise, size: 11)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 7)
                    }
                }
            }

            FinCard {
                FinCardHeader("Documents", icon: "folder")
                Text("\(doc.statements.count) statement records are available to link as supporting documents. MeOS does not store or transmit tax identifiers, and no document is shared with an external AI provider.")
                    .font(.system(size: 10.5)).foregroundStyle(Palette.muted)
            }

            FinCard {
                FinCardHeader("This is not tax advice", icon: "exclamationmark.triangle")
                Text("MeOS reports what is recorded. It does not apply deduction rules, exemptions, surcharge or slab rates, and it will not claim a liability or refund without verified rules and complete inputs. Cross-check with a qualified professional and the official portal.")
                    .font(.system(size: 10.5)).foregroundStyle(Palette.muted)
            }
        }
        .sheet(item: $export) { box in FinShareSheet(url: box.url) }
    }

    private func exportTax() {
        let s = summary
        let rows = [
            "metric,amount_inr",
            "salary,\(String(format: "%.2f", Double(s.salaryPaise) / 100))",
            "freelance,\(String(format: "%.2f", Double(s.freelancePaise) / 100))",
            "business,\(String(format: "%.2f", Double(s.businessPaise) / 100))",
            "interest,\(String(format: "%.2f", Double(s.interestPaise) / 100))",
            "dividend,\(String(format: "%.2f", Double(s.dividendPaise) / 100))",
            "other,\(String(format: "%.2f", Double(s.otherIncomePaise) / 100))",
            "tax_paid,\(String(format: "%.2f", Double(s.taxPaidPaise) / 100))",
            "capital_gains_recorded,\(String(format: "%.2f", Double(s.capitalGainsPaise) / 100))",
            "sale_proceeds_recorded,\(String(format: "%.2f", Double(s.recordedSaleProceedsPaise) / 100))",
        ].joined(separator: "\n")
        if let url = FinExport.write(rows, name: "meos-tax-\(s.fyLabel.replacingOccurrences(of: " ", with: "-"))") {
            export = FinURLBox(url: url)
        }
    }
}

// MARK: - Audit & reconciliation

struct MeFinanceAudit: View {
    @EnvironmentObject var state: AppState
    @Binding var selection: FinDestination
    @State private var issue: FinIntegrityIssue?
    @State private var duplicates: FinDuplicateGroup?
    @State private var showCorrections = false

    private var doc: FinanceDocument { state.finance }
    private var issues: [FinIntegrityIssue] { FinanceEngine.integrityIssues(doc) }
    private var corrections: [FinAuditEntry] {
        doc.audit.filter { $0.action == .updated || $0.action == .deleted }.sorted { $0.at > $1.at }
    }

    var body: some View {
        FinPage(title: "Audit & reconciliation",
                sub: "The integrity dashboard. Every correction keeps its original value.",
                badge: doc.settings.demoMode ? "Demo data" : nil) {

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), spacing: 10)], spacing: 10) {
                ForEach(FinIntegrityKind.allCases) { kind in
                    let matching = issues.filter { $0.kind == kind }
                    FinCard(padding: 12) {
                        HStack {
                            Image(systemName: kind.symbol)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(matching.isEmpty ? Palette.faint : Palette.orange)
                            Spacer()
                            Text("\(matching.reduce(0) { $0 + max(1, $1.transactionIDs.count) })")
                                .font(.system(size: 15, weight: .bold, design: .rounded)).monospacedDigit()
                        }
                        Text(kind.label).font(.system(size: 9.5, weight: .medium)).foregroundStyle(Palette.muted).lineLimit(2)
                    }
                }
            }

            FinSectionTitle(text: "Open items", detail: "\(issues.count)")
            if issues.isEmpty {
                FinCard {
                    FinEmptyState(icon: "checkmark.shield", title: "Ledger is clean",
                                  detail: "No duplicates, uncategorised rows, unmatched transfers, mismatches or missing references were found.")
                }
            } else {
                ForEach(issues) { issue in
                    FinCard {
                        HStack(alignment: .top, spacing: 9) {
                            Image(systemName: issue.kind.symbol)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(issue.severity > 1 ? Palette.negative : Palette.orange)
                                .frame(width: 24, height: 24)
                                .background((issue.severity > 1 ? Palette.negative : Palette.orange).opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(issue.title).font(.system(size: 12.5, weight: .semibold))
                                Text(issue.detail).font(.system(size: 10.5)).foregroundStyle(Palette.muted)
                            }
                            Spacer()
                            reviewControl(issue)
                        }
                    }
                }
            }

            FinSectionTitle(text: "Reconciliations", detail: "\(doc.reconciliations.count)")
            FinCard(padding: 0) {
                if doc.reconciliations.isEmpty {
                    Text("No account has been reconciled yet.").font(.system(size: 11)).foregroundStyle(Palette.muted).padding(14)
                } else {
                    ForEach(doc.reconciliations.sorted { $0.periodEnd > $1.periodEnd }) { r in
                        HStack {
                            Image(systemName: r.status == .matched ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .font(.system(size: 10)).foregroundStyle(r.status == .matched ? Palette.green : Palette.orange)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(doc.account(r.accountID)?.name ?? "Account").font(.system(size: 11, weight: .medium))
                                Text("\(FinanceFormat.date(r.periodEnd)) · counted \(FinanceFormat.inr(r.computedClosingPaise)) / statement \(FinanceFormat.inr(r.closingPaise))")
                                    .font(.system(size: 9)).foregroundStyle(Palette.muted)
                            }
                            Spacer()
                            FinBadge(text: r.status.label, tint: r.status == .matched ? Palette.green : Palette.orange)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                    }
                }
            }

            FinSectionTitle(text: "Correction history", detail: "\(corrections.count)")
            FinCard(padding: 0) {
                if corrections.isEmpty {
                    Text("No corrections. Nothing has been edited or deleted.").font(.system(size: 11)).foregroundStyle(Palette.muted).padding(14)
                } else {
                    ForEach(corrections.prefix(40)) { a in
                        HStack(alignment: .top, spacing: 9) {
                            Image(systemName: a.action == .deleted ? "trash" : "pencil")
                                .font(.system(size: 9)).foregroundStyle(a.action == .deleted ? Palette.negative : Palette.orange).frame(width: 16)
                            VStack(alignment: .leading, spacing: 1) {
                                HStack {
                                    Text("\(a.entityType.capitalized) · \(a.field ?? a.action.label)")
                                        .font(.system(size: 10.5, weight: .semibold))
                                    Spacer()
                                    Text(a.at).font(.system(size: 8.5, design: .monospaced)).foregroundStyle(Palette.faint)
                                }
                                if let o = a.oldValue, let n = a.newValue {
                                    Text("\(o) → \(n)").font(.system(size: 10)).foregroundStyle(Palette.muted)
                                }
                                if !a.reason.isEmpty {
                                    Text(a.reason).font(.system(size: 9)).foregroundStyle(Palette.faint)
                                }
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 6)
                    }
                }
            }

            FinCard {
                FinCardHeader("Immutable by design", icon: "lock.shield")
                Text("Corrections append a new audit entry with the previous value, the new value, who made it, when, and why. Deleting a transaction writes its full snapshot into the audit log. Imported values are never silently replaced.")
                    .font(.system(size: 10.5)).foregroundStyle(Palette.muted)
            }
        }
        .sheet(item: $issue) { i in
            FinIssueReviewSheet(issue: i).environmentObject(state)
        }
        .sheet(item: $duplicates) { g in
            FinDuplicateReviewSheet(group: g).environmentObject(state)
        }
    }

    @ViewBuilder
    private func reviewControl(_ issue: FinIntegrityIssue) -> some View {
        switch issue.kind {
        case .unmatchedTransfer:
            FinDestinationLink(destination: .transfers, selection: $selection) {
                reviewLabel
            }
        case .closingMismatch, .openingMismatch:
            FinDestinationLink(destination: .accounts, selection: $selection) {
                reviewLabel
            }
        case .unreconciled:
            FinDestinationLink(destination: .statements, selection: $selection) {
                reviewLabel
            }
        default:
            Button { review(issue) } label: { reviewLabel }
                .buttonStyle(.plain)
        }
    }

    private var reviewLabel: some View {
        Text("Review").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.green)
    }

    private func review(_ issue: FinIntegrityIssue) {
        switch issue.kind {
        case .duplicate:
            if let group = FinanceEngine.duplicateGroups(doc).first { duplicates = group }
        default:
            self.issue = issue
        }
    }
}

struct FinIssueReviewSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let issue: FinIntegrityIssue
    @State private var categoryID = ""
    @State private var detailID: String?

    private var transactions: [FinTransaction] {
        state.finance.transactions.filter { issue.transactionIDs.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            FinSheetHeader(title: issue.title, sub: "\(transactions.count) records",
                           saveTitle: "Done", save: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    FinCard {
                        Text(issue.detail).font(.system(size: 11.5)).foregroundStyle(Palette.muted)
                    }
                    if issue.kind == .uncategorised {
                        FinCard {
                            FinCardHeader("Bulk categorise", icon: "tag")
                            FinPickerCard(label: "Category") {
                                Picker("Category", selection: $categoryID) {
                                    Text("Choose").tag("")
                                    ForEach(state.finance.categories.filter { !$0.archived && $0.kind == .expense }) { c in
                                        Text(c.displayName).tag(c.id)
                                    }
                                }
                                .labelsHidden().pickerStyle(.menu)
                            }
                            FinPrimaryButton(title: "Apply to \(transactions.count)", icon: "checkmark",
                                             enabled: !categoryID.isEmpty) {
                                state.financeBulkUpdate(ids: Set(transactions.map(\.id)), categoryID: categoryID,
                                                        reason: "Categorised from audit review")
                                dismiss()
                            }
                        }
                    }
                    if issue.kind == .unverified || issue.kind == .missingReference || issue.kind == .invalidDate {
                        FinCard {
                            HStack {
                                FinPrimaryButton(title: "Mark all verified", icon: "checkmark.seal") {
                                    state.financeBulkUpdate(ids: Set(transactions.map(\.id)), verification: .verified,
                                                            reason: "Verified from audit review")
                                    dismiss()
                                }
                                Spacer()
                            }
                        }
                    }
                    ForEach(transactions.prefix(50)) { t in
                        FinCard(padding: 12) {
                            Button { detailID = t.id } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(t.title).font(.system(size: 11.5, weight: .medium))
                                        Text("\(FinanceFormat.date(t.date)) · \(FinanceFormat.inr(t.amountPaise)) · \(t.verification.label)")
                                            .font(.system(size: 9.5)).foregroundStyle(Palette.muted)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(Palette.faint)
                                }
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(18)
            }
        }
        .background(Palette.background)
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 560)
        #endif
        .sheet(item: Binding(get: { detailID.map(FinIDBox.init) }, set: { detailID = $0?.id })) { box in
            FinTransactionDetailSheet(id: box.id).environmentObject(state)
        }
    }
}

struct FinDuplicateReviewSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let group: FinDuplicateGroup
    @State private var keepID = ""

    var body: some View {
        VStack(spacing: 0) {
            FinSheetHeader(title: "Duplicate candidates", sub: group.reason, saveTitle: "Done", save: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    FinCard {
                        Text("Choose the record to keep. Any others are deleted with a full audit snapshot; nothing is merged silently.")
                            .font(.system(size: 11)).foregroundStyle(Palette.muted)
                    }
                    ForEach(group.transactions) { t in
                        Button { keepID = t.id } label: {
                            HStack(spacing: 10) {
                                Image(systemName: keepID == t.id ? "largecircle.fill.circle" : "circle")
                                    .foregroundStyle(keepID == t.id ? Palette.green : Palette.muted)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(t.title).font(.system(size: 12, weight: .medium))
                                    Text("\(FinanceFormat.date(t.date)) · \(FinanceFormat.inr(t.amountPaise)) · \(state.finance.account(t.accountID)?.name ?? "—")")
                                        .font(.system(size: 9.5)).foregroundStyle(Palette.muted)
                                    Text(t.id).font(.system(size: 8, design: .monospaced)).foregroundStyle(Palette.faint)
                                }
                                Spacer()
                                FinBadge(text: t.source.label, tint: Palette.blue)
                            }
                            .padding(12)
                            .background(FinStyle.surface, in: RoundedRectangle(cornerRadius: 12))
                            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(keepID == t.id ? Palette.green.opacity(0.4) : FinStyle.border) }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                    HStack(spacing: 8) {
                        FinPrimaryButton(title: "Delete the others", icon: "trash", enabled: !keepID.isEmpty) {
                            for t in group.transactions where t.id != keepID {
                                state.financeDeleteTransaction(t.id, reason: "Duplicate of \(keepID) — resolved in audit review")
                            }
                            dismiss()
                        }
                        FinPrimaryButton(title: "Keep both", icon: "checkmark") {
                            state.financeBulkUpdate(ids: Set(group.transactions.map(\.id)), verification: .verified,
                                                    reason: "Reviewed: both records are legitimate")
                            dismiss()
                        }
                    }
                }
                .padding(18)
            }
        }
        .background(Palette.background)
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 460)
        #endif
    }
}

// MARK: - Finance settings

struct MeFinanceSettings: View {
    @EnvironmentObject var state: AppState
    @State private var draft = FinSettings()
    @State private var loaded = false
    @State private var addingCategory = false
    @State private var editingCategory: FinCategory?
    @State private var demoReset = false
    @State private var export: FinURLBox?

    private var doc: FinanceDocument { state.finance }

    var body: some View {
        FinPage(title: "Finance settings",
                sub: "Preferences, taxonomy and the demo dataset",
                badge: doc.settings.demoMode ? "Demo data" : nil) {

            FinCard {
                FinCardHeader("Tracking", sub: "The baseline for all history", icon: "calendar")
                HStack(spacing: 10) {
                    DatePicker("Tracking start", selection: Binding(get: { FinanceCal.date(draft.trackingStartDate) ?? .now },
                                                                    set: { draft.trackingStartDate = FinanceCal.key($0) }),
                               displayedComponents: .date)
                        .font(.system(size: 11))
                    DatePicker("Date of birth", selection: Binding(get: { draft.birthDate.flatMap(FinanceCal.date) ?? .now },
                                                                   set: { draft.birthDate = FinanceCal.key($0) }),
                               displayedComponents: .date)
                        .font(.system(size: 11))
                }
                if let age = FinanceCal.age(on: draft.trackingStartDate, born: draft.birthDate) {
                    Text("Tracking begins at age \(age). Nothing before this date is implied.")
                        .font(.system(size: 9.5)).foregroundStyle(Palette.muted)
                } else {
                    Text("The timeline begins here. Nothing before the tracking start is implied.")
                        .font(.system(size: 9.5)).foregroundStyle(Palette.faint)
                }
                FinToggleRow(label: "Include household debt in personal net worth",
                             detail: "Off by default. Only debt you are responsible for should reduce your net worth.",
                             isOn: Binding(get: { draft.includeHouseholdInNetWorth },
                                           set: { draft.includeHouseholdInNetWorth = $0 }))
                FinToggleRow(label: "Hide balances",
                             detail: "Replaces figures with dots when someone can see the screen.",
                             isOn: Binding(get: { draft.hideBalances }, set: { draft.hideBalances = $0 }))
                HStack(spacing: 10) {
                    FinField(label: "Emergency fund target (months)",
                             placeholder: "6",
                             text: Binding(get: { String(draft.emergencyFundMonths) },
                                           set: { draft.emergencyFundMonths = max(1, min(24, Int($0) ?? 6)) }),
                             keyboard: .numberPad)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("CURRENCY").font(.system(size: 9, weight: .bold)).tracking(0.8).foregroundStyle(Palette.faint)
                        HStack {
                            Text("INR · en_IN · Asia/Kolkata").font(.system(size: 13))
                            Spacer()
                            Image(systemName: "lock.fill").font(.system(size: 9)).foregroundStyle(Palette.faint)
                        }
                        .padding(.horizontal, 12).frame(height: 40)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(FinStyle.elevated, in: RoundedRectangle(cornerRadius: 10))
                        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(FinStyle.border) }
                    }
                }
                HStack {
                    FinPrimaryButton(title: "Save preferences", icon: "checkmark") {
                        state.financeUpdateSettings(draft)
                    }
                    Spacer()
                    Text("Stored in the encrypted synced document")
                        .font(.system(size: 9)).foregroundStyle(Palette.faint)
                }
            }

            FinCard {
                FinCardHeader("Demo data", sub: "Clearly fictional, never mixed with real records", icon: "testtube.2")
                Text(doc.settings.demoMode
                     ? "Demo mode is active. All demo rows are flagged and can be removed without touching anything you recorded."
                     : doc.isEmpty ? "This document is empty. You can load a fully labelled demo to explore every screen." : "Demo data is unavailable because this document already holds records. Export or clear them first.")
                    .font(.system(size: 10.5)).foregroundStyle(Palette.muted)
                HStack(spacing: 8) {
                    FinPrimaryButton(title: "Load demo", icon: "testtube.2",
                                     enabled: doc.isEmpty || doc.settings.demoMode) {
                        state.financeLoadDemo()
                    }
                    Button { demoReset = true } label: {
                        Text("Remove demo data").font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(doc.hasDemoRecords ? Palette.orange : Palette.faint)
                            .padding(.horizontal, 14).frame(height: 36)
                            .background(FinStyle.elevated, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!doc.hasDemoRecords)
                }
            }

            FinCard {
                FinCardHeader("Categories", sub: "\(doc.categories.filter { !$0.archived }.count) active", icon: "tag") {
                    Button { addingCategory = true } label: {
                        Image(systemName: "plus").font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                }
                ForEach(FinCategoryKind.allCases) { kind in
                    let cats = doc.categories.filter { $0.kind == kind }.sorted { ($0.archived ? 1 : 0, $0.group, $0.name) < ($1.archived ? 1 : 0, $1.group, $1.name) }
                    Text(kind.label.uppercased()).font(.system(size: 8.5, weight: .bold)).tracking(0.8).foregroundStyle(Palette.faint).padding(.top, 4)
                    ForEach(cats) { c in
                        HStack {
                            Image(systemName: c.icon).font(.system(size: 9)).foregroundStyle(Palette.muted).frame(width: 16)
                            Text(c.name).font(.system(size: 11, weight: .medium))
                            Text(c.group).font(.system(size: 9)).foregroundStyle(Palette.faint)
                            if c.isSystem { Text("seed").font(.system(size: 8)).foregroundStyle(Palette.faint) }
                            if c.archived { FinBadge(text: "archived", tint: Palette.muted) }
                            Spacer()
                            Menu {
                                Button("Edit") { editingCategory = c }
                                Button(c.archived ? "Restore" : "Archive") { state.financeArchiveCategory(c.id) }
                            } label: {
                                Image(systemName: "ellipsis").font(.system(size: 10)).frame(width: 24, height: 20)
                            }
                            .menuIndicator(.hidden)
                        }
                        .padding(.vertical, 2)
                        .opacity(c.archived ? 0.45 : 1)
                    }
                }
            }

            FinCard {
                FinCardHeader("Data model", sub: "Schema v\(doc.schemaVersion)", icon: "cylinder.split.1x2")
                HStack(spacing: 18) {
                    count("Accounts", doc.accounts.count)
                    count("Transactions", doc.transactions.count)
                    count("Investments", doc.investments.count)
                    count("Liabilities", doc.liabilities.count)
                    count("Audit entries", doc.audit.count)
                }
                Text("Every record has a stable ID and belongs to the encrypted document. Money is stored in integer paise; dates are timezone-safe ISO keys in Asia/Kolkata.")
                    .font(.system(size: 9.5)).foregroundStyle(Palette.faint)
            }

            FinCard {
                FinCardHeader("Export", icon: "square.and.arrow.up")
                Text("Exports include raw records, not derived totals. The audit log stays in the synced document.")
                    .font(.system(size: 10.5)).foregroundStyle(Palette.muted)
                HStack(spacing: 8) {
                    FinPrimaryButton(title: "Transactions CSV", icon: "tablecells") {
                        if let url = FinExport.write(FinanceEngine.transactionsCSV(doc.transactions, doc: doc), name: "meos-transactions") {
                            export = FinURLBox(url: url)
                        }
                    }
                    FinPrimaryButton(title: "Accounts CSV", icon: "building.columns") {
                        if let url = FinExport.write(FinanceEngine.accountsCSV(doc), name: "meos-accounts") {
                            export = FinURLBox(url: url)
                        }
                    }
                }
            }

            FinCard {
                FinCardHeader("Keyboard", sub: "Mac", icon: "keyboard")
                ForEach([
                    ("⌘K", "Search all finance"),
                    ("⌘N", "New transaction"),
                    ("⌘F", "Search within transactions"),
                    ("⇧⌘E", "Export current records"),
                    ("↑ ↓", "Move through the transaction table"),
                    ("Return", "Open the highlighted record"),
                    ("Esc", "Close a sheet"),
                ], id: \.0) { pair in
                    HStack {
                        Text(pair.0).font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(FinStyle.elevated, in: RoundedRectangle(cornerRadius: 4))
                        Text(pair.1).font(.system(size: 10.5)).foregroundStyle(Palette.muted)
                        Spacer()
                    }
                }
            }

            FinCard {
                FinCardHeader("Privacy", icon: "lock.shield")
                Text("Finance is stored inside the same zero-knowledge, encrypted MeOS document as every other module. Account numbers are not collected. No financial record is sent to an AI provider unless you explicitly ask a question, and tools return aggregates or matching rows without bank credentials.")
                    .font(.system(size: 10.5)).foregroundStyle(Palette.muted)
            }
        }
        .sheet(isPresented: $addingCategory) { FinCategoryEditor().environmentObject(state) }
        .sheet(item: $editingCategory) { c in FinCategoryEditor(editing: c).environmentObject(state) }
        .sheet(item: $export) { box in FinShareSheet(url: box.url) }
        .confirmationDialog("Remove all demo records?", isPresented: $demoReset, titleVisibility: .visible) {
            Button("Remove demo data", role: .destructive) { state.financeResetDemo() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Only rows flagged as demo are removed. Records you created are preserved.")
        }
        .onAppear {
            if !loaded { draft = state.finance.settings; loaded = true }
        }
        .onChange(of: draft) { _, next in
            guard loaded else { return }
            state.financeUpdateSettings(next)
        }
    }

    private func count(_ label: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased()).font(.system(size: 7.5, weight: .bold)).tracking(0.5).foregroundStyle(Palette.faint)
            Text("\(value)").font(.system(size: 15, weight: .bold, design: .rounded)).monospacedDigit()
        }
    }
}
