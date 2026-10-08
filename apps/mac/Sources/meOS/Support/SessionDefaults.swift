import Foundation

/// The two UserDefaults keys that record "this device has a live meOS session".
/// Shared because both `AppState` (the UI) and `EventIntentStore` (Siri, which
/// runs headlessly with no UI) need to read the same session — duplicating the
/// literals would let them drift apart silently.
enum SessionDefaults {
    static let active   = "myos.session.active"
    static let username = "myos.session.username"

    /// The signed-in username on this device, or nil if there's no live session.
    static var currentUsername: String? {
        let d = UserDefaults.standard
        guard d.bool(forKey: active),
              let u = d.string(forKey: username), !u.isEmpty else { return nil }
        return u
    }
}
