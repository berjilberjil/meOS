#if os(iOS)
import SwiftUI
import Photos

/// Daily body photos on iPhone. New shots you heart in Photos → Favorites
/// land here automatically the next time MyOS is open.
struct BodyPhotosCard: View {
    @EnvironmentObject var state: AppState
    @State private var photos: [ProgressPhoto] = []
    @State private var viewing: ProgressPhoto?
    @State private var status = ""

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionTitle(text: "Daily progress")
                    Spacer()
                    Text("hearted photos").font(.system(size: 10)).foregroundStyle(Palette.faint)
                }
                Text("Every photo you heart in Favorites lands here.")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)

                if photos.isEmpty {
                    Text(status.isEmpty ? "No body photos yet." : status)
                        .font(.system(size: 13)).foregroundStyle(Palette.faint)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(photos) { p in thumb(p) }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .task { await reload() }
        .onReceive(NotificationCenter.default.publisher(for: .progressPhotosDidChange)) { _ in
            photos = ProgressPhotoStore.list()
        }
        .fullScreenCover(item: $viewing) { start in
            ProgressGallery(photos: photos, start: start) {
                viewing = nil
                photos = ProgressPhotoStore.list()
            }
        }
    }

    private func thumb(_ p: ProgressPhoto) -> some View {
        Button { viewing = p } label: {
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
        }
        .buttonStyle(KPressStyle())
    }

    private func reload() async {
        await FavoritesBodyImporter.sync()
        photos = ProgressPhotoStore.list()
        if photos.isEmpty { status = "Heart today’s photo in Favorites, then come back." }
    }
}

/// Full-screen pager: swipe between days, pinch/double-tap to zoom, hold to delete.
private struct ProgressGallery: View {
    let photos: [ProgressPhoto]
    let start: ProgressPhoto
    let onClose: () -> Void

    @State private var page: String
    @State private var live: [ProgressPhoto]
    @State private var saveStatus = ""

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
                Text(Fmt.day(currentDate)).font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.text)
                Spacer()
                Button { saveCurrent() } label: {
                    Image(systemName: saveStatus == "Saved" ? "checkmark.circle.fill" : "square.and.arrow.down")
                        .font(.system(size: 14, weight: .bold))
                }
                .buttonStyle(KIconButtonStyle(size: 30, color: saveStatus == "Saved" ? Palette.green : Palette.teal))
                .accessibilityLabel("Save to Photos")
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

            HoldToConfirmButton(label: "Hold to delete") {
                deleteCurrent()
            }
            .frame(height: 44)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(Palette.bg.ignoresSafeArea())
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
        ProgressPhotoStore.delete(page)
        live = ProgressPhotoStore.list()
        if let next = live.first {
            page = next.id
        } else {
            onClose()
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
