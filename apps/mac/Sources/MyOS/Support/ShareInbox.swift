import Foundation

/// The hand-off between the iOS share extension and the app.
///
/// The extension runs in its own process, in its own container, and it cannot
/// write to `watch` itself: MyOS state is a single end-to-end encrypted blob
/// whose key never leaves the app, and the API session is a cookie the
/// extension's URL session doesn't hold. So the extension drops the bare link
/// into a file in the shared App Group container, and the app folds it into the
/// watch log the next time it is frontmost.
///
/// Nothing sensitive lives here — a YouTube id, the link, and when it was
/// shared — and the file is emptied the moment the app takes the items.
enum ShareInbox {
    /// Must match the `com.apple.security.application-groups` entitlement on
    /// BOTH the app and the extension, or the container URL comes back nil.
    static let appGroup = "group.com.berjil.myos"

    struct Item: Codable, Equatable {
        var videoId: String
        var url: String
        var sharedAt: String
    }

    /// The shared container, or nil when this build has no App Group.
    ///
    /// `containerURL(forSecurityApplicationGroupIdentifier:)` is not the test it
    /// looks like. On the ad-hoc-signed Mac build — which carries no
    /// `application-groups` entitlement — it does **not** return nil: it hands
    /// back `~/Library/Group Containers/group.com.berjil.myos`, a directory that
    /// does not exist and is never created. Every write into it then throws and
    /// is swallowed by `try?`, so the caller sees a path, writes to it happily,
    /// and nothing is ever stored. Existence is the test, not nil-ness.
    static func groupContainer() -> URL? {
        let fm = FileManager.default
        guard let url = fm.containerURL(forSecurityApplicationGroupIdentifier: appGroup),
              fm.fileExists(atPath: url.path) else { return nil }
        return url
    }

    /// nil when the App Group isn't provisioned — the Mac build, or a device
    /// where the entitlement didn't make it. Every call then quietly no-ops
    /// rather than trapping.
    private static var fileURL: URL? {
        groupContainer()?.appendingPathComponent("share-inbox.json")
    }

    /// Two processes touch this file. The lock only orders writers within one
    /// process; the atomic write is what keeps a reader from seeing a torn file.
    private static let lock = NSLock()

    static func pending() -> [Item] {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Item].self, from: data)) ?? []
    }

    /// Queue one video. Deduped on id, so sharing the same clip twice before the
    /// app has drained it doesn't log it twice.
    @discardableResult
    static func add(videoId: String, url shared: String) -> Bool {
        guard let file = fileURL else { return false }
        lock.lock(); defer { lock.unlock() }
        var items = pending()
        guard !items.contains(where: { $0.videoId == videoId }) else { return true }
        items.append(Item(videoId: videoId, url: shared, sharedAt: stamp()))
        guard let data = try? JSONEncoder().encode(items),
              (try? data.write(to: file, options: .atomic)) != nil else { return false }
        return true
    }

    /// Hand everything over and empty the file — the app owns them from here.
    static func drain() -> [Item] {
        guard let file = fileURL else { return [] }
        lock.lock(); defer { lock.unlock() }
        let items = pending()
        guard !items.isEmpty else { return [] }
        try? Data("[]".utf8).write(to: file, options: .atomic)
        return items
    }

    private static func stamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f.string(from: Date())
    }
}
