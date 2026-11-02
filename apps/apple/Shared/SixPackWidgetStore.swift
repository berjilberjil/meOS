import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// The hand-off between the app and its Home Screen / Lock Screen widgets.
///
/// The widget runs in its own process, and MeOS state lives in the app as an
/// end-to-end encrypted blob behind a vault. The widget cannot open that. So
/// every time the challenge changes, the app mirrors the (already decrypted)
/// `SixPackState` into the App Group, and the widget timeline reads that copy.
///
/// The widget is deliberately read-only. Ticking a row there could not push to
/// the server — the extension has no session or vault key — so the whole
/// surface is a tap-through to the tracker in the app instead of a control
/// that would silently disagree with every other device.
enum SixPackWidgetStore {
    /// Must match the application-groups entitlement on BOTH the app and the
    /// widget extension, or the suite is a private `UserDefaults` nobody shares.
    static let appGroup = "group.com.berjil.myos"
    static let snapshotKey = "meos.sixpack.widget.snapshot"

    struct Snapshot: Codable, Equatable {
        var sixPack: SixPackState
        var savedAt: Date
    }

    /// Called whenever `AppState.sixPack` changes — hydrate, local edit, live
    /// sync, or a reset. Cheap enough to run synchronously on the main actor.
    static func save(_ state: SixPackState) {
        let snapshot = Snapshot(sixPack: state, savedAt: Date())
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults?.set(data, forKey: snapshotKey)
        reload()
    }

    static func load() -> Snapshot? {
        guard let data = defaults?.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    /// Logging out wipes the shared copy as well. Otherwise a signed-out phone
    /// would still show the last challenge on the Home Screen.
    static func clear() {
        defaults?.removeObject(forKey: snapshotKey)
        reload()
    }

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroup)
    }

    /// Nudge WidgetKit after a change. Without this the widget keeps its old
    /// timeline entry until the system decides to refresh it.
    private static func reload() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
