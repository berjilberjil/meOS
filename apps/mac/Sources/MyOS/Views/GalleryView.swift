import SwiftUI
import AVKit

/// Decoded gallery thumbnails, keyed by item id.
///
/// Same reasoning as `ScanThumbCache`: a JPEG is cheap to decode once and
/// ruinous to decode on every body pass, which is exactly what a scrolling grid
/// does. Bounded crudely, because the alternative is an LRU nobody will tune.
@MainActor
enum GalleryThumbCache {
    private static var cache: [String: Image] = [:]

    static func image(id: String, data: Data) -> Image? {
        if let hit = cache[id] { return hit }
        guard let img = MediaJPEG.image(from: data) else { return nil }
        if cache.count > 200 { cache.removeAll() }
        cache[id] = img
        return img
    }

    static func clear() { cache.removeAll() }
}

/// One square in the grid.
struct GalleryThumb: View {
    let item: GalleryItem
    var side: CGFloat

    @ObservedObject private var media = EventMediaStore.shared

    /// Bytes for the *preview* — a video's poster, an image's own data. Nil
    /// means the sealed fetch is still in flight; the store bumps its version
    /// when it lands, which re-renders this.
    private var previewData: Data? {
        switch item.location {
        case let .sealed(key, posterKey):
            return media.data(key: item.kind == .video ? (posterKey ?? key) : key)
        case let .inline(base64, poster):
            let source = item.kind == .video ? (poster ?? base64) : base64
            return Data(base64Encoded: source)
        case let .file(url):
            return try? Data(contentsOf: url)
        }
    }

    var body: some View {
        ZStack {
            Palette.surfaceElevated
            if let data = previewData, let image = GalleryThumbCache.image(id: item.id, data: data) {
                image.resizable().aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: item.source.icon)
                    .font(.system(size: side * 0.26, weight: .semibold))
                    .foregroundStyle(Palette.faint)
            }
            if item.kind == .video {
                // A play glyph, bottom-left, the way every gallery marks video.
                VStack {
                    Spacer()
                    HStack {
                        Image(systemName: "play.fill")
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(.white)
                            .padding(4)
                            .background(.black.opacity(0.45), in: Circle())
                        Spacer()
                    }
                }
                .padding(5)
            }
        }
        .frame(width: side, height: side)
        .clipped()
        .contentShape(Rectangle())
    }
}

/// Everything MyOS has ever photographed, in one place.
///
/// Media accumulates in four unrelated corners of the app — events, body
/// progress, scans, notes — and until now the only way to find a picture was to
/// remember which screen you put it on. This is the one grid, newest first,
/// grouped by month.
struct GalleryView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var media = EventMediaStore.shared

    /// nil = everything.
    @State private var source: GalleryItem.Source?
    @State private var progress: [ProgressPhoto] = []
    @State private var viewing: GalleryItem?

    private var all: [GalleryItem] {
        GalleryFeed.items(events: state.events, scans: state.scans,
                          notes: state.notes, progress: progress)
    }

    private var shown: [GalleryItem] {
        guard let source else { return all }
        return all.filter { $0.source == source }
    }

    #if os(macOS)
    private let side: CGFloat = 132
    #else
    private let side: CGFloat = 112
    #endif

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: side), spacing: 3)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Gap.row) {
            header
            filter
            if shown.isEmpty {
                empty
            } else {
                grid
            }
        }
        .onAppear { reloadProgress() }
        .onReceive(NotificationCenter.default.publisher(for: .progressPhotosDidChange)) { _ in
            reloadProgress()
        }
        #if os(iOS)
        .fullScreenCover(item: $viewing) { item in
            GalleryViewer(items: shown, start: item) { viewing = nil }
        }
        #else
        .sheet(item: $viewing) { item in
            GalleryViewer(items: shown, start: item) { viewing = nil }
        }
        #endif
    }

    @ViewBuilder private var header: some View {
        #if os(macOS)
        HStack(alignment: .firstTextBaseline) {
            ScreenTitle(text: "Gallery")
            Text("\(all.count)")
                .font(.footnote.weight(.semibold)).monospacedDigit()
                .foregroundStyle(Palette.faint)
            Spacer()
        }
        #else
        EmptyView()
        #endif
    }

    /// Source, as a segmented control. Five short words fit; a menu would hide
    /// the fact that there is anything to filter by at all.
    private var filter: some View {
        Picker("", selection: Binding(get: { source?.rawValue ?? "all" },
                                      set: { source = $0 == "all" ? nil : GalleryItem.Source(rawValue: $0) })) {
            Text("All").tag("all")
            ForEach(GalleryItem.Source.allCases) { s in
                Text(s.label).tag(s.rawValue)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 3, pinnedViews: [.sectionHeaders]) {
            ForEach(GalleryFeed.months(shown), id: \.month) { section in
                Section {
                    ForEach(section.items) { item in
                        Button { viewing = item } label: {
                            GalleryThumb(item: item, side: side)
                        }
                        .buttonStyle(.plain)
                        .help("\(item.title) — \(Fmt.day(item.day))")
                        .accessibilityLabel("\(item.title), \(Fmt.day(item.day))")
                    }
                } header: {
                    HStack {
                        Text(GalleryFeed.monthLabel(section.month))
                            .font(.myHeading)
                            .foregroundStyle(Palette.text)
                        Spacer()
                        Text("\(section.items.count)")
                            .font(.myCaption).monospacedDigit()
                            .foregroundStyle(Palette.faint)
                    }
                    .padding(.vertical, Space.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.background)
                }
            }
        }
    }

    private var empty: some View {
        Card {
            VStack(alignment: .leading, spacing: Space.sm) {
                SectionTitle(text: "Nothing here yet")
                Text(source == nil
                     ? "Photos and videos from events, body progress, scans and notes all land here."
                     : "No media from \(source?.label.lowercased() ?? "there") yet.")
                    .font(.myBody).foregroundStyle(Palette.faint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func reloadProgress() {
        progress = ProgressPhotoStore.list()
    }
}

/// One item, big — with the rest of the filtered set to page through.
struct GalleryViewer: View {
    let items: [GalleryItem]
    let start: GalleryItem
    let onClose: () -> Void

    @State private var index: Int = 0
    @ObservedObject private var media = EventMediaStore.shared

    private var current: GalleryItem? {
        items.indices.contains(index) ? items[index] : nil
    }

    /// The full-size bytes — never the poster, even for a video.
    private func fullData(_ item: GalleryItem) -> Data? {
        switch item.location {
        case let .sealed(key, _):     return media.data(key: key)
        case let .inline(base64, _):  return Data(base64Encoded: base64)
        case let .file(url):          return try? Data(contentsOf: url)
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let item = current {
                VStack(spacing: Space.md) {
                    content(item)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    VStack(spacing: 2) {
                        Text(item.title)
                            .font(.myBody.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text("\(item.source.label) · \(Fmt.day(item.day))")
                            .font(.myCaption)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .padding(.bottom, Space.lg)
                }
            }
            controls
        }
        .onAppear { index = items.firstIndex(of: start) ?? 0 }
        #if os(macOS)
        .frame(minWidth: 720, minHeight: 520)
        #endif
    }

    @ViewBuilder private func content(_ item: GalleryItem) -> some View {
        if item.kind == .video, let data = fullData(item), let url = GalleryVideoFile.url(for: item.id, data: data) {
            VideoPlayer(player: AVPlayer(url: url))
        } else if let data = fullData(item), let image = MediaJPEG.image(from: data) {
            image.resizable().aspectRatio(contentMode: .fit)
        } else {
            ProgressView().controlSize(.large).tint(.white)
        }
    }

    private var controls: some View {
        VStack {
            HStack {
                Spacer()
                Button { onClose() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(9)
                        .background(.black.opacity(0.45), in: Circle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }
            Spacer()
            HStack {
                step(-1, "chevron.left")
                Spacer()
                step(1, "chevron.right")
            }
        }
        .padding(Space.lg)
    }

    @ViewBuilder private func step(_ delta: Int, _ icon: String) -> some View {
        let next = index + delta
        Button { if items.indices.contains(next) { index = next } } label: {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .padding(11)
                .background(.black.opacity(0.45), in: Circle())
        }
        .buttonStyle(.plain)
        .opacity(items.indices.contains(next) ? 1 : 0.25)
        .disabled(!items.indices.contains(next))
    }
}

/// A video has to be a file on disk before `AVPlayer` will look at it, and the
/// bytes arrive as sealed `Data`. Written once per item into the temp
/// directory, which the system clears for us.
enum GalleryVideoFile {
    static func url(for id: String, data: Data) -> URL? {
        let safe = id.replacingOccurrences(of: "/", with: "_")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("myos-gallery-\(safe).mp4")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        do { try data.write(to: url, options: .atomic) } catch { return nil }
        return url
    }
}
