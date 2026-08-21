import SwiftUI
import UIKit

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
                .tint(themeStore.theme.brand)
                .animation(.knTheme, value: themeStore.theme.id)
                .task { await ReminderStore.shared.syncOnLaunch() }
                // See PrefsStore.resolveOpeningTab: this marker is what lets a
                // reopen resume, while a force-quit starts from the top.
                .onAppear { PrefsStore.shared.markRunning() }
        }
    }
}


/// Clears the running marker when iOS terminates the app (force-quit), so the
/// next launch starts at the configured launch tab instead of resuming.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func applicationWillTerminate(_ application: UIApplication) {
        PrefsStore.shared.markCleanExit()
    }
}
