import AVFoundation
import AppKit

/// Compress + encode a video for inline storage on an `EventItem`. Because the whole
/// app state is one zero-knowledge-encrypted, fully-synced blob, video must stay small:
/// we transcode to ≤540p H.264 and hard-cap the encoded bytes. A first-frame poster is
/// grabbed for the grid so we never decode the whole clip just to show a thumbnail.
enum VideoMedia {
    /// Hard cap on the encoded video, in bytes (15 MB).
    static let maxBytes = 15 * 1024 * 1024

    enum Failure: LocalizedError {
        case exportFailed
        case tooLarge(mb: Int)
        var errorDescription: String? {
            switch self {
            case .exportFailed:     return "Couldn't compress that video."
            case .tooLarge(let mb): return "That clip is \(mb) MB after compression — keep it under 15 MB (try a shorter clip)."
            }
        }
    }

    /// Transcode → cap → base64. Returns an image/video `EventMedia`. Throws `Failure`.
    static func encode(from url: URL) async throws -> EventMedia {
        let asset = AVURLAsset(url: url)
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset960x540) else {
            throw Failure.exportFailed
        }
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
        export.outputURL = out
        export.outputFileType = .mp4
        export.shouldOptimizeForNetworkUse = true

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            export.exportAsynchronously { cont.resume() }
        }
        guard export.status == .completed else { throw Failure.exportFailed }
        defer { try? FileManager.default.removeItem(at: out) }

        let data = try Data(contentsOf: out)
        guard data.count <= maxBytes else { throw Failure.tooLarge(mb: data.count / (1024 * 1024)) }

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
        let ns = NSImage(cgImage: cg, size: .zero)
        return NoteImage.encode(ns, maxDimension: 900, quality: 0.6)
    }
}
