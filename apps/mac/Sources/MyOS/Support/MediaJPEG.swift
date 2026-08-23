import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Downscale + JPEG for anything we store on a synced key (belonging photos,
/// profile shots). Full-res camera files are far too big for the KV payload.
enum MediaJPEG {
    static func downscale(_ data: Data, maxSide: CGFloat = 720, quality: CGFloat = 0.6) -> Data? {
        #if os(macOS)
        guard let img = NSImage(data: data) else { return nil }
        let size = img.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(1, maxSide / max(size.width, size.height))
        let target = NSSize(width: (size.width * scale).rounded(),
                            height: (size.height * scale).rounded())
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(target.width), pixelsHigh: Int(target.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        rep.size = target
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        img.draw(in: NSRect(origin: .zero, size: target), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
        #else
        guard let img = UIImage(data: data) else { return nil }
        let size = img.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(1, maxSide / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let scaled = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            img.draw(in: CGRect(origin: .zero, size: target))
        }
        return scaled.jpegData(compressionQuality: quality)
        #endif
    }

    static func image(fromBase64 s: String) -> Image? {
        guard !s.isEmpty, let data = Data(base64Encoded: s) else { return nil }
        return image(from: data)
    }

    /// Same, for bytes that never took a trip through base64 — scan photos
    /// come back from the sealed media cache as `Data`.
    static func image(from data: Data) -> Image? {
        #if os(macOS)
        guard let ns = NSImage(data: data) else { return nil }
        // NSImage.size can be 72dpi points and disagree with the pixel
        // bitmap — SwiftUI then letterboxes or crops a sliver. Pin size
        // to the first bitmap so the whole photo is visible.
        if let rep = ns.representations.first, rep.pixelsWide > 0, rep.pixelsHigh > 0 {
            ns.size = NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        }
        return Image(nsImage: ns)
        #else
        guard let ui = UIImage(data: data) else { return nil }
        return Image(uiImage: ui)
        #endif
    }
}
