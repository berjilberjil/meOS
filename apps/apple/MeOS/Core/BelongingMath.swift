import Foundation

/// What you own — gadgets, clothes, home, books, wheels, other.
enum BelongingKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case gadgets, clothes, home, books, wheels, other
    var id: String { rawValue }
    var label: String {
        switch self {
        case .gadgets: return "Gadgets"
        case .clothes: return "Clothes"
        case .home:    return "Home"
        case .books:   return "Books"
        case .wheels:  return "Wheels"
        case .other:   return "Other"
        }
    }
    var icon: String {
        switch self {
        case .gadgets: return "headphones"
        case .clothes: return "tshirt.fill"
        case .home:    return "sofa.fill"
        case .books:   return "book.fill"
        case .wheels:  return "bicycle"
        case .other:   return "cube.fill"
        }
    }
    /// How long a typical item here should last before it has “paid for itself.”
    var defaultLifeDays: Int {
        switch self {
        case .gadgets: return 365 * 3
        case .clothes: return 365
        case .home:    return 365 * 5
        case .books:   return 365 * 4
        case .wheels:  return 365 * 5
        case .other:   return 365 * 2
        }
    }

    /// Hex used by the UI — kept here so tests can pin the mapping without SwiftUI.
    var tintHex: UInt32 {
        switch self {
        case .gadgets: return 0x4AA8FF
        case .clothes: return 0xB98CFF
        case .home:    return 0xFFC24B
        case .books:   return 0xFF8A3D
        case .wheels:  return 0x7FD1FF
        case .other:   return 0x56BB06
        }
    }
}

/// One thing you own. Prices are integer paise. Photo is optional JPEG base64.
struct BelongingItem: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var kind: BelongingKind
    var pricePaise: Int
    var boughtOn: String        // yyyy-MM-dd
    var lifeDays: Int
    var note: String
    var retired: Bool
    var photoBase64: String
    /// Built-in raw value (`gadgets`) or a custom category id.
    var categoryID: String
    /// Where it was bought — the Amazon/store product page. Empty when unknown.
    var link: String

    init(id: String = UUID().uuidString.lowercased(), name: String, kind: BelongingKind,
         pricePaise: Int, boughtOn: String, lifeDays: Int? = nil, note: String = "",
         retired: Bool = false, photoBase64: String = "", categoryID: String? = nil,
         link: String = "") {
        self.id = id; self.name = name; self.kind = kind
        self.pricePaise = max(0, pricePaise)
        self.boughtOn = boughtOn
        self.lifeDays = max(1, lifeDays ?? kind.defaultLifeDays)
        self.note = note; self.retired = retired
        self.photoBase64 = photoBase64
        self.categoryID = categoryID ?? kind.rawValue
        self.link = link.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, kind, pricePaise, boughtOn, lifeDays, note, retired, photoBase64, categoryID, link
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        kind = (try? c.decode(BelongingKind.self, forKey: .kind)) ?? .other
        pricePaise = max(0, (try? c.decode(Int.self, forKey: .pricePaise)) ?? 0)
        boughtOn = try c.decodeIfPresent(String.self, forKey: .boughtOn) ?? ""
        let decodedLife = (try? c.decode(Int.self, forKey: .lifeDays)) ?? kind.defaultLifeDays
        lifeDays = max(1, decodedLife)
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        retired = try c.decodeIfPresent(Bool.self, forKey: .retired) ?? false
        photoBase64 = try c.decodeIfPresent(String.self, forKey: .photoBase64) ?? ""
        categoryID = (try? c.decodeIfPresent(String.self, forKey: .categoryID)) ?? kind.rawValue
        // Added after the first items were saved — anything older has no link.
        link = (try? c.decodeIfPresent(String.self, forKey: .link)) ?? ""
    }
}

/// A Stuff shelf — built-in (gadgets, clothes, …) or one the user added.
struct BelongingCategory: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var icon: String
    var tintHex: UInt32
    var defaultLifeDays: Int

    init(id: String = UUID().uuidString.lowercased(), name: String, icon: String,
         tintHex: UInt32, defaultLifeDays: Int = 365 * 2) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespaces)
        self.icon = icon
        self.tintHex = tintHex
        self.defaultLifeDays = max(30, defaultLifeDays)
    }
}

extension BelongingKind {
    var asCategory: BelongingCategory {
        BelongingCategory(id: rawValue, name: label, icon: icon,
                          tintHex: tintHex, defaultLifeDays: defaultLifeDays)
    }
}

struct BelongingsState: Codable, Hashable {
    var items: [BelongingItem] = []
    /// Take-home pay, paise / month. Used to judge if ownership burn is healthy.
    var salaryPaise: Int = 40_000_00
    /// Extra shelves on top of the built-in six. Built-ins are never stored here.
    var categories: [BelongingCategory] = []

    enum CodingKeys: String, CodingKey { case items, salaryPaise, categories }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = (try? c.decode([BelongingItem].self, forKey: .items)) ?? []
        salaryPaise = (try? c.decode(Int.self, forKey: .salaryPaise)) ?? 40_000_00
        categories = (try? c.decode([BelongingCategory].self, forKey: .categories)) ?? []
    }
}

/// What Catherine extracted from a Stuff photo — a short product title, never a sentence.
struct BelongingGuess: Equatable {
    var name: String
    var categoryID: String
    var priceInr: Int
    var lifeMonths: Int
    var summary: String

    static func from(result r: ImageParseResult, allowed: [String]) -> BelongingGuess? {
        let raw = [r.name, r.object?.name, productFromBlurb(r.summary)]
        guard let name = raw.compactMap({ $0 }).map(cleanTitle).first(where: isProductTitle) else { return nil }
        var cat = (r.category ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        var price = Int(r.priceInr ?? 0)
        var months = r.lifeMonths ?? 0
        if let useful = r.object?.useful {
            if !allowed.contains(cat), let m = firstGroup(useful, #"category=([a-z0-9-]+)"#) { cat = m }
            if price <= 0, let m = firstGroup(useful, #"price_inr=(\d+)"#) { price = Int(m) ?? 0 }
            if months <= 0, let m = firstGroup(useful, #"life_months=(\d+)"#) { months = Int(m) ?? 0 }
        }
        if !allowed.contains(cat) { cat = inferCategory(name: name, allowed: allowed) }
        if price <= 0 { price = inferPriceInr(name: name, categoryID: cat) }
        if months <= 0 { months = inferLifeMonths(categoryID: cat) }
        return BelongingGuess(name: name, categoryID: cat, priceInr: price,
                              lifeMonths: months, summary: "\(name) · ~₹\(price)")
    }

    /// A title is a product name, not a scanner apology.
    static func isProductTitle(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, t.count <= 56 else { return false }
        let low = t.lowercased()
        let junk = ["no food", "could not", "couldn't", "unknown object", "the image",
                    "appears to", "was found", "try again", "not food", "food items"]
        if junk.contains(where: { low.contains($0) }) { return false }
        if t.contains(".") && t.split(whereSeparator: \.isWhitespace).count > 7 { return false }
        return true
    }

    static func cleanTitle(_ raw: String) -> String {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let r = t.range(of: #"show(?:s)? a[n]? "#, options: [.regularExpression, .caseInsensitive]) {
            t = String(t[r.upperBound...])
        }
        while let last = t.last, ".!,".contains(last) { t.removeLast() }
        t = t.trimmingCharacters(in: .whitespaces)
        let low = t.lowercased()
        if low.contains("cmf") && (low.contains("nothing") || low.contains("bud") || low.contains("audio")
                                   || low.contains("ear") || low.contains("electronic") || low.contains("device")) {
            return "CMF Buds"
        }
        return t
    }

    static func inferCategory(name: String, allowed: [String]) -> String {
        let n = name.lowercased()
        let map: [(String, [String])] = [
            ("gadgets", ["bud", "ear", "headphone", "airpod", "watch", "phone", "ipad",
                         "cable", "charger", "cmf", "nothing", "audio", "speaker", "mouse", "keyboard"]),
            ("clothes", ["tee", "shirt", "jean", "shoe", "sneaker", "jacket", "hoodie"]),
            ("wheels", ["bike", "activa", "scooter", "cycle", "helmet"]),
            ("books", ["book", "novel", "kindle"]),
            ("home", ["lamp", "sofa", "bottle", "mug", "kettle"])
        ]
        for (id, keys) in map where allowed.contains(id) {
            if keys.contains(where: { n.contains($0) }) { return id }
        }
        return allowed.contains("gadgets") ? "gadgets" : (allowed.first ?? "other")
    }

    static func inferPriceInr(name: String, categoryID: String) -> Int {
        let n = name.lowercased()
        if n.contains("cmf") && n.contains("bud") { return 2499 }
        if n.contains("airpod") { return 12900 }
        if n.contains("activa") { return 80000 }
        switch categoryID {
        case "gadgets": return 2500
        case "clothes": return 800
        case "wheels":  return 50000
        case "books":   return 400
        case "home":    return 1500
        default:        return 1000
        }
    }

    static func inferLifeMonths(categoryID: String) -> Int {
        switch categoryID {
        case "gadgets": return 36
        case "clothes": return 12
        case "wheels":  return 60
        case "books":   return 48
        case "home":    return 60
        default:        return 24
        }
    }

    private static func productFromBlurb(_ summary: String) -> String? {
        let t = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        if let r = t.range(of: #"show(?:s)? a[n]? "#, options: [.regularExpression, .caseInsensitive]) {
            return String(t[r.upperBound...])
        }
        return nil
    }

    private static func firstGroup(_ s: String, _ pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: s) else { return nil }
        return String(s[r])
    }
}

enum SpendHealth: String, Equatable {
    case good, tight, over
}

/// Pure ROI / daily-cost math. Price in paise.
enum BelongingMath {
    /// The payback window anything gets when nothing says otherwise. A gadget is
    /// the common case and three years is this app's own gadget life.
    static let defaultROIMonths = 36

    /// Months of expected life → the `lifeDays` actually stored. 30-day months,
    /// matching the Stuff editor's stepper exactly, so a value set by the MCP and
    /// one set by hand round-trip to the same number.
    static func lifeDays(months: Int) -> Int { max(1, months) * 30 }

    static func daysOwned(bought: String, today: String) -> Int {
        let inFmt = DateFormatter()
        inFmt.calendar = Calendar(identifier: .gregorian)
        inFmt.locale = Locale(identifier: "en_US_POSIX")
        inFmt.dateFormat = "yyyy-MM-dd"
        guard let a = inFmt.date(from: String(bought.prefix(10))),
              let b = inFmt.date(from: String(today.prefix(10))) else { return 1 }
        let d = Calendar(identifier: .gregorian).dateComponents([.day], from: a, to: b).day ?? 0
        return max(1, d + 1)
    }

    static func paisePerDay(price: Int, days: Int) -> Int {
        guard days > 0 else { return price }
        return (price + days / 2) / days
    }

    static func roiProgress(owned: Int, life: Int) -> Double {
        guard life > 0 else { return 1 }
        return min(1, Double(owned) / Double(life))
    }

    static func daysLeft(owned: Int, life: Int) -> Int {
        max(0, life - owned)
    }

    /// Planned monthly burn: each item costs `price / life` per day × 30.
    static func monthlyBurnPaise(items: [(price: Int, life: Int)]) -> Int {
        items.reduce(0) { $0 + paisePerDay(price: $1.price, days: max(1, $1.life)) * 30 }
    }

    /// < 50% of salary → good. Under salary → tight. At/over salary → over.
    static func health(monthlyBurn: Int, salary: Int) -> SpendHealth {
        guard salary > 0 else { return monthlyBurn == 0 ? .good : .over }
        if monthlyBurn * 2 <= salary { return .good }
        if monthlyBurn < salary { return .tight }
        return .over
    }

    static func snapshot(item: BelongingItem, today: String) -> BelongingSnapshot {
        let owned = daysOwned(bought: item.boughtOn, today: today)
        let life = max(1, item.lifeDays)
        return BelongingSnapshot(
            ownedDays: owned,
            actualPerDay: paisePerDay(price: item.pricePaise, days: owned),
            plannedPerDay: paisePerDay(price: item.pricePaise, days: life),
            progress: roiProgress(owned: owned, life: life),
            daysLeft: daysLeft(owned: owned, life: life)
        )
    }
}

struct BelongingSnapshot: Equatable {
    var ownedDays: Int
    var actualPerDay: Int
    var plannedPerDay: Int
    var progress: Double
    var daysLeft: Int
}

enum BelongingINR {
    /// Paise → ₹ string. Daily costs keep two decimals; totals stay whole rupees.
    static func format(_ paise: Int, decimals: Int = 0) -> String {
        let rupees = Double(paise) / 100.0
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_IN")
        f.minimumFractionDigits = decimals
        f.maximumFractionDigits = decimals
        return "₹" + (f.string(from: NSNumber(value: rupees)) ?? "0")
    }

    static func span(_ days: Int) -> String {
        if days <= 0 { return "Paid off" }
        if days < 30 { return "\(days)d left" }
        if days < 365 { return "\(days / 30) mo left" }
        let y = days / 365
        let m = (days % 365) / 30
        return m == 0 ? "\(y)y left" : "\(y)y \(m)mo left"
    }
}
