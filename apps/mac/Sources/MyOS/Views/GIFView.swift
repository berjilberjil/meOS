import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// In-app animated GIF exercise demos (ExerciseDB mirror), like fitOS. Loads the
// bytes once, then hands them to a native image view. macOS animates every frame
// via NSImageView; iOS shows the first frame as a static image (UIImage doesn't
// animate multi-frame GIF data without a custom decoder).

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
                    Image(systemName: "wifi.slash").font(.title3).foregroundStyle(Palette.faint)
                    Text("Demo unavailable").font(.caption2).foregroundStyle(Palette.faint)
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

#if os(macOS)
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
#else
/// Static first-frame fallback — good enough for a demo thumbnail on iOS.
private struct AnimatedGIF: View {
    let data: Data
    var body: some View {
        if let img = UIImage(data: data) {
            Image(uiImage: img).resizable().aspectRatio(contentMode: .fit)
        } else {
            Color.clear
        }
    }
}
#endif
