import SwiftUI

/// Persisted order for Today tab sections.
/// Stored as JSON in UserDefaults; decoded with any new sections appended at the end.
enum TodaySection: String, CaseIterable, Identifiable {
    /// `focusNow` is the activity-intelligence card. `activity` predates it and
    /// is about *walking* — the two were both called "Activity", which is why
    /// the older one now reads as "Steps".
    case focusNow, activity, intake, meals, workout, comingUp, bodyPhotos, watchLog, focus, news

    var id: String { rawValue }

    var label: String {
        switch self {
        case .focusNow: return "Activity"
        case .activity: return "Steps"
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
        case .focusNow: return "timer"
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

    /// The accent this section has earned, by meaning — not by position in the
    /// list. Nine sections do NOT get nine colours: activity, food, fitness and
    /// completion are green, events and information are blue, and anything
    /// without a semantic claim stays uncoloured. Nothing on Today is orange —
    /// orange is reserved for what has gone wrong.
    var accent: Accent {
        switch self {
        case .focusNow:   return .activity
        case .activity:   return .green    // fitness
        // Intake is the one *filled* card on Today — a solid block of the app's
        // colour. Its weight comes from being the only filled card, not from
        // being a different hue: orange there read as a warning, which is the
        // one job orange has.
        case .intake:     return .nutrition
        case .meals:      return .nutrition
        case .workout:    return .green    // fitness
        case .bodyPhotos: return .green    // fitness
        case .focus:      return .green    // completion
        case .comingUp:   return .blue     // events
        case .news:       return .blue     // information
        case .watchLog:   return .none
        }
    }

    var tint: Color { accent.tint }

    var available: Bool { true }

    private static let defaultOrder: [TodaySection] = [
        .focusNow, .activity, .intake, .meals, .workout, .comingUp, .bodyPhotos, .watchLog, .focus, .news
    ]

    /// Sections that belong at the top when they first appear, rather than at
    /// the bottom where a newly-added case would otherwise land. Today's whole
    /// job is "what should I know right now", and an answer to that below the
    /// fold is not an answer.
    private static let pinnedToTop: Set<TodaySection> = [.focusNow]

    static let storageKey = "today.sectionOrder"

    /// Decoded once. `ordered()` is called from `TodayView.body`, which SwiftUI
    /// re-runs on every state change — and with Today paged by day there are
    /// three of those on screen at once. A UserDefaults read plus a JSON decode
    /// per pass is work happening exactly while a finger is moving.
    private static var cachedOrder: [TodaySection]?

    /// Bumped whenever the order changes, so views can observe it.
    @MainActor
    final class OrderSignal: ObservableObject {
        static let shared = OrderSignal()
        @Published var version = 0
    }

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
            if pinnedToTop.contains(s) { sections.insert(s, at: 0) } else { sections.append(s) }
        }
        return sections.filter(\.available)
    }

    static func save(_ sections: [TodaySection]) {
        cachedOrder = sections.filter(\.available)
        let ids = sections.map(\.rawValue)
        if let data = try? JSONEncoder().encode(ids) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
        // Tell the view. `ordered()` is a plain function call that SwiftUI has
        // no dependency on, so saving a new order changed nothing on screen
        // until some unrelated publish happened to re-run the body — a sync
        // tick, or a relaunch. Dragging Meals above Steps simply read as
        // "didn't work".
        Task { @MainActor in OrderSignal.shared.version &+= 1 }
    }
}
