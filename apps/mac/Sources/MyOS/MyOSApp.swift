import SwiftUI

@main
struct MyOSApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .frame(minWidth: 940, minHeight: 640)
                .preferredColorScheme(.dark)
                .tint(Palette.brand)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .defaultSize(width: 1160, height: 780)
        .windowResizability(.contentSize)
    }
}
