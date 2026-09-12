#if os(macOS)
import SwiftUI
import AppKit
import ImageIO

/// Downsampled disk thumbnails, decoded once and off the main thread.
///
/// `NSImage(contentsOf:)` in a view body looks innocent — the load is lazy —
/// but the full-resolution JPEG decode then happens on first draw, on the main
/// thread, and SwiftUI re-runs the body on every state change. A strip of
/// progress photos therefore re-decoded every photo, at camera resolution, on
/// every pass. `CGImageSourceCreateThumbnailAtIndex` decodes straight to the
/// size actually drawn, off-main, and the result is cached by stable id.
enum MacThumbCache {
    private static let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 150
        return c
    }()

    static func cached(_ key: String) -> NSImage? { cache.object(forKey: key as NSString) }

    static func load(url: URL, key: String, maxPixel: CGFloat) async -> NSImage? {
        if let hit = cached(key) { return hit }
        let image = await Task.detached(priority: .userInitiated) { () -> NSImage? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return downsampled(data: data, maxPixel: maxPixel)
        }.value
        if let image { cache.setObject(image, forKey: key as NSString) }
        return image
    }

    static func downsampled(data: Data, maxPixel: CGFloat) -> NSImage? {
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options)
        else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}

/// A disk image that never decodes on the main thread. A cached image is there
/// on the first frame; anything else shows a surface wash until the decode
/// lands, so scrolling and paging never wait on a file.
struct DiskThumbImage: View {
    let url: URL
    /// Stable per image — the photo's id, not its index.
    let key: String
    /// `.fill` for thumbnails, `.fit` for viewers so nothing gets cropped.
    var contentMode: ContentMode = .fill
    /// Longest side, in pixels, to decode. Thumbs ~2x their point size; the
    /// near-full-screen viewer decodes near its frame instead of camera res.
    var maxPixel: CGFloat = 256

    @State private var loaded: NSImage?

    var body: some View {
        Group {
            if let image = loaded ?? MacThumbCache.cached(key) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: contentMode)
            } else {
                Palette.surfaceElevated.opacity(0.5)
            }
        }
        .task(id: key) {
            guard MacThumbCache.cached(key) == nil else { return }
            loaded = await MacThumbCache.load(url: url, key: key, maxPixel: maxPixel)
        }
    }
}
#endif
