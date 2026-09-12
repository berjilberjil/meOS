#if os(iOS)
import SwiftUI
import AVKit

/// Full-screen media viewer for event photos/videos — swipe, pinch to zoom, video playback.
struct EventMediaViewer: View {
    /// Event media loads from R2 asynchronously; without observing the
    /// store the bytes land in cache and the view never re-renders — which
    /// is exactly why thumbnails stayed grey placeholders on iPhone.
    @ObservedObject private var mediaStore = EventMediaStore.shared
    let media: [EventMedia]
    let startID: String
    let onClose: () -> Void

    @State private var page: String

    init(media: [EventMedia], start: EventMedia, onClose: @escaping () -> Void) {
        self.media = media
        self.startID = start.id
        self.onClose = onClose
        _page = State(initialValue: start.id)
    }

    private var current: EventMedia? { media.first { $0.id == page } }

    var body: some View {
        ZStack {
            Palette.background

            VStack(spacing: 0) {
                HStack {
                    Text("\(currentIndex + 1) of \(media.count)")
                        .font(.footnote.weight(.semibold)).foregroundStyle(Palette.text)
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title).foregroundStyle(.white.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)

                TabView(selection: $page) {
                    ForEach(media) { m in
                        Group {
                            if m.kind == .video {
                                VideoPage(media: m, isActive: page == m.id)
                            } else {
                                EventZoomImage(media: m)
                            }
                        }
                        .tag(m.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
        }
    }

    private var currentIndex: Int {
        media.firstIndex(where: { $0.id == page }) ?? 0
    }
}

/// Single video page — writes base64 to temp file, plays via AVPlayer.
private struct VideoPage: View {
    /// Event media loads from R2 asynchronously; without observing the
    /// store the bytes land in cache and the view never re-renders — which
    /// is exactly why thumbnails stayed grey placeholders on iPhone.
    @ObservedObject private var mediaStore = EventMediaStore.shared
    let media: EventMedia
    /// Whether this page is the one on screen. Each page owns its own player,
    /// and the viewer's `onChange` was pausing a property that was declared and
    /// never assigned — so swiping off a playing video left the audio going over
    /// the next still image, and swiping back and forth started another player
    /// each time, plus a temp .mp4 per start that nothing ever deleted.
    let isActive: Bool
    @State private var player: AVPlayer?
    @State private var file: URL?
    @State private var failed = false

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
                    .onTapGesture {
                        if player.timeControlStatus == .playing { player.pause() }
                        else { player.play() }
                    }
            } else if failed {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle).foregroundStyle(Palette.attention)
                    Text("Couldn't load video").font(.footnote).foregroundStyle(Palette.faint)
                }
            } else {
                ProgressView().tint(Palette.action)
            }
        }
        .onAppear { start() }
        // The store returns nil for "not here yet" *and* starts the fetch, so
        // treating that as a hard failure meant the first tap on any video whose
        // bytes were not already on this device — a clip made on the Mac, or
        // anything after the cache is purged — showed "Couldn't load video"
        // forever, while the download it had just triggered landed unnoticed.
        // Closing and reopening played it, which is how this hid.
        .onChange(of: mediaStore.version) { _, _ in if player == nil { start() } }
        // Symmetric: tear down when it scrolls off, build again when it comes
        // back. `onAppear` fires once per page and `mediaStore.version` does not
        // move for bytes already cached, so without the second half a video you
        // swiped past showed an endless spinner on the way back.
        .onChange(of: isActive) { _, on in
            if on { if player == nil { start() } } else { teardown() }
        }
        .onDisappear { teardown() }
    }

    private func teardown() {
        player?.pause()
        player = nil
        if let file { try? FileManager.default.removeItem(at: file) }
        file = nil
    }

    private func start() {
        // nil means "still loading" — the fetch is now in flight and `version`
        // will bump when it lands. Only a real write failure is a failure.
        guard let d = EventMediaStore.shared.data(for: media) else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
        do {
            try d.write(to: url)
            let p = AVPlayer(url: url); player = p; p.play()
        } catch { failed = true }
    }
}

/// Full-screen event photo: bytes resolve from the sealed store (kicking off
/// the R2 fetch on a miss), the full-resolution `UIImage(data:)` decode that
/// used to run inline in the page body now happens once, downsampled to
/// screen size, off the main thread, cached by media id.
private struct EventZoomImage: View {
    let media: EventMedia
    @ObservedObject private var mediaStore = EventMediaStore.shared
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                ZoomableImage(image: image)
            } else {
                ProgressView().tint(Palette.action)
            }
        }
        .task(id: media.id) { await reload() }
        .onChange(of: mediaStore.version) { _, _ in Task { await reload() } }
    }

    private func reload() async {
        if let hit = ThumbCache.cached(media.id) { image = hit; return }
        guard let data = EventMediaStore.shared.poster(for: media) else { return }
        let scale = UIScreen.main.scale
        let size = UIScreen.main.bounds.size
        image = await ThumbCache.load(data: data, key: media.id,
                                      maxPixel: max(size.width, size.height) * scale)
    }
}

/// Zoomable image — pinch to zoom, double-tap to toggle, drag when zoomed.
private struct ZoomableImage: View {    let image: UIImage
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .scaleEffect(scale)
            .offset(offset)
            .gesture(
                MagnificationGesture()
                    .onChanged { value in scale = max(1, lastScale * value) }
                    .onEnded { _ in
                        lastScale = scale
                        if scale < 1.05 { reset() }
                    }
            )
            .simultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        guard scale > 1 else { return }
                        offset = CGSize(width: lastOffset.width + value.translation.width,
                                        height: lastOffset.height + value.translation.height)
                    }
                    .onEnded { _ in lastOffset = offset }
            )
            .onTapGesture(count: 2) {
                withAnimation(.knFast) {
                    if scale > 1 { reset() } else { scale = 2.4; lastScale = 2.4 }
                }
            }
    }

    private func reset() {
        withAnimation(.knFast) {
            scale = 1; lastScale = 1; offset = .zero; lastOffset = .zero
        }
    }
}
#endif
