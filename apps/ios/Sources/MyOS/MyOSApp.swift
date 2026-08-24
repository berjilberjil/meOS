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
        }
    }
}


/// Installs the notification router, so tapping the Friday report opens on it.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = NotificationRouter.shared
        return true
    }
}
