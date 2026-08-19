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
                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)

                if showCalendar {
                    ProgressPhotoCalendar(photoDates: photoDates, pendingDates: pendingDates, selected: $selectedDate)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                dayStrip
            }
        }
        .task { await reload() }
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
                    .font(.system(size: 16, weight: .semibold))
            }
            .buttonStyle(KIconButtonStyle(size: 30, color: showCalendar ? Palette.brand : Palette.muted))
            .accessibilityLabel(showCalendar ? "Hide calendar" : "Show calendar")
            Button { adding = true } label: {
                Image(systemName: "plus.circle.fill").font(.system(size: 18, weight: .semibold))
            }
            .buttonStyle(KIconButtonStyle(size: 30, color: Palette.teal))
            .accessibilityLabel("Add photo")
        }
    }

    @ViewBuilder private var syncBadge: some View {
        if ProgressPhotoSync.isSyncing {
            ProgressView().controlSize(.mini)
        } else if !ProgressPhotoStore.pending().isEmpty {
            Image(systemName: "icloud.and.arrow.up").font(.system(size: 12)).foregroundStyle(Palette.amber)
                .accessibilityLabel("Some photos haven't uploaded yet")
        } else if !photos.isEmpty {
            Image(systemName: "icloud.fill").font(.system(size: 12)).foregroundStyle(Palette.teal)
                .accessibilityLabel("All photos synced")
        }
    }

    @ViewBuilder private var dayStrip: some View {
        if stripPhotos.isEmpty {
            Text(photos.isEmpty ? (status.isEmpty ? "No body photos yet." : status)
                                 : "No photo for \(Fmt.day(selectedDate)) yet.")
                .font(.system(size: 13)).foregroundStyle(Palette.faint)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(stripPhotos) { p in thumb(p) }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func thumb(_ p: ProgressPhoto) -> some View {
        Button { viewing = p } label: {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 6) {
                    if let ui = UIImage(contentsOfFile: p.url.path) {
                        Image(uiImage: ui).resizable().scaledToFill()
                            .frame(width: 132, height: 176)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    } else {
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(Palette.surface2).frame(width: 132, height: 176)
                    }
                    Text(Fmt.day(p.date)).font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.faint)
                }
                if !ProgressPhotoStore.isSynced(p.id) {
                    Image(systemName: "icloud.and.arrow.up.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(5)
                        .background(Palette.amber, in: Circle())
                        .padding(6)
                }
            }
        }
        .buttonStyle(KPressStyle())
    }

    private func reload() async {
        await FavoritesBodyImporter.sync()
        photos = ProgressPhotoStore.list()
        if photos.isEmpty { status = "Heart today’s photo in Favorites, or tap + to add one." }
        await ProgressPhotoSync.syncAll()
        photos = ProgressPhotoStore.list()
    }

    private func addPicked(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        pickerItem = nil
        guard let data = try? await item.loadTransferable(type: Data.self),
              let ui = UIImage(data: data),
              let jpeg = ui.jpegData(compressionQuality: 0.85)
        else { return }
        if ProgressPhotoStore.save(jpeg: jpeg, date: selectedDate) {
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
                    Image(systemName: "trash").font(.system(size: 14, weight: .bold))
                }
                .buttonStyle(KIconButtonStyle(size: 30, color: Palette.red))
                .accessibilityLabel("Delete photo")

                Spacer()
                Text(Fmt.day(currentDate)).font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.text)
                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .bold))
                }
                .buttonStyle(KIconButtonStyle(size: 30))
            }
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 8)

            TabView(selection: $page) {
                ForEach(live) { p in
                    Group {
                        if let ui = UIImage(contentsOfFile: p.url.path) {
                            ZoomableImage(image: ui)
                        } else {
                            Palette.surface2
                        }
                    }
                    .tag(p.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .onChange(of: page) { _, _ in saveStatus = "" }

            if !saveStatus.isEmpty {
                Text(saveStatus).font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(saveStatus == "Saved" ? Palette.green : Palette.amber)
            }
            Button { saveCurrent() } label: {
                Label(saveStatus == "Saved" ? "Saved to Photos" : "Save to Photos",
                      systemImage: saveStatus == "Saved" ? "checkmark.circle.fill" : "square.and.arrow.down")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(KPrimaryButtonStyle(tint: Palette.teal, fullWidth: true))
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .background(Palette.bg.ignoresSafeArea())
        .sheet(isPresented: $confirmingDelete) {
            deleteSheet
                .presentationDetents([.height(230)])
                .presentationDragIndicator(.visible)
        }
    }

    private var deleteSheet: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text("Delete this photo?").font(.system(size: 16, weight: .bold)).foregroundStyle(Palette.text)
                Text("This removes it from this device and the cloud. It can't be undone.")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.center)
            }
            HoldToConfirmButton(label: "Hold to delete") {
                confirmingDelete = false
                deleteCurrent()
            }
            Button("Cancel") { confirmingDelete = false }
                .buttonStyle(KGhostButtonStyle())
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
        ProgressPhotoStore.delete(deletingId)
        live = ProgressPhotoStore.list()
        if let next = live.first {
            page = next.id
        } else {
            onClose()
        }
        Task { await ProgressPhotoSync.delete(id: deletingId) }
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
