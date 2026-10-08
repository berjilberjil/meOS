import AVFoundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Compress + encode a video for inline storage on an `EventItem`. Because the whole
/// app state is one zero-knowledge-encrypted, fully-synced blob, video must stay small:
/// we transcode to ≤540p H.264 and hard-cap the encoded bytes. A first-frame poster is
/// grabbed for the grid so we never decode the whole clip just to show a thumbnail.
///
/// ImageIO for the poster, not AppKit — the iOS event editor encodes clips too.
enum VideoMedia {
    /// Hard cap on the encoded video, in bytes (25 MB per clip).
    static let maxBytes = 25 * 1024 * 1024

    enum Failure: LocalizedError {
        case exportFailed
        case tooLarge(mb: Int)
        var errorDescription: String? {
            switch self {
            case .exportFailed:     return "Couldn't compress that video."
            case .tooLarge(let mb): return "That clip is \(mb) MB after compression — keep it under 25 MB (try a shorter clip)."
            }
        }
    }

    /// Transcode → cap → base64. `onProgress` is called on the main actor with 0…1 while
    /// the transcode runs, so the UI can show a live percentage. Throws `Failure`.
    static func encode(from url: URL, onProgress: @escaping (Double) -> Void = { _ in }) async throws -> EventMedia {
        let asset = AVURLAsset(url: url)
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset960x540) else {
            throw Failure.exportFailed
        }
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
        export.outputURL = out
        export.outputFileType = .mp4
        export.shouldOptimizeForNetworkUse = true

        // Poll transcode progress on the main actor so the editor can render a live %.
        let poller = Task { @MainActor in
            while !Task.isCancelled {
                onProgress(Double(export.progress))
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            export.exportAsynchronously { cont.resume() }
        }
        poller.cancel()

        guard export.status == .completed else { throw Failure.exportFailed }
        defer { try? FileManager.default.removeItem(at: out) }

        let data = try Data(contentsOf: out)
        guard data.count <= maxBytes else { throw Failure.tooLarge(mb: data.count / (1024 * 1024)) }
        await MainActor.run { onProgress(1.0) }

        let poster = firstFramePoster(asset)
        return EventMedia(kind: .video, data: data.base64EncodedString(), poster: poster)
    }

    /// A downscaled JPEG (base64) of the first frame, for the thumbnail grid.
    private static func firstFramePoster(_ asset: AVAsset) -> String? {
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 900, height: 900)
        let t = CMTime(seconds: 0.1, preferredTimescale: 600)
        guard let cg = try? gen.copyCGImage(at: t, actualTime: nil) else { return nil }
        return jpegBase64(cg, quality: 0.6)
    }

    private static func jpegBase64(_ image: CGImage, quality: CGFloat) -> String? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data.base64EncodedString()
    }
}
