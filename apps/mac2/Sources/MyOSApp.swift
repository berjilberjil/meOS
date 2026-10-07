import SwiftUI
import AppKit
import UserNotifications

/// The rebuilt Mac app. Same spine as the old entry: shared `RootView` gates
/// login + biometrics and hosts the shell; the appearance preference rides
/// `ThemeStore` (light/dark) and the synced `AppearanceStore` (palette).
///
/// The one change: first launch pins Light, because the rebuilt look is
/// balanced white — see `WhiteTheme.installDefaults()`.
@main
struct MyOSApp: App {
    @StateObject private var state = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var themeStore = ThemeStore.shared

    init() {
        WhiteTheme.installDefaults()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
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
