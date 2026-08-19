import Foundation

/// Tiny YouTube helper for the Productivity tab. Parses a video id out of any
/// common link shape and fetches title/channel/thumbnail from YouTube's public
/// oEmbed endpoint — no API key, no cost. Everything degrades to a derived
/// thumbnail if the network call fails.
enum YouTube {
    /// Extract the video id from any common YouTube URL (watch, youtu.be, shorts,
    /// embed, live) or a bare id.
    static func videoID(from raw: String) -> String? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if let comps = URLComponents(string: s), let host = comps.host?.lowercased() {
            if host.contains("youtu.be") {
                let id = comps.path.split(separator: "/").first.map(String.init) ?? ""
                return valid(id)
            }
            if host.contains("youtube.com") || host.contains("youtube-nocookie.com") {
                if let v = comps.queryItems?.first(where: { $0.name == "v" })?.value, let ok = valid(v) { return ok }
                let parts = comps.path.split(separator: "/").map(String.init)
                if let i = parts.firstIndex(where: { ["shorts", "embed", "live", "v"].contains($0) }),
                   i + 1 < parts.count { return valid(parts[i + 1]) }
                if parts.count == 1 { return valid(parts[0]) }
            }
        }
        return valid(s)   // maybe they pasted a bare id
    }

    /// A YouTube id is 11 chars of [A-Za-z0-9_-]; accept a small range to be safe.
    private static func valid(_ id: String) -> String? {
        let clean = id.split(whereSeparator: { $0 == "?" || $0 == "&" || $0 == "/" }).first.map(String.init) ?? id
        let ok = clean.count >= 10 && clean.count <= 16 &&
            clean.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
        return ok ? clean : nil
    }

    /// hqdefault always exists for a valid id — the safe default thumbnail.
    static func thumbURL(_ id: String) -> String { "https://i.ytimg.com/vi/\(id)/hqdefault.jpg" }

    /// A YouTube video inside whatever the iOS share sheet handed over.
    ///
    /// Stricter than `videoID(from:)` on purpose. That one accepts a bare id as
    /// a courtesy, which is right for a paste field and wrong for a share sheet:
    /// any stray twelve-character word would read as a video. Here the host has
    /// to actually be YouTube's.
    ///
    /// Shares often arrive as "Video title\nhttps://youtu.be/xyz", so the link is
    /// picked out of the surrounding text rather than the whole string being
    /// parsed as a URL.
    static func sharedLink(in raw: String) -> (id: String, url: String)? {
        let whole = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = whole.split(whereSeparator: \.isWhitespace).map(String.init)
            .first { $0.lowercased().contains("youtu") } ?? whole
        guard let host = URLComponents(string: candidate)?.host?.lowercased(),
              host == "youtu.be" || host.hasSuffix(".youtu.be")
                || host == "youtube.com" || host.hasSuffix(".youtube.com")
                || host == "youtube-nocookie.com" || host.hasSuffix(".youtube-nocookie.com"),
              let id = videoID(from: candidate)
        else { return nil }
        return (id, candidate)
    }

    struct Meta { let title: String; let channel: String; let thumbUrl: String }

    /// Fetch title/channel/thumbnail via oEmbed. Falls back to a derived thumbnail
    /// (and empty title/channel, which stay user-editable) on any failure.
    static func fetchMeta(id: String) async -> Meta {
        let fallback = Meta(title: "", channel: "", thumbUrl: thumbURL(id))
        var comps = URLComponents(string: "https://www.youtube.com/oembed")!
        comps.queryItems = [
            URLQueryItem(name: "url", value: "https://www.youtube.com/watch?v=\(id)"),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let url = comps.url else { return fallback }
        do {
            var req = URLRequest(url: url)
            req.timeoutInterval = 12
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return fallback }
            let o = try JSONDecoder().decode(OEmbed.self, from: data)
            let thumb = (o.thumbnail_url?.isEmpty == false) ? o.thumbnail_url! : thumbURL(id)
            return Meta(title: o.title ?? "", channel: o.author_name ?? "", thumbUrl: thumb)
        } catch {
            return fallback
        }
    }

    private struct OEmbed: Decodable {
        let title: String?
        let author_name: String?
        let thumbnail_url: String?
    }
}
