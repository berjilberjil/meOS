import SwiftUI
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#else
import UIKit
import PhotosUI
#endif

/// A drop / paste / choose target for screenshots. Downscales + JPEG-encodes
/// everything to base64 (small enough for the serverless upload limit) and hands
/// it back via `onImages`. The one place image input lives in MyOS — used by the
/// Food scanner. macOS supports drag-drop + paste + a file picker; iOS supports
/// the camera (the whole point of scanning a food label on your phone) plus the
/// photo library.
struct ImageDropZone: View {
    var title: String
    var subtitle: String
    var tint: Color = Palette.action
    var busy: Bool = false
    var startWithCamera: Bool = false
    /// (base64 PNGs, mediaType) — mediaType is always "image/png" here.
    var onImages: ([String], String) -> Void

    var body: some View {
        #if os(macOS)
        MacImageDropZone(title: title, subtitle: subtitle, tint: tint, busy: busy, onImages: onImages)
        #else
        IOSImageDropZone(title: title, subtitle: subtitle, tint: tint, busy: busy,
                         startWithCamera: startWithCamera, onImages: onImages)
        #endif
    }
}

#if os(macOS)

private struct MacImageDropZone: View {
    var title: String
    var subtitle: String
    var tint: Color
    var busy: Bool
    var onImages: ([String], String) -> Void

    @State private var targeted = false
    @State private var importing = false

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Image(systemName: busy ? "sparkles" : "photo.on.rectangle.angled")
                    .font(.title.weight(.semibold))
                    .foregroundStyle(busy ? tint : (targeted ? tint : Palette.muted))
                    .symbolEffect(.pulse, isActive: busy)
            }
            .frame(height: 30)

            VStack(spacing: 3) {
                Text(busy ? "Reading it…" : title)
                    .font(.footnote.weight(.heavy))
                    .foregroundStyle(Palette.text)
                Text(busy ? "Gemini is pulling out the numbers." : subtitle)
                    .font(.caption)
                    .foregroundStyle(Palette.faint)
                    .multilineTextAlignment(.center)
            }

            if !busy {
                HStack(spacing: 8) {
                    Button { importing = true } label: { Label("Choose file", systemImage: "folder") }
                        .buttonStyle(.bordered).tint(tint)
                    Button { pasteFromClipboard() } label: { Label("Paste", systemImage: "doc.on.clipboard") }
                        .buttonStyle(.bordered).tint(tint)
                }
            } else {
                ProgressView().controlSize(.small).tint(tint)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26).padding(.horizontal, 18)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(targeted ? tint.opacity(0.10) : Palette.background.opacity(0.5))
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
        // Downscale + JPEG-encode so the upload stays well under the serverless
        // request-body limit: a full-res image as PNG base64 blows past it, and
        // the backend then reads the truncated body as empty → a 400.
        let jpegs = data.compactMap { Self.downscaledJPEG(fromImageData: $0) }
        guard !jpegs.isEmpty else { return }
        onImages(jpegs.map { $0.base64EncodedString() }, "image/jpeg")
    }

    static func downscaledJPEG(fromImageData data: Data, maxDimension: CGFloat = 1280,
                               quality: CGFloat = 0.65) -> Data? {
        guard let img = NSImage(data: data) else { return nil }
        return downscaledJPEG(img, maxDimension: maxDimension, quality: quality)
    }

    static func downscaledJPEG(_ image: NSImage, maxDimension: CGFloat = 1280,
                               quality: CGFloat = 0.65) -> Data? {
        guard let tiff = image.tiffRepresentation, let src = NSBitmapImageRep(data: tiff) else { return nil }
        let w = CGFloat(src.pixelsWide), h = CGFloat(src.pixelsHigh)
        let scale = min(1, maxDimension / max(w, h))
        let tw = max(1, Int(w * scale)), th = max(1, Int(h * scale))
        let target = NSImage(size: NSSize(width: tw, height: th))
        target.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        src.draw(in: NSRect(x: 0, y: 0, width: tw, height: th))
        target.unlockFocus()
        guard let outTiff = target.tiffRepresentation, let outRep = NSBitmapImageRep(data: outTiff) else { return nil }
        return outRep.representation(using: .jpeg, properties: [.compressionFactor: quality])
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

#else

/// iOS: a big camera hero — tap the circle to shoot, or pick from the library.
/// The old dashed empty box was not tappable after the first camera dismiss.
private struct IOSImageDropZone: View {
    var title: String
    var subtitle: String
    var tint: Color
    var busy: Bool
    var startWithCamera: Bool
    var onImages: ([String], String) -> Void

    @ObservedObject private var signals = UISignals.shared
    @State private var showCamera = false
    @State private var pickerItems: [PhotosPickerItem] = []

    var body: some View {
        VStack(spacing: 16) {
            Button { openCamera() } label: {
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(tint)
                            .frame(width: 96, height: 96)
                        if busy {
                            ProgressView().controlSize(.large).tint(.white)
                        } else {
                            Image(systemName: "viewfinder")
                                .font(.largeTitle.weight(.bold))
                                .foregroundStyle(.white)
                        }
                    }
                    VStack(spacing: 6) {
                        Text(busy ? "Reading…" : title)
                            .font(.title2.weight(.semibold)).foregroundStyle(Palette.text)
                        Text(busy ? "Catherine is looking at the photo." : subtitle)
                            .font(.subheadline).foregroundStyle(Palette.muted)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20).padding(.horizontal, 20)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .strokeBorder(tint.opacity(0.35), lineWidth: 1.5))
            }
            .buttonStyle(.plain)
            .disabled(busy)

            HStack(spacing: 10) {
                Label("Point the camera at food, a pack, or a receipt", systemImage: "lightbulb")
                    .font(.caption).foregroundStyle(Palette.faint)
                Spacer(minLength: 0)
            }

            PhotosPicker(selection: $pickerItems, maxSelectionCount: 1, matching: .images) {
                Label("Choose from library", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered).controlSize(.large).frame(maxWidth: .infinity)
            .disabled(busy)
        }
        .animation(.knNormal, value: busy)
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                var out: [Data] = []
                for item in items {
                    if let raw = try? await item.loadTransferable(type: Data.self),
                       let png = Self.normalizedPNG(raw) {
                        out.append(png)
                    }
                }
                pickerItems = []
                emit(out)
            }
        }
        .sheet(isPresented: $showCamera) {
            CameraCapture { image in
                if let img = image, let png = Self.pngData(img) { emit([png]) }
            }
            .ignoresSafeArea()
        }
        .onAppear {
            if startWithCamera || signals.openScanCamera {
                signals.openScanCamera = false
                openCamera()
            }
        }
        .onChange(of: signals.openScanCamera) { _, on in
            guard on else { return }
            signals.openScanCamera = false
            openCamera()
        }
    }

    private func openCamera() {
        guard !busy, UIImagePickerController.isSourceTypeAvailable(.camera) else { return }
        showCamera = true
    }

    private func emit(_ data: [Data]) {
        // Downscale + JPEG-encode so the upload stays well under the serverless
        // request-body limit — a full-res camera photo as PNG base64 is far too
        // large, and the backend reads the truncated body as empty → a 400.
        let jpegs = data.compactMap { Self.downscaledJPEG(fromImageData: $0) }
        guard !jpegs.isEmpty else { return }
        onImages(jpegs.map { $0.base64EncodedString() }, "image/jpeg")
    }

    static func normalizedPNG(_ data: Data) -> Data? {
        guard let img = UIImage(data: data) else { return nil }
        return pngData(img)
    }
    static func pngData(_ image: UIImage) -> Data? { image.pngData() }

    static func downscaledJPEG(fromImageData data: Data, maxDimension: CGFloat = 1280,
                               quality: CGFloat = 0.65) -> Data? {
        guard let img = UIImage(data: data) else { return nil }
        return downscaledJPEG(img, maxDimension: maxDimension, quality: quality)
    }

    static func downscaledJPEG(_ image: UIImage, maxDimension: CGFloat = 1280,
                               quality: CGFloat = 0.65) -> Data? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(1, maxDimension / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let scaled = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return scaled.jpegData(compressionQuality: quality)
    }
}

/// Thin UIImagePickerController wrapper — SwiftUI has no native camera capture view.
private struct CameraCapture: UIViewControllerRepresentable {
    let onCapture: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let vc = UIImagePickerController()
        vc.sourceType = .camera
        vc.delegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onCapture: onCapture) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (UIImage?) -> Void
        init(onCapture: @escaping (UIImage?) -> Void) { self.onCapture = onCapture }

        func imagePickerController(_ picker: UIImagePickerController,
                                    didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onCapture(info[.originalImage] as? UIImage)
            picker.dismiss(animated: true)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCapture(nil)
            picker.dismiss(animated: true)
        }
    }
}

#endif
