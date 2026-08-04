import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// A drop / paste / choose target for screenshots. Normalises everything to PNG
/// base64 and hands it back via `onImages`. Reused by the Money capture card and
/// the Portfolio tracker — the one place image input lives in MyOS.
struct ImageDropZone: View {
    var title: String
    var subtitle: String
    var tint: Color = Palette.brand
    var busy: Bool = false
    /// (base64 PNGs, mediaType) — mediaType is always "image/png" here.
    var onImages: ([String], String) -> Void

    @State private var targeted = false
    @State private var importing = false

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Image(systemName: busy ? "sparkles" : "photo.on.rectangle.angled")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(busy ? tint : (targeted ? tint : Palette.muted))
                    .symbolEffect(.pulse, isActive: busy)
            }
            .frame(height: 30)

            VStack(spacing: 3) {
                Text(busy ? "Reading it…" : title)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(Palette.text)
                Text(busy ? "Gemini is pulling out the numbers." : subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.faint)
                    .multilineTextAlignment(.center)
            }

            if !busy {
                HStack(spacing: 8) {
                    Button { importing = true } label: { Label("Choose file", systemImage: "folder") }
                        .buttonStyle(KSoftButtonStyle(tint: tint))
                    Button { pasteFromClipboard() } label: { Label("Paste", systemImage: "doc.on.clipboard") }
                        .buttonStyle(KSoftButtonStyle(tint: tint))
                }
            } else {
                ProgressView().controlSize(.small).tint(tint)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26).padding(.horizontal, 18)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(targeted ? tint.opacity(0.10) : Palette.bg.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [7, 6]))
                .foregroundStyle(targeted ? tint : Palette.border)
        )
        .animation(.knFast, value: targeted)
        .animation(.knNormal, value: busy)
        .onDrop(of: [.fileURL, .image, .png, .jpeg, .tiff], isTargeted: $targeted) { providers in
            guard !busy else { return false }
            Task { await handle(providers) }
            return true
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.image],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                let data = urls.compactMap { url -> Data? in
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    return (try? Data(contentsOf: url)).flatMap(Self.normalizedPNG)
                }
                emit(data)
            }
        }
    }

    // MARK: - Input handling

    private func handle(_ providers: [NSItemProvider]) async {
        var out: [Data] = []
        for p in providers {
            if let d = await Self.imageData(from: p) { out.append(d) }
        }
        emit(out)
    }

    private func pasteFromClipboard() {
        let pb = NSPasteboard.general
        var out: [Data] = []
        if let images = pb.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage] {
            for img in images { if let png = Self.pngData(img) { out.append(png) } }
        }
        if out.isEmpty, let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            out = urls.compactMap { (try? Data(contentsOf: $0)).flatMap(Self.normalizedPNG) }
        }
        emit(out)
    }

    private func emit(_ data: [Data]) {
        guard !data.isEmpty else { return }
        onImages(data.map { $0.base64EncodedString() }, "image/png")
    }

    // MARK: - Provider → PNG data

    private static func imageData(from provider: NSItemProvider) async -> Data? {
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier),
           let data = await loadData(provider, for: .image),
           let png = normalizedPNG(data) {
            return png
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
           let url = await loadFileURL(provider),
           let data = try? Data(contentsOf: url) {
            return normalizedPNG(data)
        }
        return nil
    }

    /// `loadDataRepresentation(for:)` returns a Progress, so Swift gives us no async
    /// bridge — wrap the completion-handler form ourselves.
    private static func loadData(_ provider: NSItemProvider, for type: UTType) async -> Data? {
        await withCheckedContinuation { cont in
            _ = provider.loadDataRepresentation(for: type) { data, _ in
                cont.resume(returning: data)
            }
        }
    }

    private static func loadFileURL(_ provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { cont in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    cont.resume(returning: url)
                } else if let url = item as? URL {
                    cont.resume(returning: url)
                } else {
                    cont.resume(returning: nil)
                }
            }
        }
    }

    /// Re-encode any image bytes to PNG so the backend gets a consistent format.
    static func normalizedPNG(_ data: Data) -> Data? {
        guard let img = NSImage(data: data) else { return nil }
        return pngData(img)
    }

    static func pngData(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
