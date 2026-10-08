import Foundation

/// The two UserDefaults keys that record "this device has a live MeOS session".
/// Shared because both `AppState` (the UI) and `EventIntentStore` (Siri, which
/// runs headlessly with no UI) need to read the same session — duplicating the
/// literals would let them drift apart silently.
///
/// Renamed from `myos.session.*`; the getters fall back to the old spelling so
/// updating never logs anyone out.
enum SessionDefaults {
    static let active   = "meos.session.active"
    static let username = "meos.session.username"
    private static let legacyActive   = "myos.session.active"
    private static let legacyUsername = "myos.session.username"

    /// The signed-in username on this device, or nil if there's no live session.
    static var currentUsername: String? {
        let d = UserDefaults.standard
        let isActive = d.bool(forKey: active) || d.bool(forKey: legacyActive)
        let u = d.string(forKey: username) ?? d.string(forKey: legacyUsername)
        guard isActive, let u, !u.isEmpty else { return nil }
        return u
    }

    /// Copy any legacy session flags forward, so the rename never logs anyone out.
    static func migrateIfNeeded() {
        let d = UserDefaults.standard
        if d.object(forKey: active) == nil, d.object(forKey: legacyActive) != nil {
            d.set(d.bool(forKey: legacyActive), forKey: active)
        }
        if d.string(forKey: username) == nil, let u = d.string(forKey: legacyUsername) {
            d.set(u, forKey: username)
        }
    }
}
