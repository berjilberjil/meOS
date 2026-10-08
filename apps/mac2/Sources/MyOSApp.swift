import SwiftUI
import AppKit
import UserNotifications

/// The rebuilt Mac app. Hosts the new white shell directly; the old RootView
/// (splash + old sidebar) is not part of this target. The login gate lands in
/// v2: on this Mac the shared session from the old app is already warm.
///
/// First launch pins Light, because the rebuilt look is balanced white —
/// see `WhiteTheme.installDefaults()`.
@main
struct meOSApp: App {
    @StateObject private var state = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var themeStore = ThemeStore.shared

    init() {
        WhiteTheme.installDefaults()
    }

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(state)
                .frame(minWidth: 980, minHeight: 640)
                .preferredColorScheme(themeStore.theme.colorScheme)
                .tint(Palette.accent)
                .animation(.knTheme, value: themeStore.theme.id)
                .task { await ReminderStore.shared.syncOnLaunch() }
        }
        .defaultSize(width: 1240, height: 820)
        .windowResizability(.contentSize)
    }
}

/// Installs the notification router, so tapping a reminder opens the screen
/// it is about.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = NotificationRouter.shared
    }
}
