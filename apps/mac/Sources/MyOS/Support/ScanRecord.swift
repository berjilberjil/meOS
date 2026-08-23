import Foundation

/// One saved camera scan. The verdict rides the synced blob so both devices see
/// the history; the photo lives in R2 under `photoKey`, sealed with the vault DEK
/// exactly like event media (same endpoint, `scan-` prefixed ids).
struct ScanRecord: Codable, Identifiable, Hashable {
    struct Food: Codable, Hashable {
        var name: String
        var serving: String
        var calories: Double
        var protein: Double
        var carbs: Double
        var fats: Double
        var detail: String
    }

    struct Object: Codable, Hashable {
        var name: String
        var needed: String      // yes | no | maybe
        var why: String
        var useful: String
    }

    var id: String
    var at: String              // yyyy-MM-dd'T'HH:mm:ss
    var date: String            // yyyy-MM-dd
    var kind: String            // food | object
    var summary: String
    var foods: [Food]
    var object: Object?
    /// nil while the upload is in flight, or if it failed — the row still shows,
    /// just without a thumbnail.
    var photoKey: String?
    /// Food only: whether it was logged into a meal from the result card.
    var logged: Bool

    /// How many scans are kept. Text-only records are tiny, but the list is
    /// append-forever otherwise and it all rides one sync payload.
    static let cap = 300

    init(id: String, at: String, date: String, kind: String, summary: String,
         foods: [Food] = [], object: Object? = nil, photoKey: String? = nil, logged: Bool = false) {
        self.id = id; self.at = at; self.date = date; self.kind = kind
        self.summary = summary; self.foods = foods; self.object = object
        self.photoKey = photoKey; self.logged = logged
    }

    enum CodingKeys: String, CodingKey { case id, at, date, kind, summary, foods, object, photoKey, logged }

    /// Tolerant on purpose: a record written by an older build (or a half-failed
    /// upload) is still worth showing.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        at = try c.decodeIfPresent(String.self, forKey: .at) ?? ""
        date = try c.decodeIfPresent(String.self, forKey: .date) ?? String(at.prefix(10))
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "object"
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        foods = try c.decodeIfPresent([Food].self, forKey: .foods) ?? []
        object = try c.decodeIfPresent(Object.self, forKey: .object)
        photoKey = try c.decodeIfPresent(String.self, forKey: .photoKey)
        logged = try c.decodeIfPresent(Bool.self, forKey: .logged) ?? false
    }

    // MARK: - Conversion

    init(_ insight: ScanInsight, id: String, at: String, date: String,
         photoKey: String? = nil, logged: Bool = false) {
        self.init(id: id, at: at, date: date,
                  kind: insight.kind.rawValue,
                  summary: insight.summary,
                  foods: insight.foods.map {
                      Food(name: $0.name, serving: $0.serving, calories: $0.calories,
                           protein: $0.protein, carbs: $0.carbs, fats: $0.fats, detail: $0.detail)
                  },
                  object: insight.object.map {
                      Object(name: $0.name, needed: $0.needed.rawValue, why: $0.why, useful: $0.useful)
                  },
                  photoKey: photoKey, logged: logged)
    }

    /// Back to the shape the result card already knows how to draw, so history
    /// detail and a fresh scan render through one code path.
    var insight: ScanInsight {
        ScanInsight(kind: kind == "food" ? .food : .object,
                    summary: summary,
                    foods: foods.map {
                        ScanInsight.Food(name: $0.name, serving: $0.serving, calories: $0.calories,
                                         protein: $0.protein, carbs: $0.carbs, fats: $0.fats,
                                         detail: $0.detail)
                    },
                    object: object.map {
                        ScanInsight.Object(name: $0.name,
                                           needed: ScanInsight.Needed(rawValue: $0.needed) ?? .maybe,
                                           why: $0.why, useful: $0.useful)
                    })
    }

    // MARK: - Display

    var isFood: Bool { kind == "food" }

    /// The row's headline — the thing scanned, not the sentence about it.
    var title: String {
        if isFood, let first = foods.first, !first.name.isEmpty {
            return foods.count > 1 ? "\(first.name) +\(foods.count - 1)" : first.name
        }
        if let n = object?.name, !n.isEmpty { return n }
        return summary.isEmpty ? "Scan" : summary
    }

    var calories: Double { foods.reduce(0) { $0 + $1.calories } }

    /// The pill on the right of a history row.
    var badge: String {
        if isFood { return "\(Int(calories.rounded())) kcal" }
        switch object?.needed {
        case "yes": return "Wanted"
        case "no":  return "Not wanted"
        default:    return "Maybe"
        }
    }

    // MARK: - Dates

    /// What a history row shows: "Today" / "Yesterday" / "12 Aug".
    static func dayLabel(_ date: String, today: String) -> String {
        if date == today { return "Today" }
        if date == shift(today, by: -1) { return "Yesterday" }
        return pretty(date)
    }

    /// POSIX/gregorian on purpose — `Calendar.current` on a key string is how
    /// day math drifts across timezones.
    private static func shift(_ key: String, by days: Int) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: key),
              let moved = f.calendar.date(byAdding: .day, value: days, to: d) else { return key }
        return f.string(from: moved)
    }

    private static func pretty(_ key: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: key) else { return key }
        let out = DateFormatter()
        out.locale = Locale(identifier: "en_US_POSIX")
        out.dateFormat = "d MMM"
        return out.string(from: d)
    }

    // MARK: - List rules

    /// Newest first, capped. Adding is its own function so the cap can never be
    /// forgotten at a call site.
    static func adding(_ record: ScanRecord, to list: [ScanRecord]) -> [ScanRecord] {
        var out = list.filter { $0.id != record.id }
        out.insert(record, at: 0)
        if out.count > cap { out = Array(out.prefix(cap)) }
        return out
    }

    /// The R2 objects a set of removed records leaves behind.
    static func orphanedKeys(_ removed: [ScanRecord]) -> [String] {
        removed.compactMap(\.photoKey).filter { !$0.isEmpty }
    }
}
