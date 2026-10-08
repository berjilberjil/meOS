import Foundation

/// Talks to the headless SvelteKit backend (apps/api). Auth is the server's
/// httpOnly cookie session (`meos_session`) — URLSession's shared cookie storage
/// persists and re-sends it automatically, so there's no token to manage.
struct APIError: LocalizedError {
    let status: Int
    let message: String
    var errorDescription: String? { message }
}

final class APIClient {
    /// Default is the deployed production backend — the app always talks to the
    /// cloud, even in local testing. Default is the Cloudflare Worker
    /// (Workers + D1 + R2). Override at runtime with the `meos.baseURL`
    /// UserDefaults key — e.g. http://localhost:5173 for local backend work, or
    /// the old Netlify host to roll back without a rebuild.
    static var baseURL: URL {
        if let s = UserDefaults.standard.string(forKey: "meos.baseURL")
            ?? UserDefaults.standard.string(forKey: "myos.baseURL"),
           let u = URL(string: s) { return u }
        return URL(string: "https://meos-api.berjiljacob.workers.dev")!
    }

    /// Join a relative API path onto `baseURL`. `appendingPathComponent` treats
    /// the whole string as one path component, so it escapes a `?` to `%3F` —
    /// which sent `api/event-media?ids=…` to a path that does not exist. The 404
    /// blacklisted the media, and every event photo that had moved to R2 stayed a
    /// grey box on any device that had not uploaded it itself. The query is split
    /// off and set as a query, so a path still gets escaped and a query does not.
    static func url(for path: String) -> URL {
        let parts = path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let base = baseURL.appendingPathComponent(String(parts[0]))
        guard parts.count > 1, !parts[1].isEmpty,
              var c = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return base }
        // Callers percent-encode their own values; encoding again would turn a
        // `%20` into `%2520`.
        c.percentEncodedQuery = String(parts[1])
        return c.url ?? base
    }

    private let session: URLSession
    /// AI calls (parse / vision / advice) can take longer than a state read —
    /// Gemini vision on a screenshot, or the weekly reasoning model. Give them room.
    private let aiSession: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    /// The zero-knowledge vault. When set and unlocked, `putState`/state reads
    /// transparently encrypt and decrypt each `meos.*` value on this device — the
    /// server only ever stores ciphertext. Set by `AppState` after construction.
    var vault: Vault?

    init() {
        let cfg = URLSessionConfiguration.default
        cfg.httpCookieStorage = .shared
        cfg.httpCookieAcceptPolicy = .always
        cfg.httpShouldSetCookies = true
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.waitsForConnectivity = false
        cfg.timeoutIntervalForRequest = 15
        cfg.timeoutIntervalForResource = 30
        session = URLSession(configuration: cfg)

        let ai = cfg.copy() as! URLSessionConfiguration
        ai.timeoutIntervalForRequest = 90
        ai.timeoutIntervalForResource = 120
        aiSession = URLSession(configuration: ai)
    }

    // MARK: - Core

    @discardableResult
    private func request(_ method: String, _ path: String, body: Encodable? = nil,
                         using session: URLSession? = nil) async throws -> Data {
        var req = URLRequest(url: Self.url(for: path))
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try encoder.encode(AnyEncodable(body))
        }
        let (data, response) = try await (session ?? self.session).data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw APIError(status: -1, message: "No response from server")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError(status: http.statusCode, message: Self.errorText(from: data, status: http.statusCode))
        }
        return data
    }

    private func get<T: Decodable>(_ path: String, as: T.Type) async throws -> T {
        try decoder.decode(T.self, from: try await request("GET", path))
    }

    /// Like `request`, but sends an already-serialized JSON body verbatim. Used for
    /// uploading encrypted envelopes and the plaintext crypto meta.
    @discardableResult
    private func requestData(_ method: String, _ path: String, bodyData: Data?,
                             using session: URLSession? = nil) async throws -> Data {
        var req = URLRequest(url: Self.url(for: path))
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let bodyData {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = bodyData
        }
        let (data, response) = try await (session ?? self.session).data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw APIError(status: -1, message: "No response from server")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError(status: http.statusCode, message: Self.errorText(from: data, status: http.statusCode))
        }
        return data
    }

    // MARK: - Auth

    @discardableResult
    func login(username: String, password: String) async throws -> AuthUser {
        let data = try await request("POST", "api/auth/login", body: ["username": username, "password": password])
        return try decoder.decode(AuthUser.self, from: data)
    }

    @discardableResult
    func register(username: String, password: String) async throws -> AuthUser {
        let data = try await request("POST", "api/auth/register", body: ["username": username, "password": password])
        return try decoder.decode(AuthUser.self, from: data)
    }

    func me() async throws -> AuthUser { try await get("api/me", as: AuthUser.self) }

    func logout() async { _ = try? await request("POST", "api/auth/logout") }

    /// Change the login password. Server checks `current`; the vault passphrase is untouched.
    func changePassword(current: String, next: String) async throws {
        _ = try await request("POST", "api/auth/password", body: ["current": current, "next": next])
    }

    // MARK: - State (zero-knowledge)

    /// Error thrown when encrypted data is present but the vault isn't unlocked —
    /// callers must gate on the vault so we never decode ciphertext into empty
    /// models (which would then get pushed back, wiping real data).
    struct VaultLockedError: Error {}

    /// Fetch the raw `{key: value}` map from the server, cache it (encrypted) for
    /// instant relaunch, and return it parsed. Values are a mix of encrypted
    /// envelopes and plaintext (crypto meta, ai.routes, or legacy pre-encryption).
    func fetchStateRaw() async throws -> [String: Any] {
        let data = try await request("GET", "api/state")
        let map = try Self.stateMap(from: data)
        Self.writeCache(data, "state.json")
        return map
    }

    /// Parse a state body into its key map, or throw.
    ///
    /// `as? [String: Any] ?? [:]` was the most destructive line in the app.
    /// A 200 whose body is not a JSON object — a Cloudflare error page, a
    /// captive-portal interstitial, a truncated response — parsed to an
    /// EMPTY map, which `decodePayload` turned into an all-nil payload,
    /// which `apply` turned into every module reset to its default. The
    /// whole app emptied on screen, `isHydrated` was set true regardless,
    /// and the next local edit pushed the emptied module up as fact.
    ///
    /// That is the "everything disappeared, then came back" report: it came
    /// back on the next fetch that happened to return real JSON, and stayed
    /// gone whenever a push landed inside that window.
    ///
    /// An unreadable body is a FAILED fetch, not an empty account. Throwing
    /// routes it to the offline path, which keeps what is already on screen.
    /// The cache is written only after this passes, so a bad body can never
    /// become the copy we relaunch from either.
    private static func stateMap(from data: Data) throws -> [String: Any] {
        guard let obj = try? JSONSerialization.jsonObject(with: data),
              let map = obj as? [String: Any] else {
            throw APIError(status: -1, message: "Server sent something that isn't your data.")
        }
        return map
    }

    /// Last `ETag` seen for `GET api/state`.
    private var stateETag: String?
    /// The ETag of the last 200, waiting on the caller to say it was applied.
    private var pendingStateETag: String?

    /// The live-sync read. Sends `If-None-Match` and returns **nil** when the
    /// server answers `304 Not Modified`, so an unchanged poll costs a few
    /// hundred bytes instead of the whole state. The poll runs every few seconds
    /// on every device, so re-downloading megabytes to be told "nothing changed"
    /// is what put the project over its egress quota.
    func fetchStateIfChanged() async throws -> [String: Any]? {
        var req = URLRequest(url: Self.url(for: "api/state"))
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let stateETag { req.setValue(stateETag, forHTTPHeaderField: "If-None-Match") }

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw APIError(status: -1, message: "No response from server")
        }
        if http.statusCode == 304 { return nil }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError(status: http.statusCode,
                           message: Self.errorText(from: data, status: http.statusCode))
        }
        // Held, not committed. Only the caller knows whether the payload was
        // actually applied, and storing it here meant a snapshot `applyRemote`
        // deliberately deferred — or one `decodePayload` threw on — was answered
        // 304 forever after and never offered again. See `AppState.applyRemote`.
        // Parsed BEFORE the ETag is held or the cache is written. An
        // unreadable body must not be remembered as "the version I have"
        // — that would answer 304 forever after and leave the real state
        // permanently unfetched. See `stateMap`.
        let map = try Self.stateMap(from: data)
        pendingStateETag = http.value(forHTTPHeaderField: "ETag")
        Self.writeCache(data, "state.json")
        return map
    }

    /// Accept the last fetch's ETag. Call only once its payload is fully applied.
    func commitStateETag() {
        guard let pendingStateETag else { return }
        stateETag = pendingStateETag
        self.pendingStateETag = nil
    }

    /// Pull the plaintext crypto metadata out of a raw state map, if the account
    /// has a vault set up. Reads the pre-rename key as a fallback.
    func cryptoMeta(from raw: [String: Any]) -> CryptoMeta? {
        guard let obj = (raw[Vault.metaKey] ?? raw[Vault.legacyMetaKey]) else { return nil }
        guard let d = try? JSONSerialization.data(withJSONObject: obj),
              let meta = try? decoder.decode(CryptoMeta.self, from: d) else { return nil }
        return meta
    }

    /// Decrypt every envelope in a raw state map (using the unlocked vault) and
    /// decode the result into the typed payload. Plaintext values pass through, so
    /// pre-encryption data still loads during migration.
    func decodePayload(fromRaw raw: [String: Any]) throws -> AppStatePayload {
        var plain: [String: Any] = [:]
        for (k, v) in raw {
            // Pre-rename builds wrote `myos.*`; this build reads `meos.*`.
            // Decrypt with the ORIGINAL key (ciphertext is bound to it as AAD)
            // and file the plaintext under the new name when nothing newer is
            // already there. The server-side move to the new spelling happens
            // in `migrateLegacyStateKeys`; this keeps reads working meanwhile.
            var storeKey = k
            if k.hasPrefix("myos."),
               let migrated = StateKey.migratedKey(k), raw[migrated] == nil {
                storeKey = migrated
            }
            if let vault, vault.isEnvelope(v) {
                guard vault.isUnlocked else { throw VaultLockedError() }
                let ptData = try vault.openValue(v as! [String: Any], key: k)
                plain[storeKey] = try JSONSerialization.jsonObject(with: ptData, options: [.fragmentsAllowed])
            } else if let vault, vault.hasMeta, vault.shouldEncrypt(k) {
                // A key that is supposed to be sealed arriving in the clear is
                // not data, it is a downgrade. The passthrough exists for the
                // one-time migration off plaintext, but it was unconditional and
                // permanent — so anything that could write to this account, or
                // to a `meos.baseURL` override, could replace an envelope with
                // JSON of its own and have the app trust it and re-seal it.
                // Dropped rather than trusted; the module keeps its local value.
                continue
            } else {
                plain[storeKey] = v
            }
        }
        do {
            let rebuilt = try JSONSerialization.data(withJSONObject: plain)
            return try decoder.decode(AppStatePayload.self, from: rebuilt)
        } catch {
            // One module in a shape this build cannot read must not take the
            // whole app away. `decodeIfPresent` throws on a type mismatch, not
            // only on absence, so a single key written by a newer build left
            // every unlock failing here — the correct passphrase, every launch,
            // with nothing on screen but "Log out". Drop the offenders and carry
            // on with the rest.
            return try decodeSkippingBadKeys(plain)
        }
    }

    /// Decode each key on its own, discarding the ones that will not parse.
    private func decodeSkippingBadKeys(_ plain: [String: Any]) throws -> AppStatePayload {
        var good: [String: Any] = [:]
        for (k, v) in plain {
            let probe = try? JSONSerialization.data(withJSONObject: [k: v])
            if let probe, (try? decoder.decode(AppStatePayload.self, from: probe)) != nil {
                good[k] = v
            }
        }
        let rebuilt = try JSONSerialization.data(withJSONObject: good)
        return try decoder.decode(AppStatePayload.self, from: rebuilt)
    }

    /// Decode a cached raw-state blob from disk (same decrypt path as the network).
    func decodeCachedPayload() -> AppStatePayload? {
        guard let d = try? Data(contentsOf: Self.cacheDir.appendingPathComponent("state.json")),
              let raw = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let payload = try? decodePayload(fromRaw: raw) else { return nil }
        return payload
    }

    /// The raw cached map (used to recover the crypto meta on relaunch before unlock).
    func cachedRawState() -> [String: Any]? {
        guard let d = try? Data(contentsOf: Self.cacheDir.appendingPathComponent("state.json")) else { return nil }
        return try? JSONSerialization.jsonObject(with: d) as? [String: Any]
    }

    /// Upsert one meos.* key. Encrypts the value on this device first, unless the
    /// key is in the plaintext set (crypto meta / ai routes) or the vault is absent.
    func putState(_ key: String, _ value: Encodable) async throws {
        let plaintext = try encoder.encode(AnyEncodable(value))
        if let vault, vault.shouldEncrypt(key) {
            guard vault.isUnlocked else { throw VaultLockedError() }
            let envelope = try vault.sealValue(plaintext, key: key)
            _ = try await requestData("PUT", "api/state/\(key)", bodyData: envelope)
        } else {
            _ = try await requestData("PUT", "api/state/\(key)", bodyData: plaintext)
        }
    }

    /// Upload the plaintext crypto metadata (`meos.crypto`).
    func putCryptoMeta(_ meta: CryptoMeta) async throws {
        let data = try encoder.encode(meta)
        _ = try await requestData("PUT", "api/state/\(Vault.metaKey)", bodyData: data)
    }

    /// Delete one state key from the server (used to purge removed modules and
    /// to drop legacy keys after migration).
    func deleteState(_ key: String) async throws {
        _ = try await request("DELETE", "api/state/\(key)")
    }

    /// One-time rename of synced state keys `myos.*` → `meos.*`.
    ///
    /// Ciphertext is bound to the exact key string (the key is the AES-GCM
    /// AAD), so a stored envelope is decrypted with the LEGACY key and
    /// re-sealed under the new one — byte-exact through the vault, never a
    /// blind copy. Plaintext keys move verbatim. The legacy key is deleted
    /// only after its replacement lands; a failed PUT retries next launch.
    /// Requires the vault unlocked (envelopes cannot open otherwise).
    func migrateLegacyStateKeys(_ raw: [String: Any]) async {
        guard let vault, vault.isUnlocked else { return }
        var pairs = StateKey.allNewKeys.compactMap { newKey -> (String, String)? in
            guard let legacy = StateKey.legacyKey(for: newKey),
                  raw[legacy] != nil, raw[newKey] == nil else { return nil }
            return (newKey, legacy)
        }
        pairs.append((Vault.metaKey, Vault.legacyMetaKey))
        pairs.append(("meos.ai.routes", "myos.ai.routes"))
        for (newKey, legacyKey) in pairs {
            guard let oldValue = raw[legacyKey], raw[newKey] == nil else { continue }
            do {
                if vault.isEnvelope(oldValue) {
                    let ptData = try vault.openValue(oldValue as! [String: Any], key: legacyKey)
                    let envelope = try vault.sealValue(ptData, key: newKey)
                    _ = try await requestData("PUT", "api/state/\(newKey)", bodyData: envelope)
                } else {
                    let body = try JSONSerialization.data(withJSONObject: oldValue, options: [.fragmentsAllowed])
                    _ = try await requestData("PUT", "api/state/\(newKey)", bodyData: body)
                }
                try? await deleteState(legacyKey)
            } catch {
                // Leave both spellings in place; the next launch retries.
                continue
            }
        }
    }

    // MARK: - AI

    func parse(text: String) async throws -> ParseResult {
        let data = try await request("POST", "api/parse", body: ["text": text], using: aiSession)
        return try decoder.decode(ParseResult.self, from: data)
    }

    /// Read one or more photos. mode: "food" (library) or "scan" (food vs object).
    func parseImage(imagesBase64: [String], mediaType: String, mode: String, context: String = "") async throws -> ImageParseResult {
        let body = ImageRequest(images: imagesBase64, mediaType: mediaType, mode: mode, context: context)
        let data = try await request("POST", "api/parse-image", body: body, using: aiSession)
        return try decoder.decode(ImageParseResult.self, from: data)
    }

    struct WeeklyReportDTO: Codable {
        let verdict: String
        let percent: Double
        let headline: String
        let read: String
        let workouts: [String]
        let diet: [String]
        let cheer: String
        let needsPhotos: Bool
    }

    /// The Friday progress report — the same vision route Scan uses, a different
    /// mode. Images are last week's first, then this week's; `context` says how
    /// many of each and carries the logged numbers.
    func weeklyReport(imagesBase64: [String], context: String) async throws -> WeeklyReportDTO {
        let body = ImageRequest(images: imagesBase64, mediaType: "image/jpeg",
                                mode: "weekly", context: context)
        let data = try await request("POST", "api/parse-image", body: body, using: aiSession)
        return try decoder.decode(WeeklyReportDTO.self, from: data)
    }

    /// One dated macro snapshot. `refresh` forces the server past its cache.
    func macro(date: String, refresh: Bool = false) async throws -> MacroSnapshot {
        var path = "api/macro?date=\(date)"
        if refresh { path += "&refresh=1" }
        // The grounded lookup and the brief are two model calls; this is slow on
        // a cold day and instant on a cached one.
        let data = try await request("GET", path, using: aiSession)
        return try decoder.decode(MacroSnapshot.self, from: data)
    }

    struct EventCategoryDTO: Codable { let tagId: String; let reason: String }

    /// Classify a spoken/typed event into a built-in tag.
    func categorizeEvent(title: String, date: String) async throws -> EventCategoryDTO {
        let data = try await request("POST", "api/categorize-event",
                                     body: ["title": title, "date": date], using: aiSession)
        return try decoder.decode(EventCategoryDTO.self, from: data)
    }

    /// Mentor chat. Sends the conversation + a data snapshot + who the assistant
    /// should be (name / tone / custom style); returns the reply.
    /// One turn of the chat. `tools` are declared per request so the client and
    /// the server can never disagree about what exists — see the note in
    /// `api/chat/+server.ts`. A non-empty `toolCalls` in the answer means the
    /// model wants a lookup before it commits to a reply.
    ///
    /// Hand-rolled JSON here rather than `Encodable`: tool parameter schemas are
    /// arbitrary nested JSON, which `Codable` cannot express without a wrapper
    /// type per tool.
    func chat(messages: [ChatTurn], context: String, agent: AgentInfo,
              tools: [[String: Any]] = []) async throws -> ChatAnswer {
        var payload: [String: Any] = [
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "context": context,
            "agent": ["name": agent.name, "tone": agent.tone, "custom": agent.custom]
        ]
        if !tools.isEmpty { payload["tools"] = tools }
        let body = try JSONSerialization.data(withJSONObject: payload)
        let data = try await requestData("POST", "api/chat", bodyData: body, using: aiSession)

        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ChatAnswer(reply: ChatText.unwrap(String(data: data, encoding: .utf8) ?? ""),
                              toolCalls: [], model: "")
        }
        let calls = (obj["toolCalls"] as? [[String: Any]] ?? []).compactMap { raw -> ToolCall? in
            guard let name = raw["name"] as? String, !name.isEmpty else { return nil }
            return ToolCall(id: raw["id"] as? String ?? name,
                            name: name,
                            args: raw["args"] as? [String: Any] ?? [:])
        }
        return ChatAnswer(reply: ChatText.unwrap(obj["reply"] as? String ?? ""),
                          toolCalls: calls,
                          model: obj["model"] as? String ?? "")
    }

    /// Today's "what to do now" mentor nudge from a data snapshot.
    func suggest(context: String) async throws -> SuggestResult {
        let data = try await request("POST", "api/suggest", body: ["context": context], using: aiSession)
        return try decoder.decode(SuggestResult.self, from: data)
    }

    /// Recent tech + finance news (Gemini search-grounded).
    func news() async throws -> NewsResult {
        let data = try await request("POST", "api/news", body: [String: String](), using: aiSession)
        return try decoder.decode(NewsResult.self, from: data)
    }

    /// Classify a YouTube video into a Productivity category (uses the free model).
    func categorize(title: String, channel: String) async throws -> String {
        struct R: Decodable { let category: String }
        let data = try await request("POST", "api/categorize",
                                     body: ["title": title, "channel": channel], using: aiSession)
        return try decoder.decode(R.self, from: data).category
    }

    /// Static anatomy body-map data (front/back SVG + muscle groups). Cached to disk.
    func anatomy() async throws -> AnatomyData {
        let data = try await request("GET", "api/anatomy")
        let value = try decoder.decode(AnatomyData.self, from: data)
        Self.writeCache(data, "anatomy.json")
        return value
    }
    func cachedAnatomy() -> AnatomyData? {
        guard let d = try? Data(contentsOf: Self.cacheDir.appendingPathComponent("anatomy.json")) else { return nil }
        return try? decoder.decode(AnatomyData.self, from: d)
    }

    // MARK: - Body photos (progress photo cloud sync)

    struct BodyPhotoDTO: Codable {
        let id: String
        let date: String
        let url: String?
        let updatedAt: String?
    }

    /// Every progress photo synced from any device, newest first.
    func listBodyPhotos() async throws -> [BodyPhotoDTO] {
        let data = try await request("GET", "api/body-photos")
        return try decoder.decode([BodyPhotoDTO].self, from: data)
    }

    /// Upload (or overwrite) one progress photo to the shared "media" bucket.
    func uploadBodyPhoto(id: String, date: String, jpeg: Data) async throws {
        let body = ["id": id, "date": date, "dataBase64": jpeg.base64EncodedString()]
        _ = try await request("POST", "api/body-photos", body: body, using: aiSession)
    }

    func deleteBodyPhoto(id: String) async throws {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        _ = try await request("DELETE", "api/body-photos/\(encoded)")
    }

    // MARK: - Event media (sealed, in R2)

    /// Upload one already-sealed event photo/video. The bytes are AES-GCM
    /// ciphertext produced on this device, so the server stores an opaque blob.
    func uploadEventMedia(id: String, sealed: Data) async throws {
        let body = ["id": id, "ciphertextBase64": sealed.base64EncodedString()]
        _ = try await request("POST", "api/event-media", body: body, using: aiSession)
    }

    /// Short-lived signed download URLs for a batch of media ids.
    func signEventMedia(ids: [String]) async throws -> [String: String] {
        guard !ids.isEmpty else { return [:] }
        let list = ids.joined(separator: ",")
        let encoded = list.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? list
        let data = try await request("GET", "api/event-media?ids=\(encoded)")
        return (try? decoder.decode([String: String].self, from: data)) ?? [:]
    }

    func deleteEventMedia(id: String) async throws {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        _ = try await request("DELETE", "api/event-media/\(encoded)")
    }

    /// Generate a weekly workout + meal plan from the goal, targets and library.
    func plan(_ req: PlanRequest) async throws -> GeneratedPlan {
        let data = try await request("POST", "api/plan", body: req, using: aiSession)
        return try decoder.decode(GeneratedPlan.self, from: data)
    }
    struct PlanRequest: Encodable {
        let goal: String
        let calories: Int
        let protein: Int
        let daysPerWeek: Int
        let foods: [String]
        let exercises: [String]
    }

    private struct ImageRequest: Encodable {
        let images: [String]
        let mediaType: String
        let mode: String
        let context: String
    }
    // MARK: - Voice

    /// Synthesise ONE sentence. Throws `APIError(status: 429)` when today's free
    /// allowance is spent — the caller treats that as "use the on-device voice",
    /// not as a failure.
    func speak(text: String, speaker: String) async throws -> Data {
        let body = try JSONSerialization.data(withJSONObject: ["text": text, "speaker": speaker])
        return try await requestData("POST", "api/voice/speak", bodyData: body, using: aiSession)
    }

    struct ChatTurn: Encodable { let role: String; let content: String }
    struct AgentInfo: Encodable { let name: String; let tone: String; let custom: String }

    /// One lookup the model asked for. `args` stays untyped because each tool
    /// declares its own schema — `runCatrineTool` is what gives it meaning.
    struct ToolCall: Equatable {
        let id: String
        let name: String
        let args: [String: Any]

        static func == (a: ToolCall, b: ToolCall) -> Bool { a.id == b.id && a.name == b.name }
    }

    struct ChatAnswer {
        var reply: String
        var toolCalls: [ToolCall]
        var model: String
    }

    /// Candidate long-term memories pulled out of one exchange. The server
    /// proposes; `MemoryBank.judge` disposes.
    struct MemoryCandidateDTO: Decodable {
        let content: String
        let category: String
        let importance: Int
        let confidence: Double
    }

    func extractMemories(user: String, assistant: String,
                         known: [String]) async throws -> [MemoryCandidateDTO] {
        struct Body: Encodable { let user: String; let assistant: String; let known: [String] }
        struct R: Decodable { let memories: [MemoryCandidateDTO] }
        let data = try await request("POST", "api/memory",
                                     body: Body(user: user, assistant: assistant, known: known),
                                     using: aiSession)
        return (try? decoder.decode(R.self, from: data).memories) ?? []
    }

    // MARK: - AI providers & models

    /// One saved provider key — masked; the raw secret never leaves the server.
    struct AIKeyDTO: Codable, Identifiable, Hashable {
        let id: Int
        let provider: String
        var label: String
        var masked: String
        var enabled: Bool
        var models: [String]
    }
    /// A routing choice: which saved key + which model name.
    struct AIRouteRef: Codable, Hashable { var keyId: Int; var model: String }
    /// Per-feature routing map. `defaultRoute` (JSON "default") covers anything not
    /// explicitly routed.
    struct AIRouting: Codable, Hashable {
        var defaultRoute: AIRouteRef?
        var features: [String: AIRouteRef]?
        enum CodingKeys: String, CodingKey {
            case defaultRoute = "default"
            case features
        }
        init(defaultRoute: AIRouteRef? = nil, features: [String: AIRouteRef]? = nil) {
            self.defaultRoute = defaultRoute; self.features = features
        }
    }

    func aiKeys() async throws -> [AIKeyDTO] {
        struct R: Decodable { let keys: [AIKeyDTO] }
        return try decoder.decode(R.self, from: try await request("GET", "api/ai/keys")).keys
    }

    /// Add a key. The server validates it live (which fetches its models) then stores
    /// it encrypted — so this can take a moment; it uses the longer AI timeout.
    func aiAddKey(provider: String, label: String, key: String) async throws -> AIKeyDTO {
        struct R: Decodable { let key: AIKeyDTO }
        let body = AddKeyRequest(provider: provider, label: label, key: key)
        return try decoder.decode(R.self, from: try await request("POST", "api/ai/keys", body: body, using: aiSession)).key
    }

    func aiUpdateKey(id: Int, label: String? = nil, enabled: Bool? = nil, key: String? = nil) async throws -> AIKeyDTO {
        struct R: Decodable { let key: AIKeyDTO }
        let body = PatchKeyRequest(label: label, enabled: enabled, key: key)
        let session = key != nil ? aiSession : nil
        return try decoder.decode(R.self, from: try await request("PATCH", "api/ai/keys/\(id)", body: body, using: session)).key
    }

    func aiDeleteKey(id: Int) async throws {
        _ = try await request("DELETE", "api/ai/keys/\(id)")
    }

    /// Re-validate a stored key and refresh its model list. Returns the fresh list.
    func aiCheckKey(id: Int) async throws -> [String] {
        struct R: Decodable { let models: [String] }
        return try decoder.decode(R.self, from: try await request("POST", "api/ai/keys/\(id)/check", using: aiSession)).models
    }

    func aiRoutes() async throws -> AIRouting {
        (try? decoder.decode(AIRouting.self, from: try await request("GET", "api/ai/routes"))) ?? AIRouting()
    }

    func aiPutRoutes(_ routing: AIRouting) async throws {
        _ = try await request("PUT", "api/ai/routes", body: routing)
    }

    private struct AddKeyRequest: Encodable { let provider: String; let label: String; let key: String }
    private struct PatchKeyRequest: Encodable { let label: String?; let enabled: Bool?; let key: String? }

    // MARK: - Instant-relaunch cache

    private static let cacheDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("MeOS", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static func writeCache(_ data: Data, _ name: String) {
        try? data.write(to: cacheDir.appendingPathComponent(name), options: .atomic)
    }

    func clearCache() {
        try? FileManager.default.removeItem(at: Self.cacheDir.appendingPathComponent("state.json"))
    }

    // MARK: - Helpers

    private static func errorText(from data: Data, status: Int) -> String {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let m = obj["message"] as? String { return m }
            if let e = obj["error"] as? [String: Any], let m = e["message"] as? String { return m }
        }
        return "Request failed (\(status))"
    }
}

/// Type-erasing wrapper so any `Encodable` can be encoded through a generic path.
struct AnyEncodable: Encodable {
    private let encodeFunc: (Encoder) throws -> Void
    init(_ wrapped: Encodable) { encodeFunc = wrapped.encode }
    func encode(to encoder: Encoder) throws { try encodeFunc(encoder) }
}
