#if os(iOS)
import SwiftUI
import UIKit
import ImageIO

/// Downsampled thumbnails, decoded once and off the main thread.
///
/// `UIImage(contentsOfFile:)` inside a view body is a full-resolution JPEG
/// decode on the main thread — and SwiftUI re-runs that body on every state
/// change. A strip of body photos therefore re-decoded every photo, at camera
/// resolution, on every pass; on the paged Today screen that landed in the
/// middle of a swipe, which is what made the page turn stall.
///
/// `CGImageSourceCreateThumbnailAtIndex` decodes straight to the size actually
/// drawn, so the work is a fraction of a full decode even the first time.
enum ThumbCache {
    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 150
        return c
    }()

    static func cached(_ key: String) -> UIImage? { cache.object(forKey: key as NSString) }

    static func load(_ url: URL, key: String, maxPixel: CGFloat) async -> UIImage? {
        if let hit = cached(key) { return hit }
        let image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            ]
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            else { return nil }
            return UIImage(cgImage: cg)
        }.value
        if let image { cache.setObject(image, forKey: key as NSString) }
        return image
    }

    /// Same, for bytes that never lived in a file — event media arrives as
    /// `Data` from the sealed store. Decoded to thumbnail size, off-main,
    /// cached by the media's stable id.
    static func load(data: Data, key: String, maxPixel: CGFloat) async -> UIImage? {
        if let hit = cached(key) { return hit }
        let image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            downsampled(data: data, maxPixel: maxPixel)
        }.value
        if let image { cache.setObject(image, forKey: key as NSString) }
        return image
    }

    private static func downsampled(data: Data, maxPixel: CGFloat) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// A thumbnail that never decodes on the main thread. A cached image is there on
/// the first frame; anything else shows `placeholder` until the decode lands, so
/// scrolling and paging never wait on a file.
struct ThumbImage<Placeholder: View>: View {
    let url: URL
    /// Stable per image — the photo's id, not its index.
    let key: String
    let width: CGFloat
    let height: CGFloat
    @ViewBuilder var placeholder: Placeholder

    @State private var loaded: UIImage?

    var body: some View {
        Group {
            if let image = loaded ?? ThumbCache.cached(key) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                placeholder
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .task(id: key) {
            guard ThumbCache.cached(key) == nil else { return }
            loaded = await ThumbCache.load(url, key: key,
                                           maxPixel: max(width, height) * UIScreen.main.scale)
        }
    }
}

/// An event-media thumbnail that never decodes on the main thread.
///
/// Event bytes come from the sealed store as `Data` — a synchronous hit, or
/// nil while the R2 fetch is in flight (which bumps `version` when it lands).
/// Either way the `UIImage(data:)` full-resolution decode used to run inline
/// in the row body, on every pass. This resolves bytes, downsamples to the
/// drawn size off-main, and caches by the media's stable id.
struct EventThumb<Placeholder: View>: View {
    let media: EventMedia
    let width: CGFloat
    let height: CGFloat
    /// Longest side, in pixels, to decode. Pass screen size for the viewer.
    var maxPixel: CGFloat? = nil
    @ViewBuilder var placeholder: Placeholder

    @ObservedObject private var store = EventMediaStore.shared
    @State private var loaded: UIImage?

    var body: some View {
        Group {
            if let image = loaded ?? ThumbCache.cached(media.id) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                placeholder
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .task(id: media.id) { await reload() }
        .onChange(of: store.version) { _, _ in Task { await reload() } }
    }

    private func reload() async {
        if ThumbCache.cached(media.id) != nil { return }
        // A miss starts the R2 fetch and returns nil; `version` bumps when
        // the bytes land, which retries this.
        guard let data = EventMediaStore.shared.poster(for: media) else { return }
        let cap = maxPixel ?? max(width, height) * UIScreen.main.scale
        loaded = await ThumbCache.load(data: data, key: media.id, maxPixel: cap)
    }
}
#endif
