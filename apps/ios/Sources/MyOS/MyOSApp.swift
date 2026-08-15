import SwiftUI

@main
struct MyOSApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .preferredColorScheme(.dark)
                .tint(Palette.brand)
                .task { await ReminderStore.shared.syncOnLaunch() }
        }
    }
}
