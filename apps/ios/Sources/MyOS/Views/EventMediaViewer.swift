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
    @State private var player: AVPlayer?

    init(media: [EventMedia], start: EventMedia, onClose: @escaping () -> Void) {
        self.media = media
        self.startID = start.id
        self.onClose = onClose
        _page = State(initialValue: start.id)
    }

    private var current: EventMedia? { media.first { $0.id == page } }

    var body: some View {
        ZStack {
            Palette.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Text("\(currentIndex + 1) of \(media.count)")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.text)
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 26)).foregroundStyle(.white.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)

                TabView(selection: $page) {
                    ForEach(media) { m in
                        Group {
                            if m.kind == .video {
                                VideoPage(media: m)
                            } else if let img = eventImage(m) {
                                ZoomableImage(image: img)
                            } else {
                                Palette.surface2
                            }
                        }
                        .tag(m.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .onChange(of: page) { _, _ in player?.pause(); player = nil }
            }
        }
        .onDisappear { player?.pause() }
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
    @State private var player: AVPlayer?
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
                        .font(.system(size: 32)).foregroundStyle(Palette.amber)
                    Text("Couldn't load video").font(.system(size: 14)).foregroundStyle(Palette.faint)
                }
            } else {
                ProgressView().tint(Palette.brand)
            }
        }
        .onAppear { start() }
        .onDisappear { player?.pause() }
    }

    private func start() {
        guard let d = EventMediaStore.shared.data(for: media) else { failed = true; return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
        do {
            try d.write(to: url)
            let p = AVPlayer(url: url); player = p; p.play()
        } catch { failed = true }
    }
}

/// Zoomable image — pinch to zoom, double-tap to toggle, drag when zoomed.
private struct ZoomableImage: View {
    let image: UIImage
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
