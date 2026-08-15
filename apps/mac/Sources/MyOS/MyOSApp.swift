import SwiftUI
import AppKit

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
                .task { await ReminderStore.shared.syncOnLaunch() }
                // Force the window chrome fully black so nothing grey shows behind
                // the traffic lights or in the (now hidden) toolbar strip.
                .background(WindowChrome())
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1160, height: 780)
        .windowResizability(.contentSize)
    }
}

/// Reaches the underlying NSWindow to remove the last of the system chrome:
/// transparent titlebar, black background, and no toolbar material. Without this,
/// macOS Tahoe paints a translucent grey "glass" toolbar strip across the top.
private struct WindowChrome: NSViewRepresentable {
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
