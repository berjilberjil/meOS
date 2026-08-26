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
        let account = ProgressPhotoStore.account
        for id in ProgressPhotoStore.deletedIds {
            guard ProgressPhotoStore.account == account else { return }
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
        // This loop is detached and each upload can take a minute. Without the
        // account check, a logout mid-loop meant the next iteration POSTed the
        // previous user's file under the new user's cookie — the server writes
        // by session, so it landed in their bucket.
        let account = ProgressPhotoStore.account
        for photo in ProgressPhotoStore.pending() {
            guard ProgressPhotoStore.account == account else { return }
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

    /// Reconcile with the cloud: take down what is missing here, and drop what
    /// is no longer there.
    static func pull() async {
        // Captured BEFORE the listing, not after. Reading it afterwards meant a
        // logout during the await left `account` holding the *new* user, and the
        // reconciliation below then deleted their photos for not appearing in
        // the previous user's listing.
        let account = ProgressPhotoStore.account
        guard let remote = try? await api.listBodyPhotos() else { return }
        guard ProgressPhotoStore.account == account else { return }
        let remoteIds = Set(remote.map(\.id))

        // A photo deleted on the other device has to disappear from this one.
        // `pull` only ever added, so deleting on the Mac left the iPhone showing
        // it forever — and still feeding it into the weekly comparison. Only
        // photos this device had confirmed uploaded are removed: anything not
        // yet synced is the owner's single copy and is never someone else's
        // delete to act on.
        for local in ProgressPhotoStore.list()
        where !remoteIds.contains(local.id) && ProgressPhotoStore.isSynced(local.id) {
            guard ProgressPhotoStore.account == account else { return }
            ProgressPhotoStore.delete(local.id)
        }

        let localIds = Set(ProgressPhotoStore.list().map(\.id))
        let deleted = ProgressPhotoStore.deletedIds
        for photo in remote where !localIds.contains(photo.id) && !deleted.contains(photo.id) {
            guard ProgressPhotoStore.account == account else { return }
            guard let urlString = photo.url, let url = URL(string: urlString) else { continue }
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode)
            else { continue }
            ProgressPhotoStore.storeRemote(jpeg: data, stem: photo.id)
        }
    }
}
