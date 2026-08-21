import SwiftUI

/// Device-local app preferences (NOT synced) — mirrors the `ThemeStore` pattern.
/// Config lives in UserDefaults; user *data* lives in AppState/StateKey. Shared
/// by both platforms (this file is in Support/, compiled into mac + iOS).
final class PrefsStore: ObservableObject {
    static let shared = PrefsStore()

    private let kHideFold = "myos.fold.hideNumbers"
    private let kLaunchTab = "myos.launchTab"
    private let kLastTab = "myos.lastTab"
    private let kRunning = "myos.wasRunning"

    /// Fold privacy: when on, every amount in the Fold dashboard is masked.
    @Published var hideFoldNumbers: Bool {
        didSet { UserDefaults.standard.set(hideFoldNumbers, forKey: kHideFold) }
    }

    /// The tab MyOS opens to on launch. Stored as a `NavTab` raw string.
    @Published var launchTab: NavTab {
        didSet { UserDefaults.standard.set(launchTab.rawValue, forKey: kLaunchTab) }
    }

    /// The tab you were last on. Written on every switch so reopening resumes
    /// where you left off instead of restarting at the top.
    @Published var lastTab: NavTab {
        didSet { UserDefaults.standard.set(lastTab.rawValue, forKey: kLastTab) }
    }

    private init() {
        hideFoldNumbers = UserDefaults.standard.bool(forKey: kHideFold)
        launchTab = NavTab.resolveLaunch(UserDefaults.standard.string(forKey: kLaunchTab))
        lastTab = NavTab.resolveLaunch(UserDefaults.standard.string(forKey: kLastTab))
    }

    /// Where to open. Resumes `lastTab` when the previous run ended without a
    /// clean shutdown — i.e. it was backgrounded or the system reclaimed it —
    /// and falls back to the configured launch tab after a real quit.
    ///
    /// The flag is set while running and cleared on terminate, so "was still
    /// running when we stopped seeing it" is what distinguishes the two. A
    /// force-quit clears it too, which is the behaviour asked for: only a full
    /// close starts from the top.
    func resolveOpeningTab(allowed: [NavTab]? = nil) -> NavTab {
        let resume = UserDefaults.standard.bool(forKey: kRunning)
        let target = resume ? lastTab : launchTab
        guard let allowed else { return target }
        return allowed.contains(target) ? target : NavTab.resolveLaunch(target.rawValue, allowed: allowed)
    }

    func markRunning() { UserDefaults.standard.set(true, forKey: kRunning) }
    func markCleanExit() { UserDefaults.standard.set(false, forKey: kRunning) }
}
