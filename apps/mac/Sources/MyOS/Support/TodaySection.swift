import SwiftUI

/// Persisted order for Today tab sections.
/// Stored as JSON in UserDefaults; decoded with any new sections appended at the end.
enum TodaySection: String, CaseIterable, Identifiable {
    case activity, intake, meals, workout, comingUp, bodyPhotos, watchLog, focus, news

    var id: String { rawValue }

    var label: String {
        switch self {
        case .activity: return "Activity"
        case .intake: return "Intake"
        case .meals: return "Meals"
        case .workout: return "Workout"
        case .comingUp: return "Coming Up"
        case .bodyPhotos: return "Body Photos"
        case .watchLog: return "Watch Log"
        case .focus: return "Today's Focus"
        case .news: return "News"
        }
    }

    var icon: String {
        switch self {
        case .activity: return "figure.walk"
        case .intake: return "flame.fill"
        case .meals: return "fork.knife"
        case .workout: return "dumbbell.fill"
        case .comingUp: return "calendar"
        case .bodyPhotos: return "camera.fill"
        case .watchLog: return "play.rectangle.fill"
        case .focus: return "checklist"
        case .news: return "newspaper.fill"
        }
    }

    /// The section's colour. Today is a stack of nine different cards, so nine
    /// different hues — the page is meant to read as a set of things, not as one
    /// long list.
    var hue: Hue {
        switch self {
        case .activity: return .green
        case .intake: return .orange
        case .meals: return .teal
        case .workout: return .blue
        case .comingUp: return .purple
        case .bodyPhotos: return .cyan
        case .watchLog: return .amber
        case .focus: return .pink
        case .news: return .indigo
        }
    }

    var tint: Color { hue.core }

    /// The three that answer "how is today going" get the saturated treatment;
    /// the rest are washed, or plain where colour would fight the content.
    var look: CardLook {
        switch self {
        case .activity, .intake, .workout: return .bold
        default: return .tinted
        }
    }

    var available: Bool { true }

    private static let defaultOrder: [TodaySection] = [
        .activity, .intake, .meals, .workout, .comingUp, .bodyPhotos, .watchLog, .focus, .news
    ]

    static let storageKey = "today.sectionOrder"

    /// Decoded once. `ordered()` is called from `TodayView.body`, which SwiftUI
    /// re-runs on every state change — and with Today paged by day there are
    /// three of those on screen at once. A UserDefaults read plus a JSON decode
    /// per pass is work happening exactly while a finger is moving.
    private static var cachedOrder: [TodaySection]?

    static func ordered() -> [TodaySection] {
        if let cachedOrder { return cachedOrder }
        let result = decodeOrder()
        cachedOrder = result
        return result
    }

    private static func decodeOrder() -> [TodaySection] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let ids = try? JSONDecoder().decode([String].self, from: data) else {
            return defaultOrder
        }
        var sections = ids.compactMap { TodaySection(rawValue: $0) }
        for s in TodaySection.allCases where !sections.contains(s) {
            sections.append(s)
        }
        return sections.filter(\.available)
    }

    static func save(_ sections: [TodaySection]) {
        cachedOrder = sections.filter(\.available)
        let ids = sections.map(\.rawValue)
        if let data = try? JSONEncoder().encode(ids) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
