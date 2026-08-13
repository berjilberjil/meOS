import SwiftUI

extension Color {
    /// Parse an "RRGGBB" (or "#RRGGBB") string into a Color via the existing hex init.
    init(hexString: String) {
        let s = hexString.hasPrefix("#") ? String(hexString.dropFirst()) : hexString
        self.init(hex: UInt32(s, radix: 16) ?? 0x9A9A9A)
    }
}

extension EventTag {
    var color: Color { Color(hexString: colorHex) }
}

/// Visual identity for spending categories and the quality read — an SF Symbol
/// and a Palette colour each, so rows, chips, and breakdowns read at a glance.
/// Keeps the colourful, playful Duolingo feel without new asset files.
enum CatStyle {
    static func icon(_ c: String) -> String {
        switch c {
        case "food": return "fork.knife"
        case "groceries": return "cart.fill"
        case "transport": return "bus.fill"
        case "travel": return "airplane"
        case "shopping": return "bag.fill"
        case "gadgets": return "iphone"
        case "health": return "cross.case.fill"
        case "fitness": return "dumbbell.fill"
        case "bills": return "bolt.fill"
        case "rent": return "house.fill"
        case "subscriptions": return "arrow.trianglehead.2.clockwise.rotate.90"
        case "entertainment": return "film.fill"
        case "education": return "book.fill"
        case "editor": return "scissors"
        case "family": return "heart.fill"
        case "loan": return "indianrupeesign.circle.fill"
        case "investment": return "chart.line.uptrend.xyaxis"
        case "salary": return "banknote.fill"
        case "freelance": return "laptopcomputer"
        case "refund": return "arrow.uturn.left"
        default: return "square.grid.2x2.fill"
        }
    }

    static func color(_ c: String) -> Color {
        switch c {
        case "food", "bills", "loan": return Palette.amber
        case "groceries", "investment", "salary", "freelance", "refund": return Palette.green
        case "transport", "gadgets", "education": return Palette.blue
        case "travel", "subscriptions": return Palette.ice
        case "shopping", "rent", "entertainment": return Palette.purple
        case "health", "family": return Palette.red
        case "fitness", "editor": return Palette.flame
        default: return Palette.muted
        }
    }

    /// A friendlier display label for a few categories; otherwise capitalised.
    static func label(_ c: String) -> String {
        switch c {
        case "subscriptions": return "Subs"
        case "misc": return "Misc"
        default: return c.capitalized
        }
    }
}

extension TxnQuality {
    var label: String {
        switch self {
        case .useless: return "Useless"
        case .useful: return "Useful"
        case .investment: return "Investment"
        }
    }
    var short: String {
        switch self {
        case .useless: return "Waste"
        case .useful: return "Needed"
        case .investment: return "Invest"
        }
    }
    var color: Color {
        switch self {
        case .useless: return Palette.red
        case .useful: return Palette.green
        case .investment: return Palette.blue
        }
    }
    var icon: String {
        switch self {
        case .useless: return "hand.thumbsdown.fill"
        case .useful: return "checkmark.seal.fill"
        case .investment: return "arrow.up.forward.circle.fill"
        }
    }
}

extension HoldingType {
    var color: Color {
        switch self {
        case .stock: return Palette.blue
        case .mutualFund: return Palette.green
        case .etf: return Palette.purple
        case .gold: return Palette.amber
        case .crypto: return Palette.flame
        case .other: return Palette.muted
        }
    }
    var icon: String {
        switch self {
        case .stock: return "chart.bar.fill"
        case .mutualFund: return "chart.pie.fill"
        case .etf: return "square.stack.3d.up.fill"
        case .gold: return "seal.fill"
        case .crypto: return "bitcoinsign.circle.fill"
        case .other: return "circle.grid.2x2.fill"
        }
    }
}
