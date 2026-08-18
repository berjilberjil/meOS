import Foundation

/// Syncs body-progress photos to the shared "media" storage bucket via the
/// backend, so a photo hearted on iPhone shows up on the Mac (and vice
/// versa). Runs opportunistically: after a manual add, after a Favorites
/// import, and once whenever a card appears. Best-effort — failures are
/// silent (no network / logged out just means "local only" for now).
@MainActor
enum ProgressPhotoSync {
    private static let api = APIClient()
    private(set) static var isSyncing = false

    /// Upload anything pending, then pull down anything this device is missing.
    static func syncAll() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        await push()
        await pull()
        NotificationCenter.default.post(name: .progressPhotosSyncDidChange, object: nil)
    }

    /// Upload every local photo the server hasn't confirmed yet.
    static func push() async {
        for photo in ProgressPhotoStore.pending() {
            guard let jpeg = try? Data(contentsOf: photo.url) else { continue }
            do {
                try await api.uploadBodyPhoto(id: photo.id, date: photo.date, jpeg: jpeg)
                ProgressPhotoStore.markSynced(photo.id)
            } catch {
                break // likely offline/logged out — stop, try again next cycle
            }
        }
    }

    /// Delete the cloud copy of one photo (best-effort; local delete already happened).
    static func delete(id: String) async {
        try? await api.deleteBodyPhoto(id: id)
    }

    /// Download any photo synced from another device that isn't on this one yet.
    static func pull() async {
        guard let remote = try? await api.listBodyPhotos() else { return }
        let localIds = Set(ProgressPhotoStore.list().map(\.id))
        for photo in remote where !localIds.contains(photo.id) {
            guard let urlString = photo.url, let url = URL(string: urlString) else { continue }
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode)
            else { continue }
            ProgressPhotoStore.storeRemote(jpeg: data, stem: photo.id)
        }
    }
}
