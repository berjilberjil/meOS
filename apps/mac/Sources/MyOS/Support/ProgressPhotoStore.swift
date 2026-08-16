import Foundation

extension Notification.Name {
    static let progressPhotosDidChange = Notification.Name("myos.progressPhotosDidChange")
}

/// One JPEG on disk. Many photos can share a calendar day.
struct ProgressPhoto: Identifiable, Hashable {
    let id: String      // filename stem
    let date: String    // yyyy-MM-dd
    let url: URL
}

/// Local body-progress photos under Application Support.
/// Not synced (images would bloat the KV store).
enum ProgressPhotoStore {
    static let dir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let d = base.appendingPathComponent("MyOS/progress", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    /// `2026-08-15.jpg` (legacy one-a-day) or `2026-08-15__assetId.jpg`.
    static func parse(_ filename: String) -> (id: String, date: String)? {
        let ext = (filename as NSString).pathExtension.lowercased()
        guard ext == "jpg" || ext == "jpeg" else { return nil }
        let stem = (filename as NSString).deletingPathExtension
        if let r = stem.range(of: "__") {
            let date = String(stem[..<r.lowerBound])
            guard date.count == 10 else { return nil }
            return (stem, date)
        }
        guard stem.count == 10 else { return nil }
        return (stem, stem)
    }

    static func url(for id: String) -> URL { dir.appendingPathComponent("\(id).jpg") }

    static func has(_ date: String) -> Bool {
        list().contains { $0.date == date }
    }

    static func list() -> [ProgressPhoto] {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.compactMap { url -> ProgressPhoto? in
            guard let parsed = parse(url.lastPathComponent) else { return nil }
            return ProgressPhoto(id: parsed.id, date: parsed.date, url: url)
        }
        .sorted { $0.date == $1.date ? $0.id > $1.id : $0.date > $1.date }
    }

    @discardableResult
    static func save(jpeg: Data, date: String, assetId: String? = nil) -> Bool {
        let stem: String
        if let assetId {
            let safe = assetId.replacingOccurrences(of: "/", with: "_")
            stem = "\(date)__\(safe)"
        } else {
            stem = "\(date)__manual-\(Int(Date().timeIntervalSince1970 * 1000))"
        }
        do {
            try jpeg.write(to: url(for: stem), options: .atomic)
            NotificationCenter.default.post(name: .progressPhotosDidChange, object: stem)
            return true
        } catch { return false }
    }

    static func delete(_ photo: ProgressPhoto) {
        try? FileManager.default.removeItem(at: photo.url)
        NotificationCenter.default.post(name: .progressPhotosDidChange, object: photo.id)
    }

    /// Delete by filename stem (or a legacy `yyyy-MM-dd` id).
    static func delete(_ id: String) {
        if let match = list().first(where: { $0.id == id }) {
            delete(match)
            return
        }
        try? FileManager.default.removeItem(at: url(for: id))
        NotificationCenter.default.post(name: .progressPhotosDidChange, object: id)
    }

    private static let importedKey = "myos.progress.importedAssetIds"

    static var importedIds: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: importedKey) ?? [])
    }

    static func markImported(_ id: String) {
        var s = importedIds
        s.insert(id)
        UserDefaults.standard.set(Array(s), forKey: importedKey)
    }
}
