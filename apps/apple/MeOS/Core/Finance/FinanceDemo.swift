import Foundation

// MARK: - Demo finance dataset
//
// Everything here is fictional and every row is flagged `isDemo`. It is built
// only through the explicit "Load demo data" action, only onto an empty
// document, and "Remove demo data" filters exclusively on that flag. No part of
// this file can write into a real record.

private struct FinDemoRNG {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
    mutating func int(_ range: ClosedRange<Int>) -> Int {
        guard range.lowerBound <= range.upperBound else { return range.lowerBound }
        let span = UInt64(range.upperBound - range.lowerBound + 1)
        return range.lowerBound + Int(next() % span)
    }
    mutating func pick<T>(_ values: [T]) -> T {
        values[int(0...(values.count - 1))]
    }
}

enum FinanceDemo {

    static func build(today: String = FinanceCal.today()) -> FinanceDocument {
        var rng = FinDemoRNG(state: 0x4D654F53_46494E41)
        var doc = FinanceDocument()
        doc.settings.demoMode = true
        doc.settings.demoSeededAt = FinNow.stamp()
        doc.settings.emergencyFundMonths = 6
        doc.categories = FinanceTaxonomy.defaultCategories()

        let start = FinanceCal.addYears(-8, to: today)
        doc.settings.trackingStartDate = start

        let cat = FinanceTaxonomy.categoryID

        // MARK: Accounts

        var salary = FinAccount(name: "Everyday salary", institution: "Northstar Bank",
                                type: .salary, openingDate: start,
                                openingBalancePaise: 500_000, notes: "Primary salary account.",
                                isDemo: true)
        salary.id = FinID.stable("demo.account.salary")

        var savings = FinAccount(name: "Rainy-day savings", institution: "Northstar Bank",
                                 type: .savings, openingDate: start,
                                 openingBalancePaise: 0, notes: "Emergency fund.",
                                 isDemo: true)
        savings.id = FinID.stable("demo.account.savings")

        var cash = FinAccount(name: "Cash wallet", institution: "",
                              type: .cash, openingDate: start,
                              openingBalancePaise: 200_000, isDemo: true)
        cash.id = FinID.stable("demo.account.cash")

        var card = FinAccount(name: "Aster credit card", institution: "Aster Financial",
                              type: .creditCard, openingDate: FinanceCal.addYears(-5, to: today),
                              openingBalancePaise: 0, creditLimitPaise: 20_000_000,
                              notes: "Paid in full most months.", isDemo: true)
        card.id = FinID.stable("demo.account.card")

        var brokerage = FinAccount(name: "Brokerage cash", institution: "Meridian Invest",
                                   type: .brokerage, openingDate: FinanceCal.addYears(-4, to: today),
                                   openingBalancePaise: 1_500_000, isDemo: true)
        brokerage.id = FinID.stable("demo.account.brokerage")

        doc.accounts = [salary, savings, cash, card, brokerage]

        let pid = FinID.stable("demo.investment.index")
        let pid2 = FinID.stable("demo.investment.bluechip")
        let pid3 = FinID.stable("demo.investment.gold")
        let pid4 = FinID.stable("demo.investment.bond")

        var transactions: [FinTransaction] = []
        var transfers: [FinTransfer] = []
        var debtPayments: [FinDebtPayment] = []

        func add(_ t: FinTransaction) {
            guard t.date <= today else { return }
            var row = t
            row.isDemo = true
            if row.source == .manual { row.source = .demo }
            transactions.append(row)
        }

        func addTransfer(from: String, to: String, amount: Int64, date: String,
                         fee: Int64 = 0, note: String = "") {
            guard date <= today else { return }
            let tid = FinID.stable("demo.transfer.\(date).\(from).\(to).\(amount)")
            var out = FinTransaction(date: date, amountPaise: amount, direction: .outflow,
                                     type: .transfer, accountID: from, transferAccountID: to,
                                     merchant: "Internal transfer", paymentMethod: .bankTransfer,
                                     note: note, verification: .verified, transferID: tid)
            var inbound = FinTransaction(date: date, amountPaise: amount, direction: .inflow,
                                         type: .transfer, accountID: to, transferAccountID: from,
                                         merchant: "Internal transfer", paymentMethod: .bankTransfer,
                                         note: note, verification: .verified, transferID: tid)
            out.linkedTransactionID = inbound.id
            inbound.linkedTransactionID = out.id
            out.isDemo = true; inbound.isDemo = true
            transactions.append(out); transactions.append(inbound)
            var record = FinTransfer(id: tid, fromAccountID: from, toAccountID: to,
                                     amountPaise: amount, date: date, feePaise: fee,
                                     note: note, fromTransactionID: out.id,
                                     toTransactionID: inbound.id, reconciled: true,
                                     isDemo: true)
            record.feePaise = fee
            transfers.append(record)
            if fee > 0 {
                add(FinTransaction(date: date, amountPaise: fee, direction: .outflow,
                                   type: .fee, accountID: from,
                                   categoryID: cat("expense.bankCharges"),
                                   merchant: "Transfer fee", verification: .verified))
            }
        }

        // MARK: Salary, freelance and savings

        let salaryStart = FinanceCal.addYears(-6, to: today)
        let freelanceStart = FinanceCal.addYears(-7, to: today)
        let rentStart = FinanceCal.addYears(-5, to: today)
        let sipStart = FinanceCal.addYears(-4, to: today)
        let loanStart = FinanceCal.addYears(-4, to: today)

        var months: [String] = []
        var cursor = FinanceCal.monthStart(start)
        let stop = FinanceCal.monthStart(today)
        while cursor <= stop {
            months.append(cursor)
            cursor = FinanceCal.addMonths(1, to: cursor)
        }

        var sipTotal: Int64 = 0
        var cardSpendSincePayment: Int64 = 0
        var monthIndex = 0

        for month in months {
            let yearOffset = Double(monthIndex) / 12.0
            let dateFor: (Int) -> String = { day in
                FinanceCal.addDays(day - 1, to: month)
            }

            // Salary — monthly, growing over the years.
            if month >= FinanceCal.monthStart(salaryStart) {
                let base = 3_200_000 + Int64(yearOffset * 780_000)
                let amount = base + Int64(rng.int(-40_000...120_000))
                let d = dateFor(1)
                add(FinTransaction(date: d, amountPaise: amount, direction: .inflow,
                                   type: .income, accountID: salary.id,
                                   categoryID: cat("income.salary"),
                                   merchant: "Northstar Studio payroll",
                                   paymentMethod: .bankTransfer,
                                   reference: "SAL-\(String(d.prefix(7)))",
                                   source: .imported, verification: .verified))
            }

            // Freelance — most months after the second year.
            if month >= FinanceCal.monthStart(freelanceStart), monthIndex % 3 != 2 {
                let amount = Int64(rng.int(800_000...4_800_000))
                add(FinTransaction(date: dateFor(rng.int(5...24)), amountPaise: amount,
                                   direction: .inflow, type: .income, accountID: salary.id,
                                   categoryID: cat("income.freelance"),
                                   merchant: rng.pick(["Studio retainer", "Brand film", "Editing project", "Design sprint"]),
                                   paymentMethod: .bankTransfer, verification: .verified))
            }

            // Rent
            if month >= FinanceCal.monthStart(rentStart) {
                let amount = Int64(1_200_000 + yearOffset * 170_000)
                add(FinTransaction(date: dateFor(3), amountPaise: amount, direction: .outflow,
                                   type: .expense, accountID: salary.id,
                                   categoryID: cat("expense.rent"),
                                   merchant: "Landlord", paymentMethod: .upi,
                                   reference: "RENT-\(String(month.prefix(7)))",
                                   verification: .verified))
            }

            // Utilities
            add(FinTransaction(date: dateFor(9), amountPaise: Int64(rng.int(120_000...460_000)),
                               direction: .outflow, type: .expense, accountID: salary.id,
                               categoryID: cat("expense.utilities"),
                               merchant: rng.pick(["State electricity", "Water board", "Broadband"]),
                               paymentMethod: .autoDebit, verification: .verified))

            // Groceries
            for _ in 0..<rng.int(2...4) {
                add(FinTransaction(date: dateFor(rng.int(4...27)),
                                   amountPaise: Int64(rng.int(120_000...620_000)),
                                   direction: .outflow, type: .expense,
                                   accountID: rng.int(0...2) == 0 ? cash.id : salary.id,
                                   categoryID: cat("expense.groceries"),
                                   merchant: rng.pick(["Fresh Basket", "Daily Mart", "Corner Store", "Green Grocer"]),
                                   paymentMethod: .upi, verification: .verified))
            }

            // Food
            for _ in 0..<rng.int(4...7) {
                add(FinTransaction(date: dateFor(rng.int(1...28)),
                                   amountPaise: Int64(rng.int(22_000...145_000)),
                                   direction: .outflow, type: .expense,
                                   accountID: rng.int(0...2) == 0 ? cash.id : card.id,
                                   categoryID: cat("expense.food"),
                                   merchant: rng.pick(["Cafe Third Wave", "Dosa House", "Sushi Bar", "Biryani Junction", "Blue Tokai"]),
                                   paymentMethod: rng.int(0...1) == 0 ? .upi : .card,
                                   verification: .verified))
            }

            // Transport
            for _ in 0..<rng.int(2...4) {
                add(FinTransaction(date: dateFor(rng.int(1...28)),
                                   amountPaise: Int64(rng.int(9_000...95_000)),
                                   direction: .outflow, type: .expense, accountID: salary.id,
                                   categoryID: cat("expense.transport"),
                                   merchant: rng.pick(["Metro card", "Uber", "Auto", "Fuel"]),
                                   paymentMethod: .upi, verification: .verified))
            }

            // Subscriptions
            add(FinTransaction(date: dateFor(6), amountPaise: 64_900, direction: .outflow,
                               type: .expense, accountID: card.id,
                               categoryID: cat("expense.subscriptions"),
                               merchant: "Streamly", paymentMethod: .card,
                               verification: .verified))
            add(FinTransaction(date: dateFor(12), amountPaise: 19_900, direction: .outflow,
                               type: .expense, accountID: card.id,
                               categoryID: cat("expense.subscriptions"),
                               merchant: "TuneBox", paymentMethod: .card,
                               verification: .verified))

            // Shopping
            if monthIndex % 2 == 0 {
                let amount = Int64(rng.int(150_000...1_100_000))
                add(FinTransaction(date: dateFor(rng.int(8...25)), amountPaise: amount,
                                   direction: .outflow, type: .expense,
                                   accountID: rng.int(0...1) == 0 ? card.id : salary.id,
                                   categoryID: cat("expense.shopping"),
                                   merchant: rng.pick(["Amazon", "Myntra", "Decathlon", "IKEA", "Croma"]),
                                   paymentMethod: .card, verification: .verified))
                cardSpendSincePayment += amount
            }

            // SIP — investment purchase, never an expense.
            if month >= FinanceCal.monthStart(sipStart) {
                let amount = 500_000 + Int64(yearOffset * 120_000)
                sipTotal += amount
                add(FinTransaction(date: dateFor(5), amountPaise: amount, direction: .outflow,
                                   type: .investmentPurchase, accountID: salary.id,
                                   merchant: "Nifty index fund",
                                   paymentMethod: .autoDebit,
                                   reference: "SIP-\(String(month.prefix(7)))",
                                   verification: .verified, investmentID: pid))
            }

            // Move money into savings.
            if month >= FinanceCal.monthStart(FinanceCal.addYears(-5, to: today)) {
                addTransfer(from: salary.id, to: savings.id,
                            amount: Int64(800_000 + yearOffset * 120_000),
                            date: dateFor(2), note: "Monthly savings")
            }

            // Credit card purchases and a payment that is a transfer, not an expense.
            if month >= FinanceCal.monthStart(FinanceCal.addYears(-5, to: today)) {
                let spend = Int64(rng.int(380_000...1_600_000))
                add(FinTransaction(date: dateFor(rng.int(10...26)), amountPaise: spend,
                                   direction: .outflow, type: .expense, accountID: card.id,
                                   categoryID: rng.pick([cat("expense.food"), cat("expense.shopping"), cat("expense.entertainment")]),
                                   merchant: rng.pick(["Amazon", "Bookstore", "Cinema", "Cafe Third Wave"]),
                                   paymentMethod: .card, verification: .verified))
                cardSpendSincePayment += spend
                if cardSpendSincePayment > 500_000 {
                    addTransfer(from: salary.id, to: card.id,
                                amount: cardSpendSincePayment - 100_000,
                                date: dateFor(27), note: "Credit card bill")
                    cardSpendSincePayment = 100_000
                }
            }

            // Education loan EMI.
            if month >= FinanceCal.monthStart(loanStart) {
                let principal: Int64 = 7_300_00 / 100 * 100
                let interest: Int64 = 1_200_00 / 100 * 100
                let amount = principal + interest
                let d = dateFor(7)
                var txn = FinTransaction(date: d, amountPaise: amount, direction: .outflow,
                                         type: .loanRepayment, accountID: salary.id,
                                         categoryID: cat("expense.interest"),
                                         merchant: "Education loan EMI",
                                         paymentMethod: .autoDebit,
                                         verification: .verified,
                                         liabilityID: FinID.stable("demo.liability.education"),
                                         principalPaise: principal,
                                         interestPaise: interest)
                txn.isDemo = true
                transactions.append(txn)
                debtPayments.append(FinDebtPayment(liabilityID: FinID.stable("demo.liability.education"),
                                                   transactionID: txn.id, date: d,
                                                   amountPaise: amount,
                                                   principalPaise: principal,
                                                   interestPaise: interest,
                                                   note: "Monthly EMI", isDemo: true))
            }

            // Yearly interest and tax.
            if month.hasSuffix("-03") {
                add(FinTransaction(date: dateFor(28), amountPaise: Int64(rng.int(120_000...460_000)),
                                   direction: .inflow, type: .interest, accountID: savings.id,
                                   categoryID: cat("income.interest"),
                                   merchant: "Northstar savings interest",
                                   reference: "INT-\(String(month.prefix(4)))",
                                   source: .imported, verification: .verified))
            }
            if month.hasSuffix("-07") {
                add(FinTransaction(date: dateFor(15), amountPaise: Int64(rng.int(800_000...2_400_000)),
                                   direction: .outflow, type: .tax, accountID: salary.id,
                                   categoryID: cat("expense.tax"),
                                   merchant: "Income tax", paymentMethod: .netBanking,
                                   verification: .verified))
            }

            // Travel twice a year.
            let monthNumber = Int(month.dropFirst(5).prefix(2)) ?? 1
            if monthNumber == 5 || monthNumber == 12 {
                add(FinTransaction(date: dateFor(rng.int(10...22)),
                                   amountPaise: Int64(rng.int(1_800_000...5_400_000)),
                                   direction: .outflow, type: .expense, accountID: card.id,
                                   categoryID: cat("expense.travel"),
                                   merchant: rng.pick(["IndiGo", "IRCTC", "Himalayan stay", "Goa trip"]),
                                   paymentMethod: .card, verification: .verified))
            }

            // Rare refund.
            if monthIndex % 11 == 4 {
                add(FinTransaction(date: dateFor(19), amountPaise: Int64(rng.int(70_000...260_000)),
                                   direction: .inflow, type: .refund, accountID: card.id,
                                   categoryID: cat("expense.shopping"),
                                   merchant: "Amazon refund", paymentMethod: .card,
                                   verification: .verified,
                                   linkedTransactionID: nil))
            }

            monthIndex += 1
        }

        // A couple of large one-off purchases.
        add(FinTransaction(date: FinanceCal.addYears(-6, to: today), amountPaise: 8_500_000,
                           direction: .outflow, type: .expense, accountID: salary.id,
                           categoryID: cat("expense.equipment"),
                           merchant: "Apple reseller", paymentMethod: .card,
                           note: "First editing laptop", verification: .verified))
        add(FinTransaction(date: FinanceCal.addYears(-2, to: today), amountPaise: 6_500_000,
                           direction: .outflow, type: .expense, accountID: salary.id,
                           categoryID: cat("expense.equipment"),
                           merchant: "Camera store", paymentMethod: .card,
                           note: "Camera body", verification: .verified))

        // MARK: Investments

        var investments: [FinInvestment] = []
        let fund1 = FinInvestment(id: pid, name: "Nifty index fund", assetClass: .mutualFund,
                                  institution: "Meridian Invest", units: 1_842.44,
                                  purchaseDate: sipStart, purchasePricePaise: 16_500,
                                  investedPaise: sipTotal,
                                  currentValuePaise: Int64(Double(sipTotal) * 1.31),
                                  currentValueOn: today,
                                  notes: "Monthly SIP from the salary account.",
                                  accountID: salary.id, isDemo: true)
        investments.append(fund1)

        let fund2 = FinInvestment(id: pid2, name: "Bluechip equity fund", assetClass: .mutualFund,
                                  institution: "Meridian Invest", units: 620.10,
                                  purchaseDate: FinanceCal.addYears(-5, to: today),
                                  purchasePricePaise: 31_400,
                                  investedPaise: 1_950_000, currentValuePaise: 2_860_000,
                                  currentValueOn: today,
                                  notes: "Lump sum plus top-ups.",
                                  isDemo: true)
        investments.append(fund2)

        let gold = FinInvestment(id: pid3, name: "Sovereign gold bonds", assetClass: .gold,
                                 institution: "Reserve Bank", units: 40,
                                 purchaseDate: FinanceCal.addYears(-3, to: today),
                                 purchasePricePaise: 480_000,
                                 investedPaise: 1_920_000, currentValuePaise: 2_640_000,
                                 currentValueOn: today,
                                 notes: "Long-term store of value.", isDemo: true)
        investments.append(gold)

        let bond = FinInvestment(id: pid4, name: "Short-duration bond fund", assetClass: .bond,
                                 institution: "Meridian Invest", units: 300,
                                 purchaseDate: FinanceCal.addYears(-2, to: today),
                                 purchasePricePaise: 10_000,
                                 investedPaise: 300_000, currentValuePaise: 336_000,
                                 currentValueOn: today,
                                 notes: "Parking money for a house deposit.", isDemo: true)
        investments.append(bond)

        // Quarterly valuations, each recorded on the day. The most recent is
        // today's value; earlier ones are historical evidence, not interpolation.
        var valuations: [FinValuation] = []
        for inv in investments {
            guard let bought = inv.purchaseDate else { continue }
            let monthsHeld = max(1, FinanceCal.daysBetween(bought, today) / 30)
            var step = 0
            while step <= monthsHeld {
                let date = FinanceCal.addMonths(-monthsHeld + step, to: today)
                if date >= bought && date <= today, step % 3 == 0 {
                    let fraction = Double(step) / Double(max(monthsHeld, 1))
                    let wobble = 1.0 + 0.035 * sin(Double(step) * 0.9)
                    let growth = 1.0 + (Double(inv.currentValuePaise) / Double(max(1, inv.investedPaise)) - 1.0) * fraction
                    let value = Int64(Double(inv.investedPaise) * growth * wobble)
                    valuations.append(FinValuation(investmentID: inv.id, date: date,
                                                   valuePaise: max(0, value),
                                                   source: .manual,
                                                   note: "Quarterly review", isDemo: true))
                }
                step += 3
            }
        }
        doc.investments = investments
        doc.valuations = valuations

        // MARK: Liabilities

        let education = FinLiability(id: FinID.stable("demo.liability.education"),
                                     name: "Education loan", kind: .educationLoan,
                                     lender: "Northstar Bank", ownership: .personal,
                                     originalPrincipalPaise: 6_000_000,
                                     outstandingPaise: 6_000_000,
                                     asOf: loanStart,
                                     interestRateBps: 950, emiPaise: 850_000,
                                     dueDay: 7, startDate: loanStart,
                                     maturityDate: FinanceCal.addYears(3, to: today),
                                     notes: "Personal responsibility. Interest is tracked separately.",
                                     isDemo: true)
        let cardLiability = FinLiability(id: FinID.stable("demo.liability.card"),
                                         name: "Aster credit card", kind: .creditCard,
                                         lender: "Aster Financial", ownership: .personal,
                                         originalPrincipalPaise: 0,
                                         outstandingPaise: 0,
                                         asOf: today, interestRateBps: 4200,
                                         emiPaise: 0, dueDay: 18,
                                         startDate: card.openingDate,
                                         accountID: card.id,
                                         notes: "Outstanding is derived from the linked card account.",
                                         isDemo: true)
        doc.liabilities = [education, cardLiability]
        doc.debtPayments = debtPayments

        // MARK: Budgets

        let monthNow = FinanceCal.monthStart(today)
        func budget(_ name: String, _ category: String, _ amount: Int64) -> FinBudget {
            FinBudget(name: name, categoryID: cat(category), period: .monthly,
                      startDate: monthNow, plannedPaise: amount, isDemo: true)
        }
        doc.budgets = [
            budget("Food & cafés", "expense.food", 800_000),
            budget("Groceries", "expense.groceries", 1_200_000),
            budget("Shopping", "expense.shopping", 1_000_000),
            budget("Subscriptions", "expense.subscriptions", 100_000),
            FinBudget(name: "Everything", categoryID: nil, period: .monthly,
                      startDate: monthNow, plannedPaise: 6_500_000,
                      note: "A ceiling for all ordinary spending.", isDemo: true),
        ]

        // MARK: Goals

        doc.goals = [
            FinGoal(name: "Emergency fund", kind: .emergencyFund,
                    targetPaise: 5_000_000, currentPaise: 3_150_000,
                    deadline: FinanceCal.addMonths(18, to: today),
                    monthlyContributionPaise: 110_000,
                    accountID: savings.id,
                    note: "Six months of essential spending.", isDemo: true),
            FinGoal(name: "New camera kit", kind: .purchase,
                    targetPaise: 1_800_000, currentPaise: 650_000,
                    deadline: FinanceCal.addMonths(9, to: today),
                    monthlyContributionPaise: 80_000,
                    note: "Planning figure only — the money stays in the accounts above.", isDemo: true),
            FinGoal(name: "Investment corpus", kind: .investment,
                    targetPaise: 20_000_000, currentPaise: 7_400_000,
                    deadline: FinanceCal.addYears(5, to: today),
                    monthlyContributionPaise: 150_000, isDemo: true),
        ]

        // MARK: Recurring commitments

        doc.recurring = [
            FinRecurring(name: "Rent", kind: .rent, amountPaise: 2_450_000,
                         cadence: .monthly, nextDate: FinanceEngine.nextMonthlyDay(3, asOf: today),
                         accountID: salary.id, categoryID: cat("expense.rent"),
                         vendor: "Landlord", isDemo: true),
            FinRecurring(name: "Nifty index SIP", kind: .sip, amountPaise: 900_000,
                         cadence: .monthly, nextDate: FinanceEngine.nextMonthlyDay(5, asOf: today),
                         accountID: salary.id, vendor: "Meridian Invest", isDemo: true),
            FinRecurring(name: "Streamly", kind: .subscription, amountPaise: 64_900,
                         cadence: .monthly, nextDate: FinanceEngine.nextMonthlyDay(6, asOf: today),
                         accountID: card.id, categoryID: cat("expense.subscriptions"),
                         vendor: "Streamly", isDemo: true),
            FinRecurring(name: "TuneBox", kind: .subscription, amountPaise: 19_900,
                         cadence: .monthly, nextDate: FinanceEngine.nextMonthlyDay(12, asOf: today),
                         accountID: card.id, categoryID: cat("expense.subscriptions"),
                         vendor: "TuneBox", isDemo: true),
            FinRecurring(name: "Broadband", kind: .bill, amountPaise: 99_900,
                         cadence: .monthly, nextDate: FinanceEngine.nextMonthlyDay(9, asOf: today),
                         accountID: salary.id, categoryID: cat("expense.utilities"),
                         vendor: "Fiberline", isDemo: true),
            FinRecurring(name: "Health insurance", kind: .insurance, amountPaise: 1_850_000,
                         cadence: .yearly, nextDate: FinanceCal.addMonths(4, to: today),
                         accountID: salary.id, categoryID: cat("expense.insurance"),
                         vendor: "Northstar Health", isDemo: true),
        ]

        // MARK: A verified statement and reconciliation

        let lastMonthEnd = FinanceCal.monthEnd(FinanceCal.addMonths(-1, to: today))
        let statementID = FinID.stable("demo.statement.salary.last")
        let statement = FinStatement(id: statementID, accountID: salary.id,
                                     institution: "Northstar Bank",
                                     fileName: "northstar-salary-\(FinanceCal.monthKey(lastMonthEnd)).csv",
                                     fileSize: 48_210, fileType: "text/csv",
                                     periodStart: FinanceCal.monthStart(lastMonthEnd),
                                     periodEnd: lastMonthEnd, uploadedAt: FinNow.stamp(),
                                     status: .parsed, checksum: "demo-checksum",
                                     note: "Demo statement. Not a real bank file.", isDemo: true)
        doc.statements = [
            statement,
            FinStatement(id: FinID.stable("demo.statement.card"),
                         accountID: card.id, institution: "Aster Financial",
                         fileName: "aster-card-\(FinanceCal.monthKey(today)).pdf",
                         fileSize: 188_301, fileType: "application/pdf",
                         uploadedAt: FinNow.stamp(), status: .awaitingParser,
                         note: "Demo upload waiting for the import engine.", isDemo: true),
        ]

        doc.transactions = transactions
        doc.transfers = transfers

        // The salary account's last-month closing balance is the verified
        // anchor. Compute it without an anchor first, then store it.
        let computedClosing = FinanceEngine.accountBalance(doc, account: salary, asOf: lastMonthEnd).paise
        if let i = doc.accounts.firstIndex(where: { $0.id == salary.id }) {
            doc.accounts[i].statementBalancePaise = computedClosing
            doc.accounts[i].statementBalanceOn = lastMonthEnd
            doc.accounts[i].statementBalanceSource = .verified
            doc.accounts[i].lastReconciledOn = today
        }
        doc.reconciliations = [
            FinReconciliation(accountID: salary.id, statementID: statementID,
                              periodStart: FinanceCal.monthStart(lastMonthEnd),
                              periodEnd: lastMonthEnd,
                              openingPaise: computedClosing,
                              expectedOpeningPaise: computedClosing,
                              closingPaise: computedClosing,
                              computedClosingPaise: computedClosing,
                              status: .matched,
                              note: "Demo reconciliation.", isDemo: true),
        ]

        // MARK: Milestones and one audit example

        doc.milestones = [
            FinMilestone(date: FinanceCal.addYears(-7, to: today), title: "First freelance payment",
                         detail: "A small editing project paid for a new hard drive.",
                         kind: .firstFreelance, certainty: .verified, isDemo: true),
            FinMilestone(date: FinanceCal.addYears(-6, to: today), title: "First salary",
                         detail: "Started full-time. Savings rate became possible.",
                         kind: .firstSalary, certainty: .verified, isDemo: true),
            FinMilestone(date: FinanceCal.addYears(-4, to: today), title: "First ₹1 lakh invested",
                         detail: "Reached a six-figure investment balance.",
                         kind: .savings, certainty: .calculated, isDemo: true),
            FinMilestone(date: FinanceCal.addYears(-2, to: today), title: "Bought the camera",
                         detail: "A planned purchase, not an impulse buy.",
                         kind: .majorPurchase, certainty: .verified, isDemo: true),
            FinMilestone(date: FinanceCal.addYears(-1, to: today), title: "Net worth crossed ₹20 lakh",
                         detail: "Combined cash and investments.", kind: .netWorth,
                         certainty: .calculated, isDemo: true),
        ]

        if let grocery = doc.transactions.first(where: { $0.categoryID == cat("expense.groceries") }) {
            var updated = grocery
            updated.note = "Card statement description corrected"
            if let i = doc.transactions.firstIndex(where: { $0.id == grocery.id }) {
                doc.transactions[i] = updated
            }
            FinAudit.record(&doc, entityType: "transaction", entityID: grocery.id,
                            action: .updated, field: "note",
                            oldValue: "", newValue: updated.note,
                            reason: "Demo correction — original values remain in the audit log",
                            sourceTransactionID: grocery.id, isDemo: true)
        }

        doc.updatedAt = FinNow.stamp()
        return doc
    }
}
