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

    init() {
        api.vault = vault
        EventMediaStore.shared.configure(api: api, vault: vault)
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
        guard let raw = api.cachedRawState() else { return }
        vault.adoptMeta(api.cryptoMeta(from: raw))
        guard vault.hasMeta,
              vault.unlockFromKeychain(username: username),
              let payload = try? api.decodePayload(fromRaw: raw) else { return }
        apply(payload)
        isHydrated = true
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
        belongings = s.belongings ?? BelongingsState()
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
            else { lastHydrateError = (error as? APIError)?.message ?? "Couldn't load your data." }
        }
    }

    func logout() async {
        DietBridge.shared.stop()
        stopLiveSync()
        stopFoldWatch()
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
        events = []; watch = []; belongings = BelongingsState(); memory = MemoryState()
        scans = []; taskMode = TaskModeState()
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
            (StateKey.fitness, fitness), (StateKey.fitnessProfile, fitnessProfile),
            (StateKey.journal, journal), (StateKey.journalPresets, journalPresets),
            (StateKey.notes, notes), (StateKey.days, days), (StateKey.profile, profile),
            (StateKey.chat, chat), (StateKey.nutrition, nutrition), (StateKey.training, training),
            (StateKey.events, events), (StateKey.eventTags, eventTags),
            (StateKey.watch, watch), (StateKey.belongings, belongings),
            (StateKey.memory, memory), (StateKey.scans, scans),
            (StateKey.taskMode, taskMode)
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
        add("profile", profile)
        add("fitness", fitness); add("fitnessProfile", fitnessProfile)
        add("journal", journal); add("journalPresets", journalPresets)
        add("notes", notes); add("days", days); add("chat", chat)
        add("nutrition", nutrition); add("training", training)
        add("events", events); add("eventTags", eventTags)
        add("watch", watch)
        add("memory", memory)
        add("belongings", belongings)
        add("scans", scans); add("taskMode", taskMode)
        return try? JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys])
    }

    // MARK: - Instant push + live pull (Mac ↔ iPhone)

    /// Writes land on the server almost immediately so the other device can
    /// pick them up on the next 2s poll. Rapid keystrokes still collapse into
    /// one PUT via a short debounce.
    /// Ignore a stale GET that still has the pre-write snapshot (Netlify KV
    /// can serve the previous value for a couple of seconds after PUT).
    private var lastLocalWrite: [String: Date] = [:]

    // Internal, not private: the AI layer extends this type from Support/AI/*.
    func push(_ key: String, _ value: Encodable) {
        guard isHydrated else {
            lastSyncError = "Not synced yet — refresh before saving."
            return
        }
        lastLocalWrite[key] = Date()
        pushGen[key, default: 0] += 1
        let gen = pushGen[key] ?? 1
        pushTasks[key]?.cancel()
        pushTasks[key] = Task { [api] in
            try? await Task.sleep(nanoseconds: 80_000_000)
            if Task.isCancelled { return }
            do {
                try await api.putState(key, value)
                await MainActor.run {
                    if self.pushGen[key] == gen { self.pushTasks[key] = nil }
                    self.lastSyncError = nil
                }
            } catch is CancellationError {
                return
            } catch let e as URLError where e.code == .cancelled {
                return
            } catch {
                let msg = (error as? APIError)?.message ?? error.localizedDescription
                await MainActor.run {
                    if self.pushGen[key] == gen { self.pushTasks[key] = nil }
                    self.lastSyncError = "Couldn't save \(key): \(msg)"
                }
            }
        }
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
            applyRemote(payload)
            lastHydrateError = nil
        } catch {
            // Stay quiet — the next tick retries. Surface only a hard hydrate miss.
        }
    }

    /// Apply a remote snapshot without stomping an in-flight local edit.
    private func applyRemote(_ s: AppStatePayload) {
        if let v = s.fitness,        !hasPendingPush(StateKey.fitness),        v != fitness        { fitness = v }
        if let v = s.fitnessProfile, !hasPendingPush(StateKey.fitnessProfile), v != fitnessProfile { fitnessProfile = v }
        if let v = s.journal,        !hasPendingPush(StateKey.journal),        v != journal        { journal = v }
        if let v = s.journalPresets, !hasPendingPush(StateKey.journalPresets), v != journalPresets { journalPresets = v }
        if let v = s.notes,          !hasPendingPush(StateKey.notes),          v != notes          { notes = v }
        if let v = s.days,           !hasPendingPush(StateKey.days),           v != days           { days = v }
        if let v = s.profile,        !hasPendingPush(StateKey.profile),        v != profile        { profile = v }
        // Never clobber an in-flight send — a 2s pull of the previous snapshot
        // was landing replies on the wrong turn.
        if let v = s.chat,           !hasPendingPush(StateKey.chat), !chatBusy, v != chat          { chat = v }
        if let v = s.nutrition,      !hasPendingPush(StateKey.nutrition),      v != nutrition,
           !wroteRecently(StateKey.nutrition) { nutrition = v }
        if let v = s.training,       !hasPendingPush(StateKey.training),       v != training       { training = v }
        if let v = s.events,         !hasPendingPush(StateKey.events),         v != events         { events = v }
        if let v = s.eventTags,      !hasPendingPush(StateKey.eventTags),      v != eventTags      { eventTags = v }
        if let v = s.watch,          !hasPendingPush(StateKey.watch),          v != watch          { watch = v }
        if let v = s.memory,         !hasPendingPush(StateKey.memory),         v != memory         { memory = v }
        if let v = s.belongings,     !hasPendingPush(StateKey.belongings),     v != belongings     { belongings = v }
        if let v = s.scans,          !hasPendingPush(StateKey.scans),          v != scans          { scans = v }
        // The mode is the one switch meant to reach across devices — a flip on
        // the Mac lands here on the phone within one poll.
        if let v = s.taskMode,       !hasPendingPush(StateKey.taskMode),       v != taskMode       { taskMode = v }
        if let v = s.fold, !hasPendingPush(StateKey.fold), v != fold {
            if FoldSnapshotBuilder.isBare(v) {
                restoreFoldIfBare()
                if let cur = fold, !FoldSnapshotBuilder.isBare(cur) { push(StateKey.fold, cur) }
            } else {
                fold = v
                FoldData.save(v)
            }
        }
        if eventTags.isEmpty { eventTags = EventTag.seedDefaults }
    }

    /// How often to ask the server "changed?". Each tick is a conditional GET
    /// that costs a few hundred bytes unless something actually changed, so this
    /// is about request count, not bytes: at 2s two devices made ~86k requests a
    /// day, which overruns a Workers free-tier daily budget on its own.
    static let livePollInterval: UInt64 = 15_000_000_000   // 15s

    /// Move any still-inline event photos/videos into R2, sealed. Runs once per
    /// launch after unlock. Each asset is uploaded before the blob is rewritten,
    /// so an interruption leaves un-migrated items rather than dangling keys.
    func migrateEventMediaToR2() async {
        guard isHydrated, let dek = vault.dek else { return }
        guard events.contains(where: { $0.media.contains(where: \.needsMigration) }) else { return }

        var next = events
        var moved = 0
        for i in next.indices {
            for j in next[i].media.indices where next[i].media[j].needsMigration {
                do {
                    if let m = try await EventMediaStore.migrate(next[i].media[j], api: api, dek: dek) {
                        next[i].media[j] = m
                        moved += 1
                    }
                } catch {
                    return   // network or vault trouble — keep what we have, retry next launch
                }
            }
        }
        guard moved > 0 else { return }
        events = next
        push(StateKey.events, events)
    }

    func startLiveSync() {
        DietBridge.shared.start(state: self)
        liveSyncTask?.cancel()
        liveSyncTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.livePollInterval)
                guard !Task.isCancelled else { return }
                await self?.pullRemote()
                // Cheap guard when there's nothing inline, so newly added media
                // moves to R2 within one tick without extra wiring.
                await self?.migrateEventMediaToR2()
                // A media fetch that failed once (locked vault at launch, a
                // network blip) would otherwise stay a grey placeholder until
                // relaunch. Retrying on the tick makes it self-healing; the
                // call returns immediately when nothing has failed.
                await MainActor.run { EventMediaStore.shared.retryFailures() }
            }
        }
        startFoldWatch()
    }

    func stopLiveSync() {
        liveSyncTask?.cancel()
        liveSyncTask = nil
        stopFoldWatch()
    }

    /// Pick up a new `fold.json` the moment it lands on disk and push so the phone
    /// gets it on the next 2s pull. Live Fold login is the source of truth.
    func ingestLocalFold() {
        guard let disk = FoldData.loadFromDisk(), disk != fold else { return }
        if FoldSnapshotBuilder.isBare(disk) {
            restoreFoldIfBare()
            return
        }
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
        let next = FoldSnapshotBuilder.resolved(
            current: fold, disk: FoldData.loadFromDisk(), recovery: FoldData.recoverySnapshot()
        )
        guard next != fold else { return }
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
        src.setEventHandler { [weak self] in self?.ingestLocalFold() }
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

    /// Set (or clear) the step count for any day. The Mac has no pedometer, so
    /// a day you want to correct after the fact is typed in against its key.
    func setSteps(_ steps: Int?, on date: String) {
        updateFitness(date) { $0.steps = steps.map { max(0, $0) } }
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
            let write = key == authoritative ? existing != n : (existing ?? 0) == 0
            guard write else { continue }
            var d = fitness[key] ?? FitnessDay()
            d.steps = max(0, n)
            fitness[key] = d
            changed = true
        }
        guard changed else { return }
        push(StateKey.fitness, fitness)
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

    func workoutPlan(_ weekday: String) -> WorkoutDayPlan { training.weekPlan[weekday] ?? WorkoutDayPlan() }
    private func mutatePlan(_ weekday: String, _ f: (inout WorkoutDayPlan) -> Void) {
        var p = training.weekPlan[weekday] ?? WorkoutDayPlan()
        f(&p)
        training.weekPlan[weekday] = p
        push(StateKey.training, training)
    }
    func setRestDay(_ weekday: String, _ rest: Bool) {
        mutatePlan(weekday) {
            $0.rest = rest
            // Rest means no work — keep the list empty so Plan never shows
            // "Rest day" above a stack of exercises.
            if rest { $0.items = [] }
        }
    }
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

    // Workout day log (tick / edit / skip). The weekly template is never mutated.
    func workoutDayLog(_ date: String) -> WorkoutDayLog { training.dayLog[date] ?? WorkoutDayLog() }
    private func mutateDayLog(_ date: String, _ f: (inout WorkoutDayLog) -> Void) {
        var l = training.dayLog[date] ?? WorkoutDayLog()
        f(&l)
        training.dayLog[date] = l
        push(StateKey.training, training)
    }
    func tickWorkout(date: String, items: [PlanExercise]? = nil) { mutateDayLog(date) { $0.tick(items: items) } }
    func skipWorkout(date: String)   { mutateDayLog(date) { $0.skip() } }
    func unskipWorkout(date: String) { mutateDayLog(date) { $0.unskip() } }
    /// The exercises for a date: the edited actual if present, else the weekday plan.
    func workoutItemsForDay(_ date: String) -> [PlanExercise] {
        if let items = workoutDayLog(date).items { return items }
        return workoutPlan(Self.weekdayKey(date)).items
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

    private func saveDay(_ d: DayPlan) {
        days[todayKey] = d
        push(StateKey.days, days)
    }

    func addTodo(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        var d = todayPlan()
        d.todos.append(FocusItem(text: t))
        saveDay(d)
    }

    func toggleTodo(_ id: String) {
        var d = todayPlan()
        guard let i = d.todos.firstIndex(where: { $0.id == id }) else { return }
        d.todos[i].done.toggle()
        saveDay(d)
    }

    func removeTodo(_ id: String) {
        var d = todayPlan()
        d.todos.removeAll { $0.id == id }
        saveDay(d)
    }

    func setFocus(_ items: [String]) {
        var d = todayPlan()
        d.todos = items
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { FocusItem(text: $0) }
        saveDay(d)
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
        var d = todayPlan()
        guard let i = d.todos.firstIndex(where: { $0.id == id }), !d.todos[i].done else { return }
        d.todos[i].done = true
        saveDay(d)
    }

    /// Planned focus length for one to-do, in minutes.
    func setTodoMinutes(_ id: String, _ mins: Int) {
        var d = todayPlan()
        guard let i = d.todos.firstIndex(where: { $0.id == id }) else { return }
        d.todos[i].mins = max(1, mins)
        saveDay(d)
    }

    /// Bank the seconds a focus session actually ran.
    func addTodoSpent(_ id: String, seconds: Int) {
        guard seconds > 0 else { return }
        var d = todayPlan()
        guard let i = d.todos.firstIndex(where: { $0.id == id }) else { return }
        d.todos[i].spent += seconds
        saveDay(d)
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
        l.append("JOURNAL: \(journalStreak)-day streak" + (e.mood.map { ", mood today \($0)/5" } ?? ", no entry today yet") + ".")
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

            // Learn from it afterwards, off the critical path — the reply is
            // already on screen and a failure here must never surface.
            await learnFromExchange(user: t, assistant: parsed.visible)
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
        events.removeAll { $0.id == id }
        push(StateKey.events, events)
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
        for shared in ShareInbox.drain() {
            guard !watch.contains(where: { $0.videoId == shared.videoId }) else { continue }
            var item = addWatchItem(WatchItem(url: shared.url, videoId: shared.videoId,
                                              thumbUrl: YouTube.thumbURL(shared.videoId)))
            let meta = await YouTube.fetchMeta(id: shared.videoId)
            item.title = meta.title
            item.channel = meta.channel
            if !meta.thumbUrl.isEmpty { item.thumbUrl = meta.thumbUrl }
            updateWatchItem(item)
            if let cat = await categorizeVideo(title: meta.title, channel: meta.channel) {
                item.category = cat
                updateWatchItem(item)
            }
        }
    }

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
