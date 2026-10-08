import UniformTypeIdentifiers

/// Shared rules for turning a Photos/Files pick into event media.
///
/// The iOS editor must not host SwiftUI `PhotosPicker` inside a view that
/// observes `AppState`. Live-sync ticks every 1.5s and remounts that picker,
/// which reloads the library and drops whatever you had tapped. Kind
/// classification lives here so Mac tests can pin photos *and* videos
/// without UIKit.
enum EventMediaImport {
    static let maxSelection = 8

    static func kind(typeIdentifier: String) -> EventMedia.Kind? {
        guard let type = UTType(typeIdentifier) else { return nil }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        return nil
    }
}
