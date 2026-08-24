import SwiftUI
import AppKit
import UserNotifications

@main
struct MyOSApp: App {
    @StateObject private var state = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var themeStore = ThemeStore.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .frame(minWidth: 940, minHeight: 640)
                .preferredColorScheme(themeStore.theme.colorScheme)
                .tint(Palette.accent)
                .animation(.knTheme, value: themeStore.theme.id)
                .task { await ReminderStore.shared.syncOnLaunch() }
        }
        .defaultSize(width: 1160, height: 780)
        .windowResizability(.contentSize)

        // The focus timer, with or without a window. Independent of Task Mode on
        // purpose: the point is crushing a task with MyOS closed.
        MenuBarExtra {
            MenuBarView()
                .environmentObject(state)
                .preferredColorScheme(themeStore.theme.colorScheme)
                .tint(Palette.accent)
        } label: {
            MenuBarLabel(state: state)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Installs the notification router, so tapping the Friday report opens on it.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = NotificationRouter.shared
    }
}
