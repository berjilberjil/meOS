import Foundation

/// The things Catherine can actually do.
///
/// These are real tool calls, not the old `ACTION` lines scraped off the end of
/// a reply. The model asks for a tool, the app runs it here and hands back the
/// result, and only then does the model answer. That is the difference between
/// "I think you decided X" and "your note from March says X".
///
/// Execution is deliberately on-device. Every tool reads or writes the vault
/// that is already unlocked in this process, so a tool can only ever touch the
/// data of the person holding the passphrase — there is no server-side path to
/// anyone's notes, and no way for one account's data to reach another's context.
///
/// The declarations travel with each request rather than being duplicated on the
/// server, so the two can never drift out of sync.

struct CatrineTool {
    let name: String
    let description: String
    /// JSON Schema for the arguments, sent verbatim to the model.
    let parameters: [String: Any]
    /// Writes are called out so the loop can bound and report them separately.
    let mutates: Bool

    init(_ name: String, _ description: String, _ properties: [String: Any],
         required: [String] = [], mutates: Bool = false) {
        self.name = name
        self.description = description
        self.parameters = ["type": "object", "properties": properties, "required": required]
        self.mutates = mutates
    }
}

enum CatrineToolbox {
    private static let query: [String: Any] = ["type": "string", "description": "What to look for."]
    private static let limit: [String: Any] = ["type": "integer", "description": "Max results (default 6)."]

    static let all: [CatrineTool] = [
        // MARK: Reads
        CatrineTool("search_brain",
                    "Search everything in MeOS at once — notes, events, focus lists, purchases, videos. Use this when you don't know which module holds the answer.",
                    ["query": query, "limit": limit], required: ["query"]),
        CatrineTool("search_notes",
                    "Search the user's notes. Use for anything they wrote down: ideas, decisions, specs, drafts. Locked notes are never returned.",
                    ["query": query, "limit": limit], required: ["query"]),
        CatrineTool("search_events",
                    "Search logged life events (trips, milestones) by title or note.",
                    ["query": query, "limit": limit], required: ["query"]),
        CatrineTool("search_purchases",
                    "Search things the user owns, with price, purchase date and payback progress.",
                    ["query": query, "limit": limit], required: ["query"]),
        CatrineTool("search_memory",
                    "Search what you already remember about the user. Use before claiming you don't know something about them.",
                    ["query": query, "limit": limit], required: ["query"]),
        CatrineTool("get_todos",
                    "The focus list for a day. Omit the date for today.",
                    ["date": ["type": "string", "description": "yyyy-MM-dd. Defaults to today."]]),
        CatrineTool("get_upcoming",
                    "Events coming up, soonest first.",
                    ["limit": limit]),

        // MARK: Finance reads
        CatrineTool("get_finance_summary",
                    "The user's recorded financial position: net worth, assets, liabilities, cash, investments, this month's income/expenses/savings, and data coverage. Use this before answering any money question. If the result says there are no records, say so — never invent a balance.",
                    [:]),
        CatrineTool("get_finance_period",
                    "Totals for a financial period from the ledger: income, expenses, net savings, savings rate, investment purchases, top categories and top payees. Defaults to the current month. Omit end for today.",
                    ["start": ["type": "string", "description": "yyyy-MM-dd. Defaults to the first of the current month."],
                     "end": ["type": "string", "description": "yyyy-MM-dd. Defaults to today."]]),
        CatrineTool("search_finance",
                    "Search the transaction ledger by payee, note, reference, tag, category or account name. Returns matching records with amounts. Transfers and investment flows are labelled as such and are not income or spending.",
                    ["query": query, "limit": limit], required: ["query"]),
        CatrineTool("get_finance_timeline",
                    "The financial timeline: first account, first income, first salary, first investment, milestones and year-end net worth, newest first. Certainty labels show what is verified, calculated or estimated.",
                    ["limit": limit]),
        CatrineTool("get_investments",
                    "Investment holdings with invested capital, current value, unrealised gain/loss, return and valuation certainty. Values are manual or statement-based unless a provider is connected.",
                    [:]),
        CatrineTool("get_liabilities",
                    "Liabilities with outstanding principal, original principal, interest rate, EMI, tenure and ownership. Household debt is flagged so it is not silently counted as personal.",
                    [:]),
        CatrineTool("get_net_worth_history",
                    "Month-end net worth points with assets, liabilities and certainty. Use for questions like how wealth changed after a job. Never interpolate missing months.",
                    ["months": ["type": "integer", "description": "How many month-ends to return, default 12, max 60."]]),

        // MARK: Writes
        CatrineTool("remember",
                    "Store a durable fact about the user — a project, preference, goal, decision or way they work. Only for things that stay true after this conversation. Never store passwords or keys unless they explicitly asked you to.",
                    ["content": ["type": "string", "description": "The fact, in one sentence, written about the user."],
                     "category": ["type": "string",
                                  "enum": MemoryCategory.allCases.map(\.rawValue),
                                  "description": "Which kind of fact this is."],
                     "importance": ["type": "integer", "description": "1 trivia … 5 core to who they are. Default 3."]],
                    required: ["content"], mutates: true),
        CatrineTool("forget",
                    "Delete remembered facts that match a description. Use when the user says to forget something or corrects you.",
                    ["query": query], required: ["query"], mutates: true),
        CatrineTool("create_note",
                    "Create a note in MeOS.",
                    ["title": ["type": "string"], "body": ["type": "string"]],
                    required: ["title"], mutates: true),
        CatrineTool("add_focus",
                    "Add a to-do to today's focus list.",
                    ["text": ["type": "string"]], required: ["text"], mutates: true),
        CatrineTool("create_event",
                    "Log a life event on a date.",
                    ["title": ["type": "string"],
                     "date": ["type": "string", "description": "yyyy-MM-dd, today or later."]],
                    required: ["title", "date"], mutates: true)
    ]

    static func byName(_ n: String) -> CatrineTool? { all.first { $0.name == n } }

    /// The shape the chat endpoint expects.
    static func wireFormat() -> [[String: Any]] {
        all.map { ["name": $0.name, "description": $0.description, "parameters": $0.parameters] }
    }
}

// MARK: - Execution

extension AppState {

    /// Run one tool and return a JSON-encodable result.
    ///
    /// Never throws: a failure is reported back to the model as data, so it can
    /// say "I couldn't find that" instead of the whole turn collapsing.
    func runCatrineTool(_ name: String, _ args: [String: Any]) -> [String: Any] {
        func str(_ k: String) -> String {
            (args[k] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        func int(_ k: String) -> Int? {
            if let i = args[k] as? Int { return i }
            if let d = args[k] as? Double { return Int(d) }
            if let s = args[k] as? String { return Int(s) }
            return nil
        }
        let cap = max(1, min(int("limit") ?? 6, 12))

        func found(_ hits: [RetrievalHit]) -> [String: Any] {
            guard !hits.isEmpty else {
                return ["found": 0,
                        "note": "Nothing in MeOS matches that. Say so — do not invent an answer."]
            }
            return ["found": hits.count,
                    "results": hits.map { h in
                        ["kind": h.doc.kind.rawValue, "title": h.doc.title,
                         "date": h.doc.date, "text": h.doc.snippet()]
                    }]
        }

        switch name {
        case "search_brain":     return found(searchBrain(str("query"), limit: cap))
        case "search_notes":     return found(searchBrain(str("query"), kinds: [.note], limit: cap))
        case "search_events":    return found(searchBrain(str("query"), kinds: [.event], limit: cap))
        case "search_purchases": return found(searchBrain(str("query"), kinds: [.stuff], limit: cap))

        case "search_memory":
            let hits = MemoryBank.recall(memory.items, for: str("query"), limit: cap)
            guard !hits.isEmpty else {
                return ["found": 0, "note": "You don't remember anything about that yet."]
            }
            return ["found": hits.count,
                    "memories": hits.map { ["content": $0.content, "category": $0.category.rawValue,
                                            "since": $0.createdAt] }]

        case "get_todos":
            let day = str("date").isEmpty ? todayKey : String(str("date").prefix(10))
            let todos = plan(for: day).todos
            return ["date": day, "count": todos.count,
                    "todos": todos.map { ["text": $0.text, "done": $0.done,
                                          "minutes_focused": $0.spent / 60] }]

        case "get_upcoming":
            let upcoming = events.filter { $0.date >= todayKey }
                .sorted { $0.date < $1.date }.prefix(cap)
            return ["today": todayKey,
                    "events": upcoming.map { ["title": $0.title, "date": $0.date, "note": $0.note] }]

        // MARK: Finance reads
        //
        // Read-only, on-device, and built from the same FinanceEngine the UI
        // uses. No bank credentials or account numbers exist to leak. Every
        // answer carries a certainty label and a data-coverage note so the
        // model cannot quietly turn an estimate into a fact.

        case "get_finance_summary":
            let nw = FinanceEngine.netWorth(finance)
            let assets = FinanceEngine.totalAssets(finance)
            let liabilities = FinanceEngine.totalLiabilities(finance)
            let portfolio = FinanceEngine.portfolio(finance)
            let cash = FinanceEngine.liquidAssets(finance)
            let month = FinanceEngine.monthTotals(finance, monthContaining: todayKey)
            let coverage: String
            if finance.isEmpty {
                coverage = "No financial records exist yet. Say that clearly instead of estimating."
            } else {
                coverage = "Records from \(finance.settings.trackingStartDate) to \(todayKey). Derived figures are computed from \(finance.transactions.count) transactions."
            }
            return [
                "currency": "INR",
                "as_of": todayKey,
                "has_records": !finance.isEmpty,
                "demo_data": finance.settings.demoMode,
                "coverage": coverage,
                "net_worth": ["paise": nw.paise, "inr": FinanceFormat.inr(nw.paise), "certainty": nw.certainty.rawValue],
                "assets": ["paise": assets.paise, "inr": FinanceFormat.inr(assets.paise), "certainty": assets.certainty.rawValue],
                "liabilities": ["paise": liabilities, "inr": FinanceFormat.inr(liabilities)],
                "cash_and_bank": ["paise": cash, "inr": FinanceFormat.inr(cash)],
                "investments": ["value_paise": portfolio.value, "value_inr": FinanceFormat.inr(portfolio.value),
                                "invested_paise": portfolio.invested, "invested_inr": FinanceFormat.inr(portfolio.invested),
                                "certainty": portfolio.certainty.rawValue],
                "this_month": [
                    "income_paise": month.incomePaise, "income_inr": FinanceFormat.inr(month.incomePaise),
                    "expenses_paise": month.expensePaise, "expenses_inr": FinanceFormat.inr(month.expensePaise),
                    "net_savings_paise": month.netSavingsPaise, "net_savings_inr": FinanceFormat.inr(month.netSavingsPaise),
                    "savings_rate_percent": month.savingsRate ?? 0,
                    "savings_rate_available": month.savingsRate != nil,
                ],
                "counts": ["accounts": finance.accounts.count, "transactions": finance.transactions.count,
                           "investments": finance.investments.count, "liabilities": finance.liabilities.count],
                "note": "Income excludes transfers, refunds, loan disbursements and investment sales. Expenses exclude transfers, investment purchases and loan principal. Never present a figure not supported here."
            ]

        case "get_finance_period":
            let rawStart = str("start")
            let rawEnd = str("end")
            let start = rawStart.isEmpty ? FinanceCal.monthStart(todayKey) : String(rawStart.prefix(10))
            let end = rawEnd.isEmpty ? todayKey : String(rawEnd.prefix(10))
            let totals = FinanceEngine.totals(finance, from: start, through: end)
            let cats = FinanceEngine.expenseByCategory(finance, from: start, through: end)
            let merchants = FinanceEngine.merchantBreakdown(finance, from: start, through: end).prefix(5)
            return [
                "period": ["start": start, "end": end],
                "has_records": totals.transactionCount > 0,
                "transaction_count": totals.transactionCount,
                "income_inr": FinanceFormat.inr(totals.incomePaise), "income_paise": totals.incomePaise,
                "expenses_inr": FinanceFormat.inr(totals.expensePaise), "expenses_paise": totals.expensePaise,
                "refunds_inr": FinanceFormat.inr(totals.refundPaise),
                "net_savings_inr": FinanceFormat.inr(totals.netSavingsPaise),
                "savings_rate_percent": totals.savingsRate ?? 0,
                "savings_rate_available": totals.savingsRate != nil,
                "invested_inr": FinanceFormat.inr(totals.investmentPaise),
                "debt_principal_repaid_inr": FinanceFormat.inr(totals.debtPrincipalPaise),
                "debt_interest_inr": FinanceFormat.inr(totals.debtInterestPaise),
                "top_expense_categories": cats.prefix(6).map { ["category": $0.name, "amount_inr": FinanceFormat.inr($0.paise), "share_percent": $0.share] },
                "top_payees": merchants.map { ["payee": $0.merchant, "amount_inr": FinanceFormat.inr($0.paise), "count": $0.count] },
                "note": "If transaction_count is 0, there are no records in this period. Do not estimate."
            ]

        case "search_finance":
            let queryText = str("query").lowercased()
            guard !queryText.isEmpty else { return ["found": 0, "note": "A search term is required."] }
            let matched = finance.transactions.filter { t in
                let category = finance.category(t.categoryID)?.displayName ?? ""
                let account = finance.account(t.accountID)?.name ?? ""
                return [t.merchant, t.note, t.reference, t.tags.joined(separator: " "), category, account, t.type.label]
                    .joined(separator: " ").lowercased().contains(queryText)
            }.sorted { $0.date > $1.date }
            guard !matched.isEmpty else {
                return ["found": 0, "note": "No recorded transaction matches that. Say so rather than inventing one."]
            }
            return [
                "found": matched.count,
                "returned": min(matched.count, cap),
                "transactions": matched.prefix(cap).map { t -> [String: Any] in
                    var row: [String: Any] = [
                        "date": t.date,
                        "payee": t.title,
                        "amount_inr": FinanceFormat.inr(t.amountPaise),
                        "direction": t.direction.rawValue,
                        "type": t.type.label,
                        "account": finance.account(t.accountID)?.name ?? "",
                        "category": finance.category(t.categoryID)?.displayName ?? "Uncategorised",
                        "verification": t.verification.rawValue,
                        "source": t.source.rawValue,
                        "is_income": FinanceEngine.isIncome(t),
                        "is_expense": FinanceEngine.isExpense(t),
                        "is_transfer": FinanceEngine.isInternalTransfer(t),
                        "is_investment_flow": FinanceEngine.isInvestmentFlow(t),
                    ]
                    if !t.note.isEmpty { row["note"] = t.note }
                    if !t.reference.isEmpty { row["reference"] = t.reference }
                    return row
                }
            ]

        case "get_finance_timeline":
            let entries = FinanceEngine.timeline(finance)
            return ["count": entries.count,
                    "entries": entries.prefix(cap).map { e in
                        ["date": e.date, "title": e.title, "detail": e.detail,
                         "kind": e.kind.rawValue, "certainty": e.certainty.rawValue,
                         "automatic": e.isAutomatic,
                         "amount_inr": e.amountPaise.map { FinanceFormat.inr($0) } ?? ""]
                    }]

        case "get_investments":
            let portfolio = FinanceEngine.portfolio(finance)
            let summaries = FinanceEngine.investmentSummaries(finance)
            return [
                "has_records": !summaries.isEmpty,
                "value_inr": FinanceFormat.inr(portfolio.value),
                "invested_inr": FinanceFormat.inr(portfolio.invested),
                "unrealised_gain_inr": FinanceFormat.inr(portfolio.unrealised, showSign: true),
                "certainty": portfolio.certainty.rawValue,
                "holdings": summaries.map { s in
                    ["name": s.investment.name, "asset_class": s.investment.assetClass.label,
                     "invested_inr": FinanceFormat.inr(s.investedPaise),
                     "value_inr": FinanceFormat.inr(s.valuePaise),
                     "unrealised_gain_inr": FinanceFormat.inr(s.unrealisedPaise, showSign: true),
                     "return_percent": s.returnPercent ?? 0,
                     "return_available": s.returnPercent != nil,
                     "certainty": s.certainty.rawValue]
                },
                "note": "Values are manual/statement valuations. There is no live market feed; carried-forward values are estimated."
            ]

        case "get_liabilities":
            let summaries = FinanceEngine.liabilitySummaries(finance)
            return [
                "has_records": !summaries.isEmpty,
                "total_personal_and_opted_in_inr": FinanceFormat.inr(FinanceEngine.totalLiabilities(finance)),
                "liabilities": summaries.map { s in
                    ["name": s.liability.name, "kind": s.liability.kind.label,
                     "ownership": s.liability.ownership.rawValue,
                     "lender": s.liability.lender,
                     "outstanding_inr": FinanceFormat.inr(s.outstandingPaise),
                     "original_principal_inr": FinanceFormat.inr(s.liability.originalPrincipalPaise),
                     "interest_rate_percent": Double(s.liability.interestRateBps) / 100,
                     "emi_inr": FinanceFormat.inr(s.liability.emiPaise),
                     "remaining_months": s.tenureMonthsLeft ?? 0,
                     "remaining_months_known": s.tenureMonthsLeft != nil]
                },
                "note": "Household debt is excluded from personal net worth unless the user opted in. Say which ownership applies."
            ]

        case "get_net_worth_history":
            let months = max(1, min(int("months") ?? 12, 60))
            let start = FinanceCal.addMonths(-months, to: todayKey)
            let points = FinanceEngine.netWorthHistory(finance, from: start, through: todayKey)
            return ["points": points.map { p in
                ["date": p.date, "assets_inr": FinanceFormat.inr(p.assetsPaise),
                 "liabilities_inr": FinanceFormat.inr(p.liabilitiesPaise),
                 "net_worth_inr": FinanceFormat.inr(p.netPaise),
                 "certainty": p.certainty.rawValue]
            }, "note": "Missing months are genuinely absent, not zero. Do not interpolate or invent points."]

        // MARK: Writes

        case "remember":
            let content = str("content")
            guard !content.isEmpty else { return ["ok": false, "error": "nothing to remember"] }
            let category = MemoryCategory(rawValue: str("category")) ?? .other
            let candidate = MemoryItem(content: content, category: category,
                                       importance: int("importance") ?? 3,
                                       source: .stated, createdAt: Self.nowStamp())
            if let why = MemoryBank.judge(candidate, against: memory.items) {
                return ["ok": false, "skipped": why.rawValue,
                        "note": why == .duplicate ? "You already remember this." : "Not stored."]
            }
            addMemory(candidate)
            return ["ok": true, "remembered": content]

        case "forget":
            let gone = forgetMemories(matching: str("query"))
            return gone.isEmpty
                ? ["ok": false, "note": "Nothing remembered matches that."]
                : ["ok": true, "forgot": gone]

        case "create_note":
            guard !str("title").isEmpty else { return ["ok": false, "error": "title required"] }
            applyMentorActions([MentorAction(kind: .createNote,
                                             fields: ["title": str("title"), "body": str("body")])])
            return ["ok": true, "created": str("title")]

        case "add_focus":
            guard !str("text").isEmpty else { return ["ok": false, "error": "text required"] }
            applyMentorActions([MentorAction(kind: .addFocus, fields: ["text": str("text")])])
            return ["ok": true, "added": str("text")]

        case "create_event":
            guard !str("title").isEmpty, !str("date").isEmpty else {
                return ["ok": false, "error": "title and date required"]
            }
            // Straight to `addEvent`, NOT through `applyMentorActions`. That
            // path resolves the date against the user's whole last message, and
            // the phrase always wins — which is right for the legacy ACTION
            // format, where the model invents last year's calendar, but wrong
            // here: this date came through a schema, and the model was told
            // today's date when it chose it. "What did I eat yesterday? Also put
            // my dentist on 15 September" filed the dentist against yesterday.
            let when = EventDate.normalizeISO(str("date")) ?? todayKey
            addEvent(date: when, title: str("title"))
            return ["ok": true, "created": str("title"), "date": when]

        default:
            return ["ok": false, "error": "no such tool: \(name)"]
        }
    }
}
