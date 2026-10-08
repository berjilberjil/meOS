import SwiftUI

/// mac port of the iOS-only EventThumb: an event-media thumbnail that never
/// decodes on the main thread. Placeholder until the decode lands, so the
/// events list never waits on bytes.
struct EventThumb<Placeholder: View>: View {
    let media: EventMedia
    let width: CGFloat
    let height: CGFloat
    /// Longest side, in pixels, to decode. Pass a bigger value for the viewer.
    var maxPixel: CGFloat? = nil
    @ViewBuilder var placeholder: Placeholder

    @ObservedObject private var store = EventMediaStore.shared
    @State private var loaded: NSImage?

    var body: some View {
        Group {
            if let image = loaded ?? MacThumbCache.cached(media.id) {
                Image(nsImage: image).resizable().scaledToFill()
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
        if MacThumbCache.cached(media.id) != nil { return }
        // A miss starts the R2 fetch and returns nil; `version` bumps when
        // the bytes land, which retries this.
        guard let data = EventMediaStore.shared.poster(for: media) else { return }
        let cap = maxPixel ?? max(width, height) * 2
        loaded = await MacThumbCache.load(data: data, key: media.id, maxPixel: cap)
    }
}
