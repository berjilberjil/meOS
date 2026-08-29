import SwiftUI
import UIKit
import UserNotifications

@main
struct MyOSApp: App {
    @StateObject private var state = AppState()
    @ObservedObject private var themeStore = ThemeStore.shared
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .preferredColorScheme(themeStore.theme.colorScheme)
                .tint(Palette.accent)
                .animation(.knTheme, value: themeStore.theme.id)
                .task { await ReminderStore.shared.syncOnLaunch() }
                .task {
                    // Let a background wake write into the state that is
                    // already on screen instead of hydrating a second one.
                    StepsBackgroundRefresh.adopt(state)
                    // Re-armed on every launch as well as after every
                    // wake: iOS drops pending requests when the app is
                    // force-quit, and force-quitting is the exact case
                    // this exists to survive.
                    StepsBackgroundRefresh.schedule()
                }
        }
    }
}


/// Installs the notification router, so tapping the Friday report opens on it.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = NotificationRouter.shared
        // Must be registered before launch returns — BGTaskScheduler
        // throws if a handler is added any later than this.
        StepsBackgroundRefresh.register()
        return true
    }
}
