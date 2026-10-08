import Foundation

/// What a camera scan decided — a plate of food, or some other object we
/// should keep or skip. Pure so Gemini's JSON can be unit-tested without a
/// network hop.
struct ScanInsight: Equatable {
    enum Kind: String, Equatable { case food, object }
    enum Needed: String, Equatable { case yes, no, maybe }

    struct Food: Equatable {
        var name: String
        var serving: String
        var calories: Double
        var protein: Double
        var carbs: Double
        var fats: Double
        var detail: String
    }

    struct Object: Equatable {
        var name: String
        var needed: Needed
        var why: String
        var useful: String
    }

    var kind: Kind
    var summary: String
    var foods: [Food]
    var object: Object?

    /// True when the model (or a network miss) did not actually identify anything.
    var failed: Bool {
        if kind == .food { return foods.isEmpty || foods.allSatisfy({ $0.name == "Food" && $0.calories == 0 }) }
        let n = (object?.name ?? "").trimmingCharacters(in: .whitespaces)
        return n.isEmpty || n.lowercased() == "unknown object" || n.lowercased() == "unknown"
    }

    static func from(_ r: ImageParseResult) -> ScanInsight {
        var dict: [String: Any] = ["kind": r.kind ?? (r.foods?.isEmpty == false ? "food" : "object"),
                                   "summary": r.summary]
        if let foods = r.foods {
            dict["foods"] = foods.map { f -> [String: Any] in
                ["name": f.name, "servingLabel": f.servingLabel, "calories": f.calories,
                 "protein": f.protein, "carbs": f.carbs, "fats": f.fats, "vitamins": f.vitamins ?? ""]
            }
        }
        if let o = r.object {
            dict["object"] = ["name": o.name, "needed": o.needed, "why": o.why, "useful": o.useful]
        }
        return parse(dict)
    }

    static func parse(_ raw: Any?) -> ScanInsight {
        guard let dict = raw as? [String: Any] else {
            return ScanInsight(kind: .object, summary: "Could not read that photo.",
                               foods: [], object: Object(name: "Unknown object", needed: .maybe,
                                                         why: "Could not tell from the photo.", useful: ""))
        }
        let kindRaw = (dict["kind"] as? String)?.lowercased()
        if kindRaw == "food" {
            let foods = (dict["foods"] as? [[String: Any]] ?? []).map { f in
                Food(name: str(f["name"], "Food"),
                     serving: str(f["servingLabel"], str(f["serving"], "1 serving")),
                     calories: num(f["calories"] ?? f["energy_kcal"]),
                     protein: num(f["protein"] ?? f["protein_g"]),
                     carbs: num(f["carbs"] ?? f["carb_g"]),
                     fats: num(f["fats"] ?? f["fat_g"]),
                     detail: str(f["vitamins"], ""))
            }
            return ScanInsight(kind: .food,
                               summary: str(dict["summary"], foods.first?.name ?? "Food"),
                               foods: foods.isEmpty ? [Food(name: "Food", serving: "1 serving",
                                                            calories: 0, protein: 0, carbs: 0, fats: 0, detail: "")] : foods,
                               object: nil)
        }
        let obj = dict["object"] as? [String: Any] ?? dict
        let neededRaw = (obj["needed"] as? String)?.lowercased()
        let needed: Needed = (neededRaw == "yes" || neededRaw == "no") ? Needed(rawValue: neededRaw!)! : .maybe
        return ScanInsight(kind: .object,
                           summary: str(dict["summary"], str(obj["name"], "Object")),
                           foods: [],
                           object: Object(name: str(obj["name"], "Unknown object"),
                                          needed: needed,
                                          why: str(obj["why"], "Could not tell from the photo."),
                                          useful: str(obj["useful"], "")))
    }

    private static func str(_ v: Any?, _ fallback: String) -> String {
        if let s = v as? String, !s.trimmingCharacters(in: .whitespaces).isEmpty { return s }
        return fallback
    }
    /// Bounded at the parse boundary.
    ///
    /// These arrive from a model through a schema that only says `z.number()`,
    /// and the record is written into `meos.scans` and synced before anything
    /// formats it — so a single absurd row made `ScanRecord.badge` trap on
    /// `Int(_:)` on every render of the scan history, on both devices, for good.
    private static func num(_ v: Any?) -> Double {
        var out: Double?
        if let d = v as? Double { out = d }
        else if let i = v as? Int { out = Double(i) }
        else if let s = v as? String, let d = Double(s) { out = d }
        guard let value = out, value.isFinite else { return 0 }
        return min(max(value, 0), 100_000)
    }
}
