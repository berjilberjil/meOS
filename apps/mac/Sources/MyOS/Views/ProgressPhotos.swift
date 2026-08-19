import SwiftUI
import AppKit
import UniformTypeIdentifiers

// Mac progress-photo card. Storage lives in ProgressPhotoStore (shared with iOS)
// and now syncs through the shared "media" bucket so a photo hearted on
// iPhone shows up here too.

extension ProgressPhotoStore {
    /// Save an image (from a file url) as the given day's JPEG.
    @discardableResult
    static func save(from source: URL, date: String) -> Bool {
        guard let img = NSImage(contentsOf: source),
              let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
        else { return false }
        return save(jpeg: jpeg, date: date)
    }
}

/// A card of progress photos with an add button, a day calendar, and a viewer.
struct ProgressPhotosCard: View {
    @EnvironmentObject var state: AppState
    @State private var photos: [ProgressPhoto] = []
    @State private var selectedDate: String = AppState.dateKey(Date())
    @State private var viewing: ProgressPhoto?
    /// The month grid stays folded until you ask for it; the strip below shows
    /// every photo (newest first) while it's closed, and one day's while it's open.
    @State private var showCalendar = false
    @State private var dropTargeted = false

    private var photoDates: Set<String> { Set(photos.map(\.date)) }
    private var pendingDates: Set<String> { Set(ProgressPhotoStore.pending().map(\.date)) }
    private var photosForSelectedDay: [ProgressPhoto] { photos.filter { $0.date == selectedDate } }
    private var stripPhotos: [ProgressPhoto] {
        showCalendar ? photosForSelectedDay : photos.sorted { $0.date > $1.date }
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionTitle(text: "Progress photos")
                    Spacer()
                    syncBadge
                    if !photos.isEmpty {
                        Button { withAnimation(.knNormal) { showCalendar.toggle() } } label: {
                            Image(systemName: showCalendar ? "calendar.badge.minus" : "calendar")
                                .font(.system(size: 13, weight: .bold))
                        }
                        .buttonStyle(KIconButtonStyle(size: 28, color: showCalendar ? Palette.brand : Palette.faint))
                        .help(showCalendar ? "Hide the calendar" : "Pick a day")
                    }
                    Button { chooseFile() } label: { Label("Add photo", systemImage: "camera.fill") }
                        .buttonStyle(KGhostButtonStyle(color: Palette.brand))
                }
                if photos.isEmpty {
                    Text(dropTargeted ? "Drop it here."
                                      : "Drop a photo here (or click Add) to track how your body changes over time. Syncs from iPhone too.")
                        .font(.system(size: 13)).foregroundStyle(dropTargeted ? Palette.brand : Palette.faint)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 14)
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                            .foregroundStyle(dropTargeted ? Palette.brand : Palette.border))
                } else {
                    if showCalendar {
                        ProgressPhotoCalendar(photoDates: photoDates, pendingDates: pendingDates, selected: $selectedDate)
                            .transition(.knReveal)
                    }
                    dayStrip
                }
            }
        }
        .task { await reload() }
        .onReceive(NotificationCenter.default.publisher(for: .progressPhotosDidChange)) { _ in
            photos = ProgressPhotoStore.list()
        }
        .onReceive(NotificationCenter.default.publisher(for: .progressPhotosSyncDidChange)) { _ in
            photos = ProgressPhotoStore.list()
        }
        .contentShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .onDrop(of: [.fileURL, .image, .png, .jpeg, .heic], isTargeted: $dropTargeted) { handleDrop($0) }
        .animation(.knFast, value: dropTargeted)
        .sheet(item: $viewing) { p in
            ProgressPhotoViewer(
                start: p,
                onClose: { viewing = nil },
                onChanged: { photos = ProgressPhotoStore.list() }
            )
        }
    }

    @ViewBuilder private var syncBadge: some View {
        if ProgressPhotoSync.isSyncing {
            ProgressView().controlSize(.small)
        } else if !ProgressPhotoStore.pending().isEmpty {
            Image(systemName: "icloud.and.arrow.up").font(.system(size: 12)).foregroundStyle(Palette.amber)
        } else if !photos.isEmpty {
            Image(systemName: "icloud.fill").font(.system(size: 12)).foregroundStyle(Palette.teal)
        }
    }

    /// One fixed height whether the day has photos or not. Photos arrive from an
    /// async reload and the strip swaps between "all days" and "one day" as the
    /// calendar opens — letting it size to its content meant the card (and every
    /// card under it) jumped around while you were scrolling past.
    private static let stripHeight: CGFloat = 150

    @ViewBuilder private var dayStrip: some View {
        Group {
            if stripPhotos.isEmpty {
                Text("No photo for \(Fmt.day(selectedDate)) yet.")
                    .font(.system(size: 12)).foregroundStyle(Palette.faint)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(stripPhotos) { p in thumb(p) }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .frame(height: Self.stripHeight, alignment: .topLeading)
    }

    /// Add photo. NSOpenPanel, not `.fileImporter` — the card already carries a
    /// sheet, and stacking SwiftUI presentations is what kept the picker shut.
    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        panel.message = "Choose a progress photo"
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        add(panel.urls)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }
        Task { @MainActor in
            var urls: [URL] = []
            for p in providers {
                let url: URL? = await withCheckedContinuation { cont in
                    _ = p.loadObject(ofClass: URL.self) { u, _ in cont.resume(returning: u) }
                }
                if let url, url.isFileURL { urls.append(url) }
            }
            add(urls)
        }
        return true
    }

    private func add(_ urls: [URL]) {
        var saved = false
        for url in urls {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            if ProgressPhotoStore.save(from: url, date: selectedDate) { saved = true }
        }
        guard saved else { return }
        photos = ProgressPhotoStore.list()
        Task { await ProgressPhotoSync.syncAll() }
    }

    private func thumb(_ p: ProgressPhoto) -> some View {
        Button { viewing = p } label: {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 4) {
                    DiskImage(url: p.url)
                        .frame(width: 92, height: 122)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
                    Text(Fmt.day(p.date)).font(.system(size: 9, weight: .semibold)).foregroundStyle(Palette.faint)
                }
                if !ProgressPhotoStore.isSynced(p.id) {
                    Image(systemName: "icloud.and.arrow.up.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(Palette.amber, in: Circle())
                        .padding(4)
                }
            }
        }
        .buttonStyle(KPressStyle())
        .onHover { h in cursor(h) }
    }

    private func reload() async {
        photos = ProgressPhotoStore.list()
        await ProgressPhotoSync.syncAll()
        photos = ProgressPhotoStore.list()
    }
}

/// Delete icon that opens a small confirm popover with a hold-to-confirm — the
/// only way a photo actually goes away, so there's never an accidental tap-delete.
private struct DeleteWithConfirmButton: View {
    let onDelete: () -> Void
    @State private var confirming = false

    var body: some View {
        Button { confirming = true } label: { Image(systemName: "trash").font(.system(size: 13, weight: .bold)) }
            .buttonStyle(KIconButtonStyle(size: 30, color: Palette.red))
            .popover(isPresented: $confirming, arrowEdge: .bottom) {
                VStack(spacing: 12) {
                    Text("Delete this photo?").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.text)
                    HoldToConfirmButton(label: "Hold to delete") {
                        confirming = false
                        onDelete()
                    }
                    .frame(width: 220)
                }
                .padding(16)
            }
    }
}

/// Loads an NSImage from a disk URL for display.
struct DiskImage: View {
    let url: URL
    /// `.fill` for thumbnails, `.fit` for the big viewer so nothing gets cropped.
    var contentMode: ContentMode = .fill
    var body: some View {
        if let img = NSImage(contentsOf: url) {
            Image(nsImage: img).resizable().aspectRatio(contentMode: contentMode)
        } else {
            Palette.surface2.opacity(0.5)
        }
    }
}

/// Near-full-screen viewer that pages across *every* photo (not just the
/// selected day) — on-screen arrows, ← / → keys, or a trackpad swipe. The Mac
/// counterpart of the iPhone's full-screen gallery. Delete lives top-left
/// behind a hold-to-confirm, so it can never be a stray click.
private struct ProgressPhotoViewer: View {
    let start: ProgressPhoto
    let onClose: () -> Void
    let onChanged: () -> Void

    @State private var live: [ProgressPhoto]
    @State private var index: Int

    init(start: ProgressPhoto, onClose: @escaping () -> Void, onChanged: @escaping () -> Void) {
        self.start = start
        self.onClose = onClose
        self.onChanged = onChanged
        let all = ProgressPhotoStore.list()
        _live = State(initialValue: all)
        _index = State(initialValue: all.firstIndex { $0.id == start.id } ?? 0)
    }

    private var current: ProgressPhoto? { live.indices.contains(index) ? live[index] : nil }
    private var canGoBack: Bool { index > 0 }
    private var canGoForward: Bool { index < live.count - 1 }

    /// Big, but never larger than the screen it opens on.
    private var viewerSize: CGSize {
        let visible = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1280, height: 800)
        return CGSize(width: min(1080, visible.width * 0.9), height: min(820, visible.height * 0.9))
    }

    var body: some View {
        VStack(spacing: 12) {
            header
            image
            keyboardShortcuts
        }
        .padding(20)
        .frame(width: viewerSize.width, height: viewerSize.height)
        .background(Palette.elevated)
    }

    private var header: some View {
        HStack {
            DeleteWithConfirmButton { deleteCurrent() }
            Spacer()
            VStack(spacing: 2) {
                Text(Fmt.day(current?.date ?? start.date))
                    .font(.system(size: 16, weight: .heavy, design: .rounded)).foregroundStyle(Palette.text)
                if live.count > 1 {
                    Text("\(index + 1) of \(live.count)")
                        .font(.system(size: 11, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(Palette.faint)
                }
            }
            Spacer()
            Button(action: onClose) { Image(systemName: "xmark").font(.system(size: 13, weight: .bold)) }
                .buttonStyle(KIconButtonStyle(size: 30))
        }
    }

    @ViewBuilder private var image: some View {
        if let p = current {
            ZStack {
                DiskImage(url: p.url, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                HStack {
                    arrow("chevron.left", enabled: canGoBack) { step(-1) }
                    Spacer()
                    arrow("chevron.right", enabled: canGoForward) { step(1) }
                }
                .padding(.horizontal, 10)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 20)
                    .onEnded { v in
                        if v.translation.width < -40 { step(1) }
                        else if v.translation.width > 40 { step(-1) }
                    }
            )
        } else {
            Spacer()
        }
    }

    private func arrow(_ icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).font(.system(size: 14, weight: .bold)) }
            .buttonStyle(KIconButtonStyle(size: 34))
            .disabled(!enabled)
            .opacity(enabled ? 0.85 : 0)
    }

    /// Invisible buttons that give the arrow keys the same job as the on-screen chevrons.
    private var keyboardShortcuts: some View {
        HStack(spacing: 0) {
            Button("") { step(-1) }.keyboardShortcut(.leftArrow, modifiers: [])
            Button("") { step(1) }.keyboardShortcut(.rightArrow, modifiers: [])
        }
        .opacity(0).frame(height: 0)
    }

    private func step(_ delta: Int) {
        let next = index + delta
        guard live.indices.contains(next) else { return }
        withAnimation(.knFast) { index = next }
    }

    private func deleteCurrent() {
        guard let p = current else { return }
        ProgressPhotoStore.delete(p)
        Task { await ProgressPhotoSync.delete(id: p.id) }
        live = ProgressPhotoStore.list()
        onChanged()
        if live.isEmpty {
            onClose()
        } else {
            index = min(index, live.count - 1)
        }
    }
}
