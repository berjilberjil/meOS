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
        do {
            switch (req.method, req.path) {
            case ("GET", "/health"):
                return HTTPRes(200, #"{"ok":true,"native":true}"#)
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
                contentLength = Int(line.split(separator: ":")[1].trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }
        let bodyStart = range.upperBound
        if data.count - bodyStart < contentLength { return nil }
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
                "age": profile.age as Any,
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
        addFoodToPlan(weekday: mcpWeekday(b), meal: meal, foodId: b.string("food_id"), quantity: b.double("quantity") ?? 1)
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
        let date = (b["logged_on"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? todayKey
        addFoodToMeal(date: date, meal: try mcpMeal(b.string("meal")), foodId: b.string("food_id"), quantity: b.double("quantity") ?? 1)
    }

    func mcpLogPlanned(_ b: [String: Any]) throws {
        let date = (b["date"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? todayKey
        tickMeal(date: date, meal: try mcpMeal(b.string("meal")))
    }

    func mcpUpsertFood(_ b: [String: Any]) throws -> [String: Any] {
        let food = Food(
            name: b.string("name"),
            category: FoodCategory(rawValue: b.string("category")) ?? .other,
            servingLabel: b["serving_label"] as? String ?? "1 serving",
            perServing: Macros(
                calories: b.double("energy_kcal") ?? 0,
                protein: b.double("protein_g") ?? 0,
                carbs: b.double("carb_g") ?? 0,
                fiber: b.double("fiber_g") ?? 0,
                fats: b.double("fat_g") ?? 0
            )
        )
        let saved = addFood(food)
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
