import Foundation

/// Live Fold Money client — phone OTP, then whatever Fold will hand back for the
/// dashboard. Tokens stay on-device in `FoldSession` (sealed with the vault DEK,
/// because the ad-hoc-signed Mac app can't write the Keychain). Refresh reuses
/// the same session.
enum FoldClient {
    private static let base = URL(string: "https://api.fold.money/api")!
    /// Everything lives under `/api`. The host root 404s on every path — probed
    /// 16 Aug 2026, `GET /v1/users/me` → 404 at the root, 401 under `/api`.
    private static let roots = ["https://api.fold.money/api"]
    private static let kUser = "fold.user"
    private static let kPhone = "fold.phone"
    private static let kDevice = "fold.deviceHash"
    /// Fold only accepts phone/Android/iOS — `macOS` returns 422 invalid device type.
    static let deviceType = "Android"

    static var isLinked: Bool { FoldSession.load() != nil }
    static var linkedPhone: String { UserDefaults.standard.string(forKey: kPhone) ?? "" }

    static func unlink() {
        FoldSession.clear()
        UserDefaults.standard.removeObject(forKey: kUser)
    }

    static func sendOTP(phone raw: String) async throws {
        let phone = normalizePhone(raw)
        guard phone.count >= 10 else { throw FoldError.badPhone }
        _ = try await postJSON("/v1/auth/otp", auth: false, body: [
            "phone": phone, "channel": "sms"
        ])
        UserDefaults.standard.set(phone, forKey: kPhone)
    }

    static func verifyOTP(phone raw: String, otp: String) async throws {
        let phone = normalizePhone(raw)
        let body: [String: Any] = [
            "phone": phone, "otp": otp.trimmingCharacters(in: .whitespaces)
        ]
        let paths = ["/v1/auth/otp/verify", "/v1/auth/verify-otp", "/v2/auth/otp/verify"]
        var last: Error = FoldError.http(404, "no verify route")
        for root in roots {
            for path in paths {
                do {
                    let json = try await send(path, method: "POST", auth: false, body: body, root: root)
                    try storeSession(json, phone: phone)
                    return
                } catch FoldError.http(let code, _) where code == 404 || code == 405 {
                    last = FoldError.http(code, "\(root)\(path)")
                    continue
                } catch {
                    last = error
                    if case FoldError.http(let code, _) = error, (400...499).contains(code), code != 404 {
                        throw error
                    }
                }
            }
        }
        throw last
    }

    /// Read a token pair out of an OTP-verify or refresh response, keeping what the
    /// response didn't rotate.
    static func tokens(from json: [String: Any],
                       keeping previous: FoldSession.Tokens?) -> FoldSession.Tokens? {
        let data = json["data"] as? [String: Any] ?? json
        guard let access = string(data["access_token"]) else { return nil }
        let uid = string(data["user_id"])
            ?? string((data["user_meta"] as? [String: Any])?["uuid"])
            ?? previous?.userID
        return FoldSession.Tokens(access: access,
                                  refresh: string(data["refresh_token"]) ?? previous?.refresh,
                                  userID: uid,
                                  expiresAt: expiry(data["expires_at"] ?? data["expires_in"]))
    }

    /// `expires_at` arrives as epoch seconds, epoch milliseconds, or RFC3339.
    /// `expires_in` (rare) is a duration from now.
    static func expiry(_ any: Any?) -> Date? {
        if let n = number(any) {
            if n < 31_536_000 { return Date().addingTimeInterval(n) }   // < 1 year → duration
            return Date(timeIntervalSince1970: n > 9_999_999_999 ? n / 1000 : n)
        }
        guard let s = string(any) else { return nil }
        if let d = date(s) { return d }
        if let n = Double(s) { return expiry(n) }
        return nil
    }

    private static func storeSession(_ json: [String: Any], phone: String) throws {
        guard let next = tokens(from: json, keeping: nil) else { throw FoldError.badOTP }
        // A dropped token used to look like a clean login and then "not signed in"
        // on the very next call. Say so instead of pretending it worked.
        guard FoldSession.save(next) else { throw FoldError.sessionNotSaved }
        if let uid = next.userID { UserDefaults.standard.set(uid, forKey: kUser) }
        UserDefaults.standard.set(phone, forKey: kPhone)
    }

    /// Pull a fresh snapshot from Fold and map it into `FoldData`.
    static func fetchSnapshot() async throws -> FoldData {
        try requireSession()
        FoldTrace.reset()
        // Write the trace whatever happens — the pull that failed is the one worth
        // reading, and it used to be the one that never got logged.
        defer { FoldTrace.writeLog() }
        await renewSession()
        var blobs: [[String: Any]] = []
        var uid = UserDefaults.standard.string(forKey: kUser) ?? ""
        var rejected = false
        for path in ["/v2/users/me", "/v1/users/me"] {
            do {
                let me = try await getJSONFirst(path)
                blobs.append(me)
                if let id = userID(from: me) { uid = id }
                break
            } catch FoldError.notLinked {
                rejected = true                            // 401 even after renewing
            } catch {
                continue
            }
        }
        // Say "sign in again" rather than reporting an empty pull when the token
        // is simply no longer accepted.
        if rejected && blobs.isEmpty { throw FoldError.notLinked }
        if !uid.isEmpty { UserDefaults.standard.set(uid, forKey: kUser) }
        guard !uid.isEmpty else { throw FoldError.http(0, "Fold signed in but returned no user id.") }

        // The transaction list route is the one piece we can't locate right now —
        // `/v1/users/{id}/transactions` 404s while its own `/available_since`
        // child 401s. Left in place so spends light up the day it answers; until
        // then the spend tiles keep their last known values.
        var txns: [[String: Any]] = []
        if let page = try? await fetchTransactions(uid: uid) {
            blobs.append(page.blob)
            txns = page.txns
        }
        // Only routes Fold actually serves. Probed 16 Aug 2026 — unauthenticated
        // 401 means "exists, needs a token", plain-text `404 page not found` means
        // the path was never registered. These 401:
        //   /v1/users/me · /v2/users/me · /v1/users/{id}/bank_accounts
        //   /v1/users/{id}/transactions/available_since · /v1/users/{id}/settings
        // These 404, and used to make up most of this list (which is why a pull
        // came back empty even when the login worked):
        //   accounts · bank-accounts (hyphen) · insights · investments · holdings
        //   net-worth · net_worth · dashboard · portfolio · summary · balances
        // `bank_accounts` is identity only (uuid, masked number, fip name) — the
        // money is on `bank_accounts/balances`. Both are needed; the builder joins
        // them on the account id.
        let extra = [
            "/v1/users/\(uid)/bank_accounts",
            "/v1/users/\(uid)/bank_accounts/balances",
            "/v1/users/\(uid)/transactions/available_since"
        ]
        for path in extra {
            if let j = try? await getJSONFirst(path) { blobs.append(j) }
        }
        // Per-account detail, in case the balance only lives on the single-account
        // route. Bounded — this is a dashboard, not a crawler.
        for id in accountIDs(in: blobs).prefix(8) {
            if let j = try? await getJSONFirst("/v1/users/\(uid)/bank_accounts/\(id)") {
                blobs.append(j)
            }
        }

        let previous = FoldData.load()
        let result = FoldSnapshotBuilder.outcome(blobs: blobs, transactions: txns, previous: previous)
        // Reaching Fold isn't the same as getting numbers out of it. Without this
        // the old snapshot was re-saved and the caption claimed "Live Fold".
        guard result.extracted else { throw FoldError.emptyPull(FoldTrace.summary) }
        if FoldSnapshotBuilder.isBare(result.data) {
            throw FoldError.http(0, "Signed in, but Fold returned no balances. Last snapshot kept.")
        }
        return result.data
    }

    /// Fold's transaction list is cursor-paged. `after` is base64 of `{8 digits},{RFC3339}`.
    static func transactionAfterCursor(till: Date = Date()) -> String {
        let n = Int.random(in: 10_000_000...99_999_999)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        iso.timeZone = TimeZone(secondsFromGMT: 0)
        return Data("\(n),\(iso.string(from: till))".utf8).base64EncodedString()
    }

    static func endpointURL(_ path: String, query: [String: String] = [:], root: String? = nil) -> URL {
        let host = root ?? base.absoluteString
        let p = path.hasPrefix("/") ? path : "/" + path
        var comps = URLComponents(string: host + p)!
        if !query.isEmpty {
            comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        return comps.url!
    }

    // MARK: - HTTP

    private static func requireSession() throws {
        guard FoldSession.load() != nil else { throw FoldError.notLinked }
    }

    /// Fold's access token dies after ~15 minutes, so every pull renews first.
    /// The route is **v2** — `/v1/auth/tokens/refresh` and every other v1 spelling
    /// answers `404 page not found`, which is why a session went stale one pull
    /// after sign-in. Probed 16 Aug 2026: `{}` → 400 "body must not be empty",
    /// `{"token":…}` → 400, `{"refresh_token":…}` → 422 only on a fake value.
    /// Renewal never throws. Renewing a token that was still valid 401'd and killed
    /// the whole pull seconds after a good sign-in — so a failed renewal just means
    /// "carry on with what we have"; if the token really is dead the pull's own 401
    /// says so.
    private static func renewSession() async {
        guard let current = FoldSession.load(), current.needsRenewal() else { return }
        guard let refresh = current.refresh, !refresh.isEmpty else { return }
        // Fold rejected an unauthenticated refresh (401) even on a fresh token, so
        // send the Bearer token with it; fall back to bare in case it's the opposite.
        for authed in [true, false] {
            guard let json = try? await postJSON("/v2/auth/tokens/refresh", auth: authed,
                                                 body: ["refresh_token": refresh]),
                  let next = tokens(from: json, keeping: current)
            else { continue }
            FoldSession.save(next)
            return
        }
    }

    private static func fetchTransactions(uid: String) async throws -> (txns: [[String: Any]], blob: [String: Any]) {
        let cal = Calendar(identifier: .gregorian)
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: Date()))
            ?? Date().addingTimeInterval(-40 * 86_400)
        var all: [[String: Any]] = []
        var after = transactionAfterCursor(till: Date())
        var last: [String: Any] = [:]
        for _ in 0..<8 {
            let json = try await getJSONFirst("/v1/users/\(uid)/transactions", query: [
                "filter": "all", "count_by": "month", "after": after
            ])
            last = json
            let page = arrayOfDicts(json["data"] ?? json, key: "transactions")
            if page.isEmpty { break }
            all.append(contentsOf: page)
            if let oldest = page.last,
               let ts = date(oldest["txn_timestamp"]) ?? date(oldest["txn_date"]),
               ts < monthStart { break }
            let next = string((json["data"] as? [String: Any])?["after"]) ?? string(json["after"])
            guard let next, !next.isEmpty, next != after else { break }
            after = next
        }
        return (all, last)
    }

    private static func getJSON(_ path: String, query: [String: String] = [:]) async throws -> [String: Any] {
        try await send(path, method: "GET", auth: true, body: nil, query: query)
    }

    private static func getJSONFirst(_ path: String, query: [String: String] = [:]) async throws -> [String: Any] {
        var last: Error = FoldError.http(404, path)
        for root in roots {
            do { return try await send(path, method: "GET", auth: true, body: nil, query: query, root: root) }
            catch FoldError.http(let code, _) where code == 404 { last = FoldError.http(code, "\(root)\(path)"); continue }
            catch { last = error }
        }
        throw last
    }

    private static func postJSON(_ path: String, auth: Bool, body: [String: Any]) async throws -> [String: Any] {
        try await send(path, method: "POST", auth: auth, body: body)
    }

    private static func send(_ path: String, method: String, auth: Bool, body: [String: Any]?, query: [String: String] = [:], root: String? = nil) async throws -> [String: Any] {
        let url = endpointURL(path, query: query, root: root)
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("ua/unfold", forHTTPHeaderField: "User-Agent")
        req.setValue(deviceHash(), forHTTPHeaderField: "X-Device-Hash")
        req.setValue("India", forHTTPHeaderField: "X-Device-Location")
        req.setValue("unfold", forHTTPHeaderField: "X-Device-Name")
        req.setValue(Self.deviceType, forHTTPHeaderField: "X-Device-Type")
        if auth, let token = FoldSession.accessToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        FoldTrace.record(FoldTrace.line(method: method, path: path, code: code,
                                        bytes: data.count, keys: topLevelKeys(data)))
        if (200..<300).contains(code) { FoldTrace.recordShape(path: path, data: data) }
        if code == 401 { throw FoldError.notLinked }
        guard (200..<300).contains(code) else {
            throw FoldError.http(code, "\(path) · \(apiMessage(from: data, code: code))")
        }
        let obj = try JSONSerialization.jsonObject(with: data)
        return obj as? [String: Any] ?? ["data": obj]
    }

    private static func deviceHash() -> String {
        if let s = UserDefaults.standard.string(forKey: kDevice), !s.isEmpty { return s }
        let s = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        UserDefaults.standard.set(s, forKey: kDevice)
        return s
    }

    /// Fold's OTP route wants E.164 (`+91…`). Unfold sends `"+91" + 10 digits`.
    static func normalizePhone(_ raw: String) -> String {
        var d = raw.filter(\.isNumber)
        if d.hasPrefix("0") { d.removeFirst() }
        if d.count == 10 { d = "91" + d }
        if d.hasPrefix("91"), d.count >= 12 { return "+" + d }
        return d.isEmpty ? d : "+" + d
    }

    static func apiMessage(from data: Data, code: Int) -> String {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let err = obj["error"] as? [String: Any], let m = string(err["message"]), !m.isEmpty {
                return m
            }
            if let m = string(obj["message"]), !m.isEmpty { return m }
        }
        return String(data: data, encoding: .utf8).map { String($0.prefix(180)) } ?? "HTTP \(code)"
    }

    /// The uuids of the linked accounts, read out of the `bank_accounts` response.
    static func accountIDs(in blobs: [[String: Any]]) -> [String] {
        var out: [String] = []
        func walk(_ any: Any) {
            if let d = any as? [String: Any] {
                // Only entries that are clearly a linked account — `fip` and a
                // masked number are what tell an account apart from a plan or a user.
                if d["fip"] != nil || d["masked_account_number"] != nil,
                   let id = string(d["uuid"]) ?? string(d["account_id"]), !out.contains(id) {
                    out.append(id)
                }
                d.values.forEach(walk)
            } else if let a = any as? [Any] {
                a.forEach(walk)
            }
        }
        blobs.forEach(walk)
        return out
    }

    /// Key names only — enough to tell "wrong shape" from "wrong route" without
    /// writing a single balance into the log.
    private static func topLevelKeys(_ data: Data) -> [String] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) else { return [] }
        if let d = obj as? [String: Any] {
            var keys = Array(d.keys)
            if let inner = d["data"] as? [String: Any] { keys += inner.keys.map { "data.\($0)" } }
            if let arr = d["data"] as? [[String: Any]], let first = arr.first {
                keys += first.keys.map { "data[].\($0)" }
            }
            return keys
        }
        if let a = obj as? [[String: Any]], let first = a.first { return first.keys.map { "[].\($0)" } }
        return []
    }

    private static func userID(from json: [String: Any]) -> String? {
        let data = json["data"] as? [String: Any] ?? json
        if let u = data["user"] as? [String: Any] {
            return string(u["uuid"]) ?? string(u["id"])
        }
        return string(data["uuid"]) ?? string(data["user_id"])
    }
}

/// What Fold answered on the last pull — one line per call, statuses and JSON key
/// names only. Written next to the state cache so a silent empty pull can be read
/// back after the fact instead of re-guessed.
enum FoldTrace {
    private(set) static var lines: [String] = []

    static func reset() { lines = [] }
    static func record(_ line: String) { lines.append(line) }

    static func line(method: String, path: String, code: Int, bytes: Int, keys: [String]) -> String {
        let shown = keys.sorted().prefix(8).joined(separator: ",")
        let tail = shown.isEmpty ? "" : ", keys: \(shown)"
        return "\(method) \(path) → \(code) (\(bytes) B\(tail))"
    }

    private static let shapePrefix = "    shape "

    /// For the error line on screen: routes and statuses only. The shape dumps are
    /// hundreds of characters and belong in the log, not across the dashboard.
    static var summary: String {
        lines.filter { !$0.hasPrefix(shapePrefix) }
            .map { $0.replacingOccurrences(of: ", keys:", with: " keys:") }
            .joined(separator: " · ")
    }

    /// The shape of a response with every value replaced by its type, arrays
    /// collapsed to their first element. Enough to write a parser against; never
    /// enough to read a balance off.
    static func skeleton(_ any: Any, depth: Int = 0) -> String {
        guard depth < 6 else { return "…" }
        switch any {
        case let d as [String: Any]:
            let body = d.keys.sorted().prefix(24)
                .map { "\($0):\(skeleton(d[$0] as Any, depth: depth + 1))" }
                .joined(separator: ",")
            return "{\(body)}"
        case let a as [Any]:
            guard let first = a.first else { return "[]" }
            return "[\(skeleton(first, depth: depth + 1))×\(a.count)]"
        case is NSNull: return "null"
        case let n as NSNumber:
            return CFGetTypeID(n) == CFBooleanGetTypeID() ? "bool" : "number"
        case is String: return "string"
        default: return "?"
        }
    }

    static func recordShape(path: String, data: Data) {
        guard let obj = try? JSONSerialization.jsonObject(with: data) else { return }
        record("    shape \(path): \(String(skeleton(obj).prefix(1600)))")
    }

    static var logURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("MyOS/fold-debug.log")
    }

    /// Appends, so a sign-in and the pull that follows it are both readable. Kept
    /// to the last 400 lines — this is a debugging aid, not a journal.
    static func writeLog() {
        guard let url = logURL, !lines.isEmpty else { return }
        let stamp = ISO8601DateFormatter().string(from: Date())
        let previous = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        var all = previous.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        all += ["[\(stamp)]"] + lines
        let body = all.suffix(400).joined(separator: "\n") + "\n"
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? body.data(using: .utf8)?.write(to: url, options: .atomic)
    }
}

enum FoldError: LocalizedError {
    case badPhone, badOTP, notLinked, sessionNotSaved, emptyPull(String), http(Int, String)
    var errorDescription: String? {
        switch self {
        case .badPhone: return "Enter a valid Indian mobile number."
        case .badOTP: return "That OTP didn’t work."
        case .notLinked: return "Fold isn’t signed in. Connect it first."
        case .sessionNotSaved: return "Fold signed in, but the session couldn’t be saved. Unlock MyOS and try again."
        case .emptyPull(let what): return "Fold answered but sent no balances — \(what)"
        case .http(_, let m) where m.lowercased().contains("invalid phone"):
            return "Fold wants +91 and your 10-digit mobile. Try again."
        case .http(let c, let m): return "Fold \(c): \(m)"
        }
    }
}

/// Disk/sync may replace the on-screen snapshot only when this device never
/// had a live Fold session. A failed live pull must keep the current numbers.
enum FoldRefresh {
    static func shouldReloadStaleSnapshot(linked: Bool, liveSucceeded: Bool) -> Bool {
        !linked && !liveSucceeded
    }

    /// Pull Mac↔phone sync when live Fold failed and this device has nothing
    /// real to show (the iPhone zero-wipe). A rich local snapshot stays put.
    static func shouldPullSync(linked: Bool, liveSucceeded: Bool, localBare: Bool) -> Bool {
        if liveSucceeded { return false }
        if localBare { return true }
        return !linked
    }
}

/// Status line under the Fold dashboard. Stale disk must not read as "Live".
enum FoldCaption {
    static func line(asOf: String, linked: Bool, error: String?) -> String {
        if asOf.isEmpty { return "Tap to pull latest from Fold" }
        if linked && error == nil { return "Live Fold · \(asOf)" }
        if !linked { return "Last snapshot · \(asOf) · Connect to refresh" }
        return "Last snapshot · \(asOf)"
    }
}

/// Pure mapper — blobs from Fold JSON → `FoldData`. Unit-tested.
enum FoldSnapshotBuilder {
    static func isBare(_ f: FoldData) -> Bool {
        f.netWorth == 0 && f.liquid == 0 && f.investments == 0 && f.debt == 0
            && f.spentThisMonth == 0 && f.banks.isEmpty && f.topSpends.isEmpty
    }

    /// The best snapshot this device actually has: what is in memory, else what
    /// is on disk. Nil when neither holds anything real.
    ///
    /// There used to be a third fallback — a hardcoded "recovery" snapshot added
    /// to rescue a device stuck on zero. It held the owner's real bank names,
    /// account digits, balances and a 42-point net-worth history, and nothing
    /// scoped it to him. Any new user who opened the Fold tab without connecting
    /// anything was shown his finances; `restoreFoldIfBare` then saved that to
    /// disk and pushed it, so it became their synced state and reached their
    /// other devices too. Nothing real to show is not an emergency — it is the
    /// "Connect Fold" screen, which this returning nil is what reveals.
    static func resolved(current: FoldData?, disk: FoldData?) -> FoldData? {
        if let c = current, !isBare(c) { return c }
        if let d = disk, !isBare(d) { return d }
        return nil
    }

    /// `extracted` is false when Fold was reached but nothing usable came back —
    /// the caller must surface that instead of re-saving the old snapshot.
    struct Outcome {
        var data: FoldData
        var extracted: Bool
    }

    static func build(blobs: [[String: Any]], transactions: [[String: Any]], previous: FoldData?) -> FoldData {
        outcome(blobs: blobs, transactions: transactions, previous: previous).data
    }

    static func outcome(blobs: [[String: Any]], transactions: [[String: Any]], previous: FoldData?) -> Outcome {
        var next = previous ?? FoldData()
        let nums = collectNumbers(blobs)
        if let v = nums["net_worth"] ?? nums["netWorth"] ?? nums["total_net_worth"] { next.netWorth = v }
        if let v = nums["liquid"] ?? nums["cash"] ?? nums["bank_balance"] ?? nums["total_balance"] { next.liquid = v }
        if let v = nums["investments"] ?? nums["investment"] ?? nums["portfolio"] { next.investments = v }
        if let v = nums["debt"] ?? nums["liabilities"] { next.debt = v }
        if let v = nums["stocks"] ?? nums["equity"] ?? nums["stocks_value"] { next.stocksValue = v }
        if let v = nums["mutual_funds"] ?? nums["mf"] ?? nums["mf_value"] { next.mfValue = v }

        let banks = collectBanks(blobs) + banksFromTransactions(transactions)
        if !banks.isEmpty {
            var seen = Set<String>()
            next.banks = banks.filter { seen.insert($0.name + $0.last4).inserted }
            if next.liquid == 0 {
                next.liquid = next.banks.reduce(0) { $0 + $1.balance }
            }
        }

        let spends = spendsThisMonth(transactions)
        if !spends.isEmpty {
            next.topSpends = spends
            next.spentThisMonth = spends.reduce(0) { $0 + $1.amount }
        }

        if next.netWorth == 0 { next.netWorth = next.liquid + next.investments - next.debt }
        if next.history.isEmpty { next.history = previous?.history ?? [] }
        if let last = next.history.last, abs(last - next.netWorth) > 1 {
            next.history.append(next.netWorth)
        } else if next.history.isEmpty, next.netWorth != 0 {
            next.history = [next.netWorth]
        }
        if next.history.count > 1, let first = next.history.first {
            next.changeValue = next.netWorth - first
            next.changePercent = first == 0 ? 0 : next.changeValue / first
            next.changeLabel = "since first point"
        }

        let extracted = !nums.isEmpty || !banks.isEmpty || !spends.isEmpty
        if !extracted, let prev = previous, !isBare(prev) { return Outcome(data: prev, extracted: false) }
        if isBare(next), let prev = previous, !isBare(prev) { return Outcome(data: prev, extracted: false) }

        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_IN")
        fmt.dateFormat = "d MMM yyyy, h:mm a"
        next.asOf = fmt.string(from: Date())
        next.currency = "INR"
        return Outcome(data: next, extracted: extracted)
    }

    private static func collectNumbers(_ blobs: [[String: Any]]) -> [String: Double] {
        var out: [String: Double] = [:]
        let keys = ["net_worth", "netWorth", "total_net_worth", "liquid", "cash", "bank_balance",
                    "total_balance", "investments", "investment", "portfolio", "debt", "liabilities",
                    "stocks", "equity", "stocks_value", "mutual_funds", "mf", "mf_value"]
        func walk(_ any: Any) {
            if let d = any as? [String: Any] {
                for (k, v) in d {
                    if keys.contains(k), let n = number(v) { out[k] = n }
                    walk(v)
                }
            } else if let a = any as? [Any] {
                a.forEach(walk)
            }
        }
        blobs.forEach(walk)
        return out
    }

    /// Fold nests accounts under `data.added` / `data.subscribed` / `data.accounts`
    /// and spells the fields several ways, so match on "does this object look like
    /// an account" rather than on one exact shape. The marker keys keep a plan or
    /// settings object with a name and an amount from becoming a bank.
    private static let accountMarkers = [
        "masked_account_number", "account_number", "account_id", "account_type",
        "account_ref_number", "fip", "financial_information_provider", "ifsc"
    ]
    private static let balanceKeys = [
        "current_balance", "balance", "available_balance", "latest_balance",
        "closing_balance", "amount"
    ]
    private static let nameKeys = ["account_name", "bank_name", "display_name", "nickname", "name"]

    /// `bank_accounts` gives identity and no money; `bank_accounts/balances` gives
    /// money and no name. Collect both keyed by account id, then join — an object
    /// carrying identity *and* balance at once still works as a special case.
    private static func collectBanks(_ blobs: [[String: Any]]) -> [FoldData.Bank] {
        var identity: [String: (name: String?, mask: String?)] = [:]
        var balances: [String: Double] = [:]
        var order: [String] = []
        var loose: [FoldData.Bank] = []

        func accountID(_ d: [String: Any]) -> String? {
            string(d["account_id"]) ?? string(d["bank_account_id"]) ?? string(d["uuid"]) ?? string(d["id"])
        }
        func mask(_ d: [String: Any]) -> String? {
            string(d["masked_account_number"]) ?? string(d["account_number"])
                ?? string(d["last4"]) ?? string(d["account_ref_number"])
        }

        func walk(_ any: Any) {
            if let d = any as? [String: Any] {
                let looksLikeAccount = accountMarkers.contains { d[$0] != nil }
                let bal = balance(in: d)
                if let id = accountID(d), looksLikeAccount || bal != nil {
                    if identity[id] == nil && balances[id] == nil { order.append(id) }
                    if looksLikeAccount {
                        let existing = identity[id]
                        identity[id] = (accountName(in: d) ?? existing?.name,
                                        mask(d) ?? existing?.mask)
                    }
                    if let bal { balances[id] = bal }
                } else if looksLikeAccount, let bal {
                    loose.append(FoldData.Bank(name: accountName(in: d) ?? "Bank",
                                               last4: String((mask(d) ?? "").filter(\.isNumber).suffix(4)),
                                               balance: bal))
                }
                d.values.forEach(walk)
            } else if let a = any as? [Any] {
                a.forEach(walk)
            }
        }
        blobs.forEach(walk)

        // Only ids that actually carry money are accounts. An identity with no
        // balance would otherwise show up as a real bank holding ₹0.
        return order.compactMap { id in
            guard let bal = balances[id] else { return nil }
            let who = identity[id]
            return FoldData.Bank(name: who?.name ?? "Bank",
                                 last4: String((who?.mask ?? "").filter(\.isNumber).suffix(4)),
                                 balance: bal)
        } + loose
    }

    /// `19539.13`, `"19539.13"`, or `{ "amount": 19539.13, "currency": "INR" }`.
    private static func balance(in d: [String: Any]) -> Double? {
        for key in balanceKeys {
            guard let raw = d[key] else { continue }
            if let n = number(raw) { return n }
            if let nested = raw as? [String: Any] {
                if let n = number(nested["amount"]) ?? number(nested["value"]) ?? number(nested["units"]) {
                    return n
                }
            }
        }
        return nil
    }

    private static func accountName(in d: [String: Any]) -> String? {
        for key in nameKeys { if let s = string(d[key]) { return s } }
        for key in ["fip", "financial_information_provider", "bank", "institution"] {
            if let nested = d[key] as? [String: Any],
               let s = string(nested["name"]) ?? string(nested["display_name"]) { return s }
            if let s = string(d[key]) { return s }
        }
        return nil
    }

    /// The most recent `current_balance` each account carried on a transaction.
    ///
    /// The fallback for when Fold gives us no balances blob at all. It used to
    /// assign unconditionally as it walked the feed, so the last write won — and
    /// the feed arrives newest-first (`fetchTransactions` stops paging once
    /// `page.last` predates the month, which only works because it is the oldest
    /// row). The dictionary named `latest` therefore ended up holding each
    /// account's *oldest* known balance, and since `liquid` and then net worth
    /// are derived from these when nothing else supplies them, the headline
    /// number on the Fold tab was a figure from weeks ago.
    private static func banksFromTransactions(_ txns: [[String: Any]]) -> [FoldData.Bank] {
        var latest: [String: (name: String, last4: String, bal: Double, at: Date?)] = [:]
        for t in txns {
            let fip = t["financial_information_provider"] as? [String: Any]
            let name = string(fip?["name"]) ?? string(t["account"]) ?? "Bank"
            let id = string(t["account_id"]) ?? name
            guard let bal = number(t["current_balance"]) else { continue }
            let at = date(t["txn_timestamp"]) ?? date(t["txn_date"])
            if let held = latest[id], !isNewer(at, than: held.at) { continue }
            latest[id] = (name, String(id.suffix(4)), bal, at)
        }
        // Sorted, because `latest.values` is a Dictionary and has no order:
        // the Fold tab's bank rows shuffled between launches. `collectBanks`
        // keeps an explicit `order` array for exactly this reason; this path
        // has no natural order to preserve, so biggest balance leads.
        return latest.values
            .sorted { $0.bal == $1.bal ? $0.name < $1.name : $0.bal > $1.bal }
            .map { FoldData.Bank(name: $0.name, last4: $0.last4, balance: $0.bal) }
    }

    /// Whether a candidate reading should displace the one already held. A dated
    /// reading beats an undated one; with nothing to compare, the first seen
    /// wins, because the feed arrives newest-first.
    private static func isNewer(_ candidate: Date?, than held: Date?) -> Bool {
        switch (candidate, held) {
        case let (.some(new), .some(old)): return new > old
        case (.some, .none):               return true
        case (.none, _):                   return false
        }
    }

    private static func spendsThisMonth(_ txns: [[String: Any]]) -> [FoldData.Spend] {
        let cal = Calendar(identifier: .gregorian)
        let now = Date()
        var byCat: [String: Double] = [:]
        for t in txns {
            let kind = (string(t["type"]) ?? string(t["kind"]) ?? "").uppercased()
            guard kind.contains("DEBIT") || kind == "DEBIT" || kind.contains("OUT") else { continue }
            if let ts = date(t["txn_timestamp"]) ?? date(t["txn_date"]) {
                let c = cal.dateComponents([.year, .month], from: ts)
                let n = cal.dateComponents([.year, .month], from: now)
                guard c.year == n.year, c.month == n.month else { continue }
            }
            let amt = abs(number(t["amount"]) ?? 0)
            guard amt > 0 else { continue }
            let cat: String
            if let s = string(t["category"]) { cat = s }
            else if let d = t["category"] as? [String: Any] { cat = string(d["name"]) ?? "Other" }
            else { cat = "Other" }
            if FoldSpend.isNonSpend(cat) { continue }
            byCat[cat, default: 0] += amt
        }
        return byCat.map { FoldData.Spend(category: $0.key, amount: $0.value) }
            .sorted { $0.amount > $1.amount }
            .prefix(6)
            .map { $0 }
    }
}

private func string(_ any: Any?) -> String? {
    if let s = any as? String, !s.isEmpty { return s }
    if let n = any as? NSNumber { return n.stringValue }
    return nil
}

private func number(_ any: Any?) -> Double? {
    if let d = any as? Double { return d }
    if let i = any as? Int { return Double(i) }
    if let n = any as? NSNumber { return n.doubleValue }
    if let s = any as? String { return Double(s) }
    return nil
}

private func date(_ any: Any?) -> Date? {
    guard let s = string(any) else { return nil }
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = iso.date(from: s) { return d }
    iso.formatOptions = [.withInternetDateTime]
    return iso.date(from: s)
}

private func arrayOfDicts(_ any: Any, key: String) -> [[String: Any]] {
    if let d = any as? [String: Any], let a = d[key] as? [[String: Any]] { return a }
    if let a = any as? [[String: Any]] { return a }
    return []
}
