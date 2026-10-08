#if os(iOS)
import Foundation
import Photos
import UIKit

/// Pulls favorited camera-roll shots into daily body photos when the app is open.
/// Every hearted shot is imported — multiple photos per day all show.
@MainActor
enum FavoritesBodyImporter {
    /// Guarded because `fetchFavorites()` is a main-actor PHAsset fetch: two
    /// overlapping calls are two library scans blocking the same thread.
    private static var running = false

    static func sync() async {
        guard !running else { return }
        running = true
        defer { running = false }
        FavoritesWatcher.shared.start()
        let ok = await requestAccess()
        guard ok else { return }
        let shots = fetchFavorites()
        let existing = Set(ProgressPhotoStore.list().map(\.date))
        let picks = FavoriteBodySync.picks(shots: shots,
                                           existingDays: existing,
                                           importedIds: ProgressPhotoStore.importedIds)
        var changed = false
        for p in picks {
            guard let jpeg = await jpeg(for: p.id) else { continue }
            if ProgressPhotoStore.save(jpeg: jpeg, date: p.day, assetId: p.id) {
                ProgressPhotoStore.markImported(p.id)
                changed = true
            }
        }
        if changed {
            NotificationCenter.default.post(name: .progressPhotosDidChange, object: nil)
        }
    }

    private static func requestAccess() async -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized, .limited: return true
        case .notDetermined:
            let next = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            return next == .authorized || next == .limited
        default: return false
        }
    }

    private static func fetchFavorites() -> [FavoriteShot] {
        let fmt = DateFormatter()
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd"
        let today = fmt.string(from: Date())

        let albums = PHAssetCollection.fetchAssetCollections(with: .smartAlbum,
                                                             subtype: .smartAlbumFavorites,
                                                             options: nil)
        guard let album = albums.firstObject else { return [] }
        let opts = PHFetchOptions()
        opts.sortDescriptors = [NSSortDescriptor(key: "modificationDate", ascending: false)]
        opts.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        let assets = PHAsset.fetchAssets(in: album, options: opts)
        var out: [FavoriteShot] = []
        assets.enumerateObjects { asset, _, _ in
            guard let created = asset.creationDate else { return }
            let createdDay = fmt.string(from: created)
            let modifiedDay = asset.modificationDate.map { fmt.string(from: $0) }
            let day = FavoriteBodySync.day(created: createdDay, modified: modifiedDay, today: today)
            out.append(FavoriteShot(id: asset.localIdentifier, day: day))
        }
        return out
    }

    private static func jpeg(for localId: String) async -> Data? {
        let r = PHAsset.fetchAssets(withLocalIdentifiers: [localId], options: nil)
        guard let asset = r.firstObject else { return nil }
        return await withCheckedContinuation { cont in
            let opts = PHImageRequestOptions()
            opts.deliveryMode = .highQualityFormat
            opts.resizeMode = .fast
            opts.isNetworkAccessAllowed = true
            opts.isSynchronous = false
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: opts) { data, _, _, _ in
                guard let data else { cont.resume(returning: nil); return }
                if let img = UIImage(data: data),
                   let jpeg = img.jpegData(compressionQuality: 0.85) {
                    cont.resume(returning: jpeg)
                } else {
                    cont.resume(returning: data)
                }
            }
        }
    }
}

/// Reloads body photos whenever Favorites change while MeOS is open.
final class FavoritesWatcher: NSObject, PHPhotoLibraryChangeObserver {
    static let shared = FavoritesWatcher()
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        PHPhotoLibrary.shared().register(self)
    }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { await FavoritesBodyImporter.sync() }
    }
}
#endif
