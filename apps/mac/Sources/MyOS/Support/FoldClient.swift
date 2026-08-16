import Foundation

/// Live Fold Money client — phone OTP, then dashboard + accounts + this month's
/// spends. Tokens stay on-device in the Keychain. Refresh uses the same session.
enum FoldClient {
    private static let base = URL(string: "https://api.fold.money/api")!
    private static let kAccess = "fold.access"
    private static let kRefresh = "fold.refresh"
    private static let kUser = "fold.user"
    private static let kPhone = "fold.phone"
    private static let kDevice = "fold.deviceHash"

    static var isLinked: Bool { KeychainStore.loadSecret(account: kAccess) != nil }
    static var linkedPhone: String { UserDefaults.standard.string(forKey: kPhone) ?? "" }

    static func unlink() {
        KeychainStore.deleteSecret(account: kAccess)
        KeychainStore.deleteSecret(account: kRefresh)
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
        let json = try await postJSON("/v1/auth/otp/verify", auth: false, body: [
            "phone": phone, "otp": otp.trimmingCharacters(in: .whitespaces)
        ])
        let data = json["data"] as? [String: Any] ?? json
        guard let access = string(data["access_token"]) else { throw FoldError.badOTP }
        KeychainStore.saveSecret(access, account: kAccess)
        if let refresh = string(data["refresh_token"]) {
            KeychainStore.saveSecret(refresh, account: kRefresh)
        }
        if let uid = string(data["user_id"]) ?? string((data["user_meta"] as? [String: Any])?["uuid"]) {
            UserDefaults.standard.set(uid, forKey: kUser)
        }
        UserDefaults.standard.set(phone, forKey: kPhone)
    }

    /// Pull a fresh snapshot from Fold and map it into `FoldData`.
    static func fetchSnapshot() async throws -> FoldData {
        try await refreshIfNeeded()
        let me = try await getJSON("/v2/users/me")
        let uid = userID(from: me) ?? UserDefaults.standard.string(forKey: kUser) ?? ""
        if !uid.isEmpty { UserDefaults.standard.set(uid, forKey: kUser) }

        var blobs: [[String: Any]] = [me]
        let extra = [
            "/v1/users/\(uid)/dashboard",
            "/v1/users/\(uid)/net-worth",
            "/v1/users/\(uid)/networth",
            "/v1/users/\(uid)/accounts",
            "/v1/users/\(uid)/bank-accounts",
            "/v1/users/\(uid)/insights",
            "/v1/users/\(uid)/investments",
            "/v1/users/\(uid)/holdings",
            "/v2/users/\(uid)/dashboard"
        ]
        for path in extra where !uid.isEmpty {
            if let j = try? await getJSON(path) { blobs.append(j) }
        }

        var txns: [[String: Any]] = []
        if !uid.isEmpty, let t = try? await getJSON("/v1/users/\(uid)/transactions?filter=all&count_by=month") {
            blobs.append(t)
            txns = arrayOfDicts(t["data"] ?? t, key: "transactions")
        }

        return FoldSnapshotBuilder.build(blobs: blobs, transactions: txns, previous: FoldData.load())
    }

    // MARK: - HTTP

    private static func refreshIfNeeded() async throws {
        guard KeychainStore.loadSecret(account: kAccess) != nil else { throw FoldError.notLinked }
        guard let refresh = KeychainStore.loadSecret(account: kRefresh) else { return }
        guard let json = try? await postJSON("/v1/auth/tokens/refresh", auth: false, body: [
            "refresh_token": refresh
        ]) else { return }
        let data = json["data"] as? [String: Any] ?? json
        if let access = string(data["access_token"]) {
            KeychainStore.saveSecret(access, account: kAccess)
        }
        if let next = string(data["refresh_token"]) {
            KeychainStore.saveSecret(next, account: kRefresh)
        }
    }

    private static func getJSON(_ path: String) async throws -> [String: Any] {
        try await send(path, method: "GET", auth: true, body: nil)
    }

    private static func postJSON(_ path: String, auth: Bool, body: [String: Any]) async throws -> [String: Any] {
        try await send(path, method: "POST", auth: auth, body: body)
    }

    private static func send(_ path: String, method: String, auth: Bool, body: [String: Any]?) async throws -> [String: Any] {
        let url: URL
        if path.contains("?") {
            url = URL(string: base.absoluteString + path)!
        } else {
            url = base.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("MyOS/1.0", forHTTPHeaderField: "User-Agent")
        req.setValue(deviceHash(), forHTTPHeaderField: "X-Device-Hash")
        req.setValue("India", forHTTPHeaderField: "X-Device-Location")
        req.setValue("MyOS", forHTTPHeaderField: "X-Device-Name")
        #if os(iOS)
        req.setValue("iOS", forHTTPHeaderField: "X-Device-Type")
        #else
        req.setValue("macOS", forHTTPHeaderField: "X-Device-Type")
        #endif
        if auth, let token = KeychainStore.loadSecret(account: kAccess) {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        if code == 401 { throw FoldError.notLinked }
        guard (200..<300).contains(code) else {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \(code)"
            throw FoldError.http(code, String(msg.prefix(180)))
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

    static func normalizePhone(_ raw: String) -> String {
        var d = raw.filter(\.isNumber)
        if d.hasPrefix("0") { d.removeFirst() }
        if d.count == 10 { d = "91" + d }
        return d
    }

    private static func userID(from json: [String: Any]) -> String? {
        let data = json["data"] as? [String: Any] ?? json
        if let u = data["user"] as? [String: Any] {
            return string(u["uuid"]) ?? string(u["id"])
        }
        return string(data["uuid"]) ?? string(data["user_id"])
    }
}

enum FoldError: LocalizedError {
    case badPhone, badOTP, notLinked, http(Int, String)
    var errorDescription: String? {
        switch self {
        case .badPhone: return "Enter a valid Indian mobile number."
        case .badOTP: return "That OTP didn’t work."
        case .notLinked: return "Fold isn’t signed in. Connect it first."
        case .http(let c, let m): return "Fold \(c): \(m)"
        }
    }
}

/// Pure mapper — blobs from Fold JSON → `FoldData`. Unit-tested.
enum FoldSnapshotBuilder {
    static func build(blobs: [[String: Any]], transactions: [[String: Any]], previous: FoldData?) -> FoldData {
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

        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_IN")
        fmt.dateFormat = "d MMM yyyy, h:mm a"
        next.asOf = fmt.string(from: Date())
        next.currency = "INR"
        return next
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

    private static func collectBanks(_ blobs: [[String: Any]]) -> [FoldData.Bank] {
        var banks: [FoldData.Bank] = []
        func walk(_ any: Any) {
            if let d = any as? [String: Any] {
                let name = string(d["account_name"]) ?? string(d["name"]) ?? string(d["bank_name"])
                let mask = string(d["masked_account_number"]) ?? string(d["last4"]) ?? string(d["account_number"])
                let bal = number(d["balance"]) ?? number(d["current_balance"]) ?? number(d["available_balance"])
                if let name, let bal, !name.isEmpty {
                    let last4 = String((mask ?? "").filter(\.isNumber).suffix(4))
                    banks.append(FoldData.Bank(name: name, last4: last4, balance: bal))
                }
                d.values.forEach(walk)
            } else if let a = any as? [Any] {
                a.forEach(walk)
            }
        }
        blobs.forEach(walk)
        return banks
    }

    private static func banksFromTransactions(_ txns: [[String: Any]]) -> [FoldData.Bank] {
        var latest: [String: (name: String, last4: String, bal: Double)] = [:]
        for t in txns {
            let fip = t["financial_information_provider"] as? [String: Any]
            let name = string(fip?["name"]) ?? string(t["account"]) ?? "Bank"
            let id = string(t["account_id"]) ?? name
            if let bal = number(t["current_balance"]) {
                latest[id] = (name, String(id.suffix(4)), bal)
            }
        }
        return latest.values.map { FoldData.Bank(name: $0.name, last4: $0.last4, balance: $0.bal) }
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
