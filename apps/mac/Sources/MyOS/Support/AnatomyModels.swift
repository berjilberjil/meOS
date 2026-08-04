import Foundation

// Anatomy data (decodes GET /api/anatomy) — the real fitOS body map: front/back
// SVG outlines + per-muscle SVG paths, muscle groups, and activation rankings.
// Emoji `icon` fields are intentionally NOT decoded (no-emoji rule).

struct AnatomyData: Codable, Hashable {
    var front: AnatomySide
    var back: AnatomySide
    var groups: [AnatomyGroup]
    var activation: [String: [Activation]]

    init() { front = AnatomySide(); back = AnatomySide(); groups = []; activation = [:] }
    enum CodingKeys: String, CodingKey { case front, back, groups, activation }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        front      = try c.decodeIfPresent(AnatomySide.self, forKey: .front) ?? AnatomySide()
        back       = try c.decodeIfPresent(AnatomySide.self, forKey: .back) ?? AnatomySide()
        groups     = try c.decodeIfPresent([AnatomyGroup].self, forKey: .groups) ?? []
        activation = try c.decodeIfPresent([String: [Activation]].self, forKey: .activation) ?? [:]
    }
}

struct AnatomySide: Codable, Hashable {
    var viewBox: String = "0 0 724 1448"
    var outline: String = ""
    var muscles: [BodyMuscle] = []
}

struct BodyMuscle: Codable, Hashable {
    var slug: String
    var paths: [String]
}

struct AnatomyGroup: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var view: String      // "front" | "back"
    var slugs: [String]
    var blurb: String
    var muscles: [AnatomyMuscle]
    enum CodingKeys: String, CodingKey { case id, name, view, slugs, blurb, muscles }  // `icon` (emoji) ignored
}

struct AnatomyMuscle: Codable, Hashable {
    var name: String
    var what: String
    var train: String
}

struct Activation: Codable, Hashable {
    var name: String
    var percent: Double
}

/// Readable names for muscle slugs (used by the workout exercise cards).
enum MuscleSlug {
    static let names: [String: String] = [
        "chest": "Chest", "obliques": "Obliques", "abs": "Abs", "biceps": "Biceps",
        "triceps": "Triceps", "deltoids": "Shoulders", "forearm": "Forearms",
        "quadriceps": "Quads", "hamstring": "Hamstrings", "calves": "Calves",
        "trapezius": "Traps", "upper-back": "Lats & back", "lower-back": "Lower back", "gluteal": "Glutes"
    ]
    static func name(_ slug: String) -> String { names[slug] ?? slug.replacingOccurrences(of: "-", with: " ").capitalized }
}
