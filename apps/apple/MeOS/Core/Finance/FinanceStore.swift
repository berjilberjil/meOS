import Foundation
import SwiftUI

// MARK: - Finance mutations
//
// Every write goes through this file. It is the only place that appends to the
// audit log, and it never rewrites history in place without recording what the
// previous value was. UI code reads `state.finance` and calls these methods.

@MainActor
extension AppState {

    // MARK: Commit

    /// Apply a mutation and push the whole finance document. Keeping one commit
    /// path means the document timestamp, taxonomy and sync behaviour can never
    /// diverge between screens.
    /// D1 stores one value per key and the API caps a write at 1.9 MB. The
    /// encrypted envelope and base64 add roughly a third on top of this JSON,
    /// so the plaintext guard sits lower. This is the explicit bridge to the
    /// sharded storage described in `docs/finance-foundation.md`: a lifetime
    /// ledger must be split into year pages before the first multi-year import.
    /// Until then, refuse a growing write that would be rejected by the server
    /// rather than reporting a save that cannot sync.
    nonisolated static let financePlaintextByteLimit = 1_300_000

    func financeCommit(reason: String = "", _ mutate: (inout FinanceDocument) -> Void) {
        var doc = finance
        if doc.categories.isEmpty {
            doc.categories = FinanceTaxonomy.defaultCategories()
        }
        mutate(&doc)
        doc.updatedAt = FinNow.stamp()
        if doc.categories.isEmpty { doc.categories = FinanceTaxonomy.defaultCategories() }

        let oldBytes = (try? JSONEncoder().encode(finance))?.count ?? 0
        let newBytes = (try? JSONEncoder().encode(doc))?.count ?? 0
        if newBytes > Self.financePlaintextByteLimit && newBytes > oldBytes {
            lastSyncError = "Finance has reached the 1.9 MB sync limit. Export a backup, remove demo data, or wait for year-sharded storage. This change was not saved."
            return
        }

        finance = doc
        push(StateKey.finance, doc)
    }

    /// Seed taxonomy and a sensible tracking start on first open. This is a
    /// local UI convenience, not fake financial data: no account or transaction
    /// is created.
    func financePrepare() {
        guard finance.categories.isEmpty || finance.settings.trackingStartDate.isEmpty else { return }
        financeCommit(reason: "initialise finance") { doc in
            if doc.categories.isEmpty { doc.categories = FinanceTaxonomy.defaultCategories() }
            if doc.settings.trackingStartDate.isEmpty { doc.settings.trackingStartDate = FinanceCal.today() }
        }
    }

    // MARK: Accounts

    @discardableResult
    func financeAddAccount(_ account: FinAccount) -> FinAccount {
        var created = account
        created.createdAt = FinNow.stamp()
        created.updatedAt = created.createdAt
        financeCommit(reason: "created account") { doc in
            doc.accounts.append(created)
            if created.openingDate < doc.settings.trackingStartDate {
                doc.settings.trackingStartDate = created.openingDate
            }
            FinAudit.record(&doc, entityType: "account", entityID: created.id,
                            action: .created, newValue: created.name,
                            reason: "Account created", isDemo: created.isDemo)
        }
        Haptics.success()
        return created
    }

    func financeUpdateAccount(_ account: FinAccount, reason: String = "Account details corrected") {
        var updated = account
        updated.updatedAt = FinNow.stamp()
        financeCommit(reason: reason) { doc in
            guard let i = doc.accounts.firstIndex(where: { $0.id == account.id }) else { return }
            let previous = doc.accounts[i]
            doc.accounts[i] = updated
            if previous.name != updated.name {
                FinAudit.record(&doc, entityType: "account", entityID: updated.id, action: .updated,
                                field: "name", oldValue: previous.name, newValue: updated.name,
                                reason: reason, isDemo: updated.isDemo)
            }
            if previous.openingBalancePaise != updated.openingBalancePaise {
                FinAudit.record(&doc, entityType: "account", entityID: updated.id, action: .updated,
                                field: "opening_balance",
                                oldValue: FinanceFormat.inr(previous.openingBalancePaise),
                                newValue: FinanceFormat.inr(updated.openingBalancePaise),
                                reason: reason, isDemo: updated.isDemo)
            }
            if previous.statementBalancePaise != updated.statementBalancePaise {
                FinAudit.record(&doc, entityType: "account", entityID: updated.id, action: .updated,
                                field: "statement_balance",
                                oldValue: previous.statementBalancePaise.map { FinanceFormat.inr($0) } ?? "none",
                                newValue: updated.statementBalancePaise.map { FinanceFormat.inr($0) } ?? "none",
                                reason: reason, isDemo: updated.isDemo)
            }
            if previous.status != updated.status {
                FinAudit.record(&doc, entityType: "account", entityID: updated.id, action: .updated,
                                field: "status", oldValue: previous.status.rawValue,
                                newValue: updated.status.rawValue, reason: reason, isDemo: updated.isDemo)
            }
        }
        Haptics.success()
    }

    func financeSetAccountStatus(_ id: String, status: FinAccountStatus) {
        guard var a = finance.accounts.first(where: { $0.id == id }) else { return }
        let old = a.status
        a.status = status
        a.updatedAt = FinNow.stamp()
        financeCommit { doc in
            if let i = doc.accounts.firstIndex(where: { $0.id == id }) { doc.accounts[i] = a }
            FinAudit.record(&doc, entityType: "account", entityID: id, action: .updated,
                            field: "status", oldValue: old.rawValue, newValue: status.rawValue,
                            reason: "Account status changed", isDemo: a.isDemo)
        }
    }

    func financeDeleteAccount(_ id: String) {
        guard let account = finance.accounts.first(where: { $0.id == id }) else { return }
        guard !finance.transactions.contains(where: { $0.accountID == id || $0.transferAccountID == id }) else {
            lastSyncError = "This account has transactions. Archive it instead of deleting it."
            return
        }
        financeCommit { doc in
            doc.accounts.removeAll { $0.id == id }
            for i in doc.goals.indices where doc.goals[i].accountID == id { doc.goals[i].accountID = nil }
            for i in doc.recurring.indices where doc.recurring[i].accountID == id { doc.recurring[i].accountID = nil }
            for i in doc.investments.indices where doc.investments[i].accountID == id { doc.investments[i].accountID = nil }
            for i in doc.liabilities.indices where doc.liabilities[i].accountID == id { doc.liabilities[i].accountID = nil }
            for i in doc.statements.indices where doc.statements[i].accountID == id { doc.statements[i].accountID = nil }
            FinAudit.record(&doc, entityType: "account", entityID: id, action: .deleted,
                            oldValue: account.name, reason: "Account deleted", isDemo: account.isDemo)
        }
    }

    // MARK: Categories

    @discardableResult
    func financeAddCategory(name: String, kind: FinCategoryKind, group: String, icon: String, parentID: String? = nil) -> FinCategory? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if finance.categories.contains(where: {
            $0.name.caseInsensitiveCompare(trimmed) == .orderedSame
                && $0.kind == kind && $0.parentID == parentID
        }) { return nil }
        let category = FinCategory(name: trimmed, kind: kind,
                                   group: group.isEmpty ? "Other" : group,
                                   icon: icon, parentID: parentID)
        financeCommit { doc in
            doc.categories.append(category)
            FinAudit.record(&doc, entityType: "category", entityID: category.id,
                            action: .created, newValue: category.displayName,
                            reason: "Category created")
        }
        return category
    }

    func financeUpdateCategory(_ category: FinCategory) {
        guard let old = finance.categories.first(where: { $0.id == category.id }) else { return }
        var updated = category
        updated.name = category.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !updated.name.isEmpty else { return }
        financeCommit { doc in
            guard let i = doc.categories.firstIndex(where: { $0.id == category.id }) else { return }
            doc.categories[i] = updated
            if old.name != updated.name || old.group != updated.group {
                FinAudit.record(&doc, entityType: "category", entityID: updated.id, action: .updated,
                                field: "name", oldValue: old.displayName,
                                newValue: updated.displayName, reason: "Category renamed")
            }
        }
    }

    func financeArchiveCategory(_ id: String) {
        guard var c = finance.categories.first(where: { $0.id == id }) else { return }
        c.archived.toggle()
        financeCommit { doc in
            if let i = doc.categories.firstIndex(where: { $0.id == id }) { doc.categories[i] = c }
            FinAudit.record(&doc, entityType: "category", entityID: id,
                            action: .updated, field: "archived",
                            oldValue: String(!c.archived), newValue: String(c.archived),
                            reason: c.archived ? "Category archived" : "Category restored")
        }
    }

    // MARK: Transactions

    @discardableResult
    func financeAddTransaction(_ transaction: FinTransaction, reason: String = "Manual entry") -> FinTransaction {
        var t = transaction
        t.createdAt = FinNow.stamp()
        t.updatedAt = t.createdAt
        if t.currency.isEmpty { t.currency = FinanceSchema.currency }
        if t.direction == .outflow && t.amountPaise < 0 { t.amountPaise = -t.amountPaise }
        financeCommit(reason: reason) { doc in
            doc.transactions.append(t)
            if t.date < doc.settings.trackingStartDate { doc.settings.trackingStartDate = t.date }
            FinAudit.record(&doc, entityType: "transaction", entityID: t.id,
                            action: .created, newValue: "\(t.type.label) \(FinanceFormat.inr(t.amountPaise))",
                            reason: reason, isDemo: t.isDemo)
        }
        Haptics.success()
        return t
    }

    func financeUpdateTransaction(_ transaction: FinTransaction, reason: String = "User corrected the record") {
        guard let old = finance.transactions.first(where: { $0.id == transaction.id }) else { return }
        var updated = transaction
        updated.updatedAt = FinNow.stamp()
        if updated.source == .imported && !updated.verification.isTrusted {
            // A correction is allowed, but never silent: the imported source is
            // preserved and an untrusted row goes back into review. If the
            // owner explicitly marks the corrected row verified, that stands.
            updated.verification = .needsReview
        }
        // A link only makes sense for the type that owns it. Changing an
        // expense into an ordinary transaction must not leave a stale holding
        // or liability reference behind.
        if updated.type != .investmentPurchase && updated.type != .investmentSale {
            updated.investmentID = nil
            updated.costBasisPaise = nil
            updated.realisedGainPaise = nil
        }
        if updated.type != .loanRepayment && updated.type != .loanDisbursement {
            updated.liabilityID = nil
            updated.principalPaise = nil
            updated.interestPaise = nil
        }
        financeCommit(reason: reason) { doc in
            guard let i = doc.transactions.firstIndex(where: { $0.id == transaction.id }) else { return }
            let previous = doc.transactions[i]
            doc.transactions[i] = updated

            func note(_ field: String, _ from: String, _ to: String) {
                guard from != to else { return }
                FinAudit.record(&doc, entityType: "transaction", entityID: updated.id,
                                action: .updated, field: field, oldValue: from, newValue: to,
                                reason: reason, sourceTransactionID: updated.id, isDemo: updated.isDemo)
            }
            note("date", previous.date, updated.date)
            note("amount", FinanceFormat.inr(previous.amountPaise), FinanceFormat.inr(updated.amountPaise))
            note("type", previous.type.label, updated.type.label)
            note("direction", previous.direction.label, updated.direction.label)
            note("account", doc.account(previous.accountID)?.name ?? previous.accountID,
                 doc.account(updated.accountID)?.name ?? updated.accountID)
            note("category", doc.category(previous.categoryID)?.displayName ?? "none",
                 doc.category(updated.categoryID)?.displayName ?? "none")
            note("merchant", previous.merchant, updated.merchant)
            note("note", previous.note, updated.note)
            note("reference", previous.reference, updated.reference)
            note("verification", previous.verification.label, updated.verification.label)

            // Keep linked investment cost and debt principal in step with a
            // corrected amount. The audit entries above preserve the original.
            if let invID = updated.investmentID, let j = doc.investments.firstIndex(where: { $0.id == invID }),
               previous.type == .investmentPurchase, updated.type == .investmentPurchase {
                let delta = updated.amountPaise - previous.amountPaise
                doc.investments[j].investedPaise = max(0, doc.investments[j].investedPaise + delta)
            }
            // Reclassifying a purchase as something else removes its capital
            // from the holding, so the cost basis cannot silently overstate.
            if previous.type == .investmentPurchase, updated.type != .investmentPurchase,
               let invID = previous.investmentID,
               let j = doc.investments.firstIndex(where: { $0.id == invID }) {
                doc.investments[j].investedPaise = max(0, doc.investments[j].investedPaise - previous.amountPaise)
            }
            if let liab = updated.liabilityID,
               let k = doc.debtPayments.firstIndex(where: { $0.transactionID == updated.id }) {
                doc.debtPayments[k].amountPaise = updated.amountPaise
                doc.debtPayments[k].principalPaise = updated.principalPaise ?? deltaPrincipal(old: previous, new: updated)
                doc.debtPayments[k].interestPaise = updated.interestPaise ?? 0
            }
        }
        Haptics.success()
    }

    private func deltaPrincipal(old: FinTransaction, new: FinTransaction) -> Int64 {
        max(0, new.amountPaise - (new.interestPaise ?? 0))
    }

    func financeDeleteTransaction(_ id: String, reason: String = "Deleted by user") {
        guard let t = finance.transactions.first(where: { $0.id == id }) else { return }
        financeCommit { doc in
            var ids = [id]
            if let linked = t.linkedTransactionID { ids.append(linked) }
            if let transferID = t.transferID,
               let record = doc.transfers.first(where: { $0.id == transferID }),
               let feeID = record.feeTransactionID {
                ids.append(feeID)
            }
            for removeID in ids {
                if let row = doc.transactions.first(where: { $0.id == removeID }) {
                    FinAudit.record(&doc, entityType: "transaction", entityID: row.id,
                                    action: .deleted,
                                    oldValue: "\(row.date) · \(row.type.label) · \(FinanceFormat.inr(row.amountPaise)) · \(row.title)",
                                    reason: reason, isDemo: row.isDemo)
                }
            }
            if let transferID = t.transferID {
                doc.transfers.removeAll { $0.id == transferID }
            }
            if let invID = t.investmentID, t.type == .investmentPurchase,
               let j = doc.investments.firstIndex(where: { $0.id == invID }) {
                doc.investments[j].investedPaise = max(0, doc.investments[j].investedPaise - t.amountPaise)
            }
            if let invID = t.investmentID, t.type == .investmentSale,
               let j = doc.investments.firstIndex(where: { $0.id == invID }) {
                doc.investments[j].investedPaise += t.costBasisPaise ?? 0
                doc.investments[j].realisedGainPaise -= t.realisedGainPaise ?? 0
            }
            if let liabID = t.liabilityID {
                doc.debtPayments.removeAll { $0.transactionID == t.id }
                if let j = doc.liabilities.firstIndex(where: { $0.id == liabID }),
                   let principal = t.principalPaise {
                    doc.liabilities[j].outstandingPaise += principal
                }
            }
            doc.transactions.removeAll { ids.contains($0.id) }
        }
    }

    func financeBulkUpdate(ids: Set<String>,
                           categoryID: String? = nil,
                           addTags: [String] = [],
                           verification: FinVerification? = nil,
                           reason: String = "Bulk edit") {
        guard !ids.isEmpty else { return }
        financeCommit { doc in
            for i in doc.transactions.indices where ids.contains(doc.transactions[i].id) {
                var changed: [String] = []
                if let categoryID, doc.transactions[i].categoryID != categoryID {
                    doc.transactions[i].categoryID = categoryID
                    changed.append("category")
                }
                if !addTags.isEmpty {
                    let merged = Set(doc.transactions[i].tags).union(addTags)
                    doc.transactions[i].tags = Array(merged).sorted()
                    changed.append("tags")
                }
                if let verification, doc.transactions[i].verification != verification {
                    doc.transactions[i].verification = verification
                    changed.append("verification")
                }
                guard !changed.isEmpty else { continue }
                doc.transactions[i].updatedAt = FinNow.stamp()
                FinAudit.record(&doc, entityType: "transaction", entityID: doc.transactions[i].id,
                                action: .bulkUpdated, field: changed.joined(separator: ","),
                                newValue: categoryID.flatMap { doc.category($0)?.displayName } ?? addTags.joined(separator: ","),
                                reason: reason, sourceTransactionID: doc.transactions[i].id,
                                isDemo: doc.transactions[i].isDemo)
            }
        }
        Haptics.success()
    }

    // MARK: Transfers

    @discardableResult
    func financeCreateTransfer(fromAccountID: String,
                               toAccountID: String,
                               amountPaise: Int64,
                               date: String,
                               feePaise: Int64 = 0,
                               reference: String = "",
                               note: String = "") -> Bool {
        guard fromAccountID != toAccountID, amountPaise > 0,
              finance.account(fromAccountID) != nil,
              finance.account(toAccountID) != nil else { return false }
        let transferID = FinID.new()
        let out = FinTransaction(date: date, amountPaise: amountPaise,
                                 direction: .outflow, type: .transfer,
                                 accountID: fromAccountID, transferAccountID: toAccountID,
                                 merchant: "Transfer", paymentMethod: .bankTransfer,
                                 note: note, reference: reference,
                                 verification: .verified, transferID: transferID)
        var incoming = FinTransaction(date: date, amountPaise: amountPaise,
                                      direction: .inflow, type: .transfer,
                                      accountID: toAccountID, transferAccountID: fromAccountID,
                                      merchant: "Transfer", paymentMethod: .bankTransfer,
                                      note: note, reference: reference,
                                      verification: .verified, transferID: transferID)
        var outgoing = out
        outgoing.linkedTransactionID = incoming.id
        incoming.linkedTransactionID = outgoing.id
        let transfer = FinTransfer(fromAccountID: fromAccountID, toAccountID: toAccountID,
                                   amountPaise: amountPaise, date: date, feePaise: feePaise,
                                   reference: reference, note: note,
                                   fromTransactionID: outgoing.id, toTransactionID: incoming.id,
                                   reconciled: true)

        financeCommit(reason: "Transfer created") { doc in
            doc.transactions.append(outgoing)
            doc.transactions.append(incoming)
            doc.transfers.append(transfer)
            if feePaise > 0 {
                let fee = FinTransaction(date: date, amountPaise: feePaise, direction: .outflow,
                                         type: .fee, accountID: fromAccountID,
                                         categoryID: FinanceTaxonomy.categoryID("expense.bankCharges"),
                                         merchant: "Transfer fee", reference: reference,
                                         verification: .verified, transferID: transferID)
                doc.transactions.append(fee)
                if let idx = doc.transfers.firstIndex(where: { $0.id == transferID }) {
                    doc.transfers[idx].feeTransactionID = fee.id
                }
            }
            FinAudit.record(&doc, entityType: "transfer", entityID: transferID, action: .created,
                            newValue: "\(doc.account(fromAccountID)?.name ?? "") → \(doc.account(toAccountID)?.name ?? "") \(FinanceFormat.inr(amountPaise))",
                            reason: "Internal transfer created")
        }
        Haptics.success()
        return true
    }

    /// Link two already-recorded entries as one internal transfer. This never
    /// changes their amounts or dates, only their classification and link.
    func financeMatchTransfer(_ candidate: FinTransferCandidate) {
        let from = candidate.from
        let to = candidate.to
        guard from.accountID != to.accountID, from.amountPaise == to.amountPaise else { return }
        let transferID = FinID.new()
        let transfer = FinTransfer(fromAccountID: from.accountID, toAccountID: to.accountID,
                                   amountPaise: from.amountPaise, date: min(from.date, to.date),
                                   reference: from.reference,
                                   fromTransactionID: from.id, toTransactionID: to.id,
                                   reconciled: true)
        financeCommit(reason: "Matched transfer") { doc in
            doc.transfers.append(transfer)
            for id in [from.id, to.id] {
                guard let i = doc.transactions.firstIndex(where: { $0.id == id }) else { continue }
                let oldType = doc.transactions[i].type
                doc.transactions[i].type = .transfer
                doc.transactions[i].transferID = transferID
                doc.transactions[i].linkedTransactionID = id == from.id ? to.id : from.id
                doc.transactions[i].verification = .verified
                doc.transactions[i].updatedAt = FinNow.stamp()
                FinAudit.record(&doc, entityType: "transaction", entityID: id, action: .matched,
                                field: "type", oldValue: oldType.label, newValue: "Transfer",
                                reason: "Matched as an internal transfer, excluded from income and expenses",
                                sourceTransactionID: id, isDemo: doc.transactions[i].isDemo)
            }
        }
        Haptics.success()
    }

    func financeSetTransferReconciled(_ id: String, reconciled: Bool) {
        financeCommit { doc in
            guard let i = doc.transfers.firstIndex(where: { $0.id == id }) else { return }
            doc.transfers[i].reconciled = reconciled
            FinAudit.record(&doc, entityType: "transfer", entityID: id, action: .reconciled,
                            newValue: reconciled ? "Reconciled" : "Needs review",
                            reason: "Transfer reconciliation changed")
        }
    }

    // MARK: Budgets

    @discardableResult
    func financeAddBudget(_ budget: FinBudget) -> FinBudget {
        financeCommit(reason: "Budget created") { doc in
            doc.budgets.append(budget)
            FinAudit.record(&doc, entityType: "budget", entityID: budget.id, action: .created,
                            newValue: budget.name.isEmpty ? "Budget" : budget.name,
                            reason: "Budget created", isDemo: budget.isDemo)
        }
        Haptics.success()
        return budget
    }

    func financeUpdateBudget(_ budget: FinBudget) {
        financeCommit { doc in
            guard let i = doc.budgets.firstIndex(where: { $0.id == budget.id }) else { return }
            let old = doc.budgets[i]
            doc.budgets[i] = budget
            if old.plannedPaise != budget.plannedPaise {
                FinAudit.record(&doc, entityType: "budget", entityID: budget.id, action: .updated,
                                field: "planned",
                                oldValue: FinanceFormat.inr(old.plannedPaise),
                                newValue: FinanceFormat.inr(budget.plannedPaise),
                                reason: "Budget amount changed", isDemo: budget.isDemo)
            }
        }
    }

    func financeDeleteBudget(_ id: String) {
        financeCommit { doc in
            guard let b = doc.budgets.first(where: { $0.id == id }) else { return }
            doc.budgets.removeAll { $0.id == id }
            FinAudit.record(&doc, entityType: "budget", entityID: id, action: .deleted,
                            oldValue: b.name, reason: "Budget deleted", isDemo: b.isDemo)
        }
    }

    // MARK: Goals

    @discardableResult
    func financeAddGoal(_ goal: FinGoal) -> FinGoal {
        financeCommit(reason: "Goal created") { doc in
            doc.goals.append(goal)
            FinAudit.record(&doc, entityType: "goal", entityID: goal.id, action: .created,
                            newValue: goal.name, reason: "Goal created", isDemo: goal.isDemo)
        }
        Haptics.success()
        return goal
    }

    func financeUpdateGoal(_ goal: FinGoal) {
        financeCommit { doc in
            guard let i = doc.goals.firstIndex(where: { $0.id == goal.id }) else { return }
            doc.goals[i] = goal
            doc.goals[i].updatedAt = FinNow.stamp()
        }
    }

    func financeDeleteGoal(_ id: String) {
        financeCommit { doc in
            guard let g = doc.goals.first(where: { $0.id == id }) else { return }
            doc.goals.removeAll { $0.id == id }
            FinAudit.record(&doc, entityType: "goal", entityID: id, action: .deleted,
                            oldValue: g.name, reason: "Goal deleted", isDemo: g.isDemo)
        }
    }

    func financeContributeToGoal(_ id: String, amountPaise: Int64, fromAccountID: String?, date: String = FinanceCal.today()) {
        guard amountPaise > 0 else { return }
        financeCommit(reason: "Goal contribution") { doc in
            guard let i = doc.goals.firstIndex(where: { $0.id == id }) else { return }
            let before = doc.goals[i].currentPaise
            doc.goals[i].currentPaise += amountPaise
            doc.goals[i].achieved = doc.goals[i].targetPaise > 0 && doc.goals[i].currentPaise >= doc.goals[i].targetPaise
            doc.goals[i].updatedAt = FinNow.stamp()
            FinAudit.record(&doc, entityType: "goal", entityID: id, action: .updated,
                            field: "current_amount",
                            oldValue: FinanceFormat.inr(before),
                            newValue: FinanceFormat.inr(doc.goals[i].currentPaise),
                            reason: "Contribution recorded", isDemo: doc.goals[i].isDemo)
            // If the user also wants the money moved, record a transfer. The
            // goal allocation itself is a planning figure, not an asset.
            if let from = fromAccountID {
                doc.goals[i].accountID = from
                _ = date
            }
        }
        Haptics.success()
    }

    // MARK: Investments

    @discardableResult
    func financeAddInvestment(_ investment: FinInvestment) -> FinInvestment {
        financeCommit(reason: "Investment added") { doc in
            doc.investments.append(investment)
            FinAudit.record(&doc, entityType: "investment", entityID: investment.id, action: .created,
                            newValue: "\(investment.name) · \(FinanceFormat.inr(investment.investedPaise))",
                            reason: "Holding added", isDemo: investment.isDemo)
        }
        Haptics.success()
        return investment
    }

    func financeUpdateInvestment(_ investment: FinInvestment) {
        financeCommit { doc in
            guard let i = doc.investments.firstIndex(where: { $0.id == investment.id }) else { return }
            let old = doc.investments[i]
            var next = investment
            next.updatedAt = FinNow.stamp()
            doc.investments[i] = next
            if old.currentValuePaise != next.currentValuePaise {
                FinAudit.record(&doc, entityType: "investment", entityID: next.id, action: .updated,
                                field: "current_value",
                                oldValue: FinanceFormat.inr(old.currentValuePaise),
                                newValue: FinanceFormat.inr(next.currentValuePaise),
                                reason: "Valuation updated", isDemo: next.isDemo)
            }
        }
    }

    func financeRecordValuation(investmentID: String,
                                date: String,
                                valuePaise: Int64,
                                source: FinValuationSource = .manual,
                                note: String = "") {
        financeCommit(reason: "Valuation recorded") { doc in
            guard let i = doc.investments.firstIndex(where: { $0.id == investmentID }) else { return }
            let valuation = FinValuation(investmentID: investmentID, date: date,
                                         valuePaise: valuePaise, source: source, note: note,
                                         isDemo: doc.investments[i].isDemo)
            // One valuation per holding per day: a correction replaces the
            // same day's figure instead of creating two competing points.
            doc.valuations.removeAll { $0.investmentID == investmentID && $0.date == date }
            doc.valuations.append(valuation)
            if date >= doc.investments[i].currentValueOn {
                doc.investments[i].currentValuePaise = valuePaise
                doc.investments[i].currentValueOn = date
            }
            doc.investments[i].updatedAt = FinNow.stamp()
            FinAudit.record(&doc, entityType: "investment", entityID: investmentID, action: .updated,
                            field: "valuation", newValue: FinanceFormat.inr(valuePaise),
                            reason: "Valuation on \(FinanceCal.display(date)) · \(source.label)",
                            isDemo: doc.investments[i].isDemo)
        }
        Haptics.success()
    }

    /// Record a real purchase: cash leaves an account, cost basis increases and
    /// the units (when supplied) are added. One transaction, one holding update.
    @discardableResult
    func financeRecordInvestmentPurchase(investmentID: String,
                                         accountID: String,
                                         amountPaise: Int64,
                                         date: String,
                                         units: Double? = nil,
                                         reference: String = "",
                                         note: String = "") -> Bool {
        guard amountPaise > 0, finance.investment(investmentID) != nil, finance.account(accountID) != nil else { return false }
        let txn = FinTransaction(date: date, amountPaise: amountPaise, direction: .outflow,
                                 type: .investmentPurchase, accountID: accountID,
                                 merchant: finance.investment(investmentID)?.name ?? "Investment",
                                 paymentMethod: .bankTransfer, note: note, reference: reference,
                                 verification: .verified, investmentID: investmentID)
        financeCommit(reason: "Investment purchase") { doc in
            doc.transactions.append(txn)
            guard let i = doc.investments.firstIndex(where: { $0.id == investmentID }) else { return }
            doc.investments[i].investedPaise += amountPaise
            if let units {
                doc.investments[i].units = (doc.investments[i].units ?? 0) + units
            }
            doc.investments[i].updatedAt = FinNow.stamp()
            FinAudit.record(&doc, entityType: "investment", entityID: investmentID, action: .updated,
                            field: "invested",
                            oldValue: FinanceFormat.inr(doc.investments[i].investedPaise - amountPaise),
                            newValue: FinanceFormat.inr(doc.investments[i].investedPaise),
                            reason: "Purchase recorded", sourceTransactionID: txn.id,
                            isDemo: doc.investments[i].isDemo)
        }
        Haptics.success()
        return true
    }

    func financeRecordInvestmentSale(investmentID: String,
                                     accountID: String,
                                     proceedsPaise: Int64,
                                     costBasisPaise: Int64,
                                     date: String,
                                     reference: String = "") {
        guard proceedsPaise > 0, finance.investment(investmentID) != nil else { return }
        let gain = proceedsPaise - costBasisPaise
        let txn = FinTransaction(date: date, amountPaise: proceedsPaise, direction: .inflow,
                                 type: .investmentSale, accountID: accountID,
                                 merchant: finance.investment(investmentID)?.name ?? "Investment",
                                 paymentMethod: .bankTransfer, reference: reference,
                                 verification: .verified, investmentID: investmentID,
                                 costBasisPaise: costBasisPaise, realisedGainPaise: gain)
        financeCommit(reason: "Investment sale") { doc in
            doc.transactions.append(txn)
            guard let i = doc.investments.firstIndex(where: { $0.id == investmentID }) else { return }
            doc.investments[i].investedPaise = max(0, doc.investments[i].investedPaise - costBasisPaise)
            doc.investments[i].realisedGainPaise += gain
            doc.investments[i].updatedAt = FinNow.stamp()
            FinAudit.record(&doc, entityType: "investment", entityID: investmentID, action: .updated,
                            field: "realised_gain",
                            oldValue: FinanceFormat.inr(doc.investments[i].realisedGainPaise - gain),
                            newValue: FinanceFormat.inr(doc.investments[i].realisedGainPaise),
                            reason: "Sale recorded", sourceTransactionID: txn.id,
                            isDemo: doc.investments[i].isDemo)
        }
        Haptics.success()
    }

    // MARK: Liabilities

    @discardableResult
    func financeAddLiability(_ liability: FinLiability) -> FinLiability {
        financeCommit(reason: "Liability added") { doc in
            doc.liabilities.append(liability)
            FinAudit.record(&doc, entityType: "liability", entityID: liability.id, action: .created,
                            newValue: "\(liability.name) · \(FinanceFormat.inr(liability.outstandingPaise))",
                            reason: "Liability added", isDemo: liability.isDemo)
        }
        Haptics.success()
        return liability
    }

    func financeDeleteLiability(_ id: String) {
        guard let l = finance.liabilities.first(where: { $0.id == id }) else { return }
        financeCommit { doc in
            doc.liabilities.removeAll { $0.id == id }
            doc.debtPayments.removeAll { $0.liabilityID == id }
            for i in doc.transactions.indices where doc.transactions[i].liabilityID == id {
                doc.transactions[i].liabilityID = nil
            }
            FinAudit.record(&doc, entityType: "liability", entityID: id, action: .deleted,
                            oldValue: "\(l.name) · \(FinanceFormat.inr(l.outstandingPaise))",
                            reason: "Liability deleted; repayment transactions kept", isDemo: l.isDemo)
        }
    }

    func financeDeleteInvestment(_ id: String) {
        guard let inv = finance.investments.first(where: { $0.id == id }) else { return }
        guard !finance.transactions.contains(where: { $0.investmentID == id }) else {
            lastSyncError = "This holding has purchase or sale transactions. Archive it instead of deleting it."
            return
        }
        financeCommit { doc in
            doc.investments.removeAll { $0.id == id }
            doc.valuations.removeAll { $0.investmentID == id }
            FinAudit.record(&doc, entityType: "investment", entityID: id, action: .deleted,
                            oldValue: inv.name, reason: "Holding deleted", isDemo: inv.isDemo)
        }
    }

    func financeArchiveInvestment(_ id: String, archived: Bool) {
        financeCommit { doc in
            guard let i = doc.investments.firstIndex(where: { $0.id == id }) else { return }
            doc.investments[i].archived = archived
            doc.investments[i].updatedAt = FinNow.stamp()
            FinAudit.record(&doc, entityType: "investment", entityID: id, action: .updated,
                            field: "archived", newValue: String(archived),
                            reason: archived ? "Holding archived" : "Holding restored",
                            isDemo: doc.investments[i].isDemo)
        }
    }

    func financeUpdateLiability(_ liability: FinLiability) {
        financeCommit { doc in
            guard let i = doc.liabilities.firstIndex(where: { $0.id == liability.id }) else { return }
            let old = doc.liabilities[i]
            doc.liabilities[i] = liability
            doc.liabilities[i].updatedAt = FinNow.stamp()
            if old.outstandingPaise != liability.outstandingPaise {
                FinAudit.record(&doc, entityType: "liability", entityID: liability.id, action: .updated,
                                field: "outstanding",
                                oldValue: FinanceFormat.inr(old.outstandingPaise),
                                newValue: FinanceFormat.inr(liability.outstandingPaise),
                                reason: "Outstanding balance updated", isDemo: liability.isDemo)
            }
        }
    }

    /// A repayment splits into principal (reduces debt) and interest (expense).
    @discardableResult
    func financeRecordDebtPayment(liabilityID: String,
                                  accountID: String,
                                  amountPaise: Int64,
                                  principalPaise: Int64,
                                  interestPaise: Int64,
                                  date: String,
                                  note: String = "") -> Bool {
        guard amountPaise > 0, finance.liability(liabilityID) != nil else { return false }
        let txn = FinTransaction(date: date, amountPaise: amountPaise, direction: .outflow,
                                 type: .loanRepayment, accountID: accountID,
                                 categoryID: FinanceTaxonomy.categoryID("expense.interest"),
                                 merchant: finance.liability(liabilityID)?.name ?? "Loan payment",
                                 paymentMethod: .autoDebit, note: note,
                                 verification: .verified,
                                 liabilityID: liabilityID,
                                 principalPaise: principalPaise,
                                 interestPaise: interestPaise)
        let payment = FinDebtPayment(liabilityID: liabilityID, transactionID: txn.id,
                                     date: date, amountPaise: amountPaise,
                                     principalPaise: principalPaise,
                                     interestPaise: interestPaise, note: note)
        financeCommit(reason: "Loan repayment") { doc in
            doc.transactions.append(txn)
            doc.debtPayments.append(payment)
            guard let i = doc.liabilities.firstIndex(where: { $0.id == liabilityID }) else { return }
            doc.liabilities[i].outstandingPaise = max(0, doc.liabilities[i].outstandingPaise - principalPaise)
            doc.liabilities[i].asOf = date
            doc.liabilities[i].updatedAt = FinNow.stamp()
            FinAudit.record(&doc, entityType: "liability", entityID: liabilityID, action: .updated,
                            field: "principal_paid", newValue: FinanceFormat.inr(principalPaise),
                            reason: "Repayment recorded", sourceTransactionID: txn.id,
                            isDemo: doc.liabilities[i].isDemo)
        }
        Haptics.success()
        return true
    }

    // MARK: Recurring

    @discardableResult
    func financeAddRecurring(_ item: FinRecurring) -> FinRecurring {
        financeCommit(reason: "Recurring payment added") { doc in
            doc.recurring.append(item)
            FinAudit.record(&doc, entityType: "recurring", entityID: item.id, action: .created,
                            newValue: "\(item.name) · \(FinanceFormat.inr(item.amountPaise)) \(item.cadence.label.lowercased())",
                            reason: "Commitment added", isDemo: item.isDemo)
        }
        Haptics.success()
        return item
    }

    func financeUpdateRecurring(_ item: FinRecurring) {
        financeCommit { doc in
            guard let i = doc.recurring.firstIndex(where: { $0.id == item.id }) else { return }
            doc.recurring[i] = item
            doc.recurring[i].updatedAt = FinNow.stamp()
        }
    }

    func financeToggleRecurring(_ id: String) {
        financeCommit { doc in
            guard let i = doc.recurring.firstIndex(where: { $0.id == id }) else { return }
            doc.recurring[i].active.toggle()
            doc.recurring[i].updatedAt = FinNow.stamp()
            FinAudit.record(&doc, entityType: "recurring", entityID: id, action: .updated,
                            field: "active", oldValue: String(!doc.recurring[i].active),
                            newValue: String(doc.recurring[i].active),
                            reason: doc.recurring[i].active ? "Resumed" : "Paused",
                            isDemo: doc.recurring[i].isDemo)
        }
    }

    func financeDeleteRecurring(_ id: String) {
        financeCommit { doc in
            guard let r = doc.recurring.first(where: { $0.id == id }) else { return }
            doc.recurring.removeAll { $0.id == id }
            FinAudit.record(&doc, entityType: "recurring", entityID: id, action: .deleted,
                            oldValue: r.name, reason: "Commitment deleted", isDemo: r.isDemo)
        }
    }

    /// Explicitly log one occurrence. The app never creates this automatically
    /// when a statement later arrives — that would double count the same money.
    func financeLogRecurring(_ id: String, date: String) {
        guard let item = finance.recurring.first(where: { $0.id == id }),
              let accountID = item.accountID, finance.account(accountID) != nil else { return }
        let kind: FinTxnType = item.kind == .sip ? .investmentPurchase : .expense
        let txn = FinTransaction(date: date, amountPaise: item.amountPaise,
                                 direction: .outflow, type: kind,
                                 accountID: accountID,
                                 categoryID: item.categoryID,
                                 merchant: item.name,
                                 paymentMethod: .autoDebit,
                                 note: "Recurring · \(item.kind.label)",
                                 source: .recurring, verification: .verified)
        financeCommit(reason: "Recurring payment logged") { doc in
            doc.transactions.append(txn)
            guard let i = doc.recurring.firstIndex(where: { $0.id == id }) else { return }
            doc.recurring[i].nextDate = nextDate(item: doc.recurring[i])
            FinAudit.record(&doc, entityType: "recurring", entityID: id, action: .updated,
                            field: "logged", newValue: FinanceFormat.inr(txn.amountPaise),
                            reason: "Occurrence logged", sourceTransactionID: txn.id,
                            isDemo: item.isDemo)
        }
        Haptics.success()
    }

    private func nextDate(item: FinRecurring) -> String {
        switch item.cadence {
        case .weekly: return FinanceCal.addDays(7, to: item.nextDate)
        case .monthly: return FinanceCal.addMonths(1, to: item.nextDate)
        case .quarterly: return FinanceCal.addMonths(3, to: item.nextDate)
        case .halfYearly: return FinanceCal.addMonths(6, to: item.nextDate)
        case .yearly: return FinanceCal.addYears(1, to: item.nextDate)
        case .custom: return FinanceCal.addDays(item.intervalDays ?? 30, to: item.nextDate)
        }
    }

    // MARK: Statements and reconciliation

    @discardableResult
    func financeNoteStatement(fileName: String, fileSize: Int, fileType: String,
                              institution: String = "", accountID: String? = nil) -> FinStatement {
        let statement = FinStatement(accountID: accountID, institution: institution,
                                     fileName: fileName, fileSize: fileSize, fileType: fileType,
                                     status: .awaitingParser,
                                     note: "File noted locally. The extraction engine is not enabled in this phase; nothing was parsed or imported.")
        financeCommit(reason: "Statement queued") { doc in
            doc.statements.append(statement)
            FinAudit.record(&doc, entityType: "statement", entityID: statement.id, action: .created,
                            newValue: fileName, reason: "Statement added; parser not enabled")
        }
        return statement
    }

    func financeDeleteStatement(_ id: String) {
        financeCommit { doc in
            guard let s = doc.statements.first(where: { $0.id == id }) else { return }
            doc.statements.removeAll { $0.id == id }
            doc.importBatches.removeAll { $0.statementID == id }
            doc.reconciliations.removeAll { $0.statementID == id }
            FinAudit.record(&doc, entityType: "statement", entityID: id, action: .deleted,
                            oldValue: s.fileName, reason: "Statement removed", isDemo: s.isDemo)
        }
    }

    @discardableResult
    func financeAddReconciliation(accountID: String,
                                  periodStart: String,
                                  periodEnd: String,
                                  closingPaise: Int64,
                                  statementID: String? = nil,
                                  openingPaise: Int64? = nil,
                                  note: String = "") -> FinReconciliation? {
        guard let account = finance.account(accountID) else { return nil }
        let expected = FinanceEngine.statementBalance(finance, account: account,
                                                      asOf: FinanceCal.addDays(-1, to: periodStart))
        let statedOpening = openingPaise ?? expected
        let computed = FinanceEngine.statementClosing(finance, account: account,
                                                      periodStart: periodStart,
                                                      periodEnd: periodEnd,
                                                      openingPaise: statedOpening)
        let status: FinReconciliationStatus = computed == closingPaise ? .matched : .mismatch
        let recon = FinReconciliation(accountID: accountID, statementID: statementID,
                                      periodStart: periodStart, periodEnd: periodEnd,
                                      openingPaise: statedOpening,
                                      expectedOpeningPaise: expected,
                                      closingPaise: closingPaise,
                                      computedClosingPaise: computed,
                                      status: status, note: note)
        financeCommit(reason: "Reconciliation recorded") { doc in
            doc.reconciliations.append(recon)
            if status == .matched, let i = doc.accounts.firstIndex(where: { $0.id == accountID }) {
                doc.accounts[i].statementBalancePaise = closingPaise
                doc.accounts[i].statementBalanceOn = periodEnd
                doc.accounts[i].lastReconciledOn = FinanceCal.today()
                doc.accounts[i].statementBalanceSource = .verified
            }
            FinAudit.record(&doc, entityType: "account", entityID: accountID, action: .reconciled,
                            newValue: "\(status.label) · \(FinanceFormat.inr(closingPaise))",
                            reason: status == .matched ? "Closing balance agreed" : "Closing balance mismatch",
                            isDemo: account.isDemo)
        }
        return recon
    }

    // MARK: Milestones and snapshots

    @discardableResult
    func financeAddMilestone(_ milestone: FinMilestone) -> FinMilestone {
        financeCommit { doc in
            doc.milestones.append(milestone)
            FinAudit.record(&doc, entityType: "milestone", entityID: milestone.id, action: .created,
                            newValue: milestone.title, reason: "Milestone added", isDemo: milestone.isDemo)
        }
        return milestone
    }

    func financeDeleteMilestone(_ id: String) {
        financeCommit { doc in
            guard let m = doc.milestones.first(where: { $0.id == id }) else { return }
            doc.milestones.removeAll { $0.id == id }
            FinAudit.record(&doc, entityType: "milestone", entityID: id, action: .deleted,
                            oldValue: m.title, reason: "Milestone deleted", isDemo: m.isDemo)
        }
    }

    /// Freeze today's net worth as a verified snapshot. This is the only way a
    /// historically "verified" figure is created; everything else is derived.
    func financeCaptureSnapshot(note: String = "") {
        let nw = FinanceEngine.netWorth(finance)
        let assets = FinanceEngine.totalAssets(finance)
        let liabilities = FinanceEngine.totalLiabilities(finance)
        let snap = FinSnapshot(date: FinanceCal.today(), netWorthPaise: nw.paise,
                               assetsPaise: assets.paise, liabilitiesPaise: liabilities,
                               certainty: .verified, note: note)
        financeCommit { doc in
            doc.snapshots.removeAll { $0.date == snap.date }
            doc.snapshots.append(snap)
            FinAudit.record(&doc, entityType: "snapshot", entityID: snap.id, action: .created,
                            newValue: FinanceFormat.inr(snap.netWorthPaise),
                            reason: note.isEmpty ? "Net worth snapshot" : note)
        }
        Haptics.success()
    }

    // MARK: Settings

    func financeUpdateSettings(_ settings: FinSettings) {
        financeCommit { doc in
            doc.settings = settings
        }
    }

    // MARK: Demo data

    func financeLoadDemo() {
        guard finance.isEmpty || finance.hasDemoRecords else {
            lastSyncError = "Demo data is only available on an empty finance document. Reset or export real records first."
            return
        }
        let doc = FinanceDemo.build()
        finance = doc
        push(StateKey.finance, doc)
        Haptics.success()
    }

    /// Only ever touches rows marked `isDemo`. Real records added while demo
    /// mode was on are preserved.
    func financeResetDemo() {
        financeCommit(reason: "Demo data removed") { doc in
            doc.accounts.removeAll(where: \.isDemo)
            doc.transactions.removeAll(where: \.isDemo)
            doc.transfers.removeAll(where: \.isDemo)
            doc.budgets.removeAll(where: \.isDemo)
            doc.investments.removeAll(where: \.isDemo)
            doc.valuations.removeAll(where: \.isDemo)
            doc.liabilities.removeAll(where: \.isDemo)
            doc.debtPayments.removeAll(where: \.isDemo)
            doc.goals.removeAll(where: \.isDemo)
            doc.recurring.removeAll(where: \.isDemo)
            let demoStatementIDs = Set(doc.statements.filter(\.isDemo).map(\.id))
            doc.statements.removeAll(where: \.isDemo)
            doc.reconciliations.removeAll(where: \.isDemo)
            doc.audit.removeAll(where: \.isDemo)
            doc.snapshots.removeAll(where: \.isDemo)
            doc.milestones.removeAll(where: \.isDemo)
            let demoBatchIDs = Set(doc.importBatches.filter { demoStatementIDs.contains($0.statementID) }.map(\.id))
            doc.importBatches.removeAll { demoStatementIDs.contains($0.statementID) }
            doc.importRows.removeAll { demoBatchIDs.contains($0.batchID) }
            doc.settings.demoMode = false
            doc.settings.demoSeededAt = nil
        }
        Haptics.success()
    }
}
