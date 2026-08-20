import Foundation

/// Per-food emoji so an egg is an egg, not a generic red fish.
enum FoodGlyph {
    static func emoji(name: String, category: FoodCategory) -> String {
        let n = name.lowercased()
        if n.contains("egg") { return "🥚" }
        if n.contains("chicken") || n.contains("broiler") || n.contains("65") { return "🍗" }
        if n.contains("mutton") || n.contains("lamb") || n.contains("goat") { return "🍖" }
        if n.contains("beef") || n.contains("steak") { return "🥩" }
        if n.contains("fish") || n.contains("salmon") || n.contains("tuna")
            || n.contains("prawn") || n.contains("shrimp") || n.contains("nethili")
            || n.contains("vanjaram") || n.contains("sardine") { return "🐟" }
        if n.contains("channa") || n.contains("chana") || n.contains("chickpea")
            || n.contains("dal") || n.contains("lentil") || n.contains("paruppu")
            || n.contains("sambar") || n.contains("rasam") || n.contains("kootu") { return "🫘" }
        if n.contains("soya") { return "🫘" }
        if n.contains("milk") && !n.contains("coconut") { return "🥛" }
        if n.contains("curd") || n.contains("yogurt") || n.contains("yoghurt")
            || n.contains("buttermilk") || n.contains("jigarthanda") { return "🥣" }
        if n.contains("cheese") || n.contains("paneer") { return "🧀" }
        if n.contains("coconut") { return "🥥" }
        if n.contains("banana") { return "🍌" }
        if n.contains("apple") { return "🍎" }
        if n.contains("mango") { return "🥭" }
        if n.contains("date") { return "🌴" }
        if n.contains("idli") || n.contains("idiyappam") || n.contains("puttu")
            || n.contains("appam") || n.contains("pongal") { return "🍚" }
        if n.contains("rice") || n.contains("biryani") || n.contains("puliyodarai") { return "🍚" }
        if n.contains("dosa") || n.contains("uttapam") || n.contains("pesarattu") { return "🥞" }
        if n.contains("roti") || n.contains("chapati") || n.contains("naan")
            || n.contains("parotta") || n.contains("paratha") || n.contains("bread") { return "🫓" }
        if n.contains("oat") || n.contains("upma") || n.contains("poha") { return "🥣" }
        if n.contains("coffee") { return "☕" }
        if n.contains("tea") { return "🍵" }
        if n.contains("water") { return "💧" }
        if n.contains("salad") || n.contains("spinach") || n.contains("broccoli")
            || n.contains("poriyal") || n.contains("aviyal") || n.contains("keerai")
            || n.contains("cabbage") || n.contains("beans") || n.contains("chutney") { return "🥬" }
        if n.contains("potato") || n.contains("sweet potato") { return "🥔" }
        if n.contains("avocado") { return "🥑" }
        if n.contains("nut") || n.contains("almond") || n.contains("peanut") { return "🥜" }
        if n.contains("vada") || n.contains("bajji") || n.contains("samosa")
            || n.contains("puff") || n.contains("panipuri") { return "🥟" }
        if n.contains("pizza") || n.contains("burger") || n.contains("fries")
            || n.contains("shawarma") { return "🍔" }
        if n.contains("jamun") || n.contains("sweet") { return "🍬" }
        if n.contains("soft drink") || n.contains("rose milk") { return "🥤" }
        if n.contains("whey") || n.contains("protein") { return "🍶" }
        if n.contains("ragi") { return "🟤" }
        switch category {
        case .protein: return "🥩"
        case .carb: return "🍞"
        case .veg: return "🥬"
        case .dairy: return "🥛"
        case .fruit: return "🍎"
        case .drink: return "🥤"
        case .junk: return "🍔"
        case .other: return "🍽️"
        }
    }
}

/// Normalize serving labels for display so the library reads as one system
/// (volume in ml, mass in g, countable units kept as-is).
enum FoodServing {
    static func display(_ label: String) -> String {
        let t = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = t.lowercased()
        if lower == "1 glass" || lower == "1 tumbler" { return "240 ml" }
        if lower == "1 scoop" { return "1 scoop (≈30 g)" }
        if lower == "1 serving" { return "1 serving" }
        return t
    }
}
