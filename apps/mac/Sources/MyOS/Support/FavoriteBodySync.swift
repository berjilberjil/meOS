import Foundation

/// One favorited camera roll shot, keyed by the calendar day it was taken.
struct FavoriteShot: Equatable {
    let id: String
    let day: String   // yyyy-MM-dd
}

/// Decides which Favorites photos should become daily body photos.
/// Pure — the PhotoKit fetch lives on iOS; this just picks.
enum FavoriteBodySync {
    /// A photo hearted today counts as today's progress shot, even if it was
    /// taken earlier. Otherwise use the capture day.
    static func day(created: String, modified: String?, today: String) -> String {
        if let modified, modified == today { return today }
        return created
    }

    /// `shots` must be newest-first. Every unimported favorite is kept — multiple
    /// hearts on the same day all show in Daily progress.
    static func picks(shots: [FavoriteShot], existingDays _: Set<String>, importedIds: Set<String>) -> [FavoriteShot] {
        shots.filter { !importedIds.contains($0.id) }
    }
}
