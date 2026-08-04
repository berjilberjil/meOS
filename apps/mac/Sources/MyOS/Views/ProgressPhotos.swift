import SwiftUI
import AppKit
import UniformTypeIdentifiers

// Progress photos — stored locally on disk (Application Support/MyOS/progress/),
// one JPEG per day, NOT synced to the server (images would bloat the KV store).
// Lets the user see how their body changes over time.

struct ProgressPhoto: Identifiable, Hashable {
    let date: String   // yyyy-MM-dd
    let url: URL
    var id: String { date }
}

enum ProgressPhotoStore {
    static let dir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let d = base.appendingPathComponent("MyOS/progress", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    static func url(for date: String) -> URL { dir.appendingPathComponent("\(date).jpg") }

    static func list() -> [ProgressPhoto] {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension.lowercased() == "jpg" }
            .map { ProgressPhoto(date: $0.deletingPathExtension().lastPathComponent, url: $0) }
            .sorted { $0.date > $1.date }
    }

    /// Save an image (from a file url) as the given day's JPEG.
    @discardableResult
    static func save(from source: URL, date: String) -> Bool {
        guard let img = NSImage(contentsOf: source),
              let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
        else { return false }
        do { try jpeg.write(to: url(for: date), options: .atomic); return true } catch { return false }
    }

    static func delete(_ date: String) { try? FileManager.default.removeItem(at: url(for: date)) }
}

/// A card of progress photos with an add button and a viewer.
struct ProgressPhotosCard: View {
    @EnvironmentObject var state: AppState
    @State private var photos: [ProgressPhoto] = []
    @State private var importing = false
    @State private var viewing: ProgressPhoto?

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionTitle(text: "Progress photos")
                    Spacer()
                    Button { importing = true } label: { Label("Add photo", systemImage: "camera.fill") }
                        .buttonStyle(KGhostButtonStyle(color: Palette.brand))
                }
                if photos.isEmpty {
                    Text("Add a photo to track how your body changes over time. Saved on this Mac only.")
                        .font(.system(size: 13)).foregroundStyle(Palette.faint)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(photos) { p in thumb(p) }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .onAppear { reload() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.image]) { result in
            if case .success(let url) = result {
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                _ = ProgressPhotoStore.save(from: url, date: state.todayKey)
                reload()
            }
        }
        .sheet(item: $viewing) { p in viewer(p) }
    }

    private func thumb(_ p: ProgressPhoto) -> some View {
        Button { viewing = p } label: {
            VStack(spacing: 4) {
                DiskImage(url: p.url)
                    .frame(width: 92, height: 122)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
                Text(Fmt.day(p.date)).font(.system(size: 9, weight: .semibold)).foregroundStyle(Palette.faint)
            }
        }
        .buttonStyle(KPressStyle())
        .onHover { h in cursor(h) }
    }

    private func viewer(_ p: ProgressPhoto) -> some View {
        VStack(spacing: 14) {
            HStack {
                Text(Fmt.day(p.date)).font(.system(size: 16, weight: .heavy, design: .rounded)).foregroundStyle(Palette.text)
                Spacer()
                Button { ProgressPhotoStore.delete(p.date); viewing = nil; reload() } label: {
                    Image(systemName: "trash").font(.system(size: 13))
                }
                .buttonStyle(KIconButtonStyle(size: 30, color: Palette.red))
                Button { viewing = nil } label: { Image(systemName: "xmark").font(.system(size: 13, weight: .bold)) }
                    .buttonStyle(KIconButtonStyle(size: 30))
            }
            DiskImage(url: p.url)
                .frame(maxWidth: 420, maxHeight: 560)
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
        .padding(20).frame(width: 480)
        .background(Palette.elevated)
    }

    private func reload() { photos = ProgressPhotoStore.list() }
}

/// Loads an NSImage from a disk URL for display.
struct DiskImage: View {
    let url: URL
    var body: some View {
        if let img = NSImage(contentsOf: url) {
            Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
        } else {
            Palette.surface2.opacity(0.5)
        }
    }
}
