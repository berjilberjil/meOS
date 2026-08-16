import SwiftUI

@main
struct MyOSApp: App {
    @StateObject private var state = AppState()
    @ObservedObject private var themeStore = ThemeStore.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .preferredColorScheme(themeStore.theme.colorScheme)
                .tint(themeStore.theme.brand)
                .animation(.knTheme, value: themeStore.theme.id)
                .task { await ReminderStore.shared.syncOnLaunch() }
        }
    }
}
