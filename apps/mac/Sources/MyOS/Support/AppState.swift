import Foundation
import SwiftUI
#if os(macOS)
import Darwin
#endif

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
    @Published var fitness: [String: FitnessDay] = [:]
    @Published var fitnessProfile = FitnessProfile()
    @Published var journal: [String: JournalEntry] = [:]
    @Published var journalPresets = JournalPresets()
    @Published var notes: [Note] = []
    @Published var days: [String: DayPlan] = [:]
    @Published var profile = Profile()
    @Published var chat = ChatState()
    @Published var themeVersion = 0        // bumped on theme change to re-render app-wide
    /// Flipped by a Notes double-tap (title / empty card / dock). NotesView consumes it.
    @Published var pendingNewNote = false
    @Published var nutrition = NutritionState()
    @Published var training = TrainingState()
    @Published var events: [EventItem] = []
    @Published var eventTags: [EventTag] = []
    @Published var watch: [WatchItem] = []
    /// What Catherine remembers about him. See `Support/AI/Memory.swift`.
    @Published var memory = MemoryState()
    /// How the last answer was built — retrieved passages, recalled memories,
    /// tool calls, timing. In memory only, for the debug sheet. Never logged.
    @Published var lastTrace: CatrineTrace?
    @Published var belongings = BelongingsState()
    /// Everything the camera has read, newest first. See `Support/ScanRecord.swift`.
    @Published var scans: [ScanRecord] = []
    /// The synced Task Mode switch. See `Support/TaskMode.swift`.
    @Published var taskMode = TaskModeState()
    /// Friday progress reports, newest first. See `Support/WeeklyReport.swift`.
    @Published var weekly: [WeeklyReport] = []
    @Published var weeklyBusy = false
    /// Where time actually went, on every device. See `Support/Activity/`.
    @Published var activity = ActivityDoc()
    /// The session happening right now on THIS device. Never synced — it is a
    /// live reading, and by the time it reached another device it would be a
    /// claim about the past.
    @Published var liveActivity: ActivityEvent?

    /// A step goal crossed just now, waiting to be celebrated on Today. Cleared
    /// when the card is dismissed; never restored from state, because the party
    /// is for the moment it happened, not for every launch afterwards.
    @Published var stepCelebration: StepCelebration?
    @Published var weeklyError: String?
    /// In memory only: stops a failing report from re-running on every
    /// return to the foreground. See `generateWeeklyReportIfDue`.
    var lastWeeklyAttempt: Date?
    /// Macro Intelligence — the snapshot on screen, and every one fetched this
    /// session. Not synced: it is public market data, re-fetchable anywhere.
    @Published var macro: MacroSnapshot?
    @Published var macroBusy = false
    @Published var macroError: String?
    var macroCache: [String: MacroSnapshot] = [:]
    @Published var fold: FoldData?
    @Published var foldBusy = false
    @Published var foldError: String?
    @Published var foldLinked = FoldClient.isLinked

    // Sync status
    @Published var lastSyncError: String?
    @Published var lastHydrateError: String?
    private(set) var isHydrated = false

    /// Internal rather than private: the AI layer lives in `Support/AI/*` as
    /// extensions on this type, and `private` is file-scoped in Swift.
    let api = APIClient()
    private var pushTasks: [String: Task<Void, Never>] = [:]
    private var pushGen: [String: Int] = [:]
    private var liveSyncTask: Task<Void, Never>?
    #if os(macOS)
    private var foldFileWatch: DispatchSourceFileSystemObject?
    #endif
    private var isPulling = false
    /// One media migration at a time. `syncNow()` and the media tick both start
    /// one, and two interleaving overwrite each other's results.
    private var isMigratingEventMedia = false

    init() {
        api.vault = vault
        EventMediaStore.shared.configure(api: api, vault: vault)
        // Body photos are sealed with the same DEK; the sync needs to reach it.
        ProgressPhotoSync.vault = vault
        // Fold's tokens are sealed with the vault DEK — read it live so a lock or
        // an unlock is picked up without anyone having to re-register the key.
        FoldSession.keyProvider = { [vault] in vault.dek }
        restoreCachedSession()
        DietBridge.shared.start(state: self)
    }

    // MARK: - Instant relaunch

    private static let kSessionActive = SessionDefaults.active
    private static let kSessionUser   = SessionDefaults.username

    /// Show cached data instantly on relaunch — but only if this device's Keychain
    /// still holds the DEK to decrypt it. On a fresh device (or after logout) there's
    /// no cached key, so nothing is shown until the user unlocks.
    private func restoreCachedSession() {
        guard UserDefaults.standard.bool(forKey: Self.kSessionActive) else { return }
        username = UserDefaults.standard.string(forKey: Self.kSessionUser) ?? ""
        ProgressPhotoStore.use(account: username)
        guard let raw = api.cachedRawState() else { return }
        vault.adoptMeta(api.cryptoMeta(from: raw))
        guard vault.hasMeta,
              vault.unlockFromKeychain(username: username),
              let payload = try? api.decodePayload(fromRaw: raw) else { return }
        apply(payload)
        isHydrated = true
        // No training migration here: this is the on-disk cache, which can be
        // older than the server. `hydrate()` runs next and migrates from the
        // authoritative copy.
        phase = .loggedIn
        DietBridge.shared.start(state: self)
        startLiveSync()
    }

    private func markSession(active: Bool, username: String = "") {
        let d = UserDefaults.standard
        d.set(active, forKey: Self.kSessionActive)
        if active { d.set(username, forKey: Self.kSessionUser) }
        else { d.removeObject(forKey: Self.kSessionUser) }
    }

    private func apply(_ s: AppStatePayload) {
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
        eventTags = s.eventTags ?? []
        if eventTags.isEmpty { eventTags = EventTag.seedDefaults }   // first run → the built-in seven
        watch     = s.watch ?? []
        memory    = s.memory ?? MemoryState()
        scans     = s.scans ?? []
        taskMode  = s.taskMode ?? TaskModeState()
        weekly    = s.weekly ?? []
        // Merged, not replaced: the other device has been appending sessions to
        // the same key. See `ActivityDoc.merged(with:)`.
        activity  = activity.merged(with: s.activity ?? ActivityDoc())
        belongings = s.belongings ?? BelongingsState()
        // Only when the payload actually carries one. Falling back to the
        // default here would reset the theme on every launch of any device
        // whose last push had not landed yet — the local cache is a better
        // answer than a default in that window.
        if let appearance = s.appearance { AppearanceStore.shared.apply(appearance) }
        if let v = s.fold, !FoldSnapshotBuilder.isBare(v) { fold = v }
        ingestLocalFold()
        restoreFoldIfBare()
    }

    /// One-time purge of the removed money keys (finance / portfolio / net worth)
    /// from the synced store — finance tracking now lives in Fold. Deletes the rows
    /// so the old data stops syncing to every device; runs once per device.
    /// One-shot: `defaults write com.berjil.myos myos.clearMealPlanOnce -bool true`
    /// then relaunch — clears the weekly meal plan after a successful hydrate.
    private static let kClearMealPlanOnce = "myos.clearMealPlanOnce"
    private func applyPendingMealPlanClear() {
        let d = UserDefaults.standard
        guard d.bool(forKey: Self.kClearMealPlanOnce) else { return }
        d.removeObject(forKey: Self.kClearMealPlanOnce)
        clearMealPlan()
    }

    private static let kFinancePurged = "myos.finance.purged.v1"
    private func purgeRemovedFinanceKeys() async {
        let d = UserDefaults.standard
        guard !d.bool(forKey: Self.kFinancePurged) else { return }
        for key in ["myos.finance", "myos.portfolio", "myos.networth"] {
            try? await api.deleteState(key)
        }
        d.set(true, forKey: Self.kFinancePurged)
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
        ProgressPhotoStore.use(account: username)
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
            migrateTrainingIfNeeded()
            pendingRaw = nil
            lastSyncError = nil; lastHydrateError = nil
            phase = .loggedIn
            applyPendingMealPlanClear()
            healFoldSnapshot()
            startLiveSync()
            DietBridge.shared.start(state: self)
            await purgeRemovedFinanceKeys()
        } catch is APIClient.VaultLockedError {
            phase = .locked
        } catch {
            isHydrated = false      // keep push gated so we never wipe server data
            if hadCache { lastHydrateError = "Offline — showing saved data." }
            else {
                let why = (error as? APIError)?.message ?? "Couldn't load your data."
                lastHydrateError = why
                // Say so on the screen the user is actually looking at. When a
                // register or login succeeded but this first fetch failed, the
                // catch touched neither `phase` nor `authError`, so the login
                // form just sat there unchanged — no spinner, no error, no
                // navigation. People concluded it had not worked, tapped CREATE
                // ACCOUNT again, were told the username was taken, and signed up
                // under a second name, orphaning the account they already had.
                if phase == .loggedOut || phase == .loading {
                    authError = "Signed in, but couldn't reach your data: \(why)"
                    // And put the user somewhere with a control. `phase` stayed
                    // `.loading`, so RootView kept showing the splash — "Getting
                    // your day ready…" — with no error, no retry and no way to
                    // the login form. The only escape was leaving the app and
                    // coming back, which nothing said.
                    phase = .loggedOut
                }
            }
        }
    }

    func logout() async {
        DietBridge.shared.stop()
        stopLiveSync()
        stopFoldWatch()
        cancelPendingPushes()
        // Local media is not part of the state blob, so clearing the cache does
        // not touch it. Point the photo store at the logged-out scope and drop
        // the decrypted event-media cache, or the next account to sign in on
        // this Mac inherits both.
        ProgressPhotoStore.use(account: "")
        EventMediaStore.shared.purgeCache()
        FoldData.deleteFromDisk()
        AISettingsStore.shared.reset()
        // The activity write-ahead log is a plain file, not account-scoped, and
        // it holds three days of app names, site domains and window titles —
        // written even while logged out, because tracking starts before auth. On
        // the next sign-in the coordinator folded all of it into whoever was
        // now signed in, and pushed it into *their* encrypted activity.
        ActivityJournal.clear()
        await api.logout()
        markSession(active: false)
        api.clearCache()
        vault.forget(username: username)
        HTTPCookieStorage.shared.cookies?.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
        fitness = [:]; journal = [:]
        notes = []; days = [:]; profile = Profile()
        fitnessProfile = FitnessProfile(); journalPresets = JournalPresets()
        chat = ChatState(); suggestions = nil
        nutrition = NutritionState(); training = TrainingState()
        events = []; eventTags = []; watch = []; belongings = BelongingsState(); memory = MemoryState()
        scans = []; taskMode = TaskModeState(); weekly = []
        // Retrieved passages and recalled memories from the last answer. Debug
        // state, but it is still this user's private data sitting in memory.
        lastTrace = nil; stepCelebration = nil
        activity = ActivityDoc(); liveActivity = nil
        fold = nil
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
        // One at a time. The submit path is not disabled while this runs, and
        // `vault.setup()` spends ~1.5s in two 600k-round PBKDF2 derivations on
        // the main thread with nothing on screen changing — so a second Return
        // was easy, and it minted a SECOND DEK over the first. Both then PUT
        // their own meta while `migrateEncryptExisting` sealed twenty modules
        // under whichever was current. If the server kept the first meta, the
        // passphrase derived DEK1, the check token validated, the vault
        // "unlocked" — and every data key failed to open, from the recovery code
        // too. A brand-new account, permanently unopenable, on its first run.
        guard !vaultBusy else { return }
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
            migrateTrainingIfNeeded()
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
            (StateKey.fitness, fitness), (StateKey.fitnessProfile, fitnessProfile),
            (StateKey.journal, journal), (StateKey.journalPresets, journalPresets),
            (StateKey.notes, notes), (StateKey.days, days), (StateKey.profile, profile),
            (StateKey.chat, chat), (StateKey.nutrition, nutrition), (StateKey.training, training),
            (StateKey.events, events), (StateKey.eventTags, eventTags),
            (StateKey.watch, watch), (StateKey.belongings, belongings),
            (StateKey.memory, memory), (StateKey.scans, scans),
            (StateKey.taskMode, taskMode), (StateKey.weekly, weekly),
            (StateKey.activity, activity)
        ]
        for (key, value) in jobs where raw[key] != nil {
            try? await api.putState(key, value)
        }
        if let f = fold { try? await api.putState(StateKey.fold, f) }
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
            migrateTrainingIfNeeded()
            pendingRaw = nil
            lastSyncError = nil; lastHydrateError = nil
            phase = .loggedIn
            applyPendingMealPlanClear()
            healFoldSnapshot()
            startLiveSync()
            DietBridge.shared.start(state: self)
            await purgeRemovedFinanceKeys()
        } catch {
            vaultError = (error as? APIError)?.message ?? "Couldn't load your data after unlock."
        }
    }

    // MARK: - Vault: manage (change passphrase, new recovery code, export)

    @discardableResult
    /// Rotate the passphrase. `current` is verified first — this is as
    /// destructive as a wipe (on the Mac the passphrase is demanded at every
    /// launch), and a wipe already re-authenticates. Without it, anyone reaching
    /// an unlocked running MyOS could type a new passphrase, have it accepted
    /// because the DEK is already in memory, and lock the owner out at the next
    /// launch — recoverable only with the recovery code.
    func changePassphrase(current: String, to newPass: String) async -> Bool {
        vaultError = nil
        guard newPass.count >= 8 else { vaultError = "Use at least 8 characters."; return false }
        guard !vaultBusy else { return false }
        vaultBusy = true; defer { vaultBusy = false }
        guard await verifyPassphrase(current) else {
            vaultError = "That isn't your current passphrase."
            return false
        }
        do {
            let meta = try vault.rewrap(newPassphrase: newPass)
            try await api.putCryptoMeta(meta)
            vault.adoptMeta(meta)          // only now that the server has it
            vault.cacheToKeychain(username: username)
            return true
        } catch {
            vaultError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    func regenerateRecoveryCode() async {
        vaultError = nil
        guard !vaultBusy else { return }
        vaultBusy = true; defer { vaultBusy = false }
        let built: (meta: CryptoMeta, recoveryCode: String)
        do { built = try vault.regenerateRecovery() } catch {
            vaultError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return
        }
        do {
            try await api.putCryptoMeta(built.meta)
            vault.adoptMeta(built.meta)     // only now that the server has it
            recoveryCodeToShow = built.recoveryCode
        } catch {
            // The PUT may well have landed and only the response been lost — a
            // 15-second request timeout on a single-shot write. That retires the
            // code on paper while never showing its replacement, and the next
            // forgotten passphrase is then unrecoverable. So ask the server what
            // it actually holds before reporting failure.
            if await serverHasMeta(built.meta) {
                vault.adoptMeta(built.meta)
                recoveryCodeToShow = built.recoveryCode
                return
            }
            vaultError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Whether the server's stored crypto metadata is the one we just built.
    private func serverHasMeta(_ meta: CryptoMeta) async -> Bool {
        guard let raw = try? await api.fetchStateRaw(),
              let stored = api.cryptoMeta(from: raw) else { return false }
        return stored.wrappedByRecovery == meta.wrappedByRecovery
            && stored.recoverySalt == meta.recoverySalt
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
        add("profile", profile)
        add("fitness", fitness); add("fitnessProfile", fitnessProfile)
        add("journal", journal); add("journalPresets", journalPresets)
        add("notes", notes); add("days", days); add("chat", chat)
        add("nutrition", nutrition); add("training", training)
        add("events", events); add("eventTags", eventTags)
        add("watch", watch)
        add("memory", memory)
        add("belongings", belongings)
        add("scans", scans); add("taskMode", taskMode); add("weekly", weekly)
        add("activity", activity)
        return try? JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys])
    }

    // MARK: - Instant push + live pull (Mac ↔ iPhone)

    /// Writes land on the server almost immediately so the other device can
    /// pick them up on the next 2s poll. Rapid keystrokes still collapse into
    /// one PUT via a short debounce.
    /// Ignore a stale GET that still has the pre-write snapshot (Netlify KV
    /// can serve the previous value for a couple of seconds after PUT).
    private var lastLocalWrite: [String: Date] = [:]

    /// How long to wait before each re-attempt of a failed PUT.
    ///
    /// A write that fails is not allowed to just vanish. The local model has
    /// already changed by the time `push` is called, and `applyRemote` will
    /// overwrite it with the server's older copy on the very next poll unless
    /// the key is still marked pending. Without this, losing the network for a
    /// moment meant the event you just added was silently deleted a second
    /// later. Retrying holds the key pending for the whole window.
    static let pushRetryDelays: [UInt64] = [
        1_000_000_000,      // 1s
        3_000_000_000,      // 3s
        8_000_000_000,      // 8s
        20_000_000_000      // 20s
    ]

    // Internal, not private: the AI layer extends this type from Support/AI/*.
    func push(_ key: String, _ value: Encodable) {
        guard isHydrated else {
            lastSyncError = "Not synced yet — refresh before saving."
            return
        }
        lastLocalWrite[key] = Date()
        quickenSync()          // you just did something; the echo matters now
        pushGen[key, default: 0] += 1
        let gen = pushGen[key] ?? 1
        pushTasks[key]?.cancel()
        pushTasks[key] = Task { [api] in
            try? await Task.sleep(nanoseconds: 80_000_000)
            if Task.isCancelled {
                await self.finishPush(key, gen: gen, error: nil)
                return
            }
            var attempt = 0
            while true {
                do {
                    try await api.putState(key, value)
                    await self.finishPush(key, gen: gen, error: nil)
                    return
                } catch is CancellationError {
                    // Superseded by a newer push, which already owns the slot —
                    // the generation guard inside `finishPush` makes this a no-op.
                    await self.finishPush(key, gen: gen, error: nil)
                    return
                } catch let e as URLError where e.code == .cancelled {
                    // NOT necessarily our own cancellation: URLSession reports
                    // this when the app is backgrounded or the network changes
                    // under an in-flight request. Returning without releasing
                    // the slot left `hasPendingPush` true forever, which wedged
                    // the key out of `applyRemote` — that module silently
                    // stopped accepting anything from the other device until
                    // the app was relaunched.
                    await self.finishPush(key, gen: gen, error: nil)
                    return
                } catch {
                    let msg = (error as? APIError)?.message ?? error.localizedDescription
                    guard Self.isWorthRetrying(error),
                          attempt < Self.pushRetryDelays.count,
                          await self.isCurrentPush(key, gen: gen) else {
                        await self.finishPush(key, gen: gen, error: msg)
                        return
                    }
                    try? await Task.sleep(nanoseconds: Self.pushRetryDelays[attempt])
                    if Task.isCancelled {
                        await self.finishPush(key, gen: gen, error: nil)
                        return
                    }
                    attempt += 1
                }
            }
        }
    }

    /// Release the pending slot for `key` — but only if this push is still the
    /// current one. A newer push has already taken the slot, and clearing it
    /// here would drop *its* protection rather than ours.
    private func finishPush(_ key: String, gen: Int, error: String?) {
        guard pushGen[key] == gen else { return }
        pushTasks[key] = nil
        lastSyncError = error.map { "Couldn't save \(key): \($0)" }
    }

    private func isCurrentPush(_ key: String, gen: Int) -> Bool { pushGen[key] == gen }

    /// Whether a failed PUT could plausibly succeed if we simply ask again.
    ///
    /// Retrying is for the network being briefly gone. A 401 means the session
    /// is over and a 400 means the server will refuse this body every time, so
    /// re-sending them just burns requests against a free tier that has to stay
    /// free. Timeouts and rate limits are the two 4xx cases worth waiting out.
    nonisolated static func isWorthRetrying(_ error: Error) -> Bool {
        guard let api = error as? APIError else { return true }   // transport-level
        if api.status == 408 || api.status == 429 { return true }
        return !(400..<500).contains(api.status)
    }

    /// Abandon every in-flight save.
    ///
    /// Pushes now retry for up to half a minute, so without this they outlive
    /// the session that authorised them: a retry landing after somebody else
    /// signs in on this device would PUT the previous account's data under the
    /// new account's cookie. Cancelling also clears the pending-key bookkeeping,
    /// which otherwise carried into the next session and made `applyRemote` skip
    /// those keys for a user they had nothing to do with.
    private func cancelPendingPushes() {
        pushTasks.values.forEach { $0.cancel() }
        pushTasks.removeAll()
        // `pushGen` is deliberately NOT reset. Generations have to keep rising
        // for the lifetime of the process: zero them here and the next session's
        // first push for a key is gen 1 again, so a cancelled task from the
        // previous session — still unwinding — matches on generation and
        // releases the new push's pending slot, re-opening the very window
        // `finishPush` exists to close.
        lastLocalWrite.removeAll()
    }

    private func hasPendingPush(_ key: String) -> Bool { pushTasks[key] != nil }
    private func wroteRecently(_ key: String, window: TimeInterval = 20) -> Bool {
        guard let t = lastLocalWrite[key] else { return false }
        return Date().timeIntervalSince(t) < window
    }

    /// Pull remote state and apply only keys this device isn't currently writing.
    /// Last write wins per module key — same model as the KV store.
    func pullRemote() async {
        if !isHydrated {
            await hydrate()
            if isHydrated { startLiveSync() }
            return
        }
        guard vault.isUnlocked, !isPulling else { return }
        isPulling = true
        defer { isPulling = false }
        do {
            // nil = 304 Not Modified: nothing to decrypt, decode or apply.
            guard let raw = try await api.fetchStateIfChanged() else {
                lastHydrateError = nil
                return
            }
            let payload = try api.decodePayload(fromRaw: raw)
            // Only once every offered key actually landed. See `applyRemote`.
            let landed = applyRemote(payload)
            if landed { api.commitStateETag() }
            // Something really came down — stay fast while the other device is
            // active, and try again promptly for anything held back.
            quickenSync()
            lastHydrateError = nil
        } catch let e as APIError where e.status == 401 || e.status == 403 {
            // The session is over. `bootstrap` gives a launch-time 401 exactly
            // this treatment, but a live-sync 401 was swallowed here — so an app
            // left open past its 60-day session kept accepting edits for hours,
            // pushed each one into a 401 that `isWorthRetrying` rightly refuses
            // to retry, showed nothing, and lost the lot at the next relaunch.
            await logout()
        } catch {
            // Stay quiet — the next tick retries. Surface only a hard hydrate miss.
        }
    }

    /// Apply a remote snapshot without stomping an in-flight local edit.
    ///
    /// Returns false when a key that differed had to be held back.
    ///
    /// That return value is the whole point. The ETag is global — one header for
    /// all twenty-odd keys — so committing it after a partial apply tells the
    /// server "I already have this version". Every later poll then answers 304
    /// and the key that was skipped is never offered again. The grace windows
    /// below are meant to expire after a few seconds; committing straight
    /// through them turned a deliberate deferral into permanent data loss. Two
    /// devices logging meals minutes apart was enough: the Mac declined the
    /// phone's nutrition once, stored the ETag, never saw it again, and
    /// overwrote it server-side on its own next write.
    private func applyRemote(_ s: AppStatePayload) -> Bool {
        var deferred = false

        /// Whether `key` must be held back this round — and remember that it was.
        func blocked(_ key: String, grace: TimeInterval? = nil, busy: Bool = false) -> Bool {
            let held = hasPendingPush(key) || busy
                || (grace.map { wroteRecently(key, window: $0) } ?? false)
            if held { deferred = true }
            return held
        }

        // Fitness and training carry the same risk as nutrition — a poll issued
        // before a local write can return after the push completed, so
        // `hasPendingPush` is already false and the remote copy silently reverts
        // a ticked set or a typed weight. They get the grace window too.
        if let v = s.fitness, v != fitness, !blocked(StateKey.fitness, grace: 20) { fitness = v }
        if let v = s.fitnessProfile, v != fitnessProfile,
           !blocked(StateKey.fitnessProfile) { fitnessProfile = v }
        // Notes and journal get a grace window on top of the in-flight check.
        // A push is only "pending" for the 80ms debounce plus its request, and
        // at a 1.5s poll that leaves gaps between keystrokes wide enough for a
        // remote snapshot to land on text being typed right now.
        if let v = s.journal, v != journal, !blocked(StateKey.journal, grace: 5) { journal = v }
        if let v = s.journalPresets, v != journalPresets,
           !blocked(StateKey.journalPresets) { journalPresets = v }
        if let v = s.notes, v != notes, !blocked(StateKey.notes, grace: 5) { notes = v }
        if let v = s.days, v != days, !blocked(StateKey.days) { days = v }
        if let v = s.profile, v != profile, !blocked(StateKey.profile) { profile = v }
        // Never clobber an in-flight send — a 2s pull of the previous snapshot
        // was landing replies on the wrong turn.
        if let v = s.chat, v != chat, !blocked(StateKey.chat, busy: chatBusy) { chat = v }
        if let v = s.nutrition, v != nutrition,
           !blocked(StateKey.nutrition, grace: 20) { nutrition = v }
        if let v = s.training, v != training, !blocked(StateKey.training, grace: 20) { training = v }
        if let v = s.events, v != events, !blocked(StateKey.events) { events = v }
        if let v = s.eventTags, v != eventTags, !blocked(StateKey.eventTags) { eventTags = v }
        if let v = s.watch, v != watch, !blocked(StateKey.watch) { watch = v }
        if let v = s.memory, v != memory, !blocked(StateKey.memory) { memory = v }
        if let v = s.belongings, v != belongings, !blocked(StateKey.belongings) { belongings = v }
        if let v = s.scans, v != scans, !blocked(StateKey.scans) { scans = v }
        // The mode is the one switch meant to reach across devices — a flip on
        // the Mac lands here on the phone within one poll.
        if let v = s.taskMode, v != taskMode, !blocked(StateKey.taskMode) { taskMode = v }
        if let v = s.weekly, v != weekly, !blocked(StateKey.weekly) { weekly = v }
        // A colour chosen on the Mac is the same colour on the phone one poll
        // later — that is most of what makes this feel like one app.
        if let v = s.appearance, !blocked(StateKey.appearance) {
            AppearanceStore.shared.apply(v)
        }
        // Activity merges rather than replaces even on a live pull: both devices
        // append to this key, so taking the remote copy wholesale would drop
        // whatever this one recorded since the last push.
        if let v = s.activity {
            let merged = activity.merged(with: v)
            if merged != activity { activity = merged }
        }
        if let v = s.fold, v != fold, !blocked(StateKey.fold) {
            if FoldSnapshotBuilder.isBare(v) {
                restoreFoldIfBare()
                if let cur = fold, !FoldSnapshotBuilder.isBare(cur) { push(StateKey.fold, cur) }
            } else {
                fold = v
                FoldData.save(v)
            }
        }
        if eventTags.isEmpty { eventTags = EventTag.seedDefaults }
        return !deferred
    }

    /// How often to ask the server "changed?".
    ///
    /// Each tick is a conditional GET that costs a few hundred bytes unless
    /// something actually changed, so the constraint is request *count*, not
    /// bytes — the Workers free tier allows 100k a day and MyOS is not allowed
    /// to cost anything. A flat 2s across two devices burns ~86k of that on
    /// polling alone, which is why this used to sit at a flat 15s and why a
    /// change made on the Mac could take a quarter of a minute to show up on
    /// the phone.
    ///
    /// Two speeds fixes both ends. The app polls fast only while it is actually
    /// in front of you — which is the only time a delay is something you can
    /// see — and drops back to the cheap beat the moment it isn't. Six focused
    /// hours a day is ~14k requests, and both devices are rarely focused at
    /// once, so the bill stays comfortably inside the free tier.
    static let activePollInterval: UInt64 = 1_500_000_000    // 1.5s, in front of you
    static let idlePollInterval: UInt64 = 15_000_000_000     // 15s, everything else

    /// The ceiling the foreground poll drifts up to while nothing is happening.
    ///
    /// A flat 1.5s regardless of what you are doing is what put this on course to
    /// exhaust the free tier: ~20k requests a day per user across two devices,
    /// against 100k a day shared by everyone. But slowing it outright would make
    /// the two devices feel disconnected exactly when you are using them.
    ///
    /// So the fast beat is kept for the moment it is worth paying for — right
    /// after something changed, here or on the other device — and the interval
    /// doubles toward this ceiling through a quiet stretch. Any local write, any
    /// remote change, or coming back to the app resets it. Sitting on a screen
    /// doing nothing costs about a fifth of what it used to; picking the phone up
    /// mid-edit is exactly as quick as before.
    static let backoffPollCeiling: UInt64 = 12_000_000_000    // 12s

    /// Current foreground interval, between `activePollInterval` and the ceiling.
    private var pollInterval: UInt64 = AppState.activePollInterval

    /// Something happened — poll fast again.
    func quickenSync() { pollInterval = Self.activePollInterval }

    /// Media keeps its own slower beat. A progress-photo sync lists an R2
    /// bucket and a media migration uploads — both far heavier than a
    /// conditional GET, and neither is something you are watching for.
    static let mediaSyncInterval: TimeInterval = 15

    /// Whether the app is the thing you are looking at. Set from `scenePhase`;
    /// drives which of the two poll speeds is in use.
    @Published var isForeground = true

    private var lastMediaSync = Date.distantPast

    /// Move any still-inline event photos/videos into R2, sealed. Runs once per
    /// launch after unlock. Each asset is uploaded before the blob is rewritten,
    /// so an interruption leaves un-migrated items rather than dangling keys.
    func migrateEventMediaToR2() async {
        guard isHydrated, let dek = vault.dek else { return }
        guard !isMigratingEventMedia else { return }
        guard events.contains(where: { $0.media.contains(where: \.needsMigration) }) else { return }
        isMigratingEventMedia = true
        defer { isMigratingEventMedia = false }

        // Collect into a map keyed by media id rather than editing a snapshot of
        // the whole array. Uploading a 25 MB video takes long enough for a lot to
        // happen: another memory logged here, one arriving from the phone through
        // `applyRemote` — which this does not block, because a migration is not a
        // push. Writing the pre-upload snapshot back afterwards deleted every one
        // of those, on both devices, silently. `syncNow()` can start a second
        // migration from its own task too, hence the reentrancy guard.
        var migrated: [String: EventMedia] = [:]
        // Labelled, so one failure ends the whole pass. A bare `break` only left
        // the inner loop, so a relocked vault or a dropped network was retried
        // once per remaining event — with a two-minute resource timeout on large
        // video that is an hour of a single pass, blocking every other migration
        // behind the reentrancy guard, and repeating on every media tick.
        passes: for event in events {
            for m in event.media where m.needsMigration {
                do {
                    if let out = try await EventMediaStore.migrate(m, api: api, dek: dek) {
                        migrated[m.id] = out
                    }
                } catch {
                    break passes   // keep what landed, retry next tick
                }
            }
        }
        guard !migrated.isEmpty else { return }

        // Re-read: `events` is whatever it is *now*, not what it was before the
        // awaits. Only the migrated media entries are replaced.
        var next = events
        var moved = 0
        for i in next.indices {
            for j in next[i].media.indices {
                if let out = migrated[next[i].media[j].id] {
                    next[i].media[j] = out
                    moved += 1
                }
            }
        }
        guard moved > 0 else { return }
        events = next
        push(StateKey.events, events)
    }

    /// True inside an `xcodebuild test` run. The unit suite launches the real
    /// app as its host, and a host that polls the production API every 1.5
    /// seconds for the length of a test run is both pointless and a good way to
    /// make the suite hang on a slow network.
    static var isRunningTests: Bool { NSClassFromString("XCTestCase") != nil }

    func startLiveSync() {
        guard !Self.isRunningTests else { return }
        DietBridge.shared.start(state: self)
        liveSyncTask?.cancel()
        liveSyncTask = Task { [weak self] in
            while !Task.isCancelled {
                let foreground = self?.isForeground ?? false
                let wait = foreground ? (self?.pollInterval ?? Self.activePollInterval)
                                      : Self.idlePollInterval
                try? await Task.sleep(nanoseconds: wait)
                guard !Task.isCancelled else { return }
                await self?.pullRemote()
                await self?.syncMediaIfDue()
                await self?.easeOffPolling()
            }
        }
        startFoldWatch()
    }

    /// Drift the foreground interval up through a quiet stretch. `quickenSync`
    /// pulls it straight back down the moment anything actually happens.
    private func easeOffPolling() {
        guard isForeground else { return }
        pollInterval = min(pollInterval * 2, Self.backoffPollCeiling)
    }

    /// The heavy half of a tick, rate-limited to its own interval so the fast
    /// state poll does not drag an R2 listing along behind it.
    private func syncMediaIfDue(force: Bool = false) async {
        guard force || Date().timeIntervalSince(lastMediaSync) >= Self.mediaSyncInterval else { return }
        lastMediaSync = Date()
        // Progress photos live in R2, keyed by filename, and are NOT part of the
        // state blob — so a state poll, ETag or not, can never reveal a photo
        // added on the other device. Before this, the Mac only listed them when
        // a photo view appeared, which is why a shot taken on the iPhone could
        // sit invisible indefinitely. Detached so a slow upload cannot stall the
        // tick.
        Task { await ProgressPhotoSync.syncAll() }
        // Cheap guard when there's nothing inline, so newly added media moves to
        // R2 within one tick without extra wiring.
        await migrateEventMediaToR2()
        // A media fetch that failed once (locked vault at launch, a network
        // blip) would otherwise stay a grey placeholder until relaunch.
        // Retrying makes it self-healing; the call returns immediately when
        // nothing has failed.
        EventMediaStore.shared.retryFailures()
    }

    /// Coming back to the app: pull now rather than waiting out a tick, and let
    /// media catch up in the same breath.
    func syncNow() async {
        quickenSync()          // back in the app — be responsive again
        await pullRemote()
        await syncMediaIfDue(force: true)
    }

    func stopLiveSync() {
        liveSyncTask?.cancel()
        liveSyncTask = nil
        stopFoldWatch()
    }

    /// Pick up `fold.json` from disk.
    ///
    /// `live` marks the file-watcher path: a Fold login writes that file, so a
    /// change landing on disk really is the newest thing anywhere and should
    /// win. Every other caller runs during hydrate, where the snapshot that just
    /// came down from the server is at least as new — and taking disk
    /// unconditionally there meant a device that had been shut for a week booted
    /// up, replaced the fresh snapshot with its stale one, and `healFoldSnapshot`
    /// pushed last week's balances back for every other device to pull down.
    func ingestLocalFold(live: Bool = false) {
        guard let disk = FoldData.loadFromDisk(), disk != fold else { return }
        if FoldSnapshotBuilder.isBare(disk) {
            restoreFoldIfBare()
            return
        }
        if !live, let current = fold, !FoldSnapshotBuilder.isBare(current) { return }
        fold = disk
        if isHydrated { push(StateKey.fold, disk) }
    }

    /// Re-upload a real snapshot so a device stuck on ₹0 can pull it back.
    func healFoldSnapshot() {
        restoreFoldIfBare()
        guard isHydrated, let f = fold, !FoldSnapshotBuilder.isBare(f) else { return }
        push(StateKey.fold, f)
    }

    func restoreFoldIfBare() {
        guard let next = FoldSnapshotBuilder.resolved(current: fold, disk: FoldData.loadFromDisk()),
              next != fold else { return }
        fold = next
        FoldData.save(next)
        if isHydrated { push(StateKey.fold, next) }
    }

    private func startFoldWatch() {
        ingestLocalFold()
        #if os(macOS)
        foldFileWatch?.cancel()
        guard let dir = FoldData.fileURL?.deletingLastPathComponent() else { return }
        let fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend, .attrib, .rename, .link], queue: .main)
        src.setEventHandler { [weak self] in self?.ingestLocalFold(live: true) }
        src.setCancelHandler { close(fd) }
        src.resume()
        foldFileWatch = src
        #endif
    }

    private func stopFoldWatch() {
        #if os(macOS)
        foldFileWatch?.cancel()
        foldFileWatch = nil
        #endif
    }

    // MARK: - Date helpers

    /// The gregorian calendar these keys are defined in, kept between calls and
    /// rebuilt only if the device changes timezone.
    ///
    /// Every one of these helpers used to build a fresh `DateFormatter`, which
    /// is one of the more expensive objects in Foundation. They are called from
    /// view bodies — the Today pager alone derives 128 day keys per render, and
    /// a journal streak walks a key per day — so the formatters were being
    /// allocated in their thousands while a finger was on the screen.
    /// `yyyy-MM-dd` is a fixed machine format; parsed by hand it is arithmetic.
    private static var cachedCalendar = Calendar(identifier: .gregorian)
    private static var cachedZone = TimeZone.current
    static var dayCalendar: Calendar {
        let zone = TimeZone.current
        if zone != cachedZone {
            cachedZone = zone
            var c = Calendar(identifier: .gregorian)
            c.timeZone = zone
            cachedCalendar = c
        }
        return cachedCalendar
    }

    static func dateKey(_ date: Date) -> String {
        let c = dayCalendar.dateComponents([.year, .month, .day], from: date)
        return key(c.year ?? 1970, c.month ?? 1, c.day ?? 1)
    }

    private static func key(_ y: Int, _ m: Int, _ d: Int) -> String {
        "\(y)-\(m < 10 ? "0" : "")\(m)-\(d < 10 ? "0" : "")\(d)"
    }

    /// `yyyy-MM-dd` → its three numbers, or nil if it isn't one.
    private static func parts(_ key: String) -> DateComponents? {
        let f = key.split(separator: "-")
        guard f.count == 3, f[0].count == 4,
              let y = Int(f[0]), let m = Int(f[1]), let d = Int(f[2]),
              (1...12).contains(m), (1...31).contains(d)
        else { return nil }
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d
        return c
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
        let cal = dayCalendar
        guard let c = parts(key),
              let d = cal.date(from: c),
              let moved = cal.date(byAdding: .day, value: n, to: d) else { return key }
        return dateKey(moved)
    }
    /// Parse a `yyyy-MM-dd` key back to a Date (same gregorian path).
    static func date(fromKey key: String) -> Date? {
        guard let c = parts(key) else { return nil }
        return dayCalendar.date(from: c)
    }

    // MARK: - AI: food photo reading

    @Published var imageBusy = false
    @Published var imageError: String?

    /// Read a photo of a packaged food (nutrition label, product pack, menu item)
    /// into draft Foods for review. Does NOT save or log anything.
    func analyzeFood(imagesBase64: [String], mediaType: String) async -> (summary: String, drafts: [Food]) {
        imageError = nil
        guard isHydrated else { imageError = "Not synced yet — try again in a moment."; return ("", []) }
        imageBusy = true
        defer { imageBusy = false }
        do {
            let r = try await api.parseImage(imagesBase64: imagesBase64, mediaType: mediaType, mode: "food")
            let drafts: [Food] = (r.foods ?? []).map { item in
                Food(name: item.name, category: FoodCategory(rawValue: item.category) ?? .other,
                     servingLabel: item.servingLabel,
                     perServing: Macros(calories: item.calories, protein: item.protein, carbs: item.carbs,
                                        fiber: item.fiber, fats: item.fats),
                     vitamins: item.vitamins)
            }
            return (r.summary, drafts)
        } catch {
            imageError = (error as? APIError)?.message ?? error.localizedDescription
            return ("", [])
        }
    }

    /// Camera tab: food → nutrition, anything else → keep / skip + why.
    func analyzeScan(imagesBase64: [String], mediaType: String) async -> ScanInsight {
        imageError = nil
        imageBusy = true
        defer { imageBusy = false }
        do {
            let r = try await api.parseImage(imagesBase64: imagesBase64, mediaType: mediaType,
                                             mode: "scan", context: mentorContext())
            let insight = ScanInsight.from(r)
            if insight.failed {
                imageError = "Catherine couldn’t read that photo. Get closer and try again."
            }
            return insight
        } catch {
            imageError = (error as? APIError)?.message ?? error.localizedDescription
            return ScanInsight.parse(nil)
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

    /// The computed calorie/macro picture — nil until height, age and an
    /// actually-logged weight exist.
    ///
    /// This used to fall back to `targetWeightKg` when nothing was logged, which
    /// quietly computed the whole picture for a body the user does not have yet.
    /// On a cut that is the wrong direction twice over: a lighter goal weight
    /// lowers BMR, so the deficit is taken off an already-too-small maintenance
    /// number, and the protein target — 2 g per kg of *goal* weight — comes out
    /// below what it takes to hold muscle at the current one. Somebody at 90 kg
    /// aiming for 70 was being handed ~275 kcal and ~40 g of protein less than
    /// their own body called for. No weight logged is a thing we do not know,
    /// so it returns nil and the UI asks for one (or uses the manual override).
    func calorieTargets() -> CalorieTargets? {
        guard let h = profile.heightCm, h > 0, let age = profile.resolvedAge, age > 0 else { return nil }
        guard let w = latestWeightKg, w > 0 else { return nil }
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

    /// Set today's step count by hand.
    func setTodaySteps(_ steps: Int?) {
        updateFitness(todayKey) { $0.steps = steps.map { max(0, $0) } }
        celebrateStepsIfCrossed(on: todayKey)
    }

    /// Set (or clear) the step count for any day. The Mac has no pedometer, so
    /// a day you want to correct after the fact is typed in against its key.
    func setSteps(_ steps: Int?, on date: String) {
        updateFitness(date) { $0.steps = steps.map { max(0, $0) } }
        celebrateStepsIfCrossed(on: date)
    }

    /// Fold a batch of pedometer readings in with ONE state push — backfilling a
    /// week day-by-day through `updateFitness` would fire seven syncs.
    ///
    /// Days that already carry a count are left alone: only `authoritative`
    /// (today, which is still counting up) gets overwritten, so a correction
    /// typed on the Mac isn't clobbered by the next phone sync.
    func mergeSteps(_ byDay: [String: Int], authoritative: String?) {
        var changed = false
        for (key, n) in byDay {
            let existing = fitness[key]?.steps
            // A past day takes the higher reading, not merely the first one. It
            // used to be written only when nothing was there at all, which froze
            // every day at whatever the pedometer happened to have read the last
            // time the app was open: close it at 6pm on 7,400 steps, walk 3,000
            // more that evening, and yesterday stayed 7,400 forever — under the
            // goal, so the streak broke on a day that was actually walked.
            let write = key == authoritative ? existing != n : n > (existing ?? 0)
            guard write else { continue }
            var d = fitness[key] ?? FitnessDay()
            d.steps = max(0, n)
            fitness[key] = d
            changed = true
        }
        guard changed else { return }
        push(StateKey.fitness, fitness)
        // After the whole batch, not inside the loop: a backfill of seven days
        // should not fire seven celebrations, and only today can produce one.
        for key in byDay.keys where key == todayKey { celebrateStepsIfCrossed(on: key) }
    }
    /// The mandatory daily step goal — the one the streak is counted on.
    var stepsTarget: Int { stepGoals.daily }

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
    /// Add a food, or replace the one already going by that name.
    ///
    /// The MCP tool is called `upsert_food` but ran through `addFood`, which
    /// prepends unconditionally — so re-running an import appended the entire
    /// library a second time rather than updating it, and a food could sit in
    /// there three deep. The existing id is deliberately kept: meal plans and
    /// day logs reference foods by id, and handing back a new one would orphan
    /// every plan that already pointed at it.
    @discardableResult
    func upsertFood(_ food: Food) -> Food {
        let key = Food.matchKey(food.name)
        guard !key.isEmpty else { return addFood(food) }
        // An id that already matches wins over the name — a caller updating a
        // seed food passes its id, and that must become a custom override rather
        // than a second entry sharing the name.
        if let i = nutrition.customFoods.firstIndex(where: { $0.id == food.id }) {
            var f = food
            f.isDefault = false
            nutrition.customFoods[i] = f
            push(StateKey.nutrition, nutrition)
            return f
        }
        guard let i = nutrition.customFoods.firstIndex(where: { Food.matchKey($0.name) == key })
        else { return addFood(food) }
        var f = food
        f.id = nutrition.customFoods[i].id
        f.isDefault = false
        nutrition.customFoods[i] = f
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
        mutateLog(date) {
            $0.meals[meal.rawValue, default: []].append(PlanItem(foodId: foodId, quantity: quantity))
            $0.skipped.removeAll { $0 == meal.rawValue }
        }
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

    // Plan → confirmed (tick / edit / skip). The weekly template is never mutated.
    func mealState(_ date: String, _ meal: MealKey) -> MealLog.MealState { mealLog(date).state(meal) }

    /// What Today / the meal editor should show: the log if already logged,
    /// otherwise today's planned foods so a tap isn't an empty sheet.
    func mealEditorItems(date: String, meal: MealKey) -> [PlanItem] {
        if mealState(date, meal) == .logged { return mealLog(date).items(meal) }
        return planItems(Self.weekdayKey(date), meal)
    }

    /// Names for a meal tile — logged foods, or the day's plan when still open.
    func mealDisplayItems(date: String, meal: MealKey) -> [PlanItem] {
        switch mealState(date, meal) {
        case .logged: return mealLog(date).items(meal)
        case .skipped: return []
        case .unconfirmed: return planItems(Self.weekdayKey(date), meal)
        }
    }
    func tickMeal(date: String, meal: MealKey) {
        let planned = planItems(Self.weekdayKey(date), meal)
        mutateLog(date) { $0.tick(meal, planned: planned) }
    }
    func setMealItems(date: String, meal: MealKey, items: [PlanItem]) {
        mutateLog(date) { $0.setItems(meal, items) }
    }
    func skipMeal(date: String, meal: MealKey)   { mutateLog(date) { $0.skip(meal) } }
    func unskipMeal(date: String, meal: MealKey) { mutateLog(date) { $0.unskip(meal) } }

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
    /// Copy one weekday's meal plan onto other weekdays (overwrites them).
    func copyMealPlanDay(from: String, to weekdays: [String]) {
        let src = mealPlan(from)
        for wd in weekdays where wd != from {
            nutrition.mealPlan[wd] = src.mapValues { $0.map { PlanItem(foodId: $0.foodId, quantity: $0.quantity) } }
        }
        push(StateKey.nutrition, nutrition)
    }
    /// Empty the weekly meal grid. Library foods stay; today's log stays.
    func clearMealPlan() {
        guard !nutrition.mealPlan.isEmpty else { return }
        nutrition.mealPlan = [:]
        push(StateKey.nutrition, nutrition)
    }
    func clearPlanMeal(weekday: String, meal: MealKey) {
        nutrition.mealPlan[weekday]?[meal.rawValue] = []
        push(StateKey.nutrition, nutrition)
    }
    func deleteLogItem(id: String) {
        var log = nutrition.log
        for (date, var day) in log {
            for meal in MealKey.allCases {
                day.meals[meal.rawValue]?.removeAll { $0.id == id }
            }
            log[date] = day
        }
        nutrition.log = log
        push(StateKey.nutrition, nutrition)
    }
    func setPlanMeal(weekday: String, meal: MealKey, foods: [(foodId: String, quantity: Double)]) {
        nutrition.mealPlan[weekday, default: [:]][meal.rawValue] = foods.map { PlanItem(foodId: $0.foodId, quantity: $0.quantity) }
        push(StateKey.nutrition, nutrition)
    }
    /// Tick every still-unconfirmed meal from today's plan (the "log all" action).
    func applyMealPlanToToday() {
        for meal in MealKey.allCases where mealState(todayKey, meal) == .unconfirmed {
            tickMeal(date: todayKey, meal: meal)
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

    /// Read-only survivor of the pre-program model: still answers for a date on
    /// a save that has not been migrated yet. Nothing writes `weekPlan` any more
    /// — see `migrateTrainingIfNeeded()` and `AppState+Program.swift`.
    func workoutPlan(_ weekday: String) -> WorkoutDayPlan { training.weekPlan[weekday] ?? WorkoutDayPlan() }

    // Workout day log (tick / edit / skip). The weekly template is never mutated.
    func workoutDayLog(_ date: String) -> WorkoutDayLog { training.dayLog[date] ?? WorkoutDayLog() }
    func mutateDayLog(_ date: String, _ f: (inout WorkoutDayLog) -> Void) {
        var l = training.dayLog[date] ?? WorkoutDayLog()
        f(&l)
        training.dayLog[date] = l
        push(StateKey.training, training)
    }
    func tickWorkout(date: String, items: [PlanExercise]? = nil) { mutateDayLog(date) { $0.tick(items: items) } }
    func skipWorkout(date: String)   { mutateDayLog(date) { $0.skip() } }
    func unskipWorkout(date: String) { mutateDayLog(date) { $0.unskip() } }
    /// The exercises for a date, in falling order of truth: what you logged,
    /// then what the active program schedules, then the legacy weekday plan
    /// (which only still answers on a save that predates programs).
    func workoutItemsForDay(_ date: String) -> [PlanExercise] {
        let log = workoutDayLog(date)
        if let items = log.loggedItems, !items.isEmpty { return items }
        if let (_, day) = programDay(for: date) {
            return day.allItems.map { PlanExercise(exerciseId: $0.exerciseId, sets: $0.sets, reps: $0.reps) }
        }
        return workoutPlan(Self.weekdayKey(date)).items
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

    /// Ask the AI for a week. Does **not** write it — call `confirmGeneratedPlan`
    /// after the user confirms, so a stray tap cannot wipe a real plan.
    func generateWeeklyPlan() async -> GeneratedPlan? {
        planError = nil; planSummary = nil
        guard isHydrated, !planBusy else { return nil }
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
            return try await api.plan(req)
        } catch {
            planError = (error as? APIError)?.message ?? error.localizedDescription
            return nil
        }
    }

    func confirmGeneratedPlan(_ plan: GeneratedPlan) {
        applyGeneratedPlan(plan)
        planSummary = plan.summary
    }

    private func applyGeneratedPlan(_ plan: GeneratedPlan) {
        let exList = allExercises, foodList = allFoods

        // Workout — written as a weekday-bound program, grouped by muscle. The
        // AI returns a flat list per day; the blocks are derived here so the
        // generated week reads like a hand-built one.
        var newDays: [ProgramDay] = []
        for wd in 0..<7 {
            let src = plan.workout.first { max(0, min(6, $0.weekday)) == wd }
            let name = ProgramMigration.weekdayNames[wd]
            guard let src, !src.rest, !src.exercises.isEmpty else {
                newDays.append(ProgramDay(name: "Rest", weekday: wd, rest: true))
                continue
            }
            var blocks: [ProgramMuscleBlock] = []
            for e in src.exercises {
                guard let id = matchId(e.name, in: exList, id: { $0.id }, label: { $0.name }) else { continue }
                let g = group(ofExercise: id)
                let item = ProgramExercise(exerciseId: id, sets: max(1, e.sets), reps: max(1, e.reps))
                if let i = blocks.firstIndex(where: { $0.group == g }) { blocks[i].items.append(item) }
                else { blocks.append(ProgramMuscleBlock(group: g, items: [item])) }
            }
            newDays.append(blocks.isEmpty
                           ? ProgramDay(name: "Rest", weekday: wd, rest: true)
                           : ProgramDay(name: name, weekday: wd, blocks: blocks))
        }
        if newDays.contains(where: { !$0.isRestDay }) {
            if let activeId = training.activeProgramId,
               let i = training.programs.firstIndex(where: { $0.id == activeId }) {
                // Rewrite the active program's schedule; its name and history stay.
                training.programs[i].days = newDays
                push(StateKey.training, training)
            } else {
                createProgram(name: "AI week", notes: plan.summary.nilIfBlank,
                              goal: fitnessProfile.goal.label, days: newDays)
            }
        }

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
        // All six fields, not three. A day where you only wrote gratitude — or
        // only lessons, or only mistakes — drew no dot in the month grid, so it
        // read as never journalled and there was no way to find it again.
        return !(e.morning.isEmpty && e.night.isEmpty && e.wins.isEmpty
                 && e.mistakes.isEmpty && e.lessons.isEmpty && e.gratitude.isEmpty
                 && e.mood == nil)
    }
    func journalMood(_ date: String) -> Int? { journal[date]?.mood }

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
    func applyMentorActions(_ actions: [MentorAction]) {
        for a in actions {
            switch a.kind {
            case .createEvent, .createShoot:
                let title = a.fields["title"] ?? a.fields["name"] ?? "New event"
                let phrase = activeThread?.messages.last(where: { $0.role == "user" })?.content ?? ""
                let date = EventDate.resolve(raw: a.fields["date"], phrase: phrase, today: todayKey)
                addEvent(date: date, title: title, note: a.fields["note"] ?? "",
                         special: a.kind == .createShoot)
            case .createNote:
                let id = addBlockNote()
                updateNote(id, title: a.fields["title"] ?? "Note", body: a.fields["body"] ?? "")
            case .lockNote:
                let q = (a.fields["title"] ?? "").lowercased()
                if let n = notes.first(where: { q.isEmpty ? $0.locked == false : $0.title.lowercased().contains(q) }) {
                    if !n.locked { toggleLockNote(n.id) }
                }
            case .addFocus:
                guard let t = a.fields["text"] ?? a.fields["title"], !t.isEmpty else { break }
                addTodo(t)
            case .logFood:
                let name = a.fields["name"] ?? a.fields["title"] ?? "Food"
                let food = addFood(Food(name: name, category: .other,
                                        servingLabel: a.fields["serving"] ?? "1 serving",
                                        perServing: Macros(calories: Double(a.fields["calories"] ?? "0") ?? 0,
                                                           protein: Double(a.fields["protein"] ?? "0") ?? 0,
                                                           carbs: Double(a.fields["carbs"] ?? "0") ?? 0,
                                                           fats: Double(a.fields["fats"] ?? "0") ?? 0)))
                addFoodToMeal(date: todayKey, meal: .snacks, foodId: food.id)
            }
        }
    }

    func requestNewNote() { pendingNewNote = true }

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
        // The same guard `updateNoteContent` carries, and for a sharper reason:
        // this is the entry point iOS saves through, from `onDisappear`. See
        // `Note.wouldChange(title:body:)`.
        guard notes[i].wouldChange(title: title, body: body) else { return }
        notes[i].title = title
        notes[i].body = body
        notes[i].content = BlockDoc.merging(plainText: body,
                                            keepingAttachmentsOf: notes[i].content)
        notes[i].updatedAt = Self.nowStamp()
        push(StateKey.notes, notes)
    }
    /// Save rich block content, keeping `body` as the plain-text mirror.
    /// Save a note's title and body — and do nothing at all if neither moved.
    ///
    /// The guard is the whole point. `NotesView.persistCurrent()` runs every
    /// time you open a note, leave the editor, or switch away from the tab, and
    /// without it every one of those *looking* at a note rewrote its
    /// `updatedAt`. The list is sorted by `updatedAt` and grouped into Today /
    /// Previous 7 Days sections, so merely clicking a note shot it to the top
    /// and out of its date section — under the cursor, mid-click. That is what
    /// "notes come and go randomly on click" was.
    ///
    /// It also stops a network push per click, and per keystroke for a note
    /// whose text has not actually changed.
    func updateNoteContent(_ id: String, title: String, doc: BlockDoc) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        guard notes[i].wouldChange(title: title, doc: doc) else { return }
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

    private func saveDay(_ d: DayPlan, on key: String) {
        days[key] = d
        push(StateKey.days, days)
    }

    /// The day whose plan actually holds `id`.
    ///
    /// Every one of these used to read `todayPlan()` and write straight back to
    /// `days[todayKey]`, with `todayKey` re-read from the clock on each call. A
    /// focus block begun at 23:50 and finished at 00:15 therefore looked for its
    /// to-do in a day that had just turned over and did not contain it — so
    /// `firstIndex` failed, the function returned silently, and because
    /// `drainSpent()` had already zeroed the counter the twenty-five minutes
    /// were gone. Completing that block did nothing either: the task stayed
    /// unticked. Work is banked against the day that owns it.
    private func dayKeyOwning(todo id: String) -> String? {
        FocusRecord.dayOwning(todo: id, in: days, today: todayKey)
    }

    /// Edit the to-do `id` wherever it lives. No-op when nothing owns it.
    private func mutateTodo(_ id: String, _ transform: (inout FocusItem) -> Void) {
        guard let key = dayKeyOwning(todo: id) else { return }
        var d = days[key] ?? DayPlan()
        guard let i = d.todos.firstIndex(where: { $0.id == id }) else { return }
        transform(&d.todos[i])
        saveDay(d, on: key)
    }

    /// Add a to-do to `date` — the day being looked at, which is not always today.
    ///
    /// It was hardcoded to `todayKey` while the card listing the items read the
    /// day it was showing, so typing a to-do under any other date put it on
    /// today's list: the field cleared, no row appeared, and the item was
    /// somewhere the user wasn't looking. Planning tomorrow — the obvious use of
    /// the forward swipe — did not work at all.
    func addTodo(_ text: String, on date: String? = nil) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        let key = date ?? todayKey
        var d = days[key] ?? DayPlan()
        d.todos.append(FocusItem(text: t))
        saveDay(d, on: key)
    }

    func toggleTodo(_ id: String) {
        mutateTodo(id) { $0.done.toggle() }
    }

    func removeTodo(_ id: String) {
        guard let key = dayKeyOwning(todo: id) else { return }
        var d = days[key] ?? DayPlan()
        d.todos.removeAll { $0.id == id }
        saveDay(d, on: key)
    }

    func setFocus(_ items: [String]) {
        let key = todayKey
        var d = days[key] ?? DayPlan()
        d.todos = items
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { FocusItem(text: $0) }
        saveDay(d, on: key)
    }
    func toggleHabit(_ name: String) {
        var d = days[todayKey] ?? DayPlan()
        d.habits[name] = !(d.habits[name] ?? false)
        days[todayKey] = d
        push(StateKey.days, days)
    }
    func habitsDoneToday() -> Int { todayPlan().habits.values.filter { $0 }.count }

    /// Any day's plan — the focus calendar reads history through this.
    func plan(for key: String) -> DayPlan { days[key] ?? DayPlan() }

    /// Mark done (not a toggle) — what the focus timer calls when a block ends.
    func completeTodo(_ id: String) {
        mutateTodo(id) { if !$0.done { $0.done = true } }
    }

    /// Planned focus length for one to-do, in minutes.
    func setTodoMinutes(_ id: String, _ mins: Int) {
        mutateTodo(id) { $0.mins = max(1, mins) }
    }

    /// Bank the seconds a focus session actually ran.
    ///
    /// `drainSpent()` has already zeroed the timer's counter by the time this is
    /// called, so anything this fails to record is lost rather than retried.
    func addTodoSpent(_ id: String, seconds: Int) {
        guard seconds > 0 else { return }
        mutateTodo(id) { $0.spent += seconds }
    }

    /// Consecutive clean days counting back from today (rules in `FocusRecord`).
    func focusStreak() -> Int { FocusRecord.streak(days: days) }

    /// Confirm the owner's passphrase without unlocking anything. PBKDF2 runs
    /// 600k rounds, so it goes off the main thread or the UI visibly stalls.
    func verifyPassphrase(_ passphrase: String) async -> Bool {
        guard !passphrase.isEmpty else { return false }
        let v = vault
        return await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                cont.resume(returning: v.verify(passphrase: passphrase))
            }
        }
    }

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
    /// Extra sends that arrived while a reply was still streaming.
    private var chatQueue: [String] = []
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
        var who = "PROFILE: \(p.name.isEmpty ? "(no name set)" : p.name)"
        if let a = p.age { who += ", age \(a)" }
        if !p.city.isEmpty { who += ", \(p.city)" }
        if !p.role.isEmpty { who += ". Role: \(p.role)" }
        if !p.work.isEmpty { who += " — \(p.work)" }
        l.append(who + ".")
        if !p.hometown.isEmpty { l.append("HOMETOWN: \(p.hometown).") }
        let about = p.about.trimmingCharacters(in: .whitespacesAndNewlines)
        if !about.isEmpty { l.append("ABOUT (their own words): \(about)") }

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
        l.append("JOURNAL: " + (e.mood.map { "mood today \($0)/5" } ?? "no entry today yet") + ".")
        l.append("STEPS: \(steps(on: todayKey).formatted()) today, goal \(stepGoals.daily.formatted()), \(stepStreak)-day streak.")
        if !e.wins.isEmpty { l.append("TODAY WINS: \(e.wins.joined(separator: "; ")).") }
        if !e.mistakes.isEmpty { l.append("TODAY MISTAKES: \(e.mistakes.joined(separator: "; ")).") }

        let pretty = {
            let f = DateFormatter()
            f.calendar = Calendar(identifier: .gregorian)
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "EEEE d MMMM yyyy"
            return f.string(from: Date())
        }()
        l.insert("TODAY IS \(pretty) (\(todayKey)). Current year is \(todayKey.prefix(4)). Never emit a date in a past year. date= must be YYYY-MM-DD on or after \(todayKey). For “next Wednesday” use the next Wednesday after today, not a Wednesday from 2024.", at: 0)

        l.append("""
        ACTIONS YOU CAN TAKE (append after your spoken reply, only if they asked):
        ACTION create_event title="…" date="YYYY-MM-DD"
        ACTION create_shoot title="…"
        ACTION create_note title="…" body="…"
        ACTION lock_note title="…"
        ACTION add_focus text="…"
        ACTION log_food name="…" calories="0" protein="0" carbs="0" fats="0"
        """)
        return l.joined(separator: "\n")
    }

    /// Send a message to the mentor. Optimistically appends the user turn, then the
    /// reply. History persists to `myos.chat`.
    /// The active conversation (falls back to the newest thread).
    var activeThread: ChatThread? {
        if let id = chat.activeID, let t = chat.threads.first(where: { $0.id == id }) { return t }
        return chat.threads.first
    }

    /// Start a fresh conversation and make it active.
    func newChat() {
        let t = ChatThread(id: newId(), title: "New chat",
                           createdAt: Self.nowStamp(), updatedAt: Self.nowStamp())
        chat.threads.insert(t, at: 0)
        chat.activeID = t.id
        chatError = nil
        chatQueue = []
        if isHydrated { push(StateKey.chat, chat) }
    }

    func selectChat(_ id: String) {
        chat.activeID = id
        chatError = nil
        if isHydrated { push(StateKey.chat, chat) }
    }

    func deleteChat(_ id: String) {
        chat.threads.removeAll { $0.id == id }
        if chat.activeID == id { chat.activeID = chat.threads.first?.id }
        if isHydrated { push(StateKey.chat, chat) }
    }

    /// Ensure there's an active thread to write into; returns its index.
    private func activeThreadIndex() -> Int {
        if let id = chat.activeID, let i = chat.threads.firstIndex(where: { $0.id == id }) { return i }
        let t = ChatThread(id: newId(), title: "New chat",
                           createdAt: Self.nowStamp(), updatedAt: Self.nowStamp())
        chat.threads.insert(t, at: 0)
        chat.activeID = t.id
        return 0
    }

    /// Send a message to the mentor in the active thread. Optimistically appends the
    /// user turn, then the reply. History persists to `myos.chat`.
    func sendChat(_ text: String) async {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        if chatBusy { chatQueue.append(t); return }
        chatError = nil
        Haptics.tap()
        let i = activeThreadIndex()
        let already = chat.threads[i].messages.last?.role == "user"
            && chat.threads[i].messages.last?.content == t
        if !already {
            chat.threads[i].messages.append(ChatMessage(role: "user", content: t, at: Self.nowStamp()))
        }
        chat.threads[i].updatedAt = Self.nowStamp()
        if chat.threads[i].title == "New chat" { chat.threads[i].title = String(t.prefix(40)) }
        let threadID = chat.threads[i].id
        let assistant = ChatMessage(role: "assistant", content: "", at: Self.nowStamp())
        let assistantID = assistant.id
        chat.threads[i].messages.append(assistant)
        if isHydrated { push(StateKey.chat, chat) }
        chatBusy = true
        let turns = chat.threads[i].messages
            .filter { $0.id != assistantID && !$0.content.isEmpty }
            .suffix(24)
            .map { APIClient.ChatTurn(role: $0.role, content: $0.content) }
        let a = AgentConfig.shared
        let agent = APIClient.AgentInfo(name: a.displayName, tone: a.tone.directive,
                                        custom: a.custom.trimmingCharacters(in: .whitespacesAndNewlines))

        func writeReply(_ text: String) {
            guard let j = chat.threads.firstIndex(where: { $0.id == threadID }),
                  let k = chat.threads[j].messages.firstIndex(where: { $0.id == assistantID }) else { return }
            chat.threads[j].messages[k].content = text
            chat.threads[j].updatedAt = Self.nowStamp()
        }

        do {
            // The bounded retrieve → tool → answer loop. See Support/AI/AgentLoop.swift.
            let outcome = try await runCatrineTurn(query: t, turns: turns, agent: agent)
            lastTrace = outcome.trace

            // `ACTION` lines were how she acted before real tools existed. Still
            // parsed so a model that emits one is honoured rather than leaking
            // the markup into the chat — but tools are the path now.
            let parsed = ChatAction.parse(outcome.reply)
            writeReply(parsed.visible)
            applyMentorActions(parsed.actions)
            Haptics.success()
            if isHydrated { push(StateKey.chat, chat) }

            // Learn from it afterwards, genuinely off the critical path. This
            // used to be awaited here, inside the busy window: the reply was on
            // screen but `chatBusy` stayed true for a whole extra AI round trip
            // — up to the 90-second request timeout — with the send button dead,
            // a red dot on the launcher, no spinner to explain it, and
            // `applyRemote` refusing every remote chat update the entire time.
            let assistantText = parsed.visible
            Task { [weak self] in await self?.learnFromExchange(user: t, assistant: assistantText) }
        } catch {
            chatError = (error as? APIError)?.message ?? error.localizedDescription
            if let j = chat.threads.firstIndex(where: { $0.id == threadID }),
               let k = chat.threads[j].messages.firstIndex(where: { $0.id == assistantID }),
               chat.threads[j].messages[k].content.isEmpty {
                chat.threads[j].messages.remove(at: k)
            }
            if isHydrated { push(StateKey.chat, chat) }
        }
        chatBusy = false
        if let next = chatQueue.first {
            chatQueue.removeFirst()
            await sendChat(next)
        }
    }

    /// Re-send the last user turn after a 502 / network miss.
    func retryLastChat() async {
        chatError = nil
        guard let last = activeThread?.messages.last(where: { $0.role == "user" }) else { return }
        await sendChat(last.content)
    }

    func sendFoldOTP(_ phone: String) async {
        foldBusy = true; foldError = nil
        defer { foldBusy = false }
        do { try await FoldClient.sendOTP(phone: phone) }
        catch { foldError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
    }

    func verifyFoldOTP(_ phone: String, otp: String) async -> Bool {
        foldBusy = true; foldError = nil
        do {
            try await FoldClient.verifyOTP(phone: phone, otp: otp)
            FoldTrace.writeLog()          // keep the verify exchange in the trace
            foldLinked = FoldClient.isLinked
        } catch {
            foldError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            if case FoldError.notLinked = error { foldLinked = false }
            foldBusy = false
            return false
        }
        do {
            let snap = try await FoldClient.fetchSnapshot()
            fold = snap
            FoldData.save(snap)
            if isHydrated { push(StateKey.fold, snap) }
            foldBusy = false
            return true
        } catch {
            foldError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            foldBusy = false
            return true
        }
    }

    func disconnectFold() {
        FoldClient.unlink()
        foldLinked = false
    }

    /// Live Fold pull when signed in. A failed live call must not re-read the
    /// Aug-14 disk/sync snapshot and pretend it just refreshed.
    func refreshFold() async {
        restoreFoldIfBare()
        foldBusy = true
        foldError = nil
        foldLinked = FoldClient.isLinked
        var liveSucceeded = false
        if FoldClient.isLinked {
            do {
                let snap = try await FoldClient.fetchSnapshot()
                fold = snap
                FoldData.save(snap)
                if isHydrated { push(StateKey.fold, snap) }
                liveSucceeded = true
            } catch {
                foldError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                if case FoldError.notLinked = error { foldLinked = false }
            }
        }
        let localBare = fold == nil || FoldSnapshotBuilder.isBare(fold!)
        if FoldRefresh.shouldPullSync(linked: foldLinked, liveSucceeded: liveSucceeded, localBare: localBare) {
            ingestLocalFold()
            await pullRemote()
            ingestLocalFold()
        }
        restoreFoldIfBare()
        foldBusy = false
        if fold == nil && foldError == nil {
            foldError = "Connect Fold with your phone OTP to pull live numbers."
        }
    }

    /// Delete the active conversation (the header trash button).
    func clearChat() {
        if let id = chat.activeID { deleteChat(id) }
        else { chat = ChatState(); if isHydrated { push(StateKey.chat, chat) } }
    }

    // MARK: - Appearance

    /// Switch the app-wide colour theme. Persists the choice and forces a re-render —
    /// every screen observes AppState, so bumping this recolours the whole app.
    /// How the app looks — primary colour, card style, mono. Synced, because a
    /// personal operating system that looks different on each device is two
    /// apps rather than one.
    func setAppearance(_ next: AppearanceSettings) {
        withAnimation(.knTheme) {
            AppearanceStore.shared.apply(next)
            themeVersion &+= 1
        }
        push(StateKey.appearance, next)
    }

    func setTheme(_ t: AppTheme) {
        withAnimation(.knTheme) {
            ThemeStore.shared.set(t)
            themeVersion &+= 1
        }
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

    // MARK: - Events (a memory log — past, present, or future)

    /// The next couple of things coming up — for the Today spine. Date-based, not "done".
    var nextEvents: [EventItem] {
        let today = todayKey
        return Array(events.filter { $0.date >= today }.sorted { $0.date < $1.date }.prefix(2))
    }

    func addEvent(date: String, title: String, tagIDs: [String] = [], note: String = "",
                  special: Bool = false, media: [EventMedia] = []) {
        let t = title.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, !date.isEmpty else { return }
        let tags = tagIDs.isEmpty ? [EventVoice.tagID(forTitle: t)] : tagIDs
        events.append(EventItem(date: date, title: t, tagIDs: tags, note: note, media: media, special: special))
        push(StateKey.events, events)
    }
    func updateEvent(_ e: EventItem) {
        guard let i = events.firstIndex(where: { $0.id == e.id }) else { return }
        var ev = e; ev.title = ev.title.trimmingCharacters(in: .whitespaces)
        events[i] = ev
        push(StateKey.events, events)
    }
    func deleteEvent(_ id: String) {
        // Take the sealed objects with it. Scans have done this since they were
        // built (`AppState+TaskScan.dropPhotos`); events never did, so deleting
        // a memory dropped the only references to its photos and video and left
        // them in the bucket with nothing left that could name them. On a stack
        // required to stay inside a free tier, that grows forever.
        let orphans = events.filter { $0.id == id }
            .flatMap(\.media)
            .flatMap { [$0.r2Key, $0.posterKey] }
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        events.removeAll { $0.id == id }
        // (`resetEverything` does the same sweep over every event.)
        push(StateKey.events, events)
        guard !orphans.isEmpty else { return }
        Task { [api] in
            for key in orphans { try? await api.deleteEventMedia(id: key) }
        }
    }
    /// Whole days from today to a date (negative = past). Timezone-stable.
    func daysUntil(_ dateKey: String) -> Int? {
        guard let d = Self.date(fromKey: dateKey), let today = Self.date(fromKey: todayKey) else { return nil }
        return Calendar(identifier: .gregorian).dateComponents([.day], from: today, to: d).day
    }

    // MARK: - Event tags (custom: name + SF Symbol + colour)

    /// Resolve an event's tag ids to tags, in order.
    func tags(for e: EventItem) -> [EventTag] {
        e.tagIDs.compactMap { id in eventTags.first { $0.id == id } }
    }
    /// The first resolvable tag — drives an event's badge colour / glyph.
    func primaryTag(for e: EventItem) -> EventTag? { tags(for: e).first }

    func addTag(name: String, symbol: String, colorHex: String) {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        eventTags.append(EventTag(name: n, symbol: symbol, colorHex: colorHex))
        push(StateKey.eventTags, eventTags)
    }
    func updateTag(_ tag: EventTag) {
        guard let i = eventTags.firstIndex(where: { $0.id == tag.id }) else { return }
        var t = tag; t.name = t.name.trimmingCharacters(in: .whitespaces)
        eventTags[i] = t
        push(StateKey.eventTags, eventTags)
    }
    /// Delete a custom tag (built-ins are protected) and scrub it from every event.
    func deleteTag(_ id: String) {
        guard let t = eventTags.first(where: { $0.id == id }), !t.builtIn else { return }
        eventTags.removeAll { $0.id == id }
        for i in events.indices { events[i].tagIDs.removeAll { $0 == id } }
        push(StateKey.eventTags, eventTags)
        push(StateKey.events, events)
    }

    // MARK: - Productivity / watch log

    var sortedWatch: [WatchItem] { watch.sorted { $0.addedAt > $1.addedAt } }

    /// Take everything the iOS share extension queued and log it.
    ///
    /// The extension only has the link — it can't reach the vault key or the
    /// API session (see `ShareInbox`) — so the enrichment that `WatchLogCard`
    /// does after a paste happens here instead: title, channel, thumbnail, then
    /// the category. The item is saved before any of that so a dead network
    /// still leaves the video in the log.
    func drainShareInbox() async {
        // Only clear an item once it is actually in the list. See `ShareInbox.drain`.
        var taken: [String] = []
        defer { ShareInbox.confirm(taken) }
        for shared in ShareInbox.drain() {
            guard !watch.contains(where: { $0.videoId == shared.videoId }) else {
                taken.append(shared.videoId)
                continue
            }
            taken.append(shared.videoId)
            let item = addWatchItem(WatchItem(url: shared.url, videoId: shared.videoId,
                                              thumbUrl: YouTube.thumbURL(shared.videoId)))
            // Merged into the live row, like the other two enrichment paths —
            // writing back a snapshot taken before these awaits reverted
            // anything the user did to the card while the lookup ran.
            let meta = await YouTube.fetchMeta(id: shared.videoId)
            enrichWatchItem(id: item.id, title: meta.title, channel: meta.channel,
                            thumbUrl: meta.thumbUrl.isEmpty ? nil : meta.thumbUrl)
            if let cat = await categorizeVideo(title: meta.title, channel: meta.channel) {
                enrichWatchItem(id: item.id, category: cat)
            }
        }
    }

    @discardableResult
    /// `on` is the day the card is showing. The stamp used to always be now, so
    /// a video added while looking at any other day was filed under today — the
    /// counter did not move, no row appeared, and it was on a list the user was
    /// not looking at.
    func addWatchItem(_ item: WatchItem, on date: String? = nil) -> WatchItem {
        var it = item
        if it.addedAt.isEmpty {
            let now = Self.nowStamp()
            it.addedAt = (date == nil || date == todayKey) ? now : (date! + String(now.dropFirst(10)))
        }
        watch.insert(it, at: 0)
        push(StateKey.watch, watch)
        return it
    }
    /// Replace a watch item wholesale. Prefer `enrichWatchItem` from anything
    /// that has been away at an `await`.
    func updateWatchItem(_ item: WatchItem) {
        guard let i = watch.firstIndex(where: { $0.id == item.id }) else { return }
        watch[i] = item
        push(StateKey.watch, watch)
    }

    /// Fold fetched metadata into whatever the record says *now*.
    ///
    /// The YouTube title/channel/category lookup takes seconds, and it used to
    /// write back a whole-record snapshot captured before those awaits — so
    /// ticking "watched" or typing a takeaway on the new card in that window was
    /// reverted the moment the fetch returned. Only the fetched fields are
    /// touched here, and they are applied to the live row.
    func enrichWatchItem(id: String, title: String? = nil, channel: String? = nil,
                         thumbUrl: String? = nil, category: WatchCategory? = nil) {
        guard let i = watch.firstIndex(where: { $0.id == id }) else { return }
        if let title, !title.isEmpty { watch[i].title = title }
        if let channel, !channel.isEmpty { watch[i].channel = channel }
        if let thumbUrl, !thumbUrl.isEmpty { watch[i].thumbUrl = thumbUrl }
        if let category { watch[i].category = category }
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
    // MARK: - Belongings (stuff you own)

    func addBelonging(_ item: BelongingItem) {
        belongings.items.insert(item, at: 0)
        push(StateKey.belongings, belongings)
    }
    func updateBelonging(_ item: BelongingItem) {
        guard let i = belongings.items.firstIndex(where: { $0.id == item.id }) else { return }
        belongings.items[i] = item
        push(StateKey.belongings, belongings)
    }
    func deleteBelonging(_ id: String) {
        belongings.items.removeAll { $0.id == id }
        push(StateKey.belongings, belongings)
    }
    func setSalaryPaise(_ v: Int) {
        belongings.salaryPaise = max(0, v)
        push(StateKey.belongings, belongings)
    }

    func belongingCategories() -> [BelongingCategory] {
        let built = BelongingKind.allCases.map(\.asCategory)
        let extra = belongings.categories.filter { c in !built.contains(where: { $0.id == c.id }) }
        return built + extra
    }

    func belongingCategory(for item: BelongingItem) -> BelongingCategory {
        let id = item.categoryID.isEmpty ? item.kind.rawValue : item.categoryID
        return belongingCategories().first { $0.id == id } ?? item.kind.asCategory
    }

    func addBelongingCategory(_ cat: BelongingCategory) {
        let name = cat.name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        var next = cat
        next.name = name
        if BelongingKind(rawValue: next.id) != nil { next.id = UUID().uuidString.lowercased() }
        belongings.categories.removeAll { $0.id == next.id }
        belongings.categories.append(next)
        push(StateKey.belongings, belongings)
    }

    func deleteBelongingCategory(_ id: String) {
        guard BelongingKind(rawValue: id) == nil else { return }
        belongings.categories.removeAll { $0.id == id }
        for i in belongings.items.indices where belongings.items[i].categoryID == id {
            belongings.items[i].categoryID = BelongingKind.other.rawValue
            belongings.items[i].kind = .other
        }
        push(StateKey.belongings, belongings)
    }

    /// Read a product photo into a short title / shelf / India price.
    /// Production still treats unknown modes as food — ignore those apologies
    /// and identify via scan instead.
    func identifyBelonging(photoBase64: String, categoryIDs: [String]) async -> BelongingGuess? {
        let list = categoryIDs.joined(separator: ", ")
        if let r = try? await api.parseImage(imagesBase64: [photoBase64], mediaType: "image/jpeg",
                                             mode: "belonging", context: list),
           let g = BelongingGuess.from(result: r, allowed: categoryIDs) {
            return g
        }
        let scanCtx = """
        THIS IS NOT FOOD. Do not mention food. Do not write a sentence.
        Identify the consumer product in the photo.
        object.name = short product title only (e.g. "CMF Buds", "Nike Vomero 18"). Never "unknown".
        object.useful = category=<id> price_inr=<rupees> life_months=<n>
        category id must be one of: \(list)
        price_inr = typical India MRP as a whole number.
        """
        guard let r = try? await api.parseImage(imagesBase64: [photoBase64], mediaType: "image/jpeg",
                                                mode: "scan", context: scanCtx) else { return nil }
        return BelongingGuess.from(result: r, allowed: categoryIDs)
    }

    /// Best-effort AI category for a video (free model). Returns nil on any failure.
    func categorizeVideo(title: String, channel: String) async -> WatchCategory? {
        guard let cat = try? await api.categorize(title: title, channel: channel) else { return nil }
        return WatchCategory(rawValue: cat)
    }

    // MARK: - Data management (reset)  — all guarded behind hold-to-confirm in the UI

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
        journal = [:];                 push(StateKey.journal, journal)
        notes = [];                    push(StateKey.notes, notes)
        fitness = [:];                 push(StateKey.fitness, fitness)
        fitnessProfile = FitnessProfile(); push(StateKey.fitnessProfile, fitnessProfile)
        nutrition = NutritionState();  push(StateKey.nutrition, nutrition)
        training = TrainingState();    push(StateKey.training, training)
        days = [:];                    push(StateKey.days, days)
        events = [];                   push(StateKey.events, events)
        watch = [];                    push(StateKey.watch, watch)
        belongings = BelongingsState(); push(StateKey.belongings, belongings)
        clearScans()
        weekly = [];                   push(StateKey.weekly, weekly)
        // These were all surviving a button that says "All data". Chat and
        // memory are the two with no other bulk-clear anywhere in the app, so
        // there was no way to remove them at all; activity is the Mac's whole
        // time-tracking history; and the body photos are files on disk that the
        // state blob never touches. Meanwhile events, watch, belongings, scans
        // and weekly were being destroyed without ever being mentioned. The
        // confirmation copy now names the lot — see DangerConfirm.
        chat = ChatState();            push(StateKey.chat, chat)
        memory = MemoryState();        push(StateKey.memory, memory)
        eraseActivity()

        // Take the sealed event media with it, exactly as `deleteEvent` does.
        // Clearing `events` alone left every photo and video in the bucket with
        // nothing able to name them again — the same leak, reachable from the
        // one button that promises to remove everything.
        let orphans = eventMediaKeys
        if !orphans.isEmpty {
            Task { [api] in
                for key in orphans { try? await api.deleteEventMedia(id: key) }
            }
        }

        // Tombstone every photo FIRST, on this actor, then delete sequentially.
        // A task per photo raced: `markDeleted` is a read-modify-write over one
        // UserDefaults array from a nonisolated context, so with hundreds of
        // imported favourites several tasks wrote back the same stale array and
        // tombstones for photos whose cloud delete had failed simply vanished —
        // nothing retried them, and the next pull downloaded them again.
        let photoIDs = ProgressPhotoStore.list().map(\.id)
        for id in photoIDs {
            ProgressPhotoStore.markDeleted(id)
            ProgressPhotoStore.delete(id)
        }
        if !photoIDs.isEmpty {
            Task { await ProgressPhotoSync.flushDeletes() }
        }
    }

    /// Every sealed R2 object the events currently reference.
    private var eventMediaKeys: [String] {
        events.flatMap(\.media)
            .flatMap { [$0.r2Key, $0.posterKey] }
            .compactMap { $0 }
            .filter { !$0.isEmpty }
    }
}

// MARK: - Voice

extension AppState {
    /// The active thread's history, in the shape `runCatrineTurn` wants.
    ///
    /// Voice and text share one thread on purpose — a spoken question and a
    /// typed follow-up are the same conversation, and she should remember both.
    func voiceTurns() -> [APIClient.ChatTurn] {
        guard let id = chat.activeID,
              let i = chat.threads.firstIndex(where: { $0.id == id }) else { return [] }
        return chat.threads[i].messages
            .filter { !$0.content.isEmpty }
            .suffix(24)
            .map { APIClient.ChatTurn(role: $0.role, content: $0.content) }
    }

    /// Record a spoken turn in the active thread so the call survives in history.
    func appendVoiceTurn(role: String, content: String) {
        guard !content.isEmpty else { return }
        let i = activeThreadIndex()
        if chat.threads[i].title == "New chat", role == "user" {
            chat.threads[i].title = String(content.prefix(40))
        }
        chat.threads[i].messages.append(ChatMessage(role: role, content: content, at: Self.nowStamp()))
        chat.threads[i].updatedAt = Self.nowStamp()
        if isHydrated { push(StateKey.chat, chat) }
    }
}
