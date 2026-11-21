import SwiftUI
import Charts

// MARK: - Investments

struct MeFinanceInvestments: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var signals = FinanceSignals.shared
    @State private var adding = false
    @State private var detailID: String?
    @State private var range: FinRangePreset = .y1

    private var doc: FinanceDocument { state.finance }
    private var summaries: [FinInvestmentSummary] { FinanceEngine.investmentSummaries(doc) }
    private var portfolio: (value: Int64, invested: Int64, unrealised: Int64, certainty: FinCertainty, allocation: [FinAllocationSlice]) {
        FinanceEngine.portfolio(doc)
    }

    var body: some View {
        let p = portfolio
        let history = FinanceEngine.portfolioHistory(
            doc,
            monthEnds: FinanceCal.months(from: FinanceEngine.rangeStart(range, doc: doc) ?? FinanceCal.addMonths(-12, to: FinanceCal.today()),
                                         through: FinanceCal.today()).map { FinanceCal.monthEnd($0) }
        )
        let returnPct = p.invested > 0 ? Double(p.unrealised) / Double(p.invested) * 100 : nil
        let realised = doc.investments.reduce(Int64(0)) { $0 + $1.realisedGainPaise }
        let income = doc.investments.reduce(Int64(0)) { $0 + $1.dividendsPaise + $1.interestPaise }

        FinPage(title: "Investments",
                sub: "Capital, current value and return. Manual valuations until a verified market feed exists.",
                badge: doc.settings.demoMode ? "Demo data" : nil) {

            #if os(macOS)
            HStack {
                FinRangeBar(selection: $range)
                Spacer()
                FinPrimaryButton(title: "Add holding", icon: "plus") { adding = true }
            }
            #else
            VStack(alignment: .leading, spacing: 8) {
                ScrollView(.horizontal) { FinRangeBar(selection: $range) }.scrollIndicators(.hidden)
                HStack { Spacer(); FinPrimaryButton(title: "Add holding", icon: "plus") { adding = true } }
            }
            #endif

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                FinStatTile(label: "Portfolio value", value: FinanceFormat.inr(p.value), sub: p.certainty.label, icon: "chart.line.uptrend.xyaxis")
                FinStatTile(label: "Invested capital", value: FinanceFormat.inr(p.invested), sub: "\(summaries.count) holdings", icon: "banknote")
                FinStatTile(label: p.unrealised >= 0 ? "Unrealised gain" : "Unrealised loss",
                            value: FinanceFormat.inr(p.unrealised, showSign: true),
                            sub: returnPct.map { FinanceFormat.signedPercent($0) } ?? "No cost basis", icon: "arrow.up.right")
                FinStatTile(label: "Realised + income", value: FinanceFormat.inr(realised + income),
                            sub: "Recorded sales, dividends, interest", icon: "checkmark.circle")
            }

            #if os(macOS)
            HStack(alignment: .top, spacing: 12) {
                historyCard(history, p: p).frame(maxWidth: .infinity)
                allocationCard(p.allocation, total: p.value).frame(maxWidth: .infinity)
            }
            #else
            historyCard(history, p: p)
            allocationCard(p.allocation, total: p.value)
            #endif

            FinSectionTitle(text: "Holdings", detail: "\(summaries.count)")
            FinCard(padding: 0) {
                if summaries.isEmpty {
                    FinEmptyState(icon: "chart.line.uptrend.xyaxis", title: "No holdings",
                                  detail: "Add a mutual fund, equity, gold or deposit with what you put in and what it is worth. A valuation is a dated fact, not a guess.") {
                        FinPrimaryButton(title: "Add holding", icon: "plus") { adding = true }
                    }
                } else {
                    #if os(macOS)
                    VStack(spacing: 0) {
                        HStack(spacing: 8) {
                            Text("HOLDING").frame(maxWidth: .infinity, alignment: .leading)
                            Text("INVESTED").frame(width: 90, alignment: .trailing)
                            Text("VALUE").frame(width: 90, alignment: .trailing)
                            Text("GAIN").frame(width: 90, alignment: .trailing)
                            Text("RETURN").frame(width: 58, alignment: .trailing)
                        }
                        .font(.system(size: 8.5, weight: .bold)).tracking(0.7).foregroundStyle(Palette.faint)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(Palette.surfaceElevated)
                        ForEach(Array(summaries.enumerated()), id: \.element.id) { index, s in
                            Button { detailID = s.investment.id } label: {
                                HStack(spacing: 8) {
                                    HStack(spacing: 8) {
                                        Image(systemName: s.investment.assetClass.icon)
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(Palette.muted).frame(width: 18)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(s.investment.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                            HStack(spacing: 4) {
                                                Text(s.investment.assetClass.shortLabel)
                                                if !s.investment.institution.isEmpty { Text("· \(s.investment.institution)") }
                                                if s.investment.isDemo { Text("· demo") }
                                                Text("· \(s.certainty.label)")
                                            }
                                            .font(.system(size: 8.5)).foregroundStyle(Palette.faint).lineLimit(1)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                    Text(FinanceFormat.compact(s.investedPaise)).font(.system(size: 10.5)).monospacedDigit().frame(width: 90, alignment: .trailing)
                                    Text(FinanceFormat.compact(s.valuePaise)).font(.system(size: 10.5, weight: .semibold)).monospacedDigit().frame(width: 90, alignment: .trailing)
                                    Text(FinanceFormat.compact(s.unrealisedPaise)).font(.system(size: 10.5, weight: .semibold)).monospacedDigit()
                                        .foregroundStyle(FinStyle.moneyColor(s.unrealisedPaise)).frame(width: 90, alignment: .trailing)
                                    Text(s.returnPercent.map { FinanceFormat.signedPercent($0) } ?? "—")
                                        .font(.system(size: 10, weight: .medium)).monospacedDigit()
                                        .foregroundStyle(FinStyle.changeColor(s.returnPercent)).frame(width: 58, alignment: .trailing)
                                }
                                .padding(.horizontal, 14).padding(.vertical, 9)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            if index < summaries.count - 1 {
                                Rectangle().fill(FinStyle.border).frame(height: 1).padding(.leading, 40)
                            }
                        }
                    }
                    #else
                    VStack(spacing: 0) {
                        ForEach(Array(summaries.enumerated()), id: \.element.id) { index, s in
                            Button { detailID = s.investment.id } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Image(systemName: s.investment.assetClass.icon)
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(Palette.muted).frame(width: 16)
                                        Text(s.investment.name).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                                        Spacer()
                                        Text(FinanceFormat.compact(s.valuePaise)).font(.system(size: 12, weight: .semibold)).monospacedDigit()
                                    }
                                    HStack(spacing: 8) {
                                        Text("Invested \(FinanceFormat.compact(s.investedPaise))")
                                        Text("Gain \(FinanceFormat.compact(s.unrealisedPaise))")
                                            .foregroundStyle(FinStyle.moneyColor(s.unrealisedPaise))
                                        Spacer()
                                        Text(s.returnPercent.map { FinanceFormat.signedPercent($0) } ?? "—")
                                            .foregroundStyle(FinStyle.changeColor(s.returnPercent))
                                        FinBadge(text: s.certainty.label, tint: FinStyle.certaintyColor(s.certainty))
                                    }
                                    .font(.system(size: 9.5)).foregroundStyle(Palette.muted)
                                    Text([s.investment.assetClass.shortLabel, s.investment.institution, s.investment.isDemo ? "demo" : ""]
                                        .filter { !$0.isEmpty }.joined(separator: " · "))
                                        .font(.system(size: 8.5)).foregroundStyle(Palette.faint)
                                }
                                .padding(.horizontal, 12).padding(.vertical, 10)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            if index < summaries.count - 1 {
                                Rectangle().fill(FinStyle.border).frame(height: 1).padding(.leading, 12)
                            }
                        }
                    }
                    #endif
                }
            }

            FinCard {
                FinCardHeader("Data honesty", icon: "info.circle")
                Text("There is no live market feed connected. Values come only from dated valuations you record or from a statement. Carried-forward values are marked estimated everywhere they appear.")
                    .font(.system(size: 10.5)).foregroundStyle(Palette.muted)
            }
        }
        .sheet(isPresented: $adding) { FinInvestmentEditor(investment: nil).environmentObject(state) }
        .sheet(item: Binding(get: { detailID.map(FinIDBox.init) }, set: { detailID = $0?.id })) { box in
            NavigationStack { FinInvestmentDetail(investmentID: box.id).environmentObject(state) }
                #if os(macOS)
                .frame(minWidth: 720, minHeight: 700)
                #endif
        }
        .onAppear {
            if signals.quickAddInvestment { signals.quickAddInvestment = false; adding = true }
        }
    }

    private func historyCard(_ points: [FinNetWorthPoint], p: (value: Int64, invested: Int64, unrealised: Int64, certainty: FinCertainty, allocation: [FinAllocationSlice])) -> some View {
        FinCard {
            FinCardHeader("Portfolio history", sub: "Recorded valuations only", icon: "chart.xyaxis.line")
            if points.count < 2 {
                FinEmptyState(icon: "chart.xyaxis.line", title: "Not enough valuations",
                              detail: "Record at least two dated valuations to show a line.")
                    .frame(height: 165)
            } else {
                FinNetWorthChart(points: points, height: 165)
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("VALUE").font(.system(size: 8, weight: .bold)).tracking(0.6).foregroundStyle(Palette.faint)
                        Text(FinanceFormat.inr(p.value)).font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("INVESTED").font(.system(size: 8, weight: .bold)).tracking(0.6).foregroundStyle(Palette.faint)
                        Text(FinanceFormat.inr(p.invested)).font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
                    }
                    Spacer()
                    FinBadge(text: p.certainty.label, tint: FinStyle.certaintyColor(p.certainty), icon: p.certainty.icon)
                }
            }
        }
    }

    private func allocationCard(_ allocation: [FinAllocationSlice], total: Int64) -> some View {
        FinCard {
            FinCardHeader("Asset allocation", sub: "\(allocation.count) classes", icon: "chart.pie")
            if allocation.isEmpty {
                FinEmptyState(icon: "chart.pie", title: "No allocation", detail: "Add a holding to see the mix.")
                    .frame(height: 165)
            } else {
                ForEach(Array(allocation.prefix(7).enumerated()), id: \.element.id) { i, a in
                    VStack(spacing: 4) {
                        HStack {
                            HStack(spacing: 5) {
                                Circle().fill(FinStyle.sliceColor(i)).frame(width: 5, height: 5)
                                Text(a.assetClass.label).font(.system(size: 10.5, weight: .medium))
                            }
                            Spacer()
                            Text(FinanceFormat.percent(a.share, decimals: 0)).font(.system(size: 9.5)).foregroundStyle(Palette.muted)
                            Text(FinanceFormat.compact(a.paise)).font(.system(size: 10, weight: .semibold)).monospacedDigit()
                                .frame(width: 64, alignment: .trailing)
                        }
                        GeometryReader { g in
                            Capsule().fill(Palette.text.opacity(0.06))
                                .overlay(alignment: .leading) {
                                    Capsule().fill(FinStyle.sliceColor(i)).frame(width: max(3, g.size.width * a.share / 100))
                                }
                        }
                        .frame(height: 4)
                    }
                }
            }
        }
    }
}

// MARK: Investment detail

struct FinInvestmentDetail: View {
    @EnvironmentObject var state: AppState
    let investmentID: String
    @State private var edit = false
    @State private var valuation = false
    @State private var buy = false
    @State private var sell = false
    @State private var detailID: String?

    private var doc: FinanceDocument { state.finance }
    private var investment: FinInvestment? { doc.investment(investmentID) }

    var body: some View {
        if let inv = investment {
            let value = FinanceEngine.investmentValue(doc, investment: inv)
            let gain = value.paise - inv.investedPaise
            let pct = inv.investedPaise > 0 ? Double(gain) / Double(inv.investedPaise) * 100 : nil
            let valuations = doc.valuations.filter { $0.investmentID == investmentID }.sorted { $0.date > $1.date }
            let linked = doc.transactions.filter { $0.investmentID == investmentID }.sorted { $0.date > $1.date }
            let history = valuationHistory(valuations, fallback: inv)

            FinPage(title: inv.name,
                    sub: [inv.assetClass.label, inv.institution].filter { !$0.isEmpty }.joined(separator: " · "),
                    badge: inv.isDemo ? "Demo data" : nil) {

                FinCard {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("CURRENT VALUE").font(.system(size: 9, weight: .bold)).tracking(0.9).foregroundStyle(Palette.faint)
                            Text(FinanceFormat.inr(value.paise)).font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit()
                                .minimumScaleFactor(0.6).lineLimit(1)
                            HStack(spacing: 5) {
                                FinBadge(text: value.certainty.label, tint: FinStyle.certaintyColor(value.certainty), icon: value.certainty.icon)
                                Text("valued \(FinanceFormat.date(latestValuationDate(valuations, fallback: inv)))")
                                    .font(.system(size: 9.5)).foregroundStyle(Palette.faint)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            Text("INVESTED").font(.system(size: 8, weight: .bold)).tracking(0.7).foregroundStyle(Palette.faint)
                            Text(FinanceFormat.inr(inv.investedPaise)).font(.system(size: 14, weight: .semibold, design: .rounded)).monospacedDigit()
                            Text(gain >= 0 ? "UNREALISED GAIN" : "UNREALISED LOSS").font(.system(size: 8, weight: .bold)).tracking(0.7).foregroundStyle(Palette.faint)
                            Text(FinanceFormat.inr(gain, showSign: true)).font(.system(size: 16, weight: .bold, design: .rounded)).monospacedDigit()
                                .foregroundStyle(FinStyle.moneyColor(gain))
                            if let pct { Text(FinanceFormat.signedPercent(pct)).font(.system(size: 10, weight: .semibold)).foregroundStyle(FinStyle.moneyColor(gain)) }
                        }
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], alignment: .leading, spacing: 8) {
                        FinPrimaryButton(title: "Valuation", icon: "calendar.badge.clock") { valuation = true }
                        FinPrimaryButton(title: "Buy", icon: "plus") { buy = true }
                        FinPrimaryButton(title: "Sell", icon: "minus") { sell = true }
                        FinPrimaryButton(title: "Edit", icon: "pencil") { edit = true }
                        Menu {
                            Button(inv.archived ? "Restore" : "Archive") {
                                state.financeArchiveInvestment(inv.id, archived: !inv.archived)
                            }
                            let linkedCount = doc.transactions.filter { $0.investmentID == inv.id }.count
                            Button(linkedCount == 0 ? "Delete holding" : "Delete holding (has transactions)",
                                   role: .destructive) {
                                state.financeDeleteInvestment(inv.id)
                            }
                            .disabled(linkedCount > 0)
                        } label: {
                            Image(systemName: "ellipsis").font(.system(size: 11, weight: .semibold))
                                .frame(width: 32, height: 32).background(FinStyle.elevated, in: Circle())
                        }
                        .menuIndicator(.hidden)
                    }
                }

                FinCard {
                    FinCardHeader("Valuation history", sub: "Every point is a dated record", icon: "chart.xyaxis.line")
                    if history.count < 2 {
                        Text("Not enough dated valuations yet.").font(.system(size: 11)).foregroundStyle(Palette.muted)
                    } else {
                        FinNetWorthChart(points: history, height: 165)
                    }
                }

                FinCard {
                    FinCardHeader("Holding", icon: "doc.text")
                    row("Asset class", inv.assetClass.label)
                    if let units = inv.units { row("Units", String(format: "%.4f", units)) }
                    if let price = inv.purchasePricePaise { row("Avg purchase price", FinanceFormat.inr(price, decimals: true)) }
                    if let date = inv.purchaseDate { row("First purchase", FinanceFormat.date(date)) }
                    row("Invested capital", FinanceFormat.inr(inv.investedPaise))
                    row("Realised gain", FinanceFormat.inr(inv.realisedGainPaise, showSign: true))
                    row("Dividends recorded", FinanceFormat.inr(inv.dividendsPaise))
                    row("Interest recorded", FinanceFormat.inr(inv.interestPaise))
                    if !inv.notes.isEmpty { row("Notes", inv.notes) }
                }

                FinSectionTitle(text: "Valuations", detail: "\(valuations.count)")
                FinCard(padding: 0) {
                    if valuations.isEmpty {
                        Text("No dated valuations. The current value is a manual figure and is marked accordingly.")
                            .font(.system(size: 11)).foregroundStyle(Palette.muted).padding(14)
                    } else {
                        ForEach(Array(valuations.enumerated()), id: \.element.id) { index, v in
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(FinanceFormat.date(v.date)).font(.system(size: 11.5, weight: .medium))
                                    Text([v.source.label, v.note].filter { !$0.isEmpty }.joined(separator: " · "))
                                        .font(.system(size: 9)).foregroundStyle(Palette.faint)
                                }
                                Spacer()
                                FinMoneyText(paise: v.valuePaise, size: 12)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            if index < valuations.count - 1 {
                                Rectangle().fill(FinStyle.border).frame(height: 1).padding(.leading, 12)
                            }
                        }
                    }
                }

                FinSectionTitle(text: "Linked transactions", detail: "\(linked.count)")
                FinCard(padding: 0) {
                    if linked.isEmpty {
                        Text("No purchases or sales linked to this holding.").font(.system(size: 11)).foregroundStyle(Palette.muted).padding(14)
                    } else {
                        ForEach(Array(linked.enumerated()), id: \.element.id) { index, t in
                            Button { detailID = t.id } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(t.title).font(.system(size: 11.5, weight: .medium))
                                        Text("\(FinanceFormat.date(t.date)) · \(t.type.label)")
                                            .font(.system(size: 9)).foregroundStyle(Palette.muted)
                                    }
                                    Spacer()
                                    Text(t.direction == .inflow ? "+" : "−")
                                    FinMoneyText(paise: t.amountPaise, size: 11.5)
                                }
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            if index < linked.count - 1 { Rectangle().fill(FinStyle.border).frame(height: 1) }
                        }
                    }
                }
            }
            .sheet(isPresented: $edit) { FinInvestmentEditor(investment: inv).environmentObject(state) }
            .sheet(isPresented: $valuation) { FinValuationEditor(investmentID: investmentID, current: value.paise).environmentObject(state) }
            .sheet(isPresented: $buy) { FinInvestmentBuySheet(investmentID: investmentID).environmentObject(state) }
            .sheet(isPresented: $sell) { FinInvestmentSellSheet(investmentID: investmentID, invested: inv.investedPaise).environmentObject(state) }
            .sheet(item: Binding(get: { detailID.map(FinIDBox.init) }, set: { detailID = $0?.id })) { box in
                FinTransactionDetailSheet(id: box.id).environmentObject(state)
            }
        } else {
            FinPage(title: "Investment") {
                FinEmptyState(icon: "questionmark.folder", title: "Holding not found", detail: "It may have been removed.")
            }
        }
    }

    private func latestValuationDate(_ valuations: [FinValuation], fallback: FinInvestment) -> String {
        valuations.first?.date ?? fallback.currentValueOn
    }

    private func valuationHistory(_ valuations: [FinValuation], fallback: FinInvestment) -> [FinNetWorthPoint] {
        var points = valuations.sorted { $0.date < $1.date }.map {
            FinNetWorthPoint(date: $0.date, assetsPaise: $0.valuePaise, liabilitiesPaise: 0,
                             netPaise: $0.valuePaise,
                             certainty: $0.date == FinanceCal.today() ? .verified : .calculated)
        }
        if points.isEmpty, fallback.investedPaise > 0, let bought = fallback.purchaseDate {
            points.append(FinNetWorthPoint(date: bought, assetsPaise: fallback.investedPaise, liabilitiesPaise: 0,
                                           netPaise: fallback.investedPaise, certainty: .calculated))
            points.append(FinNetWorthPoint(date: fallback.currentValueOn, assetsPaise: fallback.currentValuePaise,
                                           liabilitiesPaise: 0, netPaise: fallback.currentValuePaise, certainty: .estimated))
        }
        return points
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top) {
            Text(k).font(.system(size: 10.5)).foregroundStyle(Palette.muted).frame(width: 132, alignment: .leading)
            Text(v).font(.system(size: 11.5)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

// MARK: Investment forms

struct FinInvestmentEditor: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let investment: FinInvestment?
    @State private var name = ""
    @State private var assetClass: FinAssetClass = .mutualFund
    @State private var institution = ""
    @State private var unitsText = ""
    @State private var purchaseDate = Date.now
    @State private var hasPurchaseDate = true
    @State private var purchasePriceText = ""
    @State private var investedText = ""
    @State private var valueText = ""
    @State private var valueDate = Date.now
    @State private var notes = ""

    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            FinSheetHeader(title: investment == nil ? "New holding" : "Edit holding", canSave: canSave) { save() }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    FinCard {
                        FinField(label: "Name", placeholder: "Nifty index fund", text: $name)
                        FinPickerCard(label: "Asset class") {
                            Picker("Asset class", selection: $assetClass) {
                                ForEach(FinAssetClass.allCases) { c in Text(c.label).tag(c) }
                            }
                            .labelsHidden().pickerStyle(.menu)
                        }
                        FinField(label: "Institution / broker", placeholder: "Meridian Invest", text: $institution)
                        FinField(label: "Units (optional)", placeholder: "12.5", text: $unitsText, keyboard: .decimalPad)
                        FinField(label: "Invested capital (₹)", placeholder: "0", text: $investedText, keyboard: .decimalPad)
                        FinField(label: "Current value (₹)", placeholder: "0", text: $valueText, keyboard: .decimalPad)
                        FinToggleRow(label: "Has a purchase date", isOn: $hasPurchaseDate)
                        if hasPurchaseDate {
                            DatePicker("First purchase", selection: $purchaseDate, displayedComponents: .date).font(.system(size: 11))
                        }
                        FinField(label: "Average purchase price (₹, optional)", placeholder: "0", text: $purchasePriceText, keyboard: .decimalPad)
                        DatePicker("Value as of", selection: $valueDate, displayedComponents: .date).font(.system(size: 11))
                        FinField(label: "Notes", placeholder: "Why you hold it", text: $notes, multiline: true)
                    }
                    Text("Saving this creates a dated valuation, not a live price. Returns are calculated from the invested capital you record.")
                        .font(.system(size: 9.5)).foregroundStyle(Palette.faint)
                }
                .padding(18)
            }
        }
        .background(Palette.background)
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 640)
        #endif
        .onAppear {
            guard let i = investment else { return }
            name = i.name; assetClass = i.assetClass; institution = i.institution
            unitsText = i.units.map { String(format: "%.4f", $0) } ?? ""
            if let d = i.purchaseDate { hasPurchaseDate = true; purchaseDate = FinanceCal.date(d) ?? .now }
            purchasePriceText = i.purchasePricePaise.map { String(format: "%.2f", Double($0) / 100) } ?? ""
            investedText = String(format: "%.2f", Double(i.investedPaise) / 100)
            valueText = String(format: "%.2f", Double(i.currentValuePaise) / 100)
            valueDate = FinanceCal.date(i.currentValueOn) ?? .now
            notes = i.notes
        }
    }

    private func save() {
        var next = investment ?? FinInvestment(name: name)
        next.name = name
        next.assetClass = assetClass
        next.institution = institution
        next.units = Double(unitsText.replacingOccurrences(of: ",", with: "."))
        next.purchaseDate = hasPurchaseDate ? FinanceCal.key(purchaseDate) : nil
        next.purchasePricePaise = FinanceFormat.parsePaise(purchasePriceText)
        next.investedPaise = FinanceFormat.parsePaise(investedText) ?? 0
        next.currentValuePaise = FinanceFormat.parsePaise(valueText) ?? max(next.investedPaise, next.currentValuePaise)
        next.currentValueOn = FinanceCal.key(valueDate)
        next.notes = notes
        if investment == nil {
            let created = state.financeAddInvestment(next)
            if (next.currentValuePaise) > 0 {
                state.financeRecordValuation(investmentID: created.id, date: next.currentValueOn,
                                             valuePaise: next.currentValuePaise, source: .manual,
                                             note: "Opening valuation")
            }
        } else {
            state.financeUpdateInvestment(next)
            state.financeRecordValuation(investmentID: next.id, date: next.currentValueOn,
                                         valuePaise: next.currentValuePaise, source: .manual,
                                         note: "Edited from holding")
        }
        dismiss()
    }
}

struct FinValuationEditor: View {
    @EnvironmentObject var state: AppState
    let investmentID: String
    let current: Int64
    @Environment(\.dismiss) private var dismiss
    @State private var valueText = ""
    @State private var date = Date.now
    @State private var source: FinValuationSource = .manual
    @State private var note = ""

    var body: some View {
        VStack(spacing: 0) {
            FinSheetHeader(title: "Record valuation", sub: "A dated fact",
                           canSave: (FinanceFormat.parsePaise(valueText) ?? 0) > 0) {
                state.financeRecordValuation(investmentID: investmentID, date: FinanceCal.key(date),
                                             valuePaise: FinanceFormat.parsePaise(valueText) ?? 0,
                                             source: source, note: note)
                dismiss()
            }
            VStack(alignment: .leading, spacing: 14) {
                FinField(label: "Value (₹)", placeholder: String(format: "%.2f", Double(current) / 100), text: $valueText, keyboard: .decimalPad)
                DatePicker("As of", selection: $date, displayedComponents: .date).font(.system(size: 11))
                FinPickerCard(label: "Source") {
                    Picker("Source", selection: $source) {
                        ForEach(FinValuationSource.allCases) { s in Text(s.label).tag(s) }
                    }
                    .labelsHidden().pickerStyle(.segmented)
                }
                FinField(label: "Note", placeholder: "Quarterly review", text: $note)
                Text("Use Manual until a verified market provider is connected. Do not enter an assumed price as if it were observed.")
                    .font(.system(size: 9.5)).foregroundStyle(Palette.faint)
                Spacer()
            }
            .padding(18)
        }
        .background(Palette.background)
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 360)
        #endif
        .onAppear { valueText = String(format: "%.2f", Double(current) / 100) }
    }
}

struct FinInvestmentBuySheet: View {
    @EnvironmentObject var state: AppState
    let investmentID: String
    @Environment(\.dismiss) private var dismiss
    @State private var amountText = ""
    @State private var accountID = ""
    @State private var date = Date.now
    @State private var unitsText = ""
    @State private var reference = ""
    @State private var note = ""

    var body: some View {
        VStack(spacing: 0) {
            FinSheetHeader(title: "Buy / add capital", canSave: (FinanceFormat.parsePaise(amountText) ?? 0) > 0 && !accountID.isEmpty) {
                let ok = state.financeRecordInvestmentPurchase(investmentID: investmentID, accountID: accountID,
                                                               amountPaise: FinanceFormat.parsePaise(amountText) ?? 0,
                                                               date: FinanceCal.key(date),
                                                               units: Double(unitsText.replacingOccurrences(of: ",", with: ".")),
                                                               reference: reference, note: note)
                if ok { dismiss() }
            }
            VStack(alignment: .leading, spacing: 14) {
                FinField(label: "Amount (₹)", placeholder: "0", text: $amountText, keyboard: .decimalPad)
                FinPickerCard(label: "From account") {
                    Picker("Account", selection: $accountID) {
                        Text("Choose").tag("")
                        ForEach(state.finance.accounts.filter { $0.status == .active && !$0.type.isLiability }) { a in
                            Text(a.name).tag(a.id)
                        }
                    }
                    .labelsHidden().pickerStyle(.menu)
                }
                HStack(spacing: 10) {
                    FinField(label: "Units (optional)", placeholder: "0", text: $unitsText, keyboard: .decimalPad)
                    DatePicker("Date", selection: $date, displayedComponents: .date).font(.system(size: 11))
                }
                FinField(label: "Reference", placeholder: "Order / SIP reference", text: $reference)
                FinField(label: "Note", placeholder: "", text: $note)
                Text("This records the cash outflow and increases invested capital. It is not an expense.")
                    .font(.system(size: 9.5)).foregroundStyle(Palette.faint)
                Spacer()
            }
            .padding(18)
        }
        .background(Palette.background)
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 460)
        #endif
    }
}

struct FinInvestmentSellSheet: View {
    @EnvironmentObject var state: AppState
    let investmentID: String
    let invested: Int64
    @Environment(\.dismiss) private var dismiss
    @State private var proceedsText = ""
    @State private var costText = ""
    @State private var accountID = ""
    @State private var date = Date.now
    @State private var reference = ""

    var body: some View {
        VStack(spacing: 0) {
            FinSheetHeader(title: "Record a sale", sub: "Realised gain is recorded, never inferred",
                           canSave: (FinanceFormat.parsePaise(proceedsText) ?? 0) > 0 && !accountID.isEmpty) {
                state.financeRecordInvestmentSale(investmentID: investmentID, accountID: accountID,
                                                  proceedsPaise: FinanceFormat.parsePaise(proceedsText) ?? 0,
                                                  costBasisPaise: FinanceFormat.parsePaise(costText) ?? 0,
                                                  date: FinanceCal.key(date), reference: reference)
                dismiss()
            }
            VStack(alignment: .leading, spacing: 14) {
                FinField(label: "Proceeds (₹)", placeholder: "0", text: $proceedsText, keyboard: .decimalPad)
                FinField(label: "Cost basis of sold units (₹)", placeholder: "0", text: $costText, keyboard: .decimalPad)
                FinPickerCard(label: "Into account") {
                    Picker("Account", selection: $accountID) {
                        Text("Choose").tag("")
                        ForEach(state.finance.accounts.filter { $0.status == .active && !$0.type.isLiability }) { a in
                            Text(a.name).tag(a.id)
                        }
                    }
                    .labelsHidden().pickerStyle(.menu)
                }
                DatePicker("Sale date", selection: $date, displayedComponents: .date).font(.system(size: 11))
                FinField(label: "Reference", placeholder: "Contract note", text: $reference)
                Text("Gain = proceeds − cost basis. Only this recorded figure feeds capital-gains reports.")
                    .font(.system(size: 9.5)).foregroundStyle(Palette.faint)
                Spacer()
            }
            .padding(18)
        }
        .background(Palette.background)
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 480)
        #endif
        .onAppear {
            costText = String(format: "%.2f", Double(invested) / 100)
        }
    }
}

// MARK: - Liabilities

struct MeFinanceLiabilities: View {
    @EnvironmentObject var state: AppState
    @State private var adding = false
    @State private var detailID: String?

    private var doc: FinanceDocument { state.finance }
    private var summaries: [FinLiabilitySummary] { FinanceEngine.liabilitySummaries(doc) }

    var body: some View {
        let total = FinanceEngine.totalLiabilities(doc)
        let personal = summaries.filter { $0.liability.ownership == .personal }.reduce(Int64(0)) { $0 + $1.outstandingPaise }
        let household = summaries.filter { $0.liability.ownership != .personal }.reduce(Int64(0)) { $0 + $1.outstandingPaise }
        let emi = summaries.reduce(Int64(0)) { $0 + $1.liability.emiPaise }
        let interest = summaries.reduce(Int64(0)) { $0 + $1.paidInterestPaise }

        FinPage(title: "Liabilities",
                sub: "Debt is shown separately from assets. Household debt is excluded from personal net worth unless you opt in.",
                badge: doc.settings.demoMode ? "Demo data" : nil) {

            HStack {
                Spacer()
                FinPrimaryButton(title: "Add liability", icon: "plus") { adding = true }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                FinStatTile(label: "Total outstanding", value: FinanceFormat.inr(total), sub: "\(summaries.filter { !$0.liability.closed }.count) open", icon: "creditcard")
                FinStatTile(label: "Personal", value: FinanceFormat.inr(personal), sub: "Included in net worth", icon: "person")
                FinStatTile(label: "Household / shared", value: FinanceFormat.inr(household), sub: doc.settings.includeHouseholdInNetWorth ? "Included (opted in)" : "Excluded", icon: "person.2")
                FinStatTile(label: "Monthly EMI", value: FinanceFormat.inr(emi), sub: "Interest paid \(FinanceFormat.inr(interest))", icon: "calendar.badge.clock")
            }

            if summaries.isEmpty {
                FinCard {
                    FinEmptyState(icon: "creditcard", title: "No liabilities recorded",
                                  detail: "A credit card, loan or informal borrowing belongs here. Credit-card debt can be linked to the card account so it is never counted twice.") {
                        FinPrimaryButton(title: "Add liability", icon: "plus") { adding = true }
                    }
                }
            } else {
                ForEach(summaries) { s in
                    Button { detailID = s.liability.id } label: {
                        FinCard {
                            HStack(alignment: .top) {
                                Image(systemName: s.liability.kind.icon)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Palette.negative)
                                    .frame(width: 32, height: 32)
                                    .background(Palette.negative.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(s.liability.name).font(.system(size: 14, weight: .semibold))
                                        FinBadge(text: s.liability.kind.label, tint: Palette.negative)
                                        if s.liability.ownership != .personal { FinBadge(text: s.liability.ownership.label, tint: Palette.orange) }
                                        if s.liability.isDemo { FinBadge(text: "demo", tint: Palette.orange) }
                                    }
                                    Text([s.liability.lender, s.liability.interestRateBps > 0 ? "\(Double(s.liability.interestRateBps) / 100)%" : nil, s.liability.emiPaise > 0 ? "EMI \(FinanceFormat.inr(s.liability.emiPaise))" : nil]
                                        .compactMap { $0 }.joined(separator: " · "))
                                        .font(.system(size: 10)).foregroundStyle(Palette.muted)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(FinanceFormat.inr(s.outstandingPaise)).font(.system(size: 17, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(Palette.negative)
                                    Text("outstanding").font(.system(size: 9)).foregroundStyle(Palette.faint)
                                }
                            }
                            FinProgressBar(progress: s.progress, tint: Palette.green)
                            HStack {
                                Text("\(FinanceFormat.percent(s.progress * 100, decimals: 0)) repaid")
                                if let t = s.tenureMonthsLeft { Text("· \(t) months left") }
                                Spacer()
                                Text("Original \(FinanceFormat.inr(s.liability.originalPrincipalPaise))")
                            }
                            .font(.system(size: 9.5)).foregroundStyle(Palette.faint)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            FinCard {
                FinCardHeader("Ownership, not assumptions", icon: "person.2")
                Text("A loan that belongs to someone else is not your liability. Only personal debt is included by default; household debt requires an explicit switch in Finance Settings.")
                    .font(.system(size: 10.5)).foregroundStyle(Palette.muted)
            }
        }
        .sheet(isPresented: $adding) { FinLiabilityEditor(liability: nil).environmentObject(state) }
        .sheet(item: Binding(get: { detailID.map(FinIDBox.init) }, set: { detailID = $0?.id })) { box in
            NavigationStack { FinLiabilityDetail(liabilityID: box.id).environmentObject(state) }
                #if os(macOS)
                .frame(minWidth: 700, minHeight: 680)
                #endif
        }
    }
}

struct FinLiabilityDetail: View {
    @EnvironmentObject var state: AppState
    let liabilityID: String
    @State private var edit = false
    @State private var pay = false
    @State private var confirmDelete = false

    private var doc: FinanceDocument { state.finance }
    private var liability: FinLiability? { doc.liability(liabilityID) }

    var body: some View {
        if let l = liability {
            let outstanding = FinanceEngine.liabilityOutstanding(doc, liability: l)
            let payments = doc.debtPayments.filter { $0.liabilityID == liabilityID }.sorted { $0.date > $1.date }
            let principalPaid = payments.reduce(Int64(0)) { $0 + $1.principalPaise }
            let interestPaid = payments.reduce(Int64(0)) { $0 + $1.interestPaise }
            let progress = l.originalPrincipalPaise > 0 ? min(1, Double(principalPaid) / Double(l.originalPrincipalPaise)) : 0
            let linkedAccount = doc.account(l.accountID)

            FinPage(title: l.name,
                    sub: [l.kind.label, l.lender].filter { !$0.isEmpty }.joined(separator: " · "),
                    badge: l.isDemo ? "Demo data" : nil) {

                FinCard {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("OUTSTANDING").font(.system(size: 9, weight: .bold)).tracking(0.9).foregroundStyle(Palette.faint)
                            Text(FinanceFormat.inr(outstanding)).font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(Palette.negative)
                                .minimumScaleFactor(0.6).lineLimit(1)
                            Text("as recorded · \(l.ownership.label)").font(.system(size: 9.5)).foregroundStyle(Palette.faint)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            Text("ORIGINAL PRINCIPAL").font(.system(size: 8, weight: .bold)).tracking(0.7).foregroundStyle(Palette.faint)
                            Text(FinanceFormat.inr(l.originalPrincipalPaise)).font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit()
                            Text("\(FinanceFormat.percent(progress * 100, decimals: 0)) repaid").font(.system(size: 9)).foregroundStyle(Palette.muted)
                        }
                    }
                    FinProgressBar(progress: progress, tint: Palette.green, height: 8)
                    HStack(spacing: 8) {
                        if l.kind == .creditCard, linkedAccount != nil {
                            Text("Outstanding is calculated from the linked card account. Record a transfer from a bank account to pay it.")
                                .font(.system(size: 10)).foregroundStyle(Palette.muted)
                        } else {
                            FinPrimaryButton(title: "Record repayment", icon: "plus") { pay = true }
                        }
                        FinPrimaryButton(title: "Edit", icon: "pencil") { edit = true }
                        if l.closed { FinBadge(text: "Closed", tint: Palette.green) }
                        Menu {
                            Button("Delete liability", role: .destructive) { confirmDelete = true }
                        } label: {
                            Image(systemName: "ellipsis").font(.system(size: 11, weight: .semibold))
                                .frame(width: 32, height: 32).background(FinStyle.elevated, in: Circle())
                        }
                        .menuIndicator(.hidden)
                    }
                }

                FinCard {
                    FinCardHeader("Terms", icon: "doc.text")
                    row("Lender", l.lender)
                    row("Interest rate", l.interestRateBps > 0 ? "\(Double(l.interestRateBps) / 100)% p.a." : "Not recorded")
                    row("EMI", l.emiPaise > 0 ? FinanceFormat.inr(l.emiPaise) : "Not recorded")
                    row("Due day", "\(l.dueDay)")
                    row("Start", FinanceFormat.date(l.startDate))
                    if let m = l.maturityDate { row("Maturity", FinanceFormat.date(m)) }
                    row("Principal paid", FinanceFormat.inr(principalPaid))
                    row("Interest paid", FinanceFormat.inr(interestPaid))
                    if let a = linkedAccount { row("Linked account", a.name) }
                    if !l.notes.isEmpty { row("Notes", l.notes) }
                }

                FinSectionTitle(text: "Repayment history", detail: "\(payments.count)")
                FinCard(padding: 0) {
                    if payments.isEmpty {
                        Text("No repayments recorded. Principal reduces the balance; interest is an expense.")
                            .font(.system(size: 11)).foregroundStyle(Palette.muted).padding(14)
                    } else {
                        ForEach(Array(payments.enumerated()), id: \.element.id) { index, p in
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(FinanceFormat.date(p.date)).font(.system(size: 11.5, weight: .medium))
                                    Text("Principal \(FinanceFormat.inr(p.principalPaise)) · interest \(FinanceFormat.inr(p.interestPaise))")
                                        .font(.system(size: 9)).foregroundStyle(Palette.muted)
                                }
                                Spacer()
                                FinMoneyText(paise: p.amountPaise, size: 11.5)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            if index < payments.count - 1 { Rectangle().fill(FinStyle.border).frame(height: 1) }
                        }
                    }
                }
            }
            .sheet(isPresented: $edit) { FinLiabilityEditor(liability: l).environmentObject(state) }
            .sheet(isPresented: $pay) { FinDebtPaymentSheet(liabilityID: liabilityID, suggestedEMI: l.emiPaise).environmentObject(state) }
            .confirmationDialog("Delete this liability?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    state.financeDeleteLiability(liabilityID)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Repayment transactions are kept, but lose their liability link. The audit log records the deletion.")
            }
        } else {
            FinPage(title: "Liability") {
                FinEmptyState(icon: "questionmark.folder", title: "Liability not found", detail: "It may have been removed.")
            }
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top) {
            Text(k).font(.system(size: 10.5)).foregroundStyle(Palette.muted).frame(width: 120, alignment: .leading)
            Text(v).font(.system(size: 11.5)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

struct FinLiabilityEditor: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let liability: FinLiability?
    @State private var name = ""
    @State private var kind: FinLiabilityKind = .personalLoan
    @State private var lender = ""
    @State private var ownership: FinOwnership = .personal
    @State private var originalText = ""
    @State private var outstandingText = ""
    @State private var asOf = Date.now
    @State private var rateText = ""
    @State private var emiText = ""
    @State private var dueDay = 5
    @State private var start = Date.now
    @State private var hasMaturity = false
    @State private var maturity = Date.now
    @State private var accountID = ""
    @State private var notes = ""
    @State private var closed = false

    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            FinSheetHeader(title: liability == nil ? "New liability" : "Edit liability", canSave: canSave) { save() }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    FinCard {
                        FinField(label: "Name", placeholder: "Education loan", text: $name)
                        FinPickerCard(label: "Kind") {
                            Picker("Kind", selection: $kind) {
                                ForEach(FinLiabilityKind.allCases) { k in Text(k.label).tag(k) }
                            }
                            .labelsHidden().pickerStyle(.menu)
                        }
                        FinField(label: "Lender", placeholder: "Northstar Bank", text: $lender)
                        FinPickerCard(label: "Ownership") {
                            Picker("Ownership", selection: $ownership) {
                                ForEach(FinOwnership.allCases) { o in Text(o.label).tag(o) }
                            }
                            .labelsHidden().pickerStyle(.segmented)
                        }
                        if kind == .creditCard {
                            FinPickerCard(label: "Linked card account") {
                                Picker("Account", selection: $accountID) {
                                    Text("None").tag("")
                                    ForEach(state.finance.accounts.filter { $0.type == .creditCard }) { a in
                                        Text(a.name).tag(a.id)
                                    }
                                }
                                .labelsHidden().pickerStyle(.menu)
                            }
                            Text("When linked, the outstanding balance is derived from the card account and can never double count.")
                                .font(.system(size: 9.5)).foregroundStyle(Palette.faint)
                        }
                    }
                    FinCard {
                        FinCardHeader("Money", icon: "indianrupeesign")
                        HStack(spacing: 10) {
                            FinField(label: "Original principal (₹)", placeholder: "0", text: $originalText, keyboard: .decimalPad)
                            FinField(label: "Outstanding (₹)", placeholder: "0", text: $outstandingText, keyboard: .decimalPad)
                        }
                        DatePicker("Outstanding as of", selection: $asOf, displayedComponents: .date).font(.system(size: 11))
                        HStack(spacing: 10) {
                            FinField(label: "Interest rate (%)", placeholder: "9.5", text: $rateText, keyboard: .decimalPad)
                            FinField(label: "EMI (₹)", placeholder: "0", text: $emiText, keyboard: .decimalPad)
                        }
                        HStack(spacing: 10) {
                            FinField(label: "Due day", placeholder: "5", text: Binding(get: { String(dueDay) }, set: { dueDay = max(1, min(28, Int($0) ?? 1)) }), keyboard: .numberPad)
                            DatePicker("Started", selection: $start, displayedComponents: .date).font(.system(size: 11))
                        }
                        FinToggleRow(label: "Has a maturity date", isOn: $hasMaturity)
                        if hasMaturity {
                            DatePicker("Maturity", selection: $maturity, displayedComponents: .date).font(.system(size: 11))
                        }
                        FinToggleRow(label: "Closed", isOn: $closed)
                        FinField(label: "Notes", placeholder: "", text: $notes, multiline: true)
                    }
                }
                .padding(18)
            }
        }
        .background(Palette.background)
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 620)
        #endif
        .onAppear {
            guard let l = liability else { return }
            name = l.name; kind = l.kind; lender = l.lender; ownership = l.ownership
            originalText = String(format: "%.2f", Double(l.originalPrincipalPaise) / 100)
            outstandingText = String(format: "%.2f", Double(l.outstandingPaise) / 100)
            asOf = FinanceCal.date(l.asOf) ?? .now
            rateText = String(format: "%.2f", Double(l.interestRateBps) / 100)
            emiText = String(format: "%.2f", Double(l.emiPaise) / 100)
            dueDay = l.dueDay
            start = FinanceCal.date(l.startDate) ?? .now
            if let m = l.maturityDate { hasMaturity = true; maturity = FinanceCal.date(m) ?? .now }
            accountID = l.accountID ?? ""
            notes = l.notes
            closed = l.closed
        }
    }

    private func save() {
        var next = liability ?? FinLiability(name: name)
        next.name = name
        next.kind = kind
        next.lender = lender
        next.ownership = ownership
        next.originalPrincipalPaise = FinanceFormat.parsePaise(originalText) ?? 0
        next.outstandingPaise = FinanceFormat.parsePaise(outstandingText) ?? 0
        next.asOf = FinanceCal.key(asOf)
        next.interestRateBps = Int(((Double(rateText.replacingOccurrences(of: ",", with: ".")) ?? 0) * 100).rounded())
        next.emiPaise = FinanceFormat.parsePaise(emiText) ?? 0
        next.dueDay = dueDay
        next.startDate = FinanceCal.key(start)
        next.maturityDate = hasMaturity ? FinanceCal.key(maturity) : nil
        next.accountID = accountID.isEmpty ? nil : accountID
        next.notes = notes
        next.closed = closed
        if liability == nil { state.financeAddLiability(next) } else { state.financeUpdateLiability(next) }
        dismiss()
    }
}

struct FinDebtPaymentSheet: View {
    @EnvironmentObject var state: AppState
    let liabilityID: String
    let suggestedEMI: Int64
    @Environment(\.dismiss) private var dismiss
    @State private var totalText = ""
    @State private var principalText = ""
    @State private var interestText = ""
    @State private var accountID = ""
    @State private var date = Date.now
    @State private var note = ""

    private var total: Int64 { FinanceFormat.parsePaise(totalText) ?? 0 }
    private var principal: Int64 { FinanceFormat.parsePaise(principalText) ?? 0 }
    private var interest: Int64 { FinanceFormat.parsePaise(interestText) ?? 0 }
    private var valid: Bool { total > 0 && principal + interest == total && !accountID.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            FinSheetHeader(title: "Record repayment", sub: "Principal reduces debt; interest is an expense",
                           canSave: valid) {
                let ok = state.financeRecordDebtPayment(liabilityID: liabilityID, accountID: accountID,
                                                        amountPaise: total, principalPaise: principal,
                                                        interestPaise: interest, date: FinanceCal.key(date),
                                                        note: note)
                if ok { dismiss() }
            }
            VStack(alignment: .leading, spacing: 14) {
                FinField(label: "Total paid (₹)", placeholder: "0", text: $totalText, keyboard: .decimalPad)
                HStack(spacing: 10) {
                    FinField(label: "Principal (₹)", placeholder: "0", text: $principalText, keyboard: .decimalPad)
                    FinField(label: "Interest (₹)", placeholder: "0", text: $interestText, keyboard: .decimalPad)
                }
                FinPickerCard(label: "Paid from") {
                    Picker("Account", selection: $accountID) {
                        Text("Choose").tag("")
                        ForEach(state.finance.accounts.filter { $0.status == .active && !$0.type.isLiability }) { a in
                            Text(a.name).tag(a.id)
                        }
                    }
                    .labelsHidden().pickerStyle(.menu)
                }
                DatePicker("Date", selection: $date, displayedComponents: .date).font(.system(size: 11))
                FinField(label: "Note", placeholder: "", text: $note)
                if !valid && total > 0 {
                    Text("Principal + interest must equal the total paid.").font(.system(size: 9.5)).foregroundStyle(Palette.orange)
                }
                Text("Use the EMI split from the statement where possible. The app does not estimate an interest split.")
                    .font(.system(size: 9.5)).foregroundStyle(Palette.faint)
                Spacer()
            }
            .padding(18)
        }
        .background(Palette.background)
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 500)
        #endif
        .onAppear {
            if suggestedEMI > 0 {
                totalText = String(format: "%.2f", Double(suggestedEMI) / 100)
            }
        }
    }
}

// MARK: - Net worth

struct MeFinanceNetWorth: View {
    @EnvironmentObject var state: AppState
    @State private var range: FinRangePreset = .y1
    @State private var snapshotNote = ""

    private var doc: FinanceDocument { state.finance }

    var body: some View {
        let nw = FinanceEngine.netWorth(doc)
        let assets = FinanceEngine.totalAssets(doc)
        let liabilities = FinanceEngine.totalLiabilities(doc)
        let start = FinanceEngine.rangeStart(range, doc: doc) ?? FinanceCal.addMonths(-12, to: FinanceCal.today())
        let history = FinanceEngine.netWorthHistory(doc, from: start, through: FinanceCal.today())
        let p = FinanceEngine.portfolio(doc)
        let accountSummaries = FinanceEngine.accountSummaries(doc)
        let investmentTotal = p.value
        let depositTotal = accountSummaries.filter { $0.account.type.isDeposit }.reduce(Int64(0)) { $0 + $1.balance.paise }
        let cashTotal = accountSummaries.filter { $0.account.type.isCashLike }.reduce(Int64(0)) { $0 + $1.balance.paise }
        let creditTotal = accountSummaries.filter { $0.account.type.isLiability }.reduce(Int64(0)) { $0 + max(0, -$1.balance.paise) }
        let loans = FinanceEngine.liabilitySummaries(doc).filter { $0.liability.kind != .creditCard }
        let loansTotal = loans.reduce(Int64(0)) { $0 + $1.outstandingPaise }
        let hide = doc.settings.hideBalances

        FinPage(title: "Net worth",
                sub: "Assets minus liabilities, at each month end. Nothing is interpolated.",
                badge: doc.settings.demoMode ? "Demo data" : nil) {

            FinCard {
                #if os(macOS)
                HStack(alignment: .top) {
                    netWorthHero(nw: nw, history: history, hide: hide)
                    Spacer()
                    FinRangeBar(selection: $range)
                }
                #else
                VStack(alignment: .leading, spacing: 8) {
                    netWorthHero(nw: nw, history: history, hide: hide)
                    ScrollView(.horizontal) { FinRangeBar(selection: $range) }.scrollIndicators(.hidden)
                }
                #endif
                FinNetWorthChart(points: history, height: 230)
                if history.isEmpty {
                    Text("No dated records yet.").font(.system(size: 10.5)).foregroundStyle(Palette.faint)
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 175), spacing: 12)], spacing: 12) {
                FinStatTile(label: "Total assets", value: hide ? "₹ ••••" : FinanceFormat.inr(assets.paise), sub: assets.certainty.label, icon: "building.columns")
                FinStatTile(label: "Total liabilities", value: hide ? "₹ ••••" : FinanceFormat.inr(liabilities), sub: "Personal, plus opt-in household", icon: "creditcard")
                FinStatTile(label: "Liquid cash", value: hide ? "₹ ••••" : FinanceFormat.inr(cashTotal), sub: "Cash-like accounts", icon: "banknote")
                FinStatTile(label: "Investments", value: hide ? "₹ ••••" : FinanceFormat.inr(investmentTotal), sub: "Current valuation", icon: "chart.line.uptrend.xyaxis")
            }

            #if os(macOS)
            HStack(alignment: .top, spacing: 12) {
                compositionCard(cashTotal: cashTotal, depositTotal: depositTotal, investmentTotal: investmentTotal,
                                creditTotal: creditTotal, loans: loansTotal, hide: hide).frame(maxWidth: .infinity)
                certaintyCard(history).frame(maxWidth: .infinity)
            }
            #else
            compositionCard(cashTotal: cashTotal, depositTotal: depositTotal, investmentTotal: investmentTotal,
                            creditTotal: creditTotal, loans: loansTotal, hide: hide)
            certaintyCard(history)
            #endif

            FinCard {
                FinCardHeader("Month-end ledger", sub: "\(history.count) points", icon: "tablecells")
                if history.isEmpty {
                    Text("No month-end values yet.").font(.system(size: 11)).foregroundStyle(Palette.muted)
                } else {
                    ForEach(Array(history.suffix(12).reversed()), id: \.id) { p in
                        #if os(macOS)
                        HStack {
                            Text(FinanceCal.monthLabel(p.date)).font(.system(size: 11, weight: .medium)).frame(width: 90, alignment: .leading)
                            Text(FinanceFormat.inr(p.assetsPaise)).font(.system(size: 10.5)).monospacedDigit().frame(width: 100, alignment: .trailing)
                            Text(FinanceFormat.inr(p.liabilitiesPaise)).font(.system(size: 10.5)).monospacedDigit().foregroundStyle(Palette.negative).frame(width: 90, alignment: .trailing)
                            Spacer()
                            FinBadge(text: p.certainty.label, tint: FinStyle.certaintyColor(p.certainty))
                            Text(FinanceFormat.inr(p.netPaise)).font(.system(size: 11.5, weight: .semibold, design: .rounded)).monospacedDigit()
                                .frame(width: 120, alignment: .trailing)
                        }
                        .padding(.vertical, 3)
                        #else
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(FinanceCal.monthLabel(p.date)).font(.system(size: 11, weight: .medium))
                                Spacer()
                                FinBadge(text: p.certainty.label, tint: FinStyle.certaintyColor(p.certainty))
                                Text(FinanceFormat.inr(p.netPaise)).font(.system(size: 11.5, weight: .semibold, design: .rounded)).monospacedDigit()
                            }
                            HStack(spacing: 10) {
                                Text("Assets \(FinanceFormat.compact(p.assetsPaise))").foregroundStyle(Palette.muted)
                                Text("Debt \(FinanceFormat.compact(p.liabilitiesPaise))").foregroundStyle(Palette.negative)
                                Spacer()
                            }
                            .font(.system(size: 9.5))
                        }
                        .padding(.vertical, 4)
                        #endif
                    }
                }
            }

            FinCard {
                FinCardHeader("Verify this moment", sub: "A verified snapshot is a dated fact", icon: "checkmark.seal")
                HStack(spacing: 8) {
                    FinField(label: "Note", placeholder: "Why this snapshot matters", text: $snapshotNote)
                    FinPrimaryButton(title: "Capture", icon: "camera") {
                        state.financeCaptureSnapshot(note: snapshotNote)
                        snapshotNote = ""
                    }
                }
                Text("Snapshots override the calculated point for that date and are marked verified. They never change an account or transaction.")
                    .font(.system(size: 9.5)).foregroundStyle(Palette.faint)
            }

            FinCard {
                FinCardHeader("How this is calculated", icon: "function")
                FinDefinitionList()
            }
        }
    }

    @ViewBuilder
    private func netWorthHero(nw: FinAmount, history: [FinNetWorthPoint], hide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("NET WORTH").font(.system(size: 9, weight: .bold)).tracking(0.9).foregroundStyle(Palette.faint)
            Text(hide ? "₹ ••••••" : FinanceFormat.inr(nw.paise)).font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit()
            HStack(spacing: 5) {
                FinBadge(text: nw.certainty.label, tint: FinStyle.certaintyColor(nw.certainty), icon: nw.certainty.icon)
                if let last = history.last, let prev = history.dropLast().last {
                    Text("\(FinanceFormat.inr(last.netPaise - prev.netPaise, showSign: true)) vs \(FinanceCal.monthLabel(prev.date))")
                        .font(.system(size: 10)).foregroundStyle(Palette.muted)
                }
            }
        }
    }

    private func compositionCard(cashTotal: Int64, depositTotal: Int64, investmentTotal: Int64,
                                 creditTotal: Int64, loans: Int64, hide: Bool) -> some View {
        let total = max(1, cashTotal + depositTotal + investmentTotal)
        return FinCard {
            FinCardHeader("Asset composition", icon: "chart.pie")
            compositionRow("Cash & bank", cashTotal, total, Palette.green, hide)
            compositionRow("Deposits", depositTotal, total, Palette.blue, hide)
            compositionRow("Investments", investmentTotal, total, Palette.text.opacity(0.65), hide)
            Divider().overlay(FinStyle.border)
            compositionRow("Credit cards", creditTotal, max(1, creditTotal + loans), Palette.negative, hide)
            compositionRow("Loans", loans, max(1, creditTotal + loans), Palette.orange, hide)
        }
    }

    private func compositionRow(_ label: String, _ value: Int64, _ total: Int64, _ tint: Color, _ hide: Bool) -> some View {
        VStack(spacing: 4) {
            HStack {
                HStack(spacing: 5) {
                    Circle().fill(tint).frame(width: 5, height: 5)
                    Text(label).font(.system(size: 10.5, weight: .medium))
                }
                Spacer()
                Text(hide ? "•••" : FinanceFormat.inr(value)).font(.system(size: 10.5, weight: .semibold)).monospacedDigit()
                Text(FinanceFormat.percent(Double(value) / Double(total) * 100, decimals: 0))
                    .font(.system(size: 9)).foregroundStyle(Palette.faint).frame(width: 30, alignment: .trailing)
            }
            GeometryReader { g in
                Capsule().fill(Palette.text.opacity(0.06))
                    .overlay(alignment: .leading) {
                        Capsule().fill(tint).frame(width: max(2, g.size.width * min(1, Double(value) / Double(total))))
                    }
            }
            .frame(height: 4)
        }
    }

    private func certaintyCard(_ history: [FinNetWorthPoint]) -> some View {
        let counts = Dictionary(grouping: history, by: \.certainty).mapValues(\.count)
        return FinCard {
            FinCardHeader("What is known", sub: "Every point carries its provenance", icon: "checkmark.shield")
            ForEach(FinCertainty.allCases) { c in
                HStack {
                    Image(systemName: c.icon).font(.system(size: 9)).foregroundStyle(FinStyle.certaintyColor(c)).frame(width: 16)
                    Text(c.label).font(.system(size: 10.5, weight: .medium))
                    Spacer()
                    Text("\(counts[c] ?? 0)").font(.system(size: 10.5, weight: .semibold)).monospacedDigit()
                }
            }
            Text("Verified comes from a statement or a captured snapshot. Calculated is derived from transactions. Estimated is carried forward from an older valuation. Nothing else is shown.")
                .font(.system(size: 9.5)).foregroundStyle(Palette.faint)
        }
    }
}

// MARK: - Timeline

struct MeFinanceTimeline: View {
    @EnvironmentObject var state: AppState
    @State private var filter: FinMilestoneKind?
    @State private var year = ""
    @State private var month: Int?
    @State private var custom = false
    @State private var customStart = FinanceCal.date(FinanceCal.addYears(-1, to: FinanceCal.today())) ?? .now
    @State private var customEnd = Date.now
    @State private var adding = false

    private var doc: FinanceDocument { state.finance }
    private var all: [FinTimelineEntry] { FinanceEngine.timeline(doc) }
    private var years: [String] {
        Array(Set(all.map { String($0.date.prefix(4)) })).sorted(by: >)
    }
    private var entries: [FinTimelineEntry] {
        let start = FinanceCal.key(customStart)
        let end = FinanceCal.key(customEnd)
        return all.filter { e in
            if let filter, e.kind != filter { return false }
            if custom { return e.date >= start && e.date <= end }
            if !year.isEmpty && !e.date.hasPrefix(year) { return false }
            if let month {
                let prefix = "\(year)-\(String(format: "%02d", month))"
                if !e.date.hasPrefix(prefix) { return false }
            }
            return true
        }
    }
    private var grouped: [(String, [FinTimelineEntry])] {
        let dict = Dictionary(grouping: entries) { String($0.date.prefix(4)) }
        return dict.keys.sorted(by: >).map { ($0, dict[$0]!.sorted { $0.date > $1.date }) }
    }

    var body: some View {
        FinPage(title: "Financial timeline",
                sub: "A life reconstructed from dated records. Automatic entries are derived, never invented.",
                badge: doc.settings.demoMode ? "Demo data" : nil) {

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                FinChipButton(text: "All", on: filter == nil) { filter = nil }
                ForEach([FinMilestoneKind.firstIncome, .firstSalary, .firstInvestment, .majorPurchase, .debt, .netWorth], id: \.self) { k in
                    FinChipButton(text: k.label, on: filter == k) { filter = k }
                }
                if !years.isEmpty {
                    Menu {
                        Button("Every year") { year = ""; month = nil }
                        ForEach(years, id: \.self) { y in Button(y) { year = y; month = nil } }
                    } label: {
                        Text(year.isEmpty ? "All years" : year)
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 11).frame(height: 32)
                            .background(FinStyle.elevated, in: Capsule())
                    }
                    .menuIndicator(.hidden)
                    if !year.isEmpty {
                        Menu {
                            Button("Every month") { month = nil }
                            ForEach(1...12, id: \.self) { m in
                                Button(FinanceCal.monthLabel("\(year)-\(String(format: "%02d", m))-01")) { month = m }
                            }
                        } label: {
                            Text(month == nil ? "Every month" : FinanceCal.monthLabel("\(year)-\(String(format: "%02d", month ?? 1))-01"))
                                .font(.system(size: 11, weight: .semibold))
                                .padding(.horizontal, 11).frame(height: 32)
                                .background(FinStyle.elevated, in: Capsule())
                        }
                        .menuIndicator(.hidden)
                    }
                }
                FinChipButton(text: "Custom range", on: custom, icon: "calendar") { custom.toggle() }
                FinPrimaryButton(title: "Milestone", icon: "plus") { adding = true }
                }
            }
            .scrollIndicators(.hidden)

            if custom {
                HStack(spacing: 8) {
                    DatePicker("From", selection: $customStart, displayedComponents: .date).font(.system(size: 11))
                    DatePicker("To", selection: $customEnd, displayedComponents: .date).font(.system(size: 11))
                    Spacer()
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 185), spacing: 12)], spacing: 12) {
                FinStatTile(label: "Milestones", value: "\(all.filter { !$0.isAutomatic }.count)", sub: "Added by you", icon: "star")
                FinStatTile(label: "Automatic", value: "\(all.filter(\.isAutomatic).count)", sub: "Derived from records", icon: "function")
                FinStatTile(label: "Years covered", value: "\(years.count)", sub: years.last.map { "since \($0)" } ?? "No records", icon: "calendar")
            }

            if grouped.isEmpty {
                FinCard {
                    FinEmptyState(icon: "clock.arrow.circlepath", title: "The timeline is empty",
                                  detail: "The first account, first income and first investment become milestones automatically once records exist.")
                }
            } else {
                ForEach(grouped, id: \.0) { year, list in
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 8) {
                            Text(year).font(.system(size: 22, weight: .bold, design: .rounded)).monospacedDigit()
                            Rectangle().fill(FinStyle.border).frame(height: 1)
                        }
                        .padding(.top, 6)
                        ForEach(Array(list.enumerated()), id: \.element.id) { index, e in
                            HStack(alignment: .top, spacing: 10) {
                                VStack(spacing: 0) {
                                    Circle()
                                        .fill(e.certainty == .verified ? Palette.green : e.certainty == .calculated ? Palette.blue : Palette.orange)
                                        .frame(width: 7, height: 7)
                                        .padding(.top, 5)
                                    if index < list.count - 1 {
                                        Rectangle().fill(FinStyle.border).frame(width: 1).frame(maxHeight: .infinity)
                                    }
                                }
                                .frame(width: 12)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 5) {
                                        Text(FinanceFormat.date(e.date)).font(.system(size: 9.5)).foregroundStyle(Palette.faint).monospacedDigit()
                                        FinBadge(text: e.certainty.label, tint: FinStyle.certaintyColor(e.certainty))
                                        if !e.isAutomatic { FinBadge(text: "yours", tint: Palette.blue) }
                                        else { FinBadge(text: "auto", tint: Palette.muted) }
                                    }
                                    Text(e.title).font(.system(size: 12.5, weight: .semibold))
                                    if !e.detail.isEmpty {
                                        Text(e.detail).font(.system(size: 10.5)).foregroundStyle(Palette.muted).lineLimit(2)
                                    }
                                    if let amount = e.amountPaise {
                                        Text(FinanceFormat.inr(amount)).font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(Palette.muted)
                                    }
                                }
                                Spacer(minLength: 4)
                                Image(systemName: e.kind.icon).font(.system(size: 11)).foregroundStyle(Palette.faint)
                            }
                            .padding(.vertical, 7)
                        }
                    }
                }
            }

            FinCard {
                FinCardHeader("Honest history", icon: "info.circle")
                Text("Automatic entries come from the earliest matching record in your ledger. They are not a curated story, and months without records are not filled in.")
                    .font(.system(size: 10.5)).foregroundStyle(Palette.muted)
            }
        }
        .sheet(isPresented: $adding) { FinMilestoneEditor().environmentObject(state) }
    }
}

struct FinMilestoneEditor: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var detail = ""
    @State private var date = Date.now
    @State private var kind: FinMilestoneKind = .custom
    @State private var certainty: FinCertainty = .verified

    var body: some View {
        VStack(spacing: 0) {
            FinSheetHeader(title: "Add milestone", sub: "A fact about your financial life",
                           canSave: !title.trimmingCharacters(in: .whitespaces).isEmpty) {
                state.financeAddMilestone(FinMilestone(date: FinanceCal.key(date), title: title,
                                                        detail: detail, kind: kind, certainty: certainty))
                dismiss()
            }
            VStack(alignment: .leading, spacing: 14) {
                FinField(label: "Title", placeholder: "Moved to Bengaluru", text: $title)
                FinField(label: "Detail", placeholder: "What changed", text: $detail, multiline: true)
                FinPickerCard(label: "Kind") {
                    Picker("Kind", selection: $kind) {
                        ForEach(FinMilestoneKind.allCases) { k in Text(k.label).tag(k) }
                    }
                    .labelsHidden().pickerStyle(.menu)
                }
                DatePicker("Date", selection: $date, displayedComponents: .date).font(.system(size: 11))
                FinPickerCard(label: "Certainty") {
                    Picker("Certainty", selection: $certainty) {
                        ForEach(FinCertainty.allCases) { c in Text(c.label).tag(c) }
                    }
                    .labelsHidden().pickerStyle(.segmented)
                }
                Text("Use Verified only if you know this happened on this date. Estimated is honest about a remembered date.")
                    .font(.system(size: 9.5)).foregroundStyle(Palette.faint)
                Spacer()
            }
            .padding(18)
        }
        .background(Palette.background)
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 500)
        #endif
    }
}
