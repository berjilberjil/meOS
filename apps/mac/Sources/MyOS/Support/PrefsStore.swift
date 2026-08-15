import SwiftUI

/// Device-local app preferences (NOT synced) — mirrors the `ThemeStore` pattern.
/// Config lives in UserDefaults; user *data* lives in AppState/StateKey. Shared
/// by both platforms (this file is in Support/, compiled into mac + iOS).
final class PrefsStore: ObservableObject {
    static let shared = PrefsStore()

    private let kHideFold = "myos.fold.hideNumbers"
    private let kLaunchTab = "myos.launchTab"

    /// Fold privacy: when on, every amount in the Fold dashboard is masked.
    @Published var hideFoldNumbers: Bool {
        didSet { UserDefaults.standard.set(hideFoldNumbers, forKey: kHideFold) }
    }

    /// The tab MyOS opens to on launch. Stored as a `NavTab` raw string.
    @Published var launchTab: NavTab {
        didSet { UserDefaults.standard.set(launchTab.rawValue, forKey: kLaunchTab) }
    }

    private init() {
        hideFoldNumbers = UserDefaults.standard.bool(forKey: kHideFold)
        launchTab = NavTab.resolveLaunch(UserDefaults.standard.string(forKey: kLaunchTab))
    }
}
