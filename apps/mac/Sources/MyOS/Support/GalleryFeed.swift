import Foundation

/// Every picture and video MyOS holds, in one list.
///
/// The app accumulates media in four unrelated places — event photos and
/// videos, body-progress shots, the pictures behind food and object scans, and
/// images pasted into notes — each with its own storage, its own date field and
/// its own screen. There was no way to answer "show me everything" without
/// visiting four tabs and remembering which one a picture went into.
///
/// This is the join. It deliberately does NOT move or copy any bytes: each item
/// keeps a pointer back to wherever it already lives, and the grid resolves it
/// through the store that owns it.
struct GalleryItem: Identifiable, Hashable {

    /// Which part of the app produced this.
    enum Source: String, CaseIterable, Identifiable, Hashable {
        case events, progress, scans, notes
        var id: String { rawValue }
        var label: String {
            switch self {
            case .events:   return "Events"
            case .progress: return "Progress"
            case .scans:    return "Scans"
            case .notes:    return "Notes"
            }
        }
        var icon: String {
            switch self {
            case .events:   return "calendar"
            case .progress: return "figure.stand"
            case .scans:    return "viewfinder"
            case .notes:    return "note.text"
            }
        }
    }

    enum Kind: String, Hashable { case image, video }

    /// Where the bytes actually are. Exactly one case per item — the gallery
    /// never holds a second copy of anything.
    enum Location: Hashable {
        /// Sealed in R2, read through `EventMediaStore`. Event media and scans.
        case sealed(key: String, posterKey: String?)
        /// Legacy inline base64 — old event media, and note images, which are
        /// small and live inside the note's own document.
        case inline(base64: String, poster: String?)
        /// A JPEG on disk. Progress photos, which are deliberately not synced
        /// through the state blob.
        case file(URL)
    }

    var id: String
    var source: Source
    var kind: Kind
    /// `yyyy-MM-dd`. The day the thing it belongs to happened, not the day the
    /// file was written — an event photo belongs to the event's date.
    var day: String
    /// What it came from: the event's name, the note's title, the scan summary.
    var title: String
    var location: Location
    /// Where tapping it should go back to, when there is somewhere to go.
    var ownerID: String?

    /// `yyyy-MM` — the grid's section key.
    var month: String { String(day.prefix(7)) }
}

enum GalleryFeed {

    /// Build the whole feed, newest first.
    ///
    /// Ordering is by day descending, then by source and id, so it is stable
    /// across rebuilds — a grid that reshuffles when a poll lands is a grid you
    /// cannot click.
    static func items(events: [EventItem],
                      scans: [ScanRecord],
                      notes: [Note],
                      progress: [ProgressPhoto]) -> [GalleryItem] {
        var out: [GalleryItem] = []

        for event in events {
            for m in event.media {
                out.append(GalleryItem(
                    id: "event.\(m.id)",
                    source: .events,
                    kind: m.kind == .video ? .video : .image,
                    day: event.date,
                    title: event.title.isEmpty ? "Event" : event.title,
                    location: location(for: m),
                    ownerID: event.id))
            }
        }

        for photo in progress {
            out.append(GalleryItem(
                id: "progress.\(photo.id)",
                source: .progress,
                kind: .image,
                day: photo.date,
                title: "Progress",
                location: .file(photo.url),
                ownerID: nil))
        }

        for scan in scans {
            guard let key = scan.photoKey, !key.isEmpty else { continue }
            out.append(GalleryItem(
                id: "scan.\(scan.id)",
                source: .scans,
                kind: .image,
                day: scan.date,
                title: scan.summary.isEmpty ? "Scan" : scan.summary,
                location: .sealed(key: key, posterKey: nil),
                ownerID: scan.id))
        }

        for note in notes where !note.locked {
            // A locked note's pictures stay behind the lock. The gallery is a
            // convenience, not a way around a decision already made.
            for block in note.effectiveDoc.blocks where block.type == .image {
                guard let src = block.src, !src.isEmpty else { continue }
                out.append(GalleryItem(
                    id: "note.\(note.id).\(block.id)",
                    source: .notes,
                    kind: .image,
                    day: String(note.updatedAt.prefix(10)),
                    title: note.title.isEmpty ? "Note" : note.title,
                    location: .inline(base64: src, poster: nil),
                    ownerID: note.id))
            }
        }

        return out.sorted { a, b in
            if a.day != b.day { return a.day > b.day }
            if a.source != b.source { return a.source.rawValue < b.source.rawValue }
            return a.id < b.id
        }
    }

    private static func location(for m: EventMedia) -> GalleryItem.Location {
        if let key = m.r2Key, !key.isEmpty {
            return .sealed(key: key, posterKey: m.posterKey)
        }
        return .inline(base64: m.data, poster: m.poster)
    }

    /// Group into month sections, newest month first, order preserved inside.
    static func months(_ items: [GalleryItem]) -> [(month: String, items: [GalleryItem])] {
        var order: [String] = []
        var byMonth: [String: [GalleryItem]] = [:]
        for item in items {
            if byMonth[item.month] == nil { order.append(item.month) }
            byMonth[item.month, default: []].append(item)
        }
        return order.map { ($0, byMonth[$0] ?? []) }
    }

    /// "August 2026" from a `yyyy-MM` key.
    static func monthLabel(_ key: String) -> String {
        let parts = key.split(separator: "-")
        guard parts.count == 2, let year = Int(parts[0]), let month = Int(parts[1]),
              (1...12).contains(month) else { return key }
        let names = ["January", "February", "March", "April", "May", "June",
                     "July", "August", "September", "October", "November", "December"]
        return "\(names[month - 1]) \(year)"
    }
}
