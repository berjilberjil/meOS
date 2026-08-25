import SwiftUI

extension Color {
    /// Parse an "RRGGBB" (or "#RRGGBB") string into a Color via the existing hex init.
    init(hexString: String) {
        let s = hexString.hasPrefix("#") ? String(hexString.dropFirst()) : hexString
        self.init(hex: UInt32(s, radix: 16) ?? 0x9A9A9A)
    }
}

// Color(hexString:) + EventTag.color live here (not in EventsComponents.swift) —
// TodayView needs EventTag's color for the "next events" strip without pulling
// in the rest of this AppKit-heavy file (shared with iOS).
extension EventTag {
    var color: Color { Color(hexString: colorHex) }
}

// MARK: - Hues for model types
//
// The mapping lives here rather than on the models: `FitnessModels.swift` is
// Foundation-only and stays that way, so a colour never becomes a reason the
// data layer has to import SwiftUI.

extension MealKey {
    /// Colour of the meal, walked through the day: sunrise amber, midday orange,
    /// evening indigo, snacks pink.
    var hue: Hue {
        switch self {
        case .breakfast: return .amber
        case .lunch: return .orange
        case .dinner: return .indigo
        case .snacks: return .pink
        }
    }
}
