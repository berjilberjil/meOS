import SwiftUI

// Shared tab identity — used by both the macOS sidebar (MainView) and the iOS
// tab bar (iOS MainView) plus TodayView's "go to tab" links. Kept in Support/
// so every platform target sees the same enum.
enum NavTab: String, CaseIterable, Identifiable {
    case today, scan, events, fold, stuff, fitness, productivity, journal, notes, profile, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .today: return "Today"
        case .scan: return "Scan"
        case .events: return "Events"
        case .fold: return "Fold"
        case .stuff: return "Stuff"
        case .fitness: return "Fitness"
        case .productivity: return "Productivity"
        case .journal: return "Journal"
        case .notes: return "Notes"
        case .profile: return "Profile"
        case .settings: return "Settings"
        }
    }
    var icon: String {
        switch self {
        case .today: return "sun.max.fill"
        case .scan: return "viewfinder"
        case .events: return "calendar"
        case .fold: return "indianrupeesign.circle.fill"
        case .stuff: return "shippingbox.fill"
        case .fitness: return "figure.run"
        case .productivity: return "play.rectangle.fill"
        case .journal: return "book.closed.fill"
        case .notes: return "note.text"
        case .profile: return "person.crop.circle.fill"
        case .settings: return "gearshape.fill"
        }
    }
    var tint: Color {
        switch self {
        case .today:        return Palette.amber
        case .scan:         return Palette.teal
        case .events:       return Palette.purple
        case .fold:         return Palette.gold
        case .stuff:        return Palette.flame
        case .fitness:      return Palette.rose
        case .productivity: return Palette.blue
        case .journal:      return Palette.purple
        case .notes:        return Palette.ice
        case .profile:      return Palette.teal
        case .settings:     return Palette.muted
        }
    }
}

extension NavTab {
    /// Tabs the iOS bottom bar can show (mac's sidebar shows every case).
    static let iosTabs: [NavTab] = [.today, .fold, .scan, .fitness, .notes]

    /// Resolve a persisted launch-tab raw value, clamped to `allowed`. Unknown
    /// or disallowed values fall back to `.today`.
    static func resolveLaunch(_ raw: String?, allowed: [NavTab] = NavTab.allCases) -> NavTab {
        guard let raw, let t = NavTab(rawValue: raw), allowed.contains(t) else { return .today }
        return t
    }
}
