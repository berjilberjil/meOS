import AppKit
import SwiftUI

// Media support for the note editor: encoding embedded images, drawing link-preview
// cards, and fetching link metadata. All network fetches go straight from this Mac
// to the web (YouTube, the linked page) — never through the MyOS server — so the
// zero-knowledge guarantee holds for link previews too.

// MARK: - Image encoding (downscale + JPEG so notes stay small enough to sync)

enum NoteImage {
    /// Downscale to fit `maxDimension`, JPEG-compress, and base64-encode. Returns nil
    /// if the image can't be read.
    static func encode(_ image: NSImage, maxDimension: CGFloat = 1400, quality: CGFloat = 0.7) -> String? {
        guard let jpeg = jpegData(image, maxDimension: maxDimension, quality: quality) else { return nil }
        return jpeg.base64EncodedString()
    }

    static func jpegData(_ image: NSImage, maxDimension: CGFloat, quality: CGFloat) -> Data? {
        guard let tiff = image.tiffRepresentation, let src = NSBitmapImageRep(data: tiff) else { return nil }
        let pxW = CGFloat(src.pixelsWide), pxH = CGFloat(src.pixelsHigh)
        guard pxW > 0, pxH > 0 else { return nil }
        let scale = min(1, maxDimension / max(pxW, pxH))
        let w = max(1, Int((pxW * scale).rounded())), h = max(1, Int((pxH * scale).rounded()))
        guard let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        out.size = NSSize(width: w, height: h)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
        src.draw(in: NSRect(x: 0, y: 0, width: w, height: h))
        NSGraphicsContext.restoreGraphicsState()
        return out.representation(using: .jpeg, properties: [.compressionFactor: quality])
    }
}

// MARK: - Link card rendering (drawn into an NSImage used as the attachment)

enum LinkCardRenderer {
    static let width: CGFloat = 440
    static let height: CGFloat = 96
    private static let thumbW: CGFloat = 132

    static func render(_ block: Block) -> NSImage {
        let size = NSSize(width: width, height: height)
        let img = NSImage(size: size)
        img.lockFocus()

        let card = NSRect(x: 0.5, y: 0.5, width: width - 1, height: height - 1)
        let outline = NSBezierPath(roundedRect: card, xRadius: 10, yRadius: 10)
        NSColor(Palette.surface2).setFill(); outline.fill()
        NSColor(white: 1, alpha: 0.10).setStroke(); outline.lineWidth = 1; outline.stroke()

        // Thumbnail (left), clipped to the card's left rounded corners.
        let thumbRect = NSRect(x: 0, y: 0, width: thumbW, height: height)
        NSGraphicsContext.saveGraphicsState()
        let clip = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: thumbW + 10, height: height),
                                xRadius: 10, yRadius: 10)
        clip.setClip()
        if let t = block.linkThumb, let d = Data(base64Encoded: t), let ti = NSImage(data: d) {
            drawAspectFill(ti, in: thumbRect)
        } else {
            NSColor(Palette.surface).setFill(); NSBezierPath(rect: thumbRect).fill()
            let glyph = NSAttributedString(string: "link", attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: NSColor(Palette.faint)])
            glyph.draw(at: NSPoint(x: 14, y: height / 2 - 8))
        }
        NSGraphicsContext.restoreGraphicsState()

        // Title + domain (right).
        let textX = thumbW + 14
        let textW = width - textX - 14
        let title = (block.linkTitle?.isEmpty == false ? block.linkTitle! : (block.url ?? "Link"))
        let para = NSMutableParagraphStyle(); para.lineBreakMode = .byTruncatingTail; para.maximumLineHeight = 19
        let titleAttr = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: NSColor(Palette.text), .paragraphStyle: para])
        titleAttr.draw(in: NSRect(x: textX, y: 34, width: textW, height: 42))

        let domain = block.linkDomain ?? URL(string: block.url ?? "")?.host ?? ""
        let dPara = NSMutableParagraphStyle(); dPara.lineBreakMode = .byTruncatingTail
        NSAttributedString(string: domain, attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor(Palette.faint), .paragraphStyle: dPara])
            .draw(in: NSRect(x: textX, y: 12, width: textW, height: 16))

        img.unlockFocus()
        return img
    }

    private static func drawAspectFill(_ image: NSImage, in rect: NSRect) {
        let s = image.size
        guard s.width > 0, s.height > 0 else { return }
        let scale = max(rect.width / s.width, rect.height / s.height)
        let dw = s.width * scale, dh = s.height * scale
        let dest = NSRect(x: rect.midX - dw / 2, y: rect.midY - dh / 2, width: dw, height: dh)
        image.draw(in: dest, from: .zero, operation: .copy, fraction: 1)
    }
}

// MARK: - Link metadata fetch (title + thumbnail), all client-side

enum LinkMetadata {
    struct Result { let title: String?; let thumbBase64: String?; let domain: String? }

    static func fetch(_ url: URL) async -> Result? {
        let domain = url.host?.replacingOccurrences(of: "www.", with: "")
        if let vid = youTubeID(url) {
            async let thumb = downloadThumb(URL(string: "https://img.youtube.com/vi/\(vid)/hqdefault.jpg"))
            async let title = oEmbedTitle(url)
            return Result(title: await title, thumbBase64: await thumb, domain: "youtube.com")
        }
        let og = await fetchOpenGraph(url)
        let thumb = await downloadThumb(og?.imageURL)
        return Result(title: og?.title, thumbBase64: thumb, domain: domain)
    }

    // YouTube video id from watch / youtu.be / shorts / embed URLs.
    static func youTubeID(_ url: URL) -> String? {
        guard let host = url.host?.lowercased() else { return nil }
        if host.contains("youtu.be") {
            let id = url.lastPathComponent
            return id.isEmpty ? nil : id
        }
        guard host.contains("youtube.com") else { return nil }
        if let v = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "v" })?.value { return v }
        let parts = url.pathComponents
        if let i = parts.firstIndex(where: { $0 == "shorts" || $0 == "embed" }), i + 1 < parts.count {
            return parts[i + 1]
        }
        return nil
    }

    private static func oEmbedTitle(_ url: URL) async -> String? {
        var c = URLComponents(string: "https://www.youtube.com/oembed")!
        c.queryItems = [.init(name: "url", value: url.absoluteString), .init(name: "format", value: "json")]
        guard let u = c.url, let (data, _) = try? await session.data(from: u),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return obj["title"] as? String
    }

    private struct OG { let title: String?; let imageURL: URL? }

    private static func fetchOpenGraph(_ url: URL) async -> OG? {
        guard let (data, _) = try? await session.data(from: url) else { return nil }
        // Only need the <head>; cap the string we scan so big pages stay cheap.
        let html = String(decoding: data.prefix(300_000), as: UTF8.self)
        let title = metaContent(in: html, property: "og:title") ?? titleTag(in: html)
        let image = metaContent(in: html, property: "og:image")
            ?? metaContent(in: html, property: "twitter:image")
        let imageURL = image.flatMap { URL(string: $0, relativeTo: url)?.absoluteURL }
        return OG(title: title, imageURL: imageURL)
    }

    private static func downloadThumb(_ url: URL?) async -> String? {
        guard let url, let (data, _) = try? await session.data(from: url),
              let img = NSImage(data: data) else { return nil }
        return NoteImage.encode(img, maxDimension: 500, quality: 0.7)
    }

    // MARK: HTML scraping helpers

    private static func metaContent(in html: String, property: String) -> String? {
        // Match <meta ... (property|name)="og:title" ... content="...">, either order.
        let patterns = [
            "<meta[^>]+(?:property|name)=[\"']\(NSRegularExpression.escapedPattern(for: property))[\"'][^>]+content=[\"']([^\"']+)[\"']",
            "<meta[^>]+content=[\"']([^\"']+)[\"'][^>]+(?:property|name)=[\"']\(NSRegularExpression.escapedPattern(for: property))[\"']",
        ]
        for p in patterns {
            if let m = firstGroup(p, in: html) { return decodeEntities(m) }
        }
        return nil
    }

    private static func titleTag(in html: String) -> String? {
        firstGroup("<title[^>]*>([^<]+)</title>", in: html).map(decodeEntities)
    }

    private static func firstGroup(_ pattern: String, in html: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
        else { return nil }
        let range = NSRange(html.startIndex..., in: html)
        guard let m = re.firstMatch(in: html, range: range), m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: html) else { return nil }
        return String(html[r]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeEntities(_ s: String) -> String {
        s.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }

    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 12
        c.timeoutIntervalForResource = 20
        // A real UA — some sites serve no OG tags to an unknown client.
        c.httpAdditionalHeaders = ["User-Agent": "Mozilla/5.0 (Macintosh) MyOS/1.0"]
        return URLSession(configuration: c)
    }()
}
