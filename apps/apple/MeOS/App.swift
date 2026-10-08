import SwiftUI
import UIKit
import UserNotifications

@main
struct MeOSApp: App {
    @StateObject private var state = AppState()
    @StateObject private var mio = MioController()
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            MeRoot()
                .environmentObject(state)
                .environmentObject(mio)
                .task { await ReminderStore.shared.syncOnLaunch() }
                .task {
                    StepsBackgroundRefresh.adopt(state)
                    StepsBackgroundRefresh.schedule()
                }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = NotificationRouter.shared
        StepsBackgroundRefresh.register()
        return true
    }
}
