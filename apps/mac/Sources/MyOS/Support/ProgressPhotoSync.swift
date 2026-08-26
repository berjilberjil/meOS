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

    /// Retry deletes, upload anything pending, then pull down what's missing.
    ///
    /// Deletes go first on purpose: pulling before retrying them would download
    /// the very photos this device is still trying to get rid of.
    static func syncAll() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        await flushDeletes()
        await push()
        await pull()
        NotificationCenter.default.post(name: .progressPhotosSyncDidChange, object: nil)
    }

    /// Re-ask the server to drop every photo this device has deleted but not yet
    /// had confirmed gone.
    static func flushDeletes() async {
        for id in ProgressPhotoStore.deletedIds {
            do {
                try await api.deleteBodyPhoto(id: id)
                ProgressPhotoStore.clearDeleted(id)
            } catch {
                break // offline or logged out — the tombstone keeps it queued
            }
        }
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

    /// Delete the cloud copy of one photo. The local delete has already
    /// happened, so the intent is recorded *before* the request goes out: if
    /// this fails the tombstone both stops `pull()` re-downloading the photo and
    /// keeps the delete queued for the next cycle.
    static func delete(id: String) async {
        ProgressPhotoStore.markDeleted(id)
        do {
            try await api.deleteBodyPhoto(id: id)
            ProgressPhotoStore.clearDeleted(id)
        } catch {
            // Stays tombstoned; `flushDeletes` retries on the next sync.
        }
    }

    /// Download any photo synced from another device that isn't on this one yet.
    static func pull() async {
        guard let remote = try? await api.listBodyPhotos() else { return }
        let localIds = Set(ProgressPhotoStore.list().map(\.id))
        let deleted = ProgressPhotoStore.deletedIds
        for photo in remote where !localIds.contains(photo.id) && !deleted.contains(photo.id) {
            guard let urlString = photo.url, let url = URL(string: urlString) else { continue }
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode)
            else { continue }
            ProgressPhotoStore.storeRemote(jpeg: data, stem: photo.id)
        }
    }
}
