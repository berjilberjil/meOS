import Foundation
import SwiftUI

/// Single source of truth for the native app. Mirrors fitOS's synced-store model:
/// hydrate everything from /api/state on login, then push each changed key back
/// (debounced) — so any future client (iPhone/iPad) stays in lockstep.
@MainActor
final class AppState: ObservableObject {
    /// `.setup` = logged in but no vault yet (create a passphrase). `.locked` =
    /// vault exists but this device needs the passphrase/recovery code to unlock.
    enum Phase { case loading, loggedOut, setup, locked, loggedIn }

    // Auth / session
    @Published var phase: Phase = .loading
    @Published var username = ""
    @Published var authError: String?
    @Published var isWorking = false

    // Zero-knowledge vault
    let vault = Vault()
    /// One-time recovery code to surface after setup / regeneration. The UI shows it
    /// once, then clears it.
    @Published var recoveryCodeToShow: String?
    @Published var vaultError: String?
    @Published var vaultBusy = false
    /// Raw state fetched during login, kept until unlock so we can decode without
    /// a second round trip.
    private var pendingRaw: [String: Any]?

    // Module data (each maps to one myos.* key)
    @Published var finance = FinanceState()
    @Published var portfolio = PortfolioState()
    @Published var fitness: [String: FitnessDay] = [:]
    @Published var fitnessProfile = FitnessProfile()
    @Published var journal: [String: JournalEntry] = [:]
    @Published var journalPresets = JournalPresets()
    @Published var notes: [Note] = []
    @Published var days: [String: DayPlan] = [:]
    @Published var profile = Profile()
    @Published var chat = ChatState()
    @Published var nutrition = NutritionState()
    @Published var training = TrainingState()
    @Published var events: [EventItem] = []
    @Published var watch: [WatchItem] = []
    @Published var networth = NetWorthState()

    // Sync status
    @Published var lastSyncError: String?
    @Published var lastHydrateError: String?
    private(set) var isHydrated = false

    private let api = APIClient()
    private var pushTasks: [String: Task<Void, Never>] = [:]

    init() {
        api.vault = vault
        restoreCachedSession()
    }

    // MARK: - Instant relaunch

    private static let kSessionActive = "myos.session.active"
    private static let kSessionUser   = "myos.session.username"

    /// Show cached data instantly on relaunch — but only if this device's Keychain
    /// still holds the DEK to decrypt it. On a fresh device (or after logout) there's
    /// no cached key, so nothing is shown until the user unlocks.
    private func restoreCachedSession() {
        guard UserDefaults.standard.bool(forKey: Self.kSessionActive) else { return }
        username = UserDefaults.standard.string(forKey: Self.kSessionUser) ?? ""
        guard let raw = api.cachedRawState() else { return }
        vault.adoptMeta(api.cryptoMeta(from: raw))
        guard vault.hasMeta,
              vault.unlockFromKeychain(username: username),
              let payload = try? api.decodePayload(fromRaw: raw) else { return }
        apply(payload)
        isHydrated = false        // stays gated until a fresh pull confirms
        phase = .loggedIn
    }

    private func markSession(active: Bool, username: String = "") {
        let d = UserDefaults.standard
        d.set(active, forKey: Self.kSessionActive)
        if active { d.set(username, forKey: Self.kSessionUser) }
        else { d.removeObject(forKey: Self.kSessionUser) }
    }

    private func apply(_ s: AppStatePayload) {
        finance = s.finance ?? FinanceState()
        portfolio = s.portfolio ?? PortfolioState()
        fitness = s.fitness ?? [:]
        fitnessProfile = s.fitnessProfile ?? FitnessProfile()
        journal = s.journal ?? [:]
        journalPresets = s.journalPresets ?? JournalPresets()
        notes   = s.notes ?? []
        days    = s.days ?? [:]
        profile = s.profile ?? Profile()
        chat    = s.chat ?? ChatState()
        nutrition = s.nutrition ?? NutritionState()
        training  = s.training ?? TrainingState()
        events    = s.events ?? []
        watch     = s.watch ?? []
        networth  = s.networth ?? NetWorthState()
    }

    // MARK: - Session lifecycle

    func bootstrap() async {
        let hadCache = (phase == .loggedIn)
        do {
            let user = try await api.me()
            username = user.username
            markSession(active: true, username: user.username)
        } catch let e as APIError where e.status == 401 || e.status == 403 {
            await logout(); return
        } catch {
            if hadCache { lastHydrateError = "Offline — showing saved data." }
            else { phase = .loggedOut }
            return
        }
        await loadAndGate(hadCache: hadCache)
    }

    func login(username u: String, password p: String) async {
        await authenticate { try await self.api.login(username: u, password: p) }
    }
    func register(username u: String, password p: String) async {
        await authenticate { try await self.api.register(username: u, password: p) }
    }

    private func authenticate(_ op: @escaping () async throws -> AuthUser) async {
        isWorking = true; authError = nil
        defer { isWorking = false }
        do {
            let user = try await op()
            username = user.username
            markSession(active: true, username: user.username)
            await loadAndGate(hadCache: false)
        } catch {
            authError = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    /// The heart of the gated flow: pull raw state, then either send the user to
    /// setup (no vault yet), lock (vault exists but this device can't decrypt), or
    /// decrypt + apply and go live. Never applies encrypted data without the key.
    private func loadAndGate(hadCache: Bool) async {
        do {
            let raw = try await api.fetchStateRaw()
            pendingRaw = raw
            vault.adoptMeta(api.cryptoMeta(from: raw))
            if !vault.hasMeta { phase = .setup; return }
            if !vault.isUnlocked && !vault.unlockFromKeychain(username: username) {
                phase = .locked; return
            }
            let payload = try api.decodePayload(fromRaw: raw)
            apply(payload)
            isHydrated = true
            pendingRaw = nil
            lastSyncError = nil; lastHydrateError = nil
            phase = .loggedIn
        } catch is APIClient.VaultLockedError {
            phase = .locked
        } catch {
            isHydrated = false      // keep push gated so we never wipe server data
            if hadCache { lastHydrateError = "Offline — showing saved data." }
            else { lastHydrateError = (error as? APIError)?.message ?? "Couldn't load your data." }
        }
    }

    func logout() async {
        await api.logout()
        markSession(active: false)
        api.clearCache()
        vault.forget(username: username)
        HTTPCookieStorage.shared.cookies?.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
        finance = FinanceState(); portfolio = PortfolioState(); fitness = [:]; journal = [:]
        notes = []; days = [:]; profile = Profile()
        fitnessProfile = FitnessProfile(); journalPresets = JournalPresets()
        chat = ChatState(); suggestions = nil
        nutrition = NutritionState(); training = TrainingState()
        events = []; watch = []; networth = NetWorthState()
        username = ""; isHydrated = false; lastSyncError = nil
        pendingRaw = nil; recoveryCodeToShow = nil; vaultError = nil
        phase = .loggedOut
    }

    func hydrate() async {
        lastHydrateError = nil
        await loadAndGate(hadCache: isHydrated)
    }

    func refresh() async { await hydrate() }

    // MARK: - Vault: setup / unlock / recovery

    /// First-time setup: create the passphrase, mint the vault, then encrypt every
    /// existing (plaintext) module in place. Surfaces the recovery code once.
    func completeVaultSetup(passphrase: String) async {
        vaultError = nil
        guard let raw = pendingRaw else { vaultError = "Lost the sync — reopen the app."; return }
        guard passphrase.count >= 8 else { vaultError = "Use at least 8 characters."; return }
        vaultBusy = true; defer { vaultBusy = false }
        do {
            let (meta, code) = try vault.setup(passphrase: passphrase)
            // The raw pulled at login is all plaintext (pre-encryption) → passes through.
            let payload = try api.decodePayload(fromRaw: raw)
            apply(payload)
            try await api.putCryptoMeta(meta)
            // Cache the key BEFORE migrating so an interrupted first run can still
            // unlock silently next launch (decode tolerates a plaintext/encrypted mix).
            vault.cacheToKeychain(username: username)
            isHydrated = true
            await migrateEncryptExisting(raw: raw)
            // Refresh the on-disk cache so it holds ciphertext, not the old plaintext.
            _ = try? await api.fetchStateRaw()
            recoveryCodeToShow = code
            pendingRaw = nil
            lastSyncError = nil; lastHydrateError = nil
            phase = .loggedIn
        } catch {
            vaultError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Re-upload every existing module encrypted (one-time migration after setup).
    private func migrateEncryptExisting(raw: [String: Any]) async {
        let jobs: [(String, Encodable)] = [
            (StateKey.finance, finance), (StateKey.portfolio, portfolio),
            (StateKey.fitness, fitness), (StateKey.fitnessProfile, fitnessProfile),
            (StateKey.journal, journal), (StateKey.journalPresets, journalPresets),
            (StateKey.notes, notes), (StateKey.days, days), (StateKey.profile, profile),
            (StateKey.chat, chat), (StateKey.nutrition, nutrition), (StateKey.training, training),
            (StateKey.events, events), (StateKey.watch, watch), (StateKey.networth, networth)
        ]
        for (key, value) in jobs where raw[key] != nil {
            try? await api.putState(key, value)
        }
    }

    func unlockWithPassphrase(_ passphrase: String) async {
        vaultError = nil
        vaultBusy = true; defer { vaultBusy = false }
        do {
            try vault.unlock(passphrase: passphrase)
            vault.cacheToKeychain(username: username)
            await finishUnlock()
        } catch {
            vaultError = "Wrong passphrase. Try again, or use your recovery code."
        }
    }

    func unlockWithRecovery(_ code: String) async {
        vaultError = nil
        vaultBusy = true; defer { vaultBusy = false }
        do {
            try vault.unlock(recoveryCode: code)
            vault.cacheToKeychain(username: username)
            await finishUnlock()
        } catch {
            vaultError = "That recovery code didn't work — check for typos."
        }
    }

    private func finishUnlock() async {
        do {
            let raw: [String: Any]
            if let pending = pendingRaw { raw = pending }
            else { raw = try await api.fetchStateRaw() }
            let payload = try api.decodePayload(fromRaw: raw)
            apply(payload)
            isHydrated = true
            pendingRaw = nil
            lastSyncError = nil; lastHydrateError = nil
            phase = .loggedIn
        } catch {
            vaultError = (error as? APIError)?.message ?? "Couldn't load your data after unlock."
        }
    }

    // MARK: - Vault: manage (change passphrase, new recovery code, export)

    @discardableResult
    func changePassphrase(to newPass: String) async -> Bool {
        vaultError = nil
        guard newPass.count >= 8 else { vaultError = "Use at least 8 characters."; return false }
        do {
            let meta = try vault.rewrap(newPassphrase: newPass)
            try await api.putCryptoMeta(meta)
            vault.cacheToKeychain(username: username)
            return true
        } catch {
            vaultError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    func regenerateRecoveryCode() async {
        vaultError = nil
        do {
            let (meta, code) = try vault.regenerateRecovery()
            try await api.putCryptoMeta(meta)
            recoveryCodeToShow = code
        } catch {
            vaultError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// A plaintext JSON snapshot of everything — the user's own backup / escape hatch.
    /// (This is decrypted, so it's a plain file: the UI warns before saving.)
    func exportJSON() -> Data? {
        var out: [String: Any] = ["exportedAt": Self.nowStamp(), "user": username]
        func add(_ k: String, _ v: Encodable) {
            if let d = try? JSONEncoder().encode(AnyEncodable(v)),
               let obj = try? JSONSerialization.jsonObject(with: d, options: [.fragmentsAllowed]) {
                out[k] = obj
            }
        }
        add("profile", profile); add("finance", finance); add("portfolio", portfolio)
        add("fitness", fitness); add("fitnessProfile", fitnessProfile)
        add("journal", journal); add("journalPresets", journalPresets)
        add("notes", notes); add("days", days); add("chat", chat)
        add("nutrition", nutrition); add("training", training)
        add("events", events); add("watch", watch); add("networth", networth)
        return try? JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys])
    }

    // MARK: - Debounced push

    private func push(_ key: String, _ value: Encodable) {
        guard isHydrated else {
            lastSyncError = "Not synced yet — refresh before saving."
            return
        }
        pushTasks[key]?.cancel()
        pushTasks[key] = Task { [api] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            if Task.isCancelled { return }
            do {
                try await api.putState(key, value)
                await MainActor.run { self.lastSyncError = nil }
            } catch is CancellationError {
                return                        // superseded by a newer edit — not an error
            } catch let e as URLError where e.code == .cancelled {
                return                        // the in-flight request was replaced — ignore
            } catch {
                let msg = (error as? APIError)?.message ?? error.localizedDescription
                await MainActor.run { self.lastSyncError = "Couldn't save \(key): \(msg)" }
            }
        }
    }

    // MARK: - Date helpers

    static func dateKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
    static func nowStamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f.string(from: Date())
    }
    var todayKey: String { Self.dateKey(Date()) }
    var monthPrefix: String { String(todayKey.prefix(7)) }   // yyyy-MM
    private func newId() -> String { UUID().uuidString.lowercased() }

    /// Timezone-stable day math on a `yyyy-MM-dd` key (POSIX/gregorian — never
    /// `Calendar.current` for key strings).
    static func addDays(_ n: Int, to key: String) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: key),
              let moved = f.calendar.date(byAdding: .day, value: n, to: d) else { return key }
        return f.string(from: moved)
    }
    /// Parse a `yyyy-MM-dd` key back to a Date (same POSIX/gregorian path).
    static func date(fromKey key: String) -> Date? {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: key)
    }

    // MARK: - Finance

    func addTransaction(kind: TxnKind, amountInr: Double, category: String,
                        quality: TxnQuality? = nil, merchant: String? = nil, account: String? = nil,
                        note: String? = nil, source: TxnSource? = nil, date: String? = nil) {
        let txn = Transaction(id: newId(), date: date ?? todayKey, kind: kind,
                              amountInr: max(0, amountInr), category: category,
                              quality: quality, merchant: merchant, account: account,
                              note: note, source: source)
        finance.txns.insert(txn, at: 0)
        // A "loan" expense is a gold-loan payment → shrink the outstanding balance.
        if kind == .expense && category == "loan" {
            finance.meta.goldLoanOutstandingInr = max(0, finance.meta.goldLoanOutstandingInr - txn.amountInr)
        }
        push(StateKey.finance, finance)
    }

    /// Save a reviewed batch (from a screenshot / statement) in one push.
    func addTransactions(_ drafts: [DraftTxn], source: TxnSource) {
        for d in drafts {
            let txn = Transaction(id: newId(), date: d.date.isEmpty ? todayKey : d.date, kind: d.kind,
                                  amountInr: max(0, d.amountInr), category: d.category,
                                  quality: d.quality, merchant: d.merchant, account: d.account,
                                  note: d.note, source: source)
            finance.txns.insert(txn, at: 0)
            if txn.kind == .expense && txn.category == "loan" {
                finance.meta.goldLoanOutstandingInr = max(0, finance.meta.goldLoanOutstandingInr - txn.amountInr)
            }
        }
        push(StateKey.finance, finance)
    }

    func deleteTransaction(_ id: String) {
        guard let old = finance.txns.first(where: { $0.id == id }) else { return }
        finance.txns.removeAll { $0.id == id }
        // Deleting a gold-loan payment must restore the outstanding balance it
        // shrank, otherwise the loan card/net worth drifts permanently low.
        if old.kind == .expense && old.category == "loan" {
            finance.meta.goldLoanOutstandingInr = max(0, finance.meta.goldLoanOutstandingInr + old.amountInr)
        }
        push(StateKey.finance, finance)
    }

    /// Edit a saved transaction in place (keeps its id and list position).
    func updateTransaction(_ txn: Transaction) {
        guard let i = finance.txns.firstIndex(where: { $0.id == txn.id }) else { return }
        let old = finance.txns[i]
        var t = txn
        t.amountInr = max(0, t.amountInr)
        finance.txns[i] = t
        reconcileGoldLoan(from: old, to: t)
        push(StateKey.finance, finance)
    }

    /// Keep `goldLoanOutstandingInr` in sync with the loan-payment ledger when a
    /// transaction is edited: undo the old amount's effect, apply the new one.
    private func reconcileGoldLoan(from old: Transaction, to new: Transaction) {
        let wasLoan = old.kind == .expense && old.category == "loan"
        let isLoan  = new.kind == .expense && new.category == "loan"
        guard wasLoan || isLoan else { return }
        var delta = 0.0
        if wasLoan { delta += old.amountInr }   // undo the original decrement
        if isLoan  { delta -= new.amountInr }   // apply the new one
        if delta != 0 { finance.meta.goldLoanOutstandingInr = max(0, finance.meta.goldLoanOutstandingInr + delta) }
    }

    func saveFinanceMeta(_ meta: FinanceMeta) {
        finance.meta = meta
        push(StateKey.finance, finance)
    }

    func addToEmergencyFund(_ amount: Double) {
        finance.meta.emergencyCurrentInr = max(0, finance.meta.emergencyCurrentInr + amount)
        push(StateKey.finance, finance)
    }

    var monthTxns: [Transaction] { finance.txns.filter { $0.date.hasPrefix(monthPrefix) } }
    var monthIncome: Double { monthTxns.filter { $0.kind == .income }.reduce(0) { $0 + $1.amountInr } }
    var monthExpense: Double { monthTxns.filter { $0.kind == .expense }.reduce(0) { $0 + $1.amountInr } }
    var spentToday: Double {
        finance.txns.filter { $0.date == todayKey && $0.kind == .expense }.reduce(0) { $0 + $1.amountInr }
    }
    /// Savings rate for a `yyyy-MM` month — logged income or the profile monthly
    /// income, whichever is higher, minus that month's expenses.
    func savingsRate(forMonth prefix: String) -> Double {
        let txns = finance.txns.filter { $0.date.hasPrefix(prefix) }
        let inc = max(txns.filter { $0.kind == .income }.reduce(0) { $0 + $1.amountInr },
                      finance.meta.monthlyIncomeInr)
        guard inc > 0 else { return 0 }
        let exp = txns.filter { $0.kind == .expense }.reduce(0) { $0 + $1.amountInr }
        return max(0, (inc - exp) / inc)
    }
    /// Savings rate this month.
    var savingsRate: Double { savingsRate(forMonth: monthPrefix) }
    /// Rupees kept this month (income − expense) — can read as the full income if nothing's spent.
    var monthSaved: Double { max(monthIncome, finance.meta.monthlyIncomeInr) - monthExpense }
    /// The previous calendar month's `yyyy-MM` prefix (pure string math, no timezone drift).
    var prevMonthPrefix: String {
        let parts = monthPrefix.split(separator: "-")
        guard parts.count == 2, var y = Int(parts[0]), var m = Int(parts[1]) else { return monthPrefix }
        m -= 1; if m < 1 { m = 12; y -= 1 }
        return String(format: "%04d-%02d", y, m)
    }
    /// Change in savings rate vs last month, in percentage points (nil if no prior-month data).
    var savingsRateDeltaPP: Int? {
        let prev = finance.txns.contains { $0.date.hasPrefix(prevMonthPrefix) }
        guard prev else { return nil }
        return Int((savingsRate - savingsRate(forMonth: prevMonthPrefix)) * 100)
    }
    var goldLoanPaid: Double { max(0, finance.meta.goldLoanStartInr - finance.meta.goldLoanOutstandingInr) }
    var goldLoanFraction: Double {
        guard finance.meta.goldLoanStartInr > 0 else { return 0 }
        return goldLoanPaid / finance.meta.goldLoanStartInr
    }
    var emergencyFraction: Double {
        guard finance.meta.emergencyTargetInr > 0 else { return 0 }
        return min(1, finance.meta.emergencyCurrentInr / finance.meta.emergencyTargetInr)
    }

    /// Category → total spent this month (for the breakdown).
    var monthByCategory: [(String, Double)] {
        var m: [String: Double] = [:]
        for t in monthTxns where t.kind == .expense { m[t.category, default: 0] += t.amountInr }
        return m.sorted { $0.value > $1.value }
    }

    /// This month's spend split by the useless / useful / investment read.
    /// Always returns all three (0 if none) in a fixed order for a stable bar.
    var monthByQuality: [(TxnQuality, Double)] {
        var m: [TxnQuality: Double] = [:]
        for t in monthTxns where t.kind == .expense {
            if let q = t.quality { m[q, default: 0] += t.amountInr }
        }
        return [.useless, .useful, .investment].map { ($0, m[$0] ?? 0) }
    }
    /// Spend this month the AI flagged as useless — the "leak" number.
    var monthWasted: Double { monthByQuality.first { $0.0 == .useless }?.1 ?? 0 }
    /// Expenses this month not yet judged (manual entries usually) — so the bar reads honestly.
    var monthUntagged: Double {
        let tagged = monthByQuality.reduce(0) { $0 + $1.1 }
        return max(0, monthExpense - tagged)
    }

    /// A soft duplicate check for the review sheet: same day, same amount, and a
    /// matching merchant already exists. Defaults those drafts to excluded.
    func isLikelyDuplicate(amount: Double, date: String, merchant: String?) -> Bool {
        finance.txns.contains { t in
            abs(t.amountInr - amount) < 0.5 && t.date == date &&
            (merchant == nil || t.merchant?.caseInsensitiveCompare(merchant!) == .orderedSame)
        }
    }

    // MARK: - Portfolio

    func addSnapshot(_ holdings: [Holding], note: String? = nil, date: String? = nil) {
        let snap = PortfolioSnapshot(date: date ?? todayKey, holdings: holdings, note: note)
        // Newest first; one snapshot per day (a re-upload replaces the day's).
        portfolio.snapshots.removeAll { $0.date == snap.date }
        portfolio.snapshots.insert(snap, at: 0)
        portfolio.snapshots.sort { $0.date > $1.date }
        // A fresh snapshot makes any earlier AI read stale — don't show old numbers.
        portfolio.advice = nil
        push(StateKey.portfolio, portfolio)
    }

    func deleteSnapshot(_ id: String) {
        portfolio.snapshots.removeAll { $0.id == id }
        push(StateKey.portfolio, portfolio)
    }

    /// Replace all holdings inside a snapshot (edit-everything — works on any
    /// snapshot, not just the latest). Amounts are clamped non-negative.
    func updateSnapshotHoldings(_ snapshotID: String, holdings: [Holding]) {
        guard let si = portfolio.snapshots.firstIndex(where: { $0.id == snapshotID }) else { return }
        portfolio.snapshots[si].holdings = holdings.map {
            var h = $0; h.investedInr = max(0, h.investedInr); h.currentInr = max(0, h.currentInr); return h
        }
        // Changing holdings invalidates any AI read based on the old snapshot.
        if portfolio.snapshots[si].id == portfolio.latest?.id { portfolio.advice = nil }
        push(StateKey.portfolio, portfolio)
    }

    func saveAdvice(_ advice: PortfolioAdvice) {
        portfolio.advice = advice
        push(StateKey.portfolio, portfolio)
    }

    // MARK: - Live prices (Yahoo Finance — free, no key/token)

    @Published var growwBusy = false
    @Published var growwError: String?
    @Published var growwLastRefresh: String?

    /// Pull live prices from Yahoo Finance for the latest snapshot's holdings that
    /// have a ticker + units, and update their current value (price × units). US
    /// tickers are auto-converted to INR inside MarketDataClient.
    func refreshLivePrices() async {
        growwError = nil
        guard let snap = portfolio.latest else { growwError = "Add a portfolio snapshot first."; return }
        let symbols = snap.holdings.compactMap { h -> String? in
            guard let s = h.symbol?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
            return s
        }
        guard !symbols.isEmpty else { growwError = "Set a ticker (e.g. ITC.NS, TCS.BO, AAPL) on your holdings first — edit the snapshot."; return }
        growwBusy = true
        defer { growwBusy = false }
        do {
            let prices = try await MarketDataClient.pricesInINR(symbols)
            var holdings = snap.holdings
            var updated = 0
            for i in holdings.indices {
                if let sym = holdings[i].symbol?.trimmingCharacters(in: .whitespaces),
                   let price = prices[sym], let u = holdings[i].units, u > 0 {
                    holdings[i].currentInr = price * u
                    updated += 1
                }
            }
            guard updated > 0 else { growwError = "No prices came back for those tickers. Check the format (ITC.NS, TCS.BO, AAPL)."; return }
            updateSnapshotHoldings(snap.id, holdings: holdings)
            growwLastRefresh = Self.nowStamp()
        } catch {
            growwError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    var portfolioInvested: Double { portfolio.latest?.totalInvested ?? 0 }
    var portfolioCurrent: Double { portfolio.latest?.totalCurrent ?? 0 }
    var portfolioPnl: Double { portfolio.latest?.pnl ?? 0 }
    var portfolioReturnPct: Double { portfolio.latest?.returnPct ?? 0 }
    /// Change in current value vs the previous snapshot (nil if no prior week).
    var portfolioWeekChange: Double? {
        guard let now = portfolio.latest, let prev = portfolio.previous else { return nil }
        return now.totalCurrent - prev.totalCurrent
    }

    // MARK: - AI: screenshot reading + portfolio review

    @Published var imageBusy = false
    @Published var imageError: String?
    @Published var adviceBusy = false
    @Published var adviceError: String?

    /// Read a UPI screenshot / bank statement into draft transactions for review.
    /// Returns [] on failure (with imageError set). Does NOT save anything.
    func analyzeTransactions(imagesBase64: [String], mediaType: String) async -> (summary: String, drafts: [DraftTxn]) {
        imageError = nil
        guard isHydrated else { imageError = "Not synced yet — try again in a moment."; return ("", []) }
        imageBusy = true
        defer { imageBusy = false }
        do {
            let r = try await api.parseImage(imagesBase64: imagesBase64, mediaType: mediaType, mode: "transactions")
            let drafts: [DraftTxn] = (r.transactions ?? []).map { item in
                let date = (item.date?.isEmpty == false) ? item.date! : todayKey
                let dupe = isLikelyDuplicate(amount: item.amountInr, date: date, merchant: item.merchant)
                return DraftTxn(include: !dupe, kind: item.kind, amountInr: item.amountInr,
                                category: item.category, quality: item.quality.flatMap(TxnQuality.init),
                                merchant: item.merchant, account: item.account, note: item.note, date: date)
            }
            return (r.summary, drafts)
        } catch {
            imageError = (error as? APIError)?.message ?? error.localizedDescription
            return ("", [])
        }
    }

    /// Read a portfolio screenshot into draft holdings for review. Does NOT save.
    func analyzePortfolio(imagesBase64: [String], mediaType: String) async -> (summary: String, drafts: [DraftHolding]) {
        imageError = nil
        guard isHydrated else { imageError = "Not synced yet — try again in a moment."; return ("", []) }
        imageBusy = true
        defer { imageBusy = false }
        do {
            let r = try await api.parseImage(imagesBase64: imagesBase64, mediaType: mediaType, mode: "portfolio")
            let drafts: [DraftHolding] = (r.holdings ?? []).map { h in
                DraftHolding(name: h.name, type: HoldingType(rawValue: h.type) ?? .other,
                             investedInr: h.investedInr ?? 0, currentInr: h.currentInr,
                             units: h.units, note: h.note)
            }
            return (r.summary, drafts)
        } catch {
            imageError = (error as? APIError)?.message ?? error.localizedDescription
            return ("", [])
        }
    }

    /// Ask the AI for a weekly read on the latest snapshot, grounded in the loan/
    /// income/protection context. Saves the advice on success.
    func requestPortfolioReview() async {
        adviceError = nil
        guard isHydrated else { adviceError = "Not synced yet — try again in a moment."; return }
        guard let snap = portfolio.latest else { adviceError = "Add a portfolio snapshot first."; return }
        adviceBusy = true
        defer { adviceBusy = false }
        let m = finance.meta
        let ctx = AdviceRequest.Ctx(
            monthlyIncomeInr: max(monthIncome, m.monthlyIncomeInr),
            monthExpenseInr: monthExpense,
            goldLoanOutstandingInr: m.goldLoanOutstandingInr,
            goldLoanRatePct: m.goldLoanRatePct,
            emergencyCurrentInr: m.emergencyCurrentInr,
            emergencyTargetInr: m.emergencyTargetInr,
            termInsuranceBought: m.termInsuranceBought,
            healthInsuranceBought: m.healthInsuranceBought)
        let prev = portfolio.previous.map { AdviceRequest.Prev(date: $0.date, totalCurrent: $0.totalCurrent) }
        let req = AdviceRequest(
            holdings: snap.holdings.map { AdviceRequest.H(name: $0.name, type: $0.type.rawValue,
                                                          investedInr: $0.investedInr,
                                                          currentInr: $0.currentInr, units: $0.units) },
            context: ctx, prev: prev)
        do {
            var advice = try await api.advise(req)
            advice.date = todayKey
            saveAdvice(advice)
        } catch {
            adviceError = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    // MARK: - Profile

    func updateProfile(_ transform: (inout Profile) -> Void) {
        var p = profile
        transform(&p)
        profile = p
        push(StateKey.profile, profile)
    }

    /// Most recent logged weight across the whole fitness history.
    var latestWeightKg: Double? {
        fitness.filter { $0.value.weightKg != nil }
            .max { $0.key < $1.key }?.value.weightKg
    }

    /// The computed calorie/macro picture — nil until height, age and a weight
    /// exist. Weight falls back to the target weight if nothing is logged yet.
    func calorieTargets() -> CalorieTargets? {
        guard let h = profile.heightCm, h > 0, let age = profile.age, age > 0 else { return nil }
        guard let w = latestWeightKg ?? fitnessProfile.targetWeightKg, w > 0 else { return nil }
        return Nutrition.targets(sex: fitnessProfile.sex, weightKg: w, heightCm: h, age: age,
                                 activity: fitnessProfile.activity, goal: fitnessProfile.goal)
    }

    // MARK: - Fitness

    func fitnessDay(_ date: String) -> FitnessDay { fitness[date] ?? FitnessDay() }
    func updateFitness(_ date: String, _ transform: (inout FitnessDay) -> Void) {
        var d = fitness[date] ?? FitnessDay()
        transform(&d)
        fitness[date] = d
        push(StateKey.fitness, fitness)
    }

    /// Set today's logged weight directly (used from Profile's editable field).
    func setTodayWeight(_ kg: Double?) {
        updateFitness(todayKey) { $0.weightKg = kg.map { max(0, $0) } }
    }

    /// Set today's step count. Manual today; the iPhone client writes this same field
    /// from HealthKit next month — nothing else has to change for it to sync.
    func setTodaySteps(_ steps: Int?) {
        updateFitness(todayKey) { $0.steps = steps.map { max(0, $0) } }
    }
    /// The daily step goal, defaulting to 8,000 when unset.
    var stepsTarget: Int { fitnessProfile.stepsTarget ?? 8000 }

    // MARK: - Fitness profile

    func updateFitnessProfile(_ transform: (inout FitnessProfile) -> Void) {
        var p = fitnessProfile
        transform(&p)
        fitnessProfile = p
        push(StateKey.fitnessProfile, fitnessProfile)
    }

    // MARK: - Nutrition (food library + daily log + weekly meal plan)

    /// weekday key "0"(Sun)…"6"(Sat) for a date key.
    static func weekdayKey(_ dateKey: String) -> String {
        guard let d = date(fromKey: dateKey) else { return "0" }
        let wd = Calendar(identifier: .gregorian).component(.weekday, from: d) // 1=Sun…7=Sat
        return String(wd - 1)
    }
    var todayWeekday: String { Self.weekdayKey(todayKey) }

    /// Seed foods plus the user's custom foods (custom overrides a seed by id).
    var allFoods: [Food] {
        var byId: [String: Food] = [:]
        for f in FoodSeed.all { byId[f.id] = f }
        for f in nutrition.customFoods { byId[f.id] = f }
        return byId.values.sorted { $0.name < $1.name }
    }
    func food(_ id: String) -> Food? {
        nutrition.customFoods.first { $0.id == id } ?? FoodSeed.all.first { $0.id == id }
    }

    @discardableResult
    func addFood(_ food: Food) -> Food {
        var f = food; if f.id.isEmpty { f.id = newId() }
        f.isDefault = false
        nutrition.customFoods.insert(f, at: 0)
        push(StateKey.nutrition, nutrition)
        return f
    }
    func updateFood(_ food: Food) {
        if let i = nutrition.customFoods.firstIndex(where: { $0.id == food.id }) {
            nutrition.customFoods[i] = food
        } else {
            nutrition.customFoods.insert(food, at: 0)   // editing a seed persists an override
        }
        push(StateKey.nutrition, nutrition)
    }
    func deleteFood(_ id: String) {
        nutrition.customFoods.removeAll { $0.id == id }
        push(StateKey.nutrition, nutrition)
    }

    func mealLog(_ date: String) -> MealLog { nutrition.log[date] ?? MealLog() }
    private func mutateLog(_ date: String, _ f: (inout MealLog) -> Void) {
        var l = nutrition.log[date] ?? MealLog()
        f(&l)
        nutrition.log[date] = l
        push(StateKey.nutrition, nutrition)
    }
    func addFoodToMeal(date: String, meal: MealKey, foodId: String, quantity: Double = 1) {
        mutateLog(date) { $0.meals[meal.rawValue, default: []].append(PlanItem(foodId: foodId, quantity: quantity)) }
    }
    func setMealItemQty(date: String, meal: MealKey, itemId: String, quantity: Double) {
        mutateLog(date) {
            if let i = $0.meals[meal.rawValue]?.firstIndex(where: { $0.id == itemId }) {
                $0.meals[meal.rawValue]?[i].quantity = max(0, quantity)
            }
        }
    }
    func removeMealItem(date: String, meal: MealKey, itemId: String) {
        mutateLog(date) { $0.meals[meal.rawValue]?.removeAll { $0.id == itemId } }
    }

    /// Distinct micronutrients covered by the foods eaten on a date.
    func vitaminsCovered(_ date: String) -> [String] {
        let log = mealLog(date)
        var out: [String] = []
        for meal in MealKey.allCases {
            for item in log.items(meal) {
                guard let v = food(item.foodId)?.vitamins else { continue }
                for part in v.split(separator: ",") {
                    let t = part.trimmingCharacters(in: .whitespaces)
                    if !t.isEmpty && !out.contains(t) { out.append(t) }
                }
            }
        }
        return out
    }

    /// Total macros eaten on a date. Merges the food log (meal items) with the
    /// fitness day's AI-quick-logged calories/protein, so the Food tab, Fitness
    /// card, Today line and mentor context all agree on the same numbers.
    func consumed(_ date: String) -> Macros {
        let log = mealLog(date)
        var total = Macros.zero
        for meal in MealKey.allCases {
            for item in log.items(meal) {
                if let f = food(item.foodId) { total = total + f.perServing.scaled(item.quantity) }
            }
        }
        let fd = fitness[date]
        total.calories += fd?.calories ?? 0
        total.protein += fd?.proteinG ?? 0
        return total
    }

    // Weekly meal plan (per weekday → meal → items).
    func mealPlan(_ weekday: String) -> [String: [PlanItem]] { nutrition.mealPlan[weekday] ?? [:] }
    func planItems(_ weekday: String, _ meal: MealKey) -> [PlanItem] { nutrition.mealPlan[weekday]?[meal.rawValue] ?? [] }
    func addFoodToPlan(weekday: String, meal: MealKey, foodId: String, quantity: Double = 1) {
        nutrition.mealPlan[weekday, default: [:]][meal.rawValue, default: []].append(PlanItem(foodId: foodId, quantity: quantity))
        push(StateKey.nutrition, nutrition)
    }
    func removePlanItem(weekday: String, meal: MealKey, itemId: String) {
        nutrition.mealPlan[weekday]?[meal.rawValue]?.removeAll { $0.id == itemId }
        push(StateKey.nutrition, nutrition)
    }
    /// Copy today's weekday meal plan into today's log (seed the day).
    func applyMealPlanToToday() {
        let plan = mealPlan(todayWeekday)
        guard !plan.isEmpty else { return }
        mutateLog(todayKey) { log in
            for (mealRaw, items) in plan {
                let existing = log.meals[mealRaw] ?? []
                log.meals[mealRaw] = existing + items.map { PlanItem(foodId: $0.foodId, quantity: $0.quantity) }
            }
        }
    }

    // MARK: - Training (exercise library + weekly workout plan)

    var allExercises: [Exercise] {
        var byId: [String: Exercise] = [:]
        for e in ExerciseSeed.all { byId[e.id] = e }
        for e in training.customExercises { byId[e.id] = e }
        return byId.values.sorted { $0.name < $1.name }
    }
    func exercise(_ id: String) -> Exercise? {
        training.customExercises.first { $0.id == id } ?? ExerciseSeed.all.first { $0.id == id }
    }
    @discardableResult
    func addExercise(_ ex: Exercise) -> Exercise {
        var e = ex; if e.id.isEmpty { e.id = newId() }
        e.isDefault = false
        training.customExercises.insert(e, at: 0)
        push(StateKey.training, training)
        return e
    }
    func updateExercise(_ ex: Exercise) {
        if let i = training.customExercises.firstIndex(where: { $0.id == ex.id }) {
            training.customExercises[i] = ex
        } else {
            training.customExercises.insert(ex, at: 0)
        }
        push(StateKey.training, training)
    }
    func deleteExercise(_ id: String) {
        training.customExercises.removeAll { $0.id == id }
        push(StateKey.training, training)
    }

    func workoutPlan(_ weekday: String) -> WorkoutDayPlan { training.weekPlan[weekday] ?? WorkoutDayPlan() }
    private func mutatePlan(_ weekday: String, _ f: (inout WorkoutDayPlan) -> Void) {
        var p = training.weekPlan[weekday] ?? WorkoutDayPlan()
        f(&p)
        training.weekPlan[weekday] = p
        push(StateKey.training, training)
    }
    func setRestDay(_ weekday: String, _ rest: Bool) { mutatePlan(weekday) { $0.rest = rest } }
    func addPlanExercise(weekday: String, exerciseId: String) {
        mutatePlan(weekday) { $0.rest = false; $0.items.append(PlanExercise(exerciseId: exerciseId)) }
    }
    func setPlanSets(weekday: String, itemId: String, sets: Int) {
        mutatePlan(weekday) { if let i = $0.items.firstIndex(where: { $0.id == itemId }) { $0.items[i].sets = max(1, sets) } }
    }
    func setPlanReps(weekday: String, itemId: String, reps: Int) {
        mutatePlan(weekday) { if let i = $0.items.firstIndex(where: { $0.id == itemId }) { $0.items[i].reps = max(1, reps) } }
    }
    func removePlanExercise(weekday: String, itemId: String) {
        mutatePlan(weekday) { $0.items.removeAll { $0.id == itemId } }
    }
    func copyWorkoutDay(from: String, to weekdays: [String]) {
        let src = workoutPlan(from)
        for wd in weekdays where wd != from {
            training.weekPlan[wd] = WorkoutDayPlan(rest: src.rest,
                items: src.items.map { PlanExercise(exerciseId: $0.exerciseId, sets: $0.sets, reps: $0.reps) })
        }
        push(StateKey.training, training)
    }

    // MARK: - AI plan generation ("Generate my week")

    @Published var planBusy = false
    @Published var planError: String?
    @Published var planSummary: String?

    /// Match an AI-returned name to a library item id (exact-ish, else contains).
    private func matchId<T>(_ name: String, in items: [T], id: (T) -> String, label: (T) -> String) -> String? {
        let n = name.lowercased().trimmingCharacters(in: .whitespaces)
        if let hit = items.first(where: { label($0).lowercased() == n }) { return id(hit) }
        if let hit = items.first(where: { label($0).lowercased().contains(n) || n.contains(label($0).lowercased()) }) { return id(hit) }
        return nil
    }

    /// Ask the AI for a week, then write it into the workout + meal plans (name→id
    /// matched against the library). Overwrites both weekly plans.
    func generateWeeklyPlan() async {
        planError = nil; planSummary = nil
        guard isHydrated, !planBusy else { return }
        planBusy = true
        defer { planBusy = false }
        let cal = calorieTargets()
        let req = APIClient.PlanRequest(
            goal: fitnessProfile.goal.label,
            calories: cal?.goalCalories ?? Int(fitnessProfile.calorieTargetKcal ?? 0),
            protein: cal?.proteinG ?? Int(fitnessProfile.proteinTargetG ?? 0),
            daysPerWeek: fitnessProfile.goal == .cut ? 5 : 4,
            foods: allFoods.map { $0.name },
            exercises: allExercises.map { $0.name })
        do {
            let plan = try await api.plan(req)
            applyGeneratedPlan(plan)
            planSummary = plan.summary
        } catch {
            planError = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    private func applyGeneratedPlan(_ plan: GeneratedPlan) {
        let exList = allExercises, foodList = allFoods

        // Workout
        var newWorkout: [String: WorkoutDayPlan] = [:]
        for day in plan.workout {
            let wd = String(max(0, min(6, day.weekday)))
            if day.rest || day.exercises.isEmpty {
                newWorkout[wd] = WorkoutDayPlan(rest: true, items: [])
            } else {
                let items: [PlanExercise] = day.exercises.compactMap { e in
                    guard let id = matchId(e.name, in: exList, id: { $0.id }, label: { $0.name }) else { return nil }
                    return PlanExercise(exerciseId: id, sets: max(1, e.sets), reps: max(1, e.reps))
                }
                newWorkout[wd] = WorkoutDayPlan(rest: items.isEmpty, items: items)
            }
        }
        if !newWorkout.isEmpty { training.weekPlan = newWorkout; push(StateKey.training, training) }

        // Meals
        var newMeals: [String: [String: [PlanItem]]] = [:]
        for day in plan.meals {
            let wd = String(max(0, min(6, day.weekday)))
            var meals: [String: [PlanItem]] = [:]
            func fill(_ names: [String]) -> [PlanItem] {
                names.compactMap { name in
                    matchId(name, in: foodList, id: { $0.id }, label: { $0.name }).map { PlanItem(foodId: $0, quantity: 1) }
                }
            }
            meals[MealKey.breakfast.rawValue] = fill(day.breakfast)
            meals[MealKey.lunch.rawValue]     = fill(day.lunch)
            meals[MealKey.dinner.rawValue]    = fill(day.dinner)
            meals[MealKey.snacks.rawValue]    = fill(day.snacks)
            newMeals[wd] = meals
        }
        if !newMeals.isEmpty { nutrition.mealPlan = newMeals; push(StateKey.nutrition, nutrition) }
    }

    // MARK: - Journal

    func journalEntry(_ date: String) -> JournalEntry { journal[date] ?? JournalEntry() }
    func updateJournal(_ date: String, _ transform: (inout JournalEntry) -> Void) {
        var e = journal[date] ?? JournalEntry()
        transform(&e)
        journal[date] = e
        push(StateKey.journal, journal)
    }

    // MARK: - Journal presets (editable quick-add chips)

    func updateJournalPresets(_ transform: (inout JournalPresets) -> Void) {
        var p = journalPresets
        transform(&p)
        journalPresets = p
        push(StateKey.journalPresets, journalPresets)
    }
    /// The streak's "has content" test — any reflection, win, or mood.
    func journalHasContent(_ date: String) -> Bool {
        guard let e = journal[date] else { return false }
        return !(e.morning.isEmpty && e.night.isEmpty && e.wins.isEmpty && e.mood == nil)
    }
    func journalMood(_ date: String) -> Int? { journal[date]?.mood }

    /// How a date renders on the streak calendar.
    enum StreakDay {
        case done       // journalled — lit fire
        case frozen     // missed inside a live streak — frozen fire, streak survives
        case none
    }

    /// Duolingo-style streak: walk back from today; a single missed day between
    /// journalled days is auto-frozen (the streak survives it, but it doesn't
    /// count), two consecutive missed days end the run. Today without an entry
    /// is pending, not missed — the streak stays alive until midnight.
    var journalStreakInfo: (count: Int, frozen: Set<String>) {
        var frozen = Set<String>()
        var count = 0
        var key = todayKey
        if !journalHasContent(key) { key = Self.addDays(-1, to: key) }
        var steps = 0
        while steps < 3650 {
            steps += 1
            if journalHasContent(key) {
                count += 1
                key = Self.addDays(-1, to: key)
            } else {
                let prev = Self.addDays(-1, to: key)
                guard journalHasContent(prev) else { break }
                frozen.insert(key)
                key = prev
            }
        }
        return (count, frozen)
    }

    var journalStreak: Int { journalStreakInfo.count }

    /// Per-date streak state for calendar cells. A frozen day is either inside
    /// the live run, or (historically) a single miss sandwiched between
    /// journalled days — so old months still read as an unbroken fire line.
    func journalStreakDay(_ date: String) -> StreakDay {
        if journalHasContent(date) { return .done }
        if journalStreakInfo.frozen.contains(date) { return .frozen }
        if date < todayKey,
           journalHasContent(Self.addDays(-1, to: date)),
           journalHasContent(Self.addDays(1, to: date)) { return .frozen }
        return .none
    }

    // MARK: - Notes

    @discardableResult
    func addNote(title: String, body: String) -> Note {
        // Plain-text entry point (AI quick-log). Seed block content from the body
        // so the note opens as editable blocks in the rich editor.
        let n = Note(id: newId(), createdAt: Self.nowStamp(), updatedAt: Self.nowStamp(),
                     title: title, body: body, content: BlockDoc.from(plainText: body))
        notes.insert(n, at: 0)
        push(StateKey.notes, notes)
        return n
    }
    /// Create an empty note ready for the block editor. Returns its id.
    @discardableResult
    func addBlockNote() -> String {
        let n = Note(id: newId(), createdAt: Self.nowStamp(), updatedAt: Self.nowStamp(),
                     title: "", body: "", content: BlockDoc())
        notes.insert(n, at: 0)
        push(StateKey.notes, notes)
        return n.id
    }
    func updateNote(_ id: String, title: String, body: String) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[i].title = title
        notes[i].body = body
        notes[i].content = BlockDoc.from(plainText: body)
        notes[i].updatedAt = Self.nowStamp()
        push(StateKey.notes, notes)
    }
    /// Save rich block content, keeping `body` as the plain-text mirror.
    func updateNoteContent(_ id: String, title: String, doc: BlockDoc) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[i].title = title
        notes[i].content = doc
        notes[i].body = doc.plainText
        notes[i].updatedAt = Self.nowStamp()
        push(StateKey.notes, notes)
    }
    func note(_ id: String) -> Note? { notes.first { $0.id == id } }
    func deleteNote(_ id: String) {
        notes.removeAll { $0.id == id }
        push(StateKey.notes, notes)
    }
    func togglePinNote(_ id: String) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[i].pinned.toggle()
        push(StateKey.notes, notes)
    }
    func toggleLockNote(_ id: String) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[i].locked.toggle()
        push(StateKey.notes, notes)
    }
    /// Display order: pinned first, then most-recently-edited.
    var sortedNotes: [Note] {
        notes.sorted { a, b in
            if a.pinned != b.pinned { return a.pinned }
            return a.updatedAt > b.updatedAt
        }
    }

    // MARK: - Day spine (focus + habits)

    func todayPlan() -> DayPlan { days[todayKey] ?? DayPlan() }
    func setFocus(_ items: [String]) {
        var d = days[todayKey] ?? DayPlan()
        d.focus = items.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        days[todayKey] = d
        push(StateKey.days, days)
    }
    func toggleHabit(_ name: String) {
        var d = days[todayKey] ?? DayPlan()
        d.habits[name] = !(d.habits[name] ?? false)
        days[todayKey] = d
        push(StateKey.days, days)
    }
    func habitsDoneToday() -> Int { todayPlan().habits.values.filter { $0 }.count }

    // MARK: - AI quick-log

    @Published var quickLogBusy = false
    @Published var quickLogResult: String?

    /// Send one line to /api/parse and file the structured result into modules.
    func quickLog(_ text: String) async {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        guard isHydrated else { quickLogResult = "Not synced yet — try again in a moment."; return }
        quickLogBusy = true
        defer { quickLogBusy = false }
        do {
            let r = try await api.parse(text: t)
            applyParse(r)
            quickLogResult = r.summary
        } catch {
            quickLogResult = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    // MARK: - AI parse → route to modules

    func applyParse(_ r: ParseResult) {
        for f in r.finance {
            addTransaction(kind: f.kind, amountInr: f.amountInr, category: f.category,
                           quality: f.quality.flatMap(TxnQuality.init), merchant: f.merchant,
                           note: f.note, source: .ai)
        }
        if let fit = r.fitness {
            updateFitness(todayKey) { d in
                if let w = fit.weightKg { d.weightKg = w }
                if let c = fit.calories { d.calories = (d.calories ?? 0) + c }
                if let p = fit.proteinG { d.proteinG = (d.proteinG ?? 0) + p }
                if let wa = fit.waterMl { d.waterMl = (d.waterMl ?? 0) + wa }
                if let note = fit.note, !note.isEmpty { d.note = note }
            }
        }
        if let j = r.journal {
            let hasContent = j.note != nil || j.mood != nil || !j.wins.isEmpty
                || !j.mistakes.isEmpty || !j.lessons.isEmpty || !j.gratitude.isEmpty
            if hasContent {
                updateJournal(todayKey) { e in
                    e.wins += j.wins
                    e.mistakes += j.mistakes
                    e.lessons += j.lessons
                    e.gratitude += j.gratitude
                    if let m = j.mood { e.mood = m }
                    if let note = j.note, !note.isEmpty {
                        e.night = e.night.isEmpty ? note : e.night + "\n" + note
                    }
                }
            }
        }
        for n in r.notes where !(n.title.isEmpty && n.body.isEmpty) {
            _ = addNote(title: n.title.isEmpty ? "Note" : n.title, body: n.body)
        }
    }

    // MARK: - Mentor chat + Today suggestions

    @Published var chatBusy = false
    @Published var chatError: String?
    /// A prompt requested from elsewhere (e.g. "Ask AI" on a news story). The chat
    /// widget observes this, opens itself, and sends it.
    @Published var pendingChatPrompt: String? = nil
    func askMentor(_ prompt: String) { pendingChatPrompt = prompt }
    @Published var suggestions: SuggestResult?
    @Published var suggestBusy = false
    @Published var suggestError: String?
    @Published var news: NewsResult?
    @Published var newsBusy = false
    @Published var newsError: String?
    @Published var anatomy: AnatomyData?
    @Published var anatomyError: String?

    /// A compact, human-readable snapshot of his data — the grounding the AI mentor
    /// (chat, Today suggestions, plan generation) reasons over.
    func mentorContext() -> String {
        var l: [String] = []
        let p = profile
        let m = finance.meta
        var who = "PROFILE: \(p.name.isEmpty ? "(no name set)" : p.name)"
        if let a = p.age { who += ", age \(a)" }
        if !p.city.isEmpty { who += ", \(p.city)" }
        if !p.role.isEmpty { who += ". Role: \(p.role)" }
        if !p.work.isEmpty { who += " — \(p.work)" }
        l.append(who + ".")
        if !p.hometown.isEmpty { l.append("HOMETOWN: \(p.hometown).") }
        let about = p.about.trimmingCharacters(in: .whitespacesAndNewlines)
        if !about.isEmpty { l.append("ABOUT (their own words): \(about)") }
        l.append("MONEY: income ₹\(Int(m.monthlyIncomeInr))/mo. This month — in \(Fmt.inr(monthIncome)), out \(Fmt.inr(monthExpense)), savings rate \(Int(savingsRate*100))%, wasted (useless) \(Fmt.inr(monthWasted)).")
        l.append("GOLD LOAN: \(Fmt.inr(m.goldLoanOutstandingInr)) left of \(Fmt.inr(m.goldLoanStartInr)) @ \(Fmt.trimKg(m.goldLoanRatePct))% — \(Int(goldLoanFraction*100))% cleared.")
        l.append("PROTECTION: emergency fund \(Fmt.inr(m.emergencyCurrentInr)) of \(Fmt.inr(m.emergencyTargetInr)); term insurance \(m.termInsuranceBought ? "bought" : "NOT bought"); own health insurance \(m.healthInsuranceBought ? "bought" : "NOT bought").")
        let cats = monthByCategory.prefix(4).map { "\($0.0) \(Fmt.inr($0.1))" }.joined(separator: ", ")
        if !cats.isEmpty { l.append("TOP SPEND THIS MONTH: \(cats).") }

        var fit = "FITNESS: goal \(fitnessProfile.goal.label)"
        if let w = latestWeightKg { fit += ", weight \(Fmt.trimKg(w))kg" }
        if let h = p.heightCm { fit += ", height \(Int(h))cm" }
        if let tw = fitnessProfile.targetWeightKg { fit += ", target \(Fmt.trimKg(tw))kg" }
        l.append(fit + ".")
        if let cal = calorieTargets() {
            l.append("CALORIES: BMR \(cal.bmr), TDEE \(cal.tdee). Maintain \(cal.maintain), cut \(cal.cut), bulk \(cal.bulk) kcal. Protein target \(cal.proteinG)g.")
        }
        let td = consumed(todayKey)
        l.append("TODAY INTAKE: \(Int(td.calories)) kcal, \(Int(td.protein))g protein, \(Fmt.trimKg((fitnessDay(todayKey).waterMl ?? 0)/1000))L water.")

        let e = journalEntry(todayKey)
        l.append("JOURNAL: \(journalStreak)-day streak" + (e.mood.map { ", mood today \($0)/5" } ?? ", no entry today yet") + ".")
        if !e.wins.isEmpty { l.append("TODAY WINS: \(e.wins.joined(separator: "; ")).") }
        if !e.mistakes.isEmpty { l.append("TODAY MISTAKES: \(e.mistakes.joined(separator: "; ")).") }

        if let snap = portfolio.latest, !snap.holdings.isEmpty {
            l.append("PORTFOLIO: invested \(Fmt.inr(snap.totalInvested)), current \(Fmt.inr(snap.totalCurrent)), return \(String(format: "%.1f", snap.returnPct*100))%.")
        }
        return l.joined(separator: "\n")
    }

    /// Send a message to the mentor. Optimistically appends the user turn, then the
    /// reply. History persists to `myos.chat`.
    func sendChat(_ text: String) async {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !chatBusy else { return }
        chatError = nil
        chat.messages.append(ChatMessage(role: "user", content: t, at: Self.nowStamp()))
        if isHydrated { push(StateKey.chat, chat) }
        chatBusy = true
        defer { chatBusy = false }
        let turns = chat.messages.suffix(24).map { APIClient.ChatTurn(role: $0.role, content: $0.content) }
        let a = AgentConfig.shared
        let agent = APIClient.AgentInfo(name: a.displayName, tone: a.tone.directive,
                                        custom: a.custom.trimmingCharacters(in: .whitespacesAndNewlines))
        do {
            let reply = try await api.chat(messages: turns, context: mentorContext(), agent: agent)
            chat.messages.append(ChatMessage(role: "assistant", content: reply, at: Self.nowStamp()))
            if isHydrated { push(StateKey.chat, chat) }
        } catch {
            chatError = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    func clearChat() {
        chat = ChatState()
        if isHydrated { push(StateKey.chat, chat) }
    }

    /// Fetch the Today "what to do now" suggestions (not persisted). Read-only, so
    /// it doesn't wait on hydration — the cached session already carries auth + data.
    func fetchSuggestions() async {
        guard phase == .loggedIn, !suggestBusy else { return }
        suggestError = nil
        suggestBusy = true
        defer { suggestBusy = false }
        do {
            suggestions = try await api.suggest(context: mentorContext())
        } catch {
            suggestError = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    /// Load the anatomy body map (static; disk-cached for instant open).
    func loadAnatomy() async {
        if anatomy != nil { return }
        if let cached = api.cachedAnatomy() { anatomy = cached }
        anatomyError = nil
        do { anatomy = try await api.anatomy() }
        catch { if anatomy == nil { anatomyError = (error as? APIError)?.message ?? error.localizedDescription } }
    }

    /// Fetch recent tech + finance news for Today (not persisted).
    func fetchNews() async {
        guard phase == .loggedIn, !newsBusy else { return }
        newsError = nil
        newsBusy = true
        defer { newsBusy = false }
        do {
            news = try await api.news()
        } catch {
            newsError = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    // MARK: - Net worth (hybrid: tracked pieces pulled live + manual lines)

    /// Assets already tracked elsewhere — shown read-only so they never drift/double-count.
    var autoAssets: [(String, Double)] {
        var out: [(String, Double)] = []
        if portfolioCurrent > 0 { out.append(("Investments", portfolioCurrent)) }
        if finance.meta.emergencyCurrentInr > 0 { out.append(("Emergency fund", finance.meta.emergencyCurrentInr)) }
        return out
    }
    /// Liabilities already tracked — the gold loan.
    var autoLiabilities: [(String, Double)] {
        finance.meta.goldLoanOutstandingInr > 0 ? [("Gold loan", finance.meta.goldLoanOutstandingInr)] : []
    }
    var manualAssetsTotal: Double { networth.assets.reduce(0) { $0 + $1.amountInr } }
    var manualLiabilitiesTotal: Double { networth.liabilities.reduce(0) { $0 + $1.amountInr } }
    var totalAssets: Double { autoAssets.reduce(0) { $0 + $1.1 } + manualAssetsTotal }
    var totalLiabilities: Double { autoLiabilities.reduce(0) { $0 + $1.1 } + manualLiabilitiesTotal }
    var netWorth: Double { totalAssets - totalLiabilities }

    func addNetWorthLine(asset: Bool, label: String, amountInr: Double) {
        let line = NetWorthLine(label: label.trimmingCharacters(in: .whitespaces), amountInr: max(0, amountInr))
        guard !line.label.isEmpty else { return }
        if asset { networth.assets.append(line) } else { networth.liabilities.append(line) }
        push(StateKey.networth, networth)
    }
    func updateNetWorthLine(asset: Bool, _ line: NetWorthLine) {
        var l = line; l.amountInr = max(0, l.amountInr)
        if asset {
            if let i = networth.assets.firstIndex(where: { $0.id == l.id }) { networth.assets[i] = l }
        } else {
            if let i = networth.liabilities.firstIndex(where: { $0.id == l.id }) { networth.liabilities[i] = l }
        }
        push(StateKey.networth, networth)
    }
    func deleteNetWorthLine(asset: Bool, _ id: String) {
        if asset { networth.assets.removeAll { $0.id == id } }
        else { networth.liabilities.removeAll { $0.id == id } }
        push(StateKey.networth, networth)
    }

    // MARK: - Events (upcoming life timeline)

    /// Undone events, soonest first — the timeline order.
    var sortedEvents: [EventItem] { events.filter { !$0.done }.sorted { $0.date < $1.date } }
    /// Past / handled events, most recent first — the archive.
    var doneEvents: [EventItem] { events.filter { $0.done }.sorted { $0.date > $1.date } }
    /// The next couple of things coming up — for the Today spine.
    var nextEvents: [EventItem] { Array(sortedEvents.prefix(2)) }

    func addEvent(date: String, title: String, category: EventCategory, note: String = "", special: Bool = false) {
        let t = title.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, !date.isEmpty else { return }
        events.append(EventItem(date: date, title: t, category: category, note: note, special: special))
        push(StateKey.events, events)
    }
    func updateEvent(_ e: EventItem) {
        guard let i = events.firstIndex(where: { $0.id == e.id }) else { return }
        var ev = e; ev.title = ev.title.trimmingCharacters(in: .whitespaces)
        events[i] = ev
        push(StateKey.events, events)
    }
    func toggleEventDone(_ id: String) {
        guard let i = events.firstIndex(where: { $0.id == id }) else { return }
        events[i].done.toggle()
        push(StateKey.events, events)
    }
    func deleteEvent(_ id: String) {
        events.removeAll { $0.id == id }
        push(StateKey.events, events)
    }
    /// Whole days from today to an event date (negative = overdue). Timezone-stable.
    func daysUntil(_ dateKey: String) -> Int? {
        guard let d = Self.date(fromKey: dateKey), let today = Self.date(fromKey: todayKey) else { return nil }
        return Calendar(identifier: .gregorian).dateComponents([.day], from: today, to: d).day
    }

    // MARK: - Productivity / watch log

    var sortedWatch: [WatchItem] { watch.sorted { $0.addedAt > $1.addedAt } }

    @discardableResult
    func addWatchItem(_ item: WatchItem) -> WatchItem {
        var it = item
        if it.addedAt.isEmpty { it.addedAt = Self.nowStamp() }
        watch.insert(it, at: 0)
        push(StateKey.watch, watch)
        return it
    }
    func updateWatchItem(_ item: WatchItem) {
        guard let i = watch.firstIndex(where: { $0.id == item.id }) else { return }
        watch[i] = item
        push(StateKey.watch, watch)
    }
    func toggleWatched(_ id: String) {
        guard let i = watch.firstIndex(where: { $0.id == id }) else { return }
        watch[i].watched.toggle()
        push(StateKey.watch, watch)
    }
    func deleteWatchItem(_ id: String) {
        watch.removeAll { $0.id == id }
        push(StateKey.watch, watch)
    }
    /// Best-effort AI category for a video (free model). Returns nil on any failure.
    func categorizeVideo(title: String, channel: String) async -> WatchCategory? {
        guard let cat = try? await api.categorize(title: title, channel: channel) else { return nil }
        return WatchCategory(rawValue: cat)
    }

    // MARK: - Data management (reset)  — all guarded behind hold-to-confirm in the UI

    func resetFinance()   { finance = FinanceState();   push(StateKey.finance, finance) }
    func resetPortfolio() { portfolio = PortfolioState(); push(StateKey.portfolio, portfolio) }
    func resetJournal()   { journal = [:];              push(StateKey.journal, journal) }
    func resetNotes()     { notes = [];                 push(StateKey.notes, notes) }
    func resetFitness()   {
        fitness = [:];                 push(StateKey.fitness, fitness)
        fitnessProfile = FitnessProfile(); push(StateKey.fitnessProfile, fitnessProfile)
        nutrition = NutritionState();  push(StateKey.nutrition, nutrition)
        training = TrainingState();    push(StateKey.training, training)
    }

    /// Wipe every accumulated-data module. Keeps the person's `profile` identity
    /// and the journal preset chips — those are configuration, not data.
    func resetEverything() {
        finance = FinanceState();      push(StateKey.finance, finance)
        portfolio = PortfolioState();  push(StateKey.portfolio, portfolio)
        journal = [:];                 push(StateKey.journal, journal)
        notes = [];                    push(StateKey.notes, notes)
        fitness = [:];                 push(StateKey.fitness, fitness)
        fitnessProfile = FitnessProfile(); push(StateKey.fitnessProfile, fitnessProfile)
        nutrition = NutritionState();  push(StateKey.nutrition, nutrition)
        training = TrainingState();    push(StateKey.training, training)
        days = [:];                    push(StateKey.days, days)
        events = [];                   push(StateKey.events, events)
        watch = [];                    push(StateKey.watch, watch)
        networth = NetWorthState();    push(StateKey.networth, networth)
    }
}
