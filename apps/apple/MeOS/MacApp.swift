import SwiftUI

@main
struct MeOSMacApp: App {
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
