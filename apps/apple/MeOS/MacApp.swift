import SwiftUI
import UserNotifications
import AppKit

#if os(macOS)
/// The iOS app installs this delegate from `App.swift`. The Mac target had no
/// delegate at all, so reminders arrived without a banner while MeOS was open
/// and a tap could not route anywhere. The router is shared; only the wiring
/// was missing.
final class MacAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = NotificationRouter.shared
    }
}
#endif

@main
struct MeOSMacApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate
    #endif
    @StateObject private var state = AppState()
    @StateObject private var mio = MioController()

    var body: some Scene {
        WindowGroup("MeOS") {
            MeRoot()
                .environmentObject(state)
                .environmentObject(mio)
                .frame(minWidth: 900, minHeight: 620)
                .preferredColorScheme(.dark)
                .textFieldStyle(.plain)
                .buttonStyle(.plain)
                .task { await ReminderStore.shared.syncOnLaunch() }
        }
        .defaultSize(width: 1240, height: 820)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands { SidebarCommands() }
    }
}
