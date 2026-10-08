import SwiftUI
import AVKit

/// Media viewer for event photos and videos — paging, zoom, video playback.
///
/// The iOS viewer, ported. It fills a sheet instead of the whole screen, the
/// paging behaviour is the same, and zoom is the trackpad pinch (with
/// double-click to toggle) rather than a finger pinch.
struct EventMediaViewer: View {
    /// Event media loads from R2 asynchronously; without observing the store
    /// the bytes land in cache and the view never re-renders.
    @ObservedObject private var mediaStore = EventMediaStore.shared
    let media: [EventMedia]
    let startID: String
    let onClose: () -> Void

    @State private var page: String?

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
                            .font(.title).foregroundStyle(Palette.muted)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.escape, modifiers: [])
                }
                .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)

                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        ForEach(media) { m in
                            Group {
                                if m.kind == .video {
                                    VideoPage(media: m, isActive: page == m.id)
                                } else {
                                    EventZoomImage(media: m)
                                }
                            }
                            .containerRelativeFrame(.horizontal)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $page)
            }
        }
    }

    private var currentIndex: Int {
        media.firstIndex(where: { $0.id == page }) ?? 0
    }
}

/// Single video page — writes base64 to temp file, plays via AVPlayer.
private struct VideoPage: View {
    @ObservedObject private var mediaStore = EventMediaStore.shared
    let media: EventMedia
    /// Whether this page is the one on screen — a player is built when it
    /// arrives and torn down when it leaves, so audio never trails across a
    /// page turn and no stale temp files pile up.
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
        .onChange(of: mediaStore.version) { _, _ in if player == nil { start() } }
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
        // nil means "still loading" — the fetch is in flight and `version`
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

/// Full-size event photo: bytes resolve from the sealed store, decoded once,
/// downsampled to screen size, off the main thread, cached by media id.
private struct EventZoomImage: View {
    let media: EventMedia
    @ObservedObject private var mediaStore = EventMediaStore.shared
    @State private var image: NSImage?

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
        if let hit = MacThumbCache.cached(media.id) { image = hit; return }
        guard let data = EventMediaStore.shared.poster(for: media) else { return }
        let maxPixel: CGFloat = NSScreen.main.map { max($0.frame.width, $0.frame.height) * $0.backingScaleFactor } ?? 2048
        image = await MacThumbCache.load(data: data, key: media.id, maxPixel: maxPixel)
    }
}

/// Zoomable image — trackpad pinch to zoom, double-click to toggle, drag when
/// zoomed.
private struct ZoomableImage: View {
    let image: NSImage
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        Image(nsImage: image)
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
