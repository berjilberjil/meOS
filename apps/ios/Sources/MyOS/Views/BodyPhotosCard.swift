#if os(iOS)
import SwiftUI
import PhotosUI
import Photos

/// Daily body photos on iPhone. New shots you heart in Photos → Favorites
/// land here automatically the next time MyOS is open, or add one yourself.
/// Everything also syncs to the shared "media" storage so it shows up on Mac.
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
                Text("Every photo you heart in Favorites lands here — or add one yourself.")
                    .font(.caption).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)

                if showCalendar {
                    ProgressPhotoCalendar(photoDates: photoDates, pendingDates: pendingDates, selected: $selectedDate)
                        .transition(.knReveal)
                }

                dayStrip
            }
        }
        // Reads the store and nothing else. Importing from Favorites and the
        // cloud sync used to run from here, which on the paged Today screen
        // meant a main-actor PHAsset fetch per day page, during the swipe.
        // `MainView` owns both now.
        .task {
            photos = ProgressPhotoStore.list()
            if photos.isEmpty { status = "Heart today’s photo in Favorites, or tap + to add one." }
        }
        .onReceive(NotificationCenter.default.publisher(for: .progressPhotosDidChange)) { _ in
            photos = ProgressPhotoStore.list()
        }
        .onReceive(NotificationCenter.default.publisher(for: .progressPhotosSyncDidChange)) { _ in
            photos = ProgressPhotoStore.list()
        }
        .photosPicker(isPresented: $adding, selection: $pickerItem, matching: .images)
        .onChange(of: pickerItem) { _, item in Task { await addPicked(item) } }
        .fullScreenCover(item: $viewing) { start in
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

    /// One fixed height whether the day has photos or not — see the note on the
    /// Mac card. Photos land asynchronously and the strip swaps between "all
    /// days" and "one day" when the calendar opens; sizing to content made the
    /// Today feed jump under your thumb mid-scroll.
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
                    ThumbImage(url: p.url, key: p.id, width: 132, height: 176) {
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

    /// `@MainActor` because everything after the first `await` in a nonisolated
    /// async method runs off the main actor — and this writes `@State` three
    /// times, which SwiftUI answers with "Publishing changes from background
    /// threads is not allowed" and intermittently dropped strip updates. The
    /// sibling `EventsView.loadPicked` wraps the same writes in `MainActor.run`;
    /// this one simply diverged.
    @MainActor
    private func addPicked(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        pickerItem = nil
        guard let data = try? await item.loadTransferable(type: Data.self),
              let ui = UIImage(data: data),
              let jpeg = ui.jpegData(compressionQuality: 0.85)
        else { return }
        // Today unless the calendar is open. `selectedDate` is seeded once and
        // left wherever it was last pointed, and once the calendar is folded
        // nothing on screen says which day that is — so a shot taken today was
        // filed under whatever old date you had been looking at, and the
        // comparison then read it as that day's body. Same after midnight, with
        // the calendar never opened at all.
        let target = showCalendar ? selectedDate : state.todayKey
        if ProgressPhotoStore.save(jpeg: jpeg, date: target) {
            photos = ProgressPhotoStore.list()
            await ProgressPhotoSync.syncAll()
            photos = ProgressPhotoStore.list()
        }
    }
}

/// Full-screen pager: swipe between days, pinch/double-tap to zoom. One
/// "Save to Photos" action; delete lives behind a confirm sheet up top so it
/// can never be a stray tap — nothing is ever "soft-deleted", the file (and
/// its cloud copy) is only removed once you hold to confirm.
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
            }
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 8)

            TabView(selection: $page) {
                ForEach(live) { p in
                    // Decoded per page, downsampled, off the main thread.
                    // `TabView` builds every page eagerly, so the old
                    // `UIImage(contentsOfFile:)` full-resolution-decoded the
                    // whole library the instant the viewer opened — and the
                    // Favorites importer brings in every hearted camera-roll
                    // shot, so that is hundreds of JPEGs at once. The UI froze
                    // for seconds and a real device jetsammed the app. The strip
                    // has used ThumbCache for exactly this reason all along.
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
                Label(saveStatus == "Saved" ? "Saved to Photos" : "Save to Photos",
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
                .presentationDetents([.height(230)])
                .presentationDragIndicator(.visible)
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
        guard let p = live.first(where: { $0.id == page }),
              let ui = UIImage(contentsOfFile: p.url.path) else {
            saveStatus = "Couldn’t read that photo."
            return
        }
        Task {
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else {
                await MainActor.run { saveStatus = "Allow Photos access in Settings." }
                return
            }
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAsset(from: ui)
                }
                await MainActor.run { saveStatus = "Saved" }
            } catch {
                await MainActor.run { saveStatus = "Couldn’t save — try again." }
            }
        }
    }

    private func deleteCurrent() {
        let deletingId = page
        // Where the deleted photo sat, so the viewer lands on its neighbour.
        // Jumping to `live.first` meant deleting an old photo threw you to
        // today's shot, so clearing out a run of old ones meant scrolling back
        // from the top of the library every single time.
        let index = live.firstIndex { $0.id == deletingId } ?? 0
        // Into the bin, not off the disk — the cloud copy is what lets the Mac
        // give this back too, so it stays until the entry expires.
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

/// One page of the full-screen gallery.
///
/// Loads its own image lazily and downsampled, so opening the viewer costs one
/// decode rather than one per photo in the library.
private struct GalleryPage: View {
    let photo: ProgressPhoto
    @State private var image: UIImage?

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
            // Screen-sized, not sensor-sized: plenty for pinch-zoom on a phone.
            image = await ThumbCache.load(photo.url, key: "full-\(photo.id)", maxPixel: 2048)
        }
    }
}

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
            scale = 1
            lastScale = 1
            offset = .zero
            lastOffset = .zero
        }
    }
}
#endif
