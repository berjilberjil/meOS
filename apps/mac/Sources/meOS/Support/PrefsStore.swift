import SwiftUI

/// Device-local app preferences (NOT synced) — mirrors the `ThemeStore` pattern.
/// Config lives in UserDefaults; user *data* lives in AppState/StateKey. Shared
/// by both platforms (this file is in Support/, compiled into mac + iOS).
final class PrefsStore: ObservableObject {
    static let shared = PrefsStore()

    private let kHideFold = "myos.fold.hideNumbers"
    private let kLaunchTab = "myos.launchTab"
    private let kLastTab = "myos.lastTab"
    private let kRoutes = "myos.routes"
    private let kResumeMigrated = "myos.launchTab.resumeDefault"

    /// Fold privacy: when on, every amount in the Fold dashboard is masked.
    @Published var hideFoldNumbers: Bool {
        didSet { UserDefaults.standard.set(hideFoldNumbers, forKey: kHideFold) }
    }

    /// A tab to pin the app to on every launch. `nil` — the default — means
    /// "wherever I left off", which is what reopening an app should do.
    @Published var launchTab: NavTab? {
        didSet {
            if let launchTab { UserDefaults.standard.set(launchTab.rawValue, forKey: kLaunchTab) }
            else { UserDefaults.standard.removeObject(forKey: kLaunchTab) }
        }
    }

    /// The tab you were last on. Written on every switch so reopening resumes
    /// where you left off instead of restarting at the top.
    @Published var lastTab: NavTab {
        didSet { UserDefaults.standard.set(lastTab.rawValue, forKey: kLastTab) }
    }

    private init() {
        let d = UserDefaults.standard
        // One-time: opening on a fixed tab was the only behaviour, so a choice
        // made back then wasn't a choice against resuming. Existing values move
        // to Resume; the fixed option is still one tap away in Settings.
        if !d.bool(forKey: kResumeMigrated) {
            d.removeObject(forKey: kLaunchTab)
            d.set(true, forKey: kResumeMigrated)
        }
        hideFoldNumbers = d.bool(forKey: kHideFold)
        launchTab = d.string(forKey: kLaunchTab).flatMap { NavTab(rawValue: $0) }
        lastTab = NavTab.resolveLaunch(d.string(forKey: kLastTab))
    }

    /// Where to open. A pinned launch tab wins; otherwise resume the last one —
    /// including after a quit, because "take me back where I was" is the point.
    func resolveOpeningTab(allowed: [NavTab]? = nil) -> NavTab {
        let target = launchTab ?? lastTab
        guard let allowed else { return target }
        return allowed.contains(target) ? target : NavTab.resolveLaunch(target.rawValue, allowed: allowed)
    }

    // MARK: - Where you were inside a tab

    /// The tab is only half of "where I left off" — the other half is the note
    /// that was open, which is `@State` in the view and therefore dies with the
    /// process. Screens park an id here and pick it back up on the next launch.
    func route(for tab: NavTab) -> String? {
        guard let v = routes[tab.rawValue], !v.isEmpty else { return nil }
        return v
    }

    func setRoute(_ value: String?, for tab: NavTab) {
        var next = routes
        if let value, !value.isEmpty { next[tab.rawValue] = value } else { next[tab.rawValue] = nil }
        routes = next
    }

    private var routes: [String: String] {
        get { (UserDefaults.standard.dictionary(forKey: kRoutes) as? [String: String]) ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: kRoutes) }
    }
}
