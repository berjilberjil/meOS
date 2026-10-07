import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// Daily body photos, on the Mac — the iOS card, ported.
///
/// Everything syncs to the shared media storage so it shows up on the phone.
/// On the Mac there is no Favorites import and no camera roll, so photos are
/// added with the picker; "Save to Photos" becomes the platform save panel.
/// Replaces the old Mac `ProgressPhotosCard` everywhere Today and Fitness
/// showed it.
struct BodyPhotosCard: View {
    @EnvironmentObject var state: AppState
    @State private var photos: [ProgressPhoto] = []
    @State private var selectedDate: String = AppState.dateKey(Date())
    @State private var viewing: ProgressPhoto?
    @State private var status = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var adding = false
    /// The month grid is heavy; it stays folded away until you ask for it.
    @State private var showCalendar = false

    private var photoDates: Set<String> { Set(photos.map(\.date)) }
    private var pendingDates: Set<String> { Set(ProgressPhotoStore.pending().map(\.date)) }
    private var photosForSelectedDay: [ProgressPhoto] { photos.filter { $0.date == selectedDate } }
    private var stripPhotos: [ProgressPhoto] {
        showCalendar ? photosForSelectedDay : photos.sorted { $0.date > $1.date }
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                header
                Text("Add a photo yourself — it syncs to your phone, and the other way round.")
                    .font(.caption).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)

                if showCalendar {
                    ProgressPhotoCalendar(photoDates: photoDates, pendingDates: pendingDates, selected: $selectedDate)
                        .transition(.knReveal)
                }

                dayStrip
            }
        }
        .task {
            photos = ProgressPhotoStore.list()
            if photos.isEmpty { status = "Tap + to add today's shot." }
        }
        .onReceive(NotificationCenter.default.publisher(for: .progressPhotosDidChange)) { _ in
            photos = ProgressPhotoStore.list()
        }
        .onReceive(NotificationCenter.default.publisher(for: .progressPhotosSyncDidChange)) { _ in
            photos = ProgressPhotoStore.list()
        }
        .photosPicker(isPresented: $adding, selection: $pickerItem, matching: .images)
        .onChange(of: pickerItem) { _, item in Task { await addPicked(item) } }
        .sheet(item: $viewing) { start in
            ProgressGallery(photos: photos, start: start) {
                viewing = nil
                photos = ProgressPhotoStore.list()
            }
        }
    }

    private var header: some View {
        HStack {
            SectionTitle(text: "Daily progress")
            Spacer()
            syncBadge
            Button {
                withAnimation(.knNormal) { showCalendar.toggle() }
            } label: {
                Image(systemName: showCalendar ? "calendar.badge.minus" : "calendar")
                    .font(.callout.weight(.semibold))
            }
            .buttonStyle(.borderless).tint(showCalendar ? Palette.action : Palette.muted)
            .accessibilityLabel(showCalendar ? "Hide calendar" : "Show calendar")
            Button { adding = true } label: {
                Image(systemName: "plus.circle.fill").font(.body.weight(.semibold))
            }
            .buttonStyle(.borderless).tint(Palette.success)
            .accessibilityLabel("Add photo")
        }
    }

    @ViewBuilder private var syncBadge: some View {
        if ProgressPhotoSync.isSyncing {
            ProgressView().controlSize(.mini)
        } else if !ProgressPhotoStore.pending().isEmpty {
            Image(systemName: "icloud.and.arrow.up").font(.caption).foregroundStyle(Palette.attention)
                .accessibilityLabel("Some photos haven't uploaded yet")
        } else if !photos.isEmpty {
            Image(systemName: "icloud.fill").font(.caption).foregroundStyle(Palette.success)
                .accessibilityLabel("All photos synced")
        }
    }

    /// One fixed height whether the day has photos or not — the strip swaps
    /// between "all days" and "one day" when the calendar opens; sizing to
    /// content makes the Today feed jump mid-scroll.
    private static let stripHeight: CGFloat = 203

    @ViewBuilder private var dayStrip: some View {
        Group {
            if stripPhotos.isEmpty {
                Text(photos.isEmpty ? (status.isEmpty ? "No body photos yet." : status)
                                     : "No photo for \(Fmt.day(selectedDate)) yet.")
                    .font(.footnote).foregroundStyle(Palette.faint)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(stripPhotos) { p in thumb(p) }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .frame(height: Self.stripHeight, alignment: .topLeading)
    }

    private func thumb(_ p: ProgressPhoto) -> some View {
        Button { viewing = p } label: {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 6) {
                    PhotoThumb(url: p.url, key: p.id, width: 132, height: 176) {
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(Palette.surfaceElevated)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    Text(Fmt.day(p.date)).font(.caption2.weight(.semibold)).foregroundStyle(Palette.faint)
                }
                if !ProgressPhotoStore.isSynced(p.id) {
                    Image(systemName: "icloud.and.arrow.up.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(5)
                        .background(Palette.attention, in: Circle())
                        .padding(6)
                }
            }
        }
        .buttonStyle(.plain)
    }

    @MainActor
    private func addPicked(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        pickerItem = nil
        guard let data = try? await item.loadTransferable(type: Data.self),
              let img = NSImage(data: data),
              let jpeg = Self.jpegData(from: img, quality: 0.85)
        else { return }
        // Today unless the calendar is open — the strip is filed under
        // whatever day you were looking at, never a stale selection.
        let target = showCalendar ? selectedDate : state.todayKey
        if ProgressPhotoStore.save(jpeg: jpeg, date: target) {
            photos = ProgressPhotoStore.list()
            await ProgressPhotoSync.syncAll()
            photos = ProgressPhotoStore.list()
        }
    }

    static func jpegData(from image: NSImage, quality: CGFloat) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
    }
}

/// The gallery behind a thumbnail: paging between days, zoom, save, delete.
///
/// Delete is behind a hold-to-confirm and goes to the recycle bin, never off
/// the disk — the cloud copy is what lets the phone give it back too.
private struct ProgressGallery: View {
    @EnvironmentObject var state: AppState
    let photos: [ProgressPhoto]
    let start: ProgressPhoto
    let onClose: () -> Void

    @State private var page: String
    @State private var live: [ProgressPhoto]
    @State private var saveStatus = ""
    @State private var confirmingDelete = false

    init(photos: [ProgressPhoto], start: ProgressPhoto, onClose: @escaping () -> Void) {
        self.photos = photos
        self.start = start
        self.onClose = onClose
        _page = State(initialValue: start.id)
        _live = State(initialValue: photos)
    }

    private var currentDate: String {
        live.first(where: { $0.id == page })?.date ?? start.date
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { confirmingDelete = true } label: {
                    Image(systemName: "trash").font(.footnote.weight(.bold))
                }
                .buttonStyle(.borderless).tint(Palette.warning)
                .accessibilityLabel("Delete photo")

                Spacer()
                Text(Fmt.day(currentDate)).font(.callout.weight(.semibold)).foregroundStyle(Palette.text)
                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark").font(.footnote.weight(.bold))
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 8)

            TabView(selection: $page) {
                ForEach(live) { p in
                    GalleryPage(photo: p).tag(p.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .onChange(of: page) { _, _ in saveStatus = "" }

            if !saveStatus.isEmpty {
                Text(saveStatus).font(.caption.weight(.semibold))
                    .foregroundStyle(saveStatus == "Saved" ? Palette.green : Palette.attention)
            }
            Button { saveCurrent() } label: {
                Label(saveStatus == "Saved" ? "Saved" : "Save a copy\u{2026}",
                      systemImage: saveStatus == "Saved" ? "checkmark.circle.fill" : "square.and.arrow.down")
                    .font(.footnote.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(Palette.success).controlSize(.large).frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .background(Palette.background)
        .sheet(isPresented: $confirmingDelete) {
            deleteSheet
        }
    }

    private var deleteSheet: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text("Delete this photo?").font(.callout.weight(.bold)).foregroundStyle(Palette.text)
                Text("This removes it from this device and the cloud. It can't be undone.")
                    .font(.caption).foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.center)
            }
            HoldToConfirmButton(label: "Hold to delete") {
                confirmingDelete = false
                deleteCurrent()
            }
            Button("Cancel") { confirmingDelete = false }
                .buttonStyle(.borderless)
        }
        .padding(20)
    }

    private func saveCurrent() {
        guard let p = live.first(where: { $0.id == page }) else {
            saveStatus = "Couldn't read that photo."
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.jpeg]
        panel.nameFieldStringValue = "MyOS-\(p.date).jpg"
        panel.begin { response in
            guard response == .OK, let url = panel.url,
                  let data = try? Data(contentsOf: p.url) else { return }
            do {
                try data.write(to: url)
                Task { @MainActor in saveStatus = "Saved" }
            } catch {
                Task { @MainActor in saveStatus = "Couldn't save — try again." }
            }
        }
    }

    private func deleteCurrent() {
        let deletingId = page
        // Where the deleted photo sat, so the viewer lands on its neighbour.
        let index = live.firstIndex { $0.id == deletingId } ?? 0
        // Into the bin, not off the disk — the cloud copy is what lets the
        // phone give this back too, so it stays until the entry expires.
        if let photo = live.first(where: { $0.id == deletingId }) {
            state.recycleProgressPhoto(photo)
        }
        live = ProgressPhotoStore.list()
        if live.isEmpty {
            onClose()
        } else {
            page = live[min(index, live.count - 1)].id
        }
    }
}

/// One page of the gallery: decoded lazily, downsampled, cached.
private struct GalleryPage: View {
    let photo: ProgressPhoto
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                ZoomableImage(image: image)
            } else {
                Palette.surfaceElevated
            }
        }
        .task(id: photo.id) {
            guard image == nil else { return }
            image = await MacThumbCache.load(url: photo.url, key: "full-\(photo.id)", maxPixel: 2048)
        }
    }
}

/// Disk-backed photo, downsampled via the shared Mac thumb cache.
private struct PhotoThumb<Placeholder: View>: View {
    let url: URL
    let key: String
    let width: CGFloat
    let height: CGFloat
    @ViewBuilder let placeholder: () -> Placeholder
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                placeholder().overlay(ProgressView().controlSize(.mini).tint(Palette.faint))
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .task(id: key) {
            image = await MacThumbCache.load(url: url, key: key, maxPixel: max(width, height) * 2)
        }
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
