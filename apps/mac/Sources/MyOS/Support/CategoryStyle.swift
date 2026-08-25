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

// MARK: - Accents for model types
//
// Deliberately thin. Meals used to be amber / orange / indigo / pink, which is
// exactly the "collection of unrelated widgets" problem — breakfast and dinner
// are the same kind of thing and belong to the same visual system.

extension MealKey {
    /// Every meal is nutrition, and nutrition is orange.
    var accent: Accent { .orange }
}
