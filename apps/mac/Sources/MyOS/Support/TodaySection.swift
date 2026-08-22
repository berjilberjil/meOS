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

    var tint: Color {
        switch self {
        case .activity: return Palette.green
        case .intake: return Palette.flame
        case .meals: return Palette.teal
        case .workout: return Palette.blue
        case .comingUp: return Palette.purple
        case .bodyPhotos: return Palette.ice
        case .watchLog: return Palette.amber
        case .focus: return Palette.teal
        case .news: return Palette.blue
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
