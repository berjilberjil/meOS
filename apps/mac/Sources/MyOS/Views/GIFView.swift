import SwiftUI
import AppKit

// In-app animated GIF exercise demos (ExerciseDB mirror), like fitOS. Loads the
// bytes once, then hands them to an NSImageView that animates them.

struct GIFView: View {
    let url: URL
    @State private var data: Data?
    @State private var failed = false

    var body: some View {
        ZStack {
            Palette.surface2.opacity(0.5)
            if let data {
                AnimatedGIF(data: data)
            } else if failed {
                VStack(spacing: 6) {
                    Image(systemName: "wifi.slash").font(.system(size: 20)).foregroundStyle(Palette.faint)
                    Text("Demo unavailable").font(.system(size: 11)).foregroundStyle(Palette.faint)
                }
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .task(id: url) {
            failed = false; data = nil
            do {
                let (d, _) = try await URLSession.shared.data(from: url)
                data = d
            } catch {
                failed = true
            }
        }
    }
}

/// NSImageView wrapper that animates a GIF from raw data.
private struct AnimatedGIF: NSViewRepresentable {
    let data: Data
    func makeNSView(context: Context) -> NSImageView {
        let v = NSImageView()
        v.imageScaling = .scaleProportionallyUpOrDown
        v.animates = true
        v.image = NSImage(data: data)
        v.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        v.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return v
    }
    func updateNSView(_ v: NSImageView, context: Context) {
        v.image = NSImage(data: data)
        v.animates = true
    }
}
