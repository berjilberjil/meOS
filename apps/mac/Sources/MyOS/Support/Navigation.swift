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
    /// The tab's colour. It paints the whole screen behind the tab's cards, so
    /// moving between tabs reads as moving between rooms — which is the point of
    /// having eleven of them.
    var hue: Hue {
        switch self {
        case .today:        return .amber
        case .scan:         return .teal
        case .events:       return .purple
        case .fold:         return .green
        case .stuff:        return .orange
        case .fitness:      return .pink
        case .productivity: return .blue
        case .journal:      return .purple
        case .notes:        return .cyan
        case .profile:      return .teal
        case .settings:     return .indigo
        }
    }

    var tint: Color { hue.core }
}

extension NavTab {
    /// Tabs the iOS bottom bar can show (mac's sidebar shows every case).
    static let iosTabs: [NavTab] = [.today, .productivity, .scan, .fitness, .notes]

    /// Resolve a persisted launch-tab raw value, clamped to `allowed`. Unknown
    /// or disallowed values fall back to `.today`.
    static func resolveLaunch(_ raw: String?, allowed: [NavTab] = NavTab.allCases) -> NavTab {
        guard let raw, let t = NavTab(rawValue: raw), allowed.contains(t) else { return .today }
        return t
    }
}
