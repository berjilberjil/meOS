import SwiftUI
import AppKit

@main
struct MyOSApp: App {
    @StateObject private var state = AppState()
    @ObservedObject private var themeStore = ThemeStore.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .frame(minWidth: 940, minHeight: 640)
                .preferredColorScheme(themeStore.theme.colorScheme)
                .tint(themeStore.theme.brand)
                .animation(.knTheme, value: themeStore.theme.id)
                .task { await ReminderStore.shared.syncOnLaunch() }
                // Window chrome follows the active theme so Light doesn't sit on a
                // forced-black titlebar (that snap was the "theme isn't switching").
                .background(WindowChrome(themeID: themeStore.theme.id))
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1160, height: 780)
        .windowResizability(.contentSize)

        // The focus timer, with or without a window. Independent of Task Mode on
        // purpose: the point is crushing a task with MyOS closed.
        MenuBarExtra {
            MenuBarView()
                .environmentObject(state)
                .preferredColorScheme(themeStore.theme.colorScheme)
                .tint(themeStore.theme.brand)
                .fontDesign(.rounded)
        } label: {
            MenuBarLabel(state: state)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Reaches the underlying NSWindow to remove the last of the system chrome:
/// transparent titlebar, black background, and no toolbar material. Without this,
/// macOS Tahoe paints a translucent grey "glass" toolbar strip across the top.
private struct WindowChrome: NSViewRepresentable {
    var themeID: String

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { configure(v.window) }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configure(nsView.window) }
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isOpaque = true
        window.backgroundColor = NSColor(Palette.bg)
        // Drop the toolbar entirely — the app draws its own sidebar and headers,
        // so the empty system toolbar strip (and its grey material) is pure chrome.
        window.toolbar = nil
    }
}
