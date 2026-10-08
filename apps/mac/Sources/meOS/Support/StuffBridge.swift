import Foundation

/// The Stuff (belongings / spending) half of the local MCP bridge.
///
/// Kept out of `DietBridge.swift` so that file stays about food; the HTTP
/// plumbing and the token check are shared, only the routes live here.
///
/// Everything is a pure translation between JSON and the same `AppState`
/// mutations the Stuff tab calls, so an item added by Catherine or an MCP client
/// is indistinguishable from one typed in by hand — and syncs the same way.

/// Body accessors, mirroring the private ones in `DietBridge.swift`. Both are
/// file-scoped, so the duplicate names don't collide.
private extension Dictionary where Key == String, Value == Any {
    func str(_ k: String) -> String {
        (self[k] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    func num(_ k: String) -> Int? {
        if let i = self[k] as? Int { return i }
        // Clamped: an MCP client or a model can hand over 1e21 — legal JSON,
        // legal Double, far outside Int64 — and `Int(_: Double)` traps there.
        if let d = self[k] as? Double {
            guard d.isFinite else { return nil }
            return Int(Swift.min(Swift.max(d.rounded(), -1e15), 1e15))
        }
        if let s = self[k] as? String { return Int(s.filter { $0.isNumber || $0 == "-" }) }
        return nil
    }
    func flag(_ k: String) -> Bool? {
        if let b = self[k] as? Bool { return b }
        if let s = self[k] as? String { return ["true", "yes", "1"].contains(s.lowercased()) }
        return nil
    }
}

extension AppState {

    // MARK: - Reads

    func mcpStuffCategories() -> [[String: Any]] {
        belongingCategories().map { c in
            ["id": c.id, "name": c.name, "icon": c.icon,
             "default_roi_months": max(1, c.defaultLifeDays / 30),
             "built_in": BelongingKind(rawValue: c.id) != nil]
        }
    }

    /// One item as JSON, with the ROI maths already worked out. The bill image is
    /// summarised as a flag — a base64 JPEG has no business in a tool result.
    func mcpStuffItem(_ item: BelongingItem) -> [String: Any] {
        let snap = BelongingMath.snapshot(item: item, today: todayKey)
        return [
            "id": item.id,
            "name": item.name,
            "link": item.link,
            "category": item.categoryID,
            "category_name": belongingCategory(for: item).name,
            "price_inr": item.pricePaise / 100,
            "price_paise": item.pricePaise,
            "bought_on": item.boughtOn,
            "roi_months": max(1, item.lifeDays / 30),
            "note": item.note,
            "retired": item.retired,
            "has_bill": !item.photoBase64.isEmpty,
            "roi": [
                "days_owned": snap.ownedDays,
                "progress": snap.progress,
                "days_left": snap.daysLeft,
                "paid_off": snap.daysLeft == 0,
                "cost_per_day_inr": Double(snap.actualPerDay) / 100.0,
                "planned_per_day_inr": Double(snap.plannedPerDay) / 100.0
            ]
        ]
    }

    func mcpStuffList(q: String, categoryID: String, limit: Int, includeRetired: Bool) -> [[String: Any]] {
        var items = belongings.items
        if !includeRetired { items = items.filter { !$0.retired } }
        if !categoryID.isEmpty {
            let cat = categoryID.lowercased()
            items = items.filter { $0.categoryID.lowercased() == cat }
        }
        if !q.isEmpty {
            items = items.filter {
                $0.name.localizedCaseInsensitiveContains(q)
                    || $0.note.localizedCaseInsensitiveContains(q)
                    || $0.link.localizedCaseInsensitiveContains(q)
            }
        }
        return items
            .sorted { $0.boughtOn > $1.boughtOn }
            .prefix(max(1, min(limit, 200)))
            .map { mcpStuffItem($0) }
    }

    /// What the money is doing: what's owned, what it burns a month, and whether
    /// that's healthy against take-home pay. Same maths the Stuff tab shows.
    func mcpStuffSummary() -> [String: Any] {
        let live = belongings.items.filter { !$0.retired }
        let spent = live.reduce(0) { $0 + $1.pricePaise }
        let burn = BelongingMath.monthlyBurnPaise(items: live.map { (price: $0.pricePaise, life: $0.lifeDays) })
        let health = BelongingMath.health(monthlyBurn: burn, salary: belongings.salaryPaise)

        var byCategory: [[String: Any]] = []
        for cat in belongingCategories() {
            let owned = live.filter { $0.categoryID == cat.id }
            guard !owned.isEmpty else { continue }
            byCategory.append([
                "id": cat.id,
                "name": cat.name,
                "count": owned.count,
                "spent_inr": owned.reduce(0) { $0 + $1.pricePaise } / 100
            ])
        }
        return [
            "today": todayKey,
            "item_count": live.count,
            "retired_count": belongings.items.count - live.count,
            "total_spent_inr": spent / 100,
            "monthly_burn_inr": burn / 100,
            "salary_inr": belongings.salaryPaise / 100,
            "health": health.rawValue,
            "paid_off_count": live.filter {
                BelongingMath.snapshot(item: $0, today: todayKey).daysLeft == 0
            }.count,
            "by_category": byCategory.sorted { ($0["spent_inr"] as? Int ?? 0) > ($1["spent_inr"] as? Int ?? 0) }
        ]
    }

    // MARK: - Writes

    /// Resolve whatever the caller called the category into a real shelf id.
    /// Accepts an id ("gadgets"), a display name ("Gadgets"), or nothing at all —
    /// in which case the product name decides, using the same guesser the photo
    /// scanner uses.
    func mcpStuffCategoryID(_ raw: String, name: String) -> String {
        let cats = belongingCategories()
        let want = raw.lowercased()
        if !want.isEmpty {
            if let hit = cats.first(where: { $0.id.lowercased() == want }) { return hit.id }
            if let hit = cats.first(where: { $0.name.lowercased() == want }) { return hit.id }
        }
        return BelongingGuess.inferCategory(name: name, allowed: cats.map(\.id))
    }

    /// Add a purchase. `name` is the only hard requirement — everything else has
    /// a sane default, because the usual caller is an assistant reading a receipt
    /// screenshot and it will not always find every field.
    func mcpStuffAdd(_ b: [String: Any]) throws -> [String: Any] {
        let name = b.str("name")
        guard !name.isEmpty else {
            throw NSError(domain: "StuffBridge", code: 400,
                          userInfo: [NSLocalizedDescriptionKey: "name is required"])
        }
        let catID = mcpStuffCategoryID(b.str("category"), name: name)
        let months = b.num("roi_months") ?? BelongingMath.defaultROIMonths
        let paise = b.num("price_paise") ?? ((b.num("price_inr") ?? 0) * 100)
        let bought = b.str("bought_on").isEmpty ? todayKey : String(b.str("bought_on").prefix(10))

        let item = BelongingItem(
            name: name,
            kind: BelongingKind(rawValue: catID) ?? .other,
            pricePaise: max(0, paise),
            boughtOn: bought,
            lifeDays: BelongingMath.lifeDays(months: months),
            note: b.str("note"),
            photoBase64: Self.stuffBill(b),
            categoryID: catID,
            link: b.str("link")
        )
        addBelonging(item)
        return mcpStuffItem(item)
    }

    func mcpStuffUpdate(_ b: [String: Any]) throws -> [String: Any] {
        let id = b.str("id")
        guard let i = belongings.items.firstIndex(where: { $0.id == id }) else {
            throw NSError(domain: "StuffBridge", code: 404,
                          userInfo: [NSLocalizedDescriptionKey: "no item with id \(id)"])
        }
        var item = belongings.items[i]
        if !b.str("name").isEmpty { item.name = b.str("name") }
        if !b.str("link").isEmpty { item.link = b.str("link") }
        if !b.str("note").isEmpty { item.note = b.str("note") }
        if !b.str("bought_on").isEmpty { item.boughtOn = String(b.str("bought_on").prefix(10)) }
        if let months = b.num("roi_months") { item.lifeDays = BelongingMath.lifeDays(months: months) }
        if let paise = b.num("price_paise") { item.pricePaise = max(0, paise) }
        else if let inr = b.num("price_inr") { item.pricePaise = max(0, inr * 100) }
        if !b.str("category").isEmpty {
            let catID = mcpStuffCategoryID(b.str("category"), name: item.name)
            item.categoryID = catID
            item.kind = BelongingKind(rawValue: catID) ?? .other
        }
        if let retired = b.flag("retired") { item.retired = retired }
        let bill = Self.stuffBill(b)
        if !bill.isEmpty { item.photoBase64 = bill }
        updateBelonging(item)
        return mcpStuffItem(item)
    }

    /// The bill screenshot, downscaled before it goes anywhere near the state
    /// blob — every byte here is encrypted, synced to every device and kept
    /// forever, so a 4 MB receipt PNG would be a permanent tax on every sync.
    private static func stuffBill(_ b: [String: Any]) -> String {
        let raw = b.str("bill_image_base64")
        guard !raw.isEmpty else { return "" }
        let cleaned = raw.contains(",") ? String(raw.split(separator: ",").last ?? "") : raw
        guard let data = Data(base64Encoded: cleaned, options: .ignoreUnknownCharacters) else { return "" }
        guard let small = MediaJPEG.downscale(data, maxSide: 1280, quality: 0.7) else {
            return data.base64EncodedString()
        }
        return small.base64EncodedString()
    }
}
