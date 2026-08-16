import Foundation

/// Per-food emoji so an egg is an egg, not a generic red fish.
enum FoodGlyph {
    static func emoji(name: String, category: FoodCategory) -> String {
        let n = name.lowercased()
        if n.contains("egg") { return "🥚" }
        if n.contains("chicken") || n.contains("broiler") { return "🍗" }
        if n.contains("mutton") || n.contains("lamb") || n.contains("goat") { return "🍖" }
        if n.contains("beef") || n.contains("steak") { return "🥩" }
        if n.contains("fish") || n.contains("salmon") || n.contains("tuna") || n.contains("prawn") || n.contains("shrimp") { return "🐟" }
        if n.contains("channa") || n.contains("chana") || n.contains("chickpea") || n.contains("dal") || n.contains("lentil") { return "🫘" }
        if n.contains("milk") { return "🥛" }
        if n.contains("curd") || n.contains("yogurt") || n.contains("yoghurt") { return "🥣" }
        if n.contains("cheese") || n.contains("paneer") { return "🧀" }
        if n.contains("coconut") { return "🥥" }
        if n.contains("banana") { return "🍌" }
        if n.contains("apple") { return "🍎" }
        if n.contains("mango") { return "🥭" }
        if n.contains("rice") || n.contains("biryani") || n.contains("idli") || n.contains("pongal") { return "🍚" }
        if n.contains("dosa") || n.contains("roti") || n.contains("chapati") || n.contains("naan") || n.contains("bread") { return "🍞" }
        if n.contains("oat") { return "🥣" }
        if n.contains("coffee") { return "☕" }
        if n.contains("tea") { return "🍵" }
        if n.contains("water") { return "💧" }
        if n.contains("salad") || n.contains("spinach") || n.contains("broccoli") { return "🥬" }
        if n.contains("avocado") { return "🥑" }
        if n.contains("nut") || n.contains("almond") || n.contains("peanut") { return "🥜" }
        if n.contains("pizza") || n.contains("burger") || n.contains("fries") { return "🍔" }
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
