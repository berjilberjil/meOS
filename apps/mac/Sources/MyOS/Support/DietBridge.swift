import Foundation
#if os(macOS)
import Network

/// Loopback HTTP bridge so the native diet MCP can read/write the unlocked
/// in-memory store. Mac and iPhone then sync through the existing push/pull.
@MainActor
final class DietBridge {
    static let shared = DietBridge()
    static let port: UInt16 = 17881
    static let tokenKey = "myos.mcp.token"

    static func jsonString(_ s: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: s, options: .fragmentsAllowed)) ?? Data("\"\"".utf8)
        return String(data: data, encoding: .utf8) ?? "\"\""
    }

    static func token() -> String {
        let d = UserDefaults.standard
        if let t = d.string(forKey: tokenKey), !t.isEmpty { return t }
        let t = UUID().uuidString.lowercased()
        d.set(t, forKey: tokenKey)
        return t
    }

    private var listener: NWListener?
    private weak var state: AppState?

    func start(state: AppState) {
        self.state = state
        _ = Self.token()
        guard listener == nil else { return }
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            params.requiredLocalEndpoint = NWEndpoint.hostPort(
                host: NWEndpoint.Host("127.0.0.1"),
                port: NWEndpoint.Port(rawValue: Self.port)!)
            let l = try NWListener(using: params)
            l.newConnectionHandler = { [weak self] conn in
                conn.start(queue: .global(qos: .userInitiated))
                dietBridgeRead(conn) { req in
                    Task { @MainActor in
                        let res = self?.handle(req) ?? HTTPRes(403, #"{"error":"bridge down"}"#)
                        dietBridgeWrite(conn, res)
                    }
                }
            }
            l.stateUpdateHandler = { state in
                let line = "listener \(state)"
                try? line.write(toFile: NSTemporaryDirectory() + "myos-diet-bridge.log", atomically: true, encoding: .utf8)
            }
            l.start(queue: .global(qos: .utility))
            listener = l
            try? "started port \(Self.port)".write(toFile: NSTemporaryDirectory() + "myos-diet-bridge.log", atomically: true, encoding: .utf8)
        } catch {
            try? "fail \(error)".write(toFile: NSTemporaryDirectory() + "myos-diet-bridge.log", atomically: true, encoding: .utf8)
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        state = nil
    }

    private func handle(_ req: HTTPReq) -> HTTPRes {
        guard let state else { return HTTPRes(503, #"{"error":"not ready"}"#) }
        guard req.token == Self.token() else { return HTTPRes(401, #"{"error":"bad token"}"#) }
        // A write needs a hydrated store. The bridge starts from `AppState.init`,
        // long before any unlock, and on the Mac the app always lands on the
        // passphrase screen. Before hydrate, `push` refuses the write, the next
        // `apply()` overwrites the in-memory mutation from the server — and the
        // tool had already been told `{"ok":true}`. Meals logged at the lock
        // screen simply never existed.
        // Reads too, not just writes. `/health` is deliberately exempt — the
        // client polls it to decide whether the local bridge is usable at all.
        // Serving a read from a default-constructed store meant that with the
        // Mac sitting at its passphrase screen, `get_context` answered "0 kcal,
        // 0 g protein, no custom foods" — so the assistant told the user they
        // had eaten nothing today and their food library did not exist.
        if req.path != "/health", !state.isHydrated {
            return HTTPRes(503, #"{"error":"MyOS is locked or not synced yet"}"#)
        }
        do {
            switch (req.method, req.path) {
            case ("GET", "/health"):
                let err = state.lastSyncError ?? ""
                return HTTPRes(200, """
                    {"ok":true,"native":true,"hydrated":\(state.isHydrated),"sync_error":\(Self.jsonString(err))}
                    """)
            case ("GET", "/context"):
                return HTTPRes.json(try state.mcpContext())
            case ("GET", "/week"):
                return HTTPRes.json(try state.mcpWeekPlan())
            case ("GET", "/day"):
                let date = req.query["date"] ?? state.todayKey
                return HTTPRes.json(try state.mcpDayLog(date))
            case ("GET", "/foods"):
                let q = req.query["q"] ?? ""
                let limit = Int(req.query["limit"] ?? "12") ?? 12
                return HTTPRes.json(state.mcpSearchFoods(q, limit: limit))
            case ("POST", "/slot"):
                let b = try req.json()
                try state.mcpSetSlot(b)
                return HTTPRes(200, #"{"ok":true}"#)
            case ("POST", "/slot/add"):
                let b = try req.json()
                try state.mcpAddSlot(b)
                return HTTPRes(200, #"{"ok":true}"#)
            case ("POST", "/slot/remove"):
                let b = try req.json()
                state.mcpRemoveSlot(id: b.string("id"))
                return HTTPRes(200, #"{"ok":true}"#)
            case ("POST", "/slot/clear"):
                let b = try req.json()
                try state.mcpClearSlot(b)
                return HTTPRes(200, #"{"ok":true}"#)
            case ("POST", "/week/clear"):
                state.clearMealPlan()
                return HTTPRes(200, #"{"ok":true}"#)
            case ("POST", "/log"):
                let b = try req.json()
                try state.mcpLogFood(b)
                return HTTPRes(200, #"{"ok":true}"#)
            case ("POST", "/log/planned"):
                let b = try req.json()
                try state.mcpLogPlanned(b)
                return HTTPRes(200, #"{"ok":true}"#)
            case ("POST", "/log/delete"):
                let b = try req.json()
                state.deleteLogItem(id: b.string("id"))
                return HTTPRes(200, #"{"ok":true}"#)
            case ("POST", "/food"):
                let b = try req.json()
                return HTTPRes.json(try state.mcpUpsertFood(b))
            case ("POST", "/goals"):
                let b = try req.json()
                state.mcpSetGoals(b)
                return HTTPRes(200, #"{"ok":true}"#)

            // Stuff / spending — handlers live in StuffBridge.swift.
            case ("GET", "/stuff"):
                return HTTPRes.json(["items": state.mcpStuffList(
                    q: req.query["q"] ?? "",
                    categoryID: req.query["category"] ?? "",
                    limit: Int(req.query["limit"] ?? "50") ?? 50,
                    includeRetired: req.query["include_retired"] == "true")])
            case ("GET", "/stuff/summary"):
                return HTTPRes.json(state.mcpStuffSummary())
            case ("GET", "/stuff/categories"):
                return HTTPRes.json(["categories": state.mcpStuffCategories()])
            case ("POST", "/stuff"):
                return HTTPRes.json(["item": try state.mcpStuffAdd(try req.json())])
            case ("POST", "/stuff/update"):
                return HTTPRes.json(["item": try state.mcpStuffUpdate(try req.json())])
            case ("POST", "/stuff/delete"):
                let b = try req.json()
                state.deleteBelonging(b["id"] as? String ?? "")
                return HTTPRes(200, #"{"ok":true}"#)
            default:
                return HTTPRes(404, #"{"error":"not found"}"#)
            }
        } catch {
            let msg = error.localizedDescription.replacingOccurrences(of: "\"", with: "'")
            return HTTPRes(400, "{\"error\":\"\(msg)\"}")
        }
    }
}

private func dietBridgeRead(_ conn: NWConnection, done: @escaping (HTTPReq) -> Void) {
    var buf = Data()
    func more() {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, isComplete, err in
            if let data { buf.append(data) }
            if let req = HTTPReq.parse(buf) { done(req); return }
            // Bounded. A peer that opens a connection and never sends a header
            // terminator — or declares a body it does not deliver — otherwise
            // grew this buffer for as long as it stayed connected.
            if buf.count > HTTPReq.maxBodyBytes + 64 * 1024 { done(HTTPReq.bad); return }
            if isComplete || err != nil { done(HTTPReq.bad); return }
            more()
        }
    }
    more()
}

private func dietBridgeWrite(_ conn: NWConnection, _ res: HTTPRes) {
    conn.send(content: res.data, completion: .contentProcessed { _ in
        conn.cancel()
    })
}

struct HTTPReq {
    /// Anything larger than this is not a diet log. Bounds both the declared
    /// Content-Length and, with it, the buffer the reader will accumulate.
    static let maxBodyBytes = 4 * 1024 * 1024

    var method = "GET"
    var path = "/"
    var query: [String: String] = [:]
    var token = ""
    var body = Data()
    static let bad = HTTPReq()

    func json() throws -> [String: Any] {
        guard let obj = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            throw NSError(domain: "DietBridge", code: 400, userInfo: [NSLocalizedDescriptionKey: "JSON object required"])
        }
        return obj
    }

    static func parse(_ data: Data) -> HTTPReq? {
        guard let range = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let head = String(data: data.subdata(in: data.startIndex..<range.lowerBound), encoding: .utf8) ?? ""
        let lines = head.split(separator: "\r\n", omittingEmptySubsequences: false).map(String.init)
        guard let first = lines.first else { return nil }
        let parts = first.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        var req = HTTPReq()
        req.method = String(parts[0])
        let raw = String(parts[1])
        if let q = raw.firstIndex(of: "?") {
            req.path = String(raw[..<q])
            let qs = String(raw[raw.index(after: q)...])
            for pair in qs.split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
                if kv.count == 2 { req.query[kv[0]] = kv[1].removingPercentEncoding ?? kv[1] }
            }
        } else {
            req.path = raw
        }
        var contentLength = 0
        for line in lines.dropFirst() {
            let lower = line.lowercased()
            if let r = line.range(of: "Bearer ", options: .caseInsensitive) {
                req.token = String(line[r.upperBound...]).trimmingCharacters(in: .whitespaces)
            }
            if lower.hasPrefix("content-length:") {
                // Bounded, and split with a count check. `split(":")[1]` traps on
                // a header with no value, and a negative length made `subdata`
                // trap on an inverted range — both before the token was even
                // looked at, so any process on the machine could kill the app
                // with one line of netcat.
                let kv = line.split(separator: ":", maxSplits: 1)
                guard kv.count == 2,
                      let n = Int(kv[1].trimmingCharacters(in: .whitespaces)),
                      n >= 0, n <= Self.maxBodyBytes else { return nil }
                contentLength = n
            }
        }
        let bodyStart = range.upperBound
        guard bodyStart <= data.count, data.count - bodyStart >= contentLength else { return nil }
        req.body = data.subdata(in: bodyStart..<(bodyStart + contentLength))
        return req
    }
}

struct HTTPRes {
    let status: Int
    let body: Data
    init(_ status: Int, _ text: String) {
        self.status = status
        self.body = Data(text.utf8)
    }
    static func json(_ obj: Any) -> HTTPRes {
        let data = (try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])) ?? Data("{}".utf8)
        return HTTPRes(200, String(data: data, encoding: .utf8) ?? "{}")
    }
    var data: Data {
        let head = "HTTP/1.1 \(status) OK\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        return Data(head.utf8) + body
    }
}

private extension Dictionary where Key == String, Value == Any {
    func string(_ k: String) -> String { self[k] as? String ?? "" }
    func int(_ k: String) -> Int? {
        if let i = self[k] as? Int { return i }
        if let s = self[k] as? String { return Int(s) }
        if let d = self[k] as? Double { return Int(d) }
        return nil
    }
    func double(_ k: String) -> Double? {
        if let d = self[k] as? Double { return d }
        if let i = self[k] as? Int { return Double(i) }
        if let s = self[k] as? String { return Double(s) }
        return nil
    }
}

extension AppState {
    fileprivate func mcpMeal(_ raw: String) throws -> MealKey {
        switch raw.lowercased() {
        case "breakfast": return .breakfast
        case "lunch": return .lunch
        case "dinner": return .dinner
        case "snack", "snacks": return .snacks
        default: throw NSError(domain: "DietBridge", code: 400, userInfo: [NSLocalizedDescriptionKey: "unknown meal \(raw)"])
        }
    }

    /// Like `mcpWeekday`, but refuses an unusable date instead of defaulting.
    ///
    /// The lenient version falls back to `weekdayKey(date)`, which itself
    /// returns "0" for anything it cannot parse — so a bad date on a planner
    /// write silently overwrote Sunday.
    /// The 400 this bridge reports, matching the convention already in use here.
    static func badRequest(_ message: String) -> Error {
        NSError(domain: "DietBridge", code: 400,
                userInfo: [NSLocalizedDescriptionKey: message])
    }

    fileprivate func mcpWeekdayChecked(_ body: [String: Any]) throws -> String {
        if let w = body.int("weekday") { return String(max(0, min(6, w))) }
        if let s = body["weekday"] as? String, WEEKDAY_OK.contains(s) { return s }
        if let date = body["date"] as? String, !date.isEmpty {
            return Self.weekdayKey(try mcpDate(date))
        }
        return todayWeekday
    }

    fileprivate func mcpWeekday(_ body: [String: Any]) -> String {
        if let w = body.int("weekday") { return String(max(0, min(6, w))) }
        if let s = body["weekday"] as? String, WEEKDAY_OK.contains(s) { return s }
        if let date = body["date"] as? String, !date.isEmpty { return Self.weekdayKey(date) }
        return todayWeekday
    }

    func mcpSearchFoods(_ q: String, limit: Int) -> [[String: Any]] {
        let all = allFoods
        let hits = q.isEmpty ? all : all.filter { $0.name.localizedCaseInsensitiveContains(q) }
        return hits.prefix(max(1, min(limit, 40))).map { f in
            ["id": f.id, "name": f.name, "category": f.category.rawValue,
             "serving": f.servingLabel, "kcal": f.perServing.calories, "protein": f.perServing.protein]
        }
    }

    func mcpWeekPlan() throws -> [String: Any] {
        var days: [[String: Any]] = []
        for wd in WeekdayKeys.all {
            var meals: [String: Any] = [:]
            var dayItems: [PlanItem] = []
            for meal in MealKey.allCases {
                let items = planItems(wd, meal)
                dayItems.append(contentsOf: items)
                meals[meal.rawValue] = items.map { mcpItem($0) }
            }
            let t = totals(dayItems)
            days.append(["weekday": Int(wd) ?? 0, "name": DAY_NAMES[Int(wd) ?? 0], "totals": t, "meals": meals])
        }
        return ["weekdays": "0=Sun … 6=Sat", "days": days]
    }

    func mcpDayLog(_ date: String) throws -> [String: Any] {
        let log = mealLog(date)
        var meals: [String: Any] = [:]
        var all: [PlanItem] = []
        for meal in MealKey.allCases {
            let items = log.items(meal)
            all.append(contentsOf: items)
            meals[meal.rawValue] = items.map { mcpItem($0) }
        }
        return ["date": date, "totals": totals(all), "meals": meals, "skipped": log.skipped]
    }

    func mcpContext() throws -> [String: Any] {
        let t = calorieTargets()
        let eaten = consumed(todayKey)
        return [
            "date": todayKey,
            "weekday": todayWeekday,
            "profile": [
                "height_cm": profile.heightCm as Any,
                "age": profile.resolvedAge as Any,
                "sex": fitnessProfile.sex.rawValue,
                "goal": fitnessProfile.goal.rawValue
            ],
            "goals": [
                "energy_kcal": t?.goalCalories ?? Int(fitnessProfile.calorieTargetKcal ?? 0),
                "protein_g": t?.proteinG ?? Int(fitnessProfile.proteinTargetG ?? 0),
                "carb_g": t?.carbG as Any,
                "fat_g": t?.fatG as Any
            ],
            "latest_weight_kg": latestWeightKg as Any,
            "today": ["energy_kcal": eaten.calories, "protein_g": eaten.protein],
            "today_plan": try mcpWeekPlan()
        ]
    }

    func mcpSetSlot(_ b: [String: Any]) throws {
        let meal = try mcpMeal(b.string("meal"))
        let wd = mcpWeekday(b)
        let foods = mcpFoods(b["foods"])
        setPlanMeal(weekday: wd, meal: meal, foods: foods)
    }

    func mcpAddSlot(_ b: [String: Any]) throws {
        let meal = try mcpMeal(b.string("meal"))
        addFoodToPlan(weekday: try mcpWeekdayChecked(b), meal: meal,
                      foodId: try mcpFoodID(b.string("food_id")), quantity: b.double("quantity") ?? 1)
    }

    func mcpClearSlot(_ b: [String: Any]) throws {
        clearPlanMeal(weekday: mcpWeekday(b), meal: try mcpMeal(b.string("meal")))
    }

    func mcpRemoveSlot(id: String) {
        for wd in WeekdayKeys.all {
            for meal in MealKey.allCases {
                if planItems(wd, meal).contains(where: { $0.id == id }) {
                    removePlanItem(weekday: wd, meal: meal, itemId: id)
                    return
                }
            }
        }
    }

    func mcpLogFood(_ b: [String: Any]) throws {
        let date = try mcpDate(b["logged_on"])
        let id = try mcpFoodID(b.string("food_id"))
        addFoodToMeal(date: date, meal: try mcpMeal(b.string("meal")),
                      foodId: id, quantity: b.double("quantity") ?? 1)
    }

    /// A `yyyy-MM-dd` key, or today. Rejects anything else.
    ///
    /// The schema types these as plain strings and they were used verbatim as
    /// dictionary keys, so `"2026-2-5"` wrote a day the app never reads back —
    /// `{"ok":true}`, and the meal was invisible forever. A malformed date on
    /// the planner path was worse: `weekdayKey` fell back to "0" and quietly
    /// overwrote Sunday.
    func mcpDate(_ raw: Any?) throws -> String {
        guard let s = (raw as? String).flatMap({ $0.isEmpty ? nil : $0 }) else { return todayKey }
        guard let d = Self.date(fromKey: s), Self.dateKey(d) == s else {
            throw AppState.badRequest("date must be yyyy-MM-dd, got \(s)")
        }
        return s
    }

    /// A food the library actually holds.
    ///
    /// It used to be passed straight through, so an id a model invented instead
    /// of taking from `search_foods` stored a row that resolves to nothing: the
    /// tool reported success, the entry rendered as "unknown", and it added zero
    /// calories to the day.
    func mcpFoodID(_ id: String) throws -> String {
        guard !id.isEmpty, food(id) != nil else {
            throw AppState.badRequest("no food with id \(id)")
        }
        return id
    }

    func mcpLogPlanned(_ b: [String: Any]) throws {
        let date = try mcpDate(b["date"])
        let meal = try mcpMeal(b.string("meal"))
        // Refuse rather than overwrite or no-op. `tick` ASSIGNS the planned
        // items over the meal, so calling this after logging lunch by hand
        // replaced what was actually eaten with the template — reported as
        // success. With nothing planned it wrote nothing at all, also reported
        // as success.
        guard !planItems(Self.weekdayKey(date), meal).isEmpty else {
            throw AppState.badRequest("nothing planned for \(meal.rawValue) on \(date)")
        }
        guard mealState(date, meal) != .logged else {
            throw AppState.badRequest("\(meal.rawValue) on \(date) is already logged")
        }
        tickMeal(date: date, meal: meal)
    }

    /// Create a food, or update only the fields the caller actually sent.
    ///
    /// It used to build a whole `Food` with `?? 0` defaults and hand that to
    /// `upsertFood`, which replaces the matched record wholesale — so
    /// `upsert_food({name:"Protein bar", energy_kcal:210})` on an existing food
    /// zeroed its protein, carbs, fat and fibre, reset the serving label and
    /// dropped its vitamins. Every meal ever logged references that food by id,
    /// so the whole history's protein retroactively fell to zero, and the tool
    /// answered `{id,name}` as if nothing had happened.
    func mcpUpsertFood(_ b: [String: Any]) throws -> [String: Any] {
        let name = b.string("name")
        guard !name.isEmpty else { throw AppState.badRequest("name required") }
        // Match across the whole library, not only custom foods — otherwise
        // upserting a seed food's name quietly created a second entry with the
        // same name.
        let existing = allFoods.first { Food.matchKey($0.name) == Food.matchKey(name) }
        var food = existing ?? Food(name: name, category: .other,
                                    servingLabel: "1 serving", perServing: .zero)
        food.name = name
        if let c = FoodCategory(rawValue: b.string("category")) { food.category = c }
        if let label = b["serving_label"] as? String, !label.isEmpty { food.servingLabel = label }
        if let v = b.double("energy_kcal") { food.perServing.calories = v }
        if let v = b.double("protein_g")   { food.perServing.protein = v }
        if let v = b.double("carb_g")      { food.perServing.carbs = v }
        if let v = b.double("fiber_g")     { food.perServing.fiber = v }
        if let v = b.double("fat_g")       { food.perServing.fats = v }
        if let v = b["vitamins"] as? String, !v.isEmpty { food.vitamins = v }
        let saved = upsertFood(food)
        return ["id": saved.id, "name": saved.name]
    }

    func mcpSetGoals(_ b: [String: Any]) {
        updateFitnessProfile { p in
            if let v = b.double("energy_kcal") { p.calorieTargetKcal = v }
            if let v = b.double("protein_g") { p.proteinTargetG = v }
        }
    }

    private func mcpFoods(_ raw: Any?) -> [(foodId: String, quantity: Double)] {
        guard let arr = raw as? [[String: Any]] else { return [] }
        return arr.compactMap { row in
            let id = (row["food_id"] as? String) ?? (row["foodId"] as? String) ?? ""
            guard !id.isEmpty else { return nil }
            let q = (row["quantity"] as? Double) ?? (row["quantity"] as? Int).map(Double.init) ?? 1
            return (id, q)
        }
    }

    private func mcpItem(_ it: PlanItem) -> [String: Any] {
        let f = food(it.foodId)
        let macros = f?.perServing.scaled(it.quantity)
        return [
            "id": it.id, "food_id": it.foodId, "name": f?.name ?? "unknown",
            "quantity": it.quantity, "kcal": macros?.calories ?? 0, "protein": macros?.protein ?? 0
        ]
    }

    private func totals(_ items: [PlanItem]) -> [String: Double] {
        let t = items.reduce(Macros.zero) { $0 + (food($1.foodId)?.perServing.scaled($1.quantity) ?? .zero) }
        return ["energy_kcal": t.calories, "protein_g": t.protein, "carb_g": t.carbs, "fat_g": t.fats, "fiber_g": t.fiber]
    }
}

private let WEEKDAY_OK: Set<String> = ["0", "1", "2", "3", "4", "5", "6"]
private let DAY_NAMES = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
#endif

#if os(iOS)
@MainActor
final class DietBridge {
    static let shared = DietBridge()
    func start(state: AppState) {}
    func stop() {}
}
#endif
