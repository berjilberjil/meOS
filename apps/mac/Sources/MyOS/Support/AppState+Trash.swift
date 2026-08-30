import Foundation

/// The recycle bin: capture on the way out, restore on the way back, and a
/// sweep that lets go on the thirtieth day.
///
/// Kept out of `AppState.swift` on purpose — that file is already the largest
/// thing in the app, and the bin is a self-contained story: one array, one key,
/// and a switch that knows how to put each kind of thing back.
///
/// The one rule everything here obeys: **nothing is destroyed at delete time**.
/// Every `delete*` on `AppState` now hands its object here whole, including the
/// R2 object ids it referenced, and those ids are released only when the entry
/// is finally purged. Before this, deleting an event also deleted its photos
/// from the bucket in the same breath — which would have made "restore" mean
/// restoring the words and losing the pictures.
@MainActor
extension AppState {

    // MARK: - Capture

    /// Put a deleted thing in the bin and save.
    ///
    /// Called by every `delete*` after it has removed the object from its live
    /// array and *before* it pushes, so one user action is one pair of writes.
    func recycle(_ kind: TrashKind,
                 id: String,
                 title: String,
                 subtitle: String = "",
                 payload: String,
                 context: String? = nil,
                 mediaKeys: [String] = []) {
        let entry = TrashEntry(itemID: id, kind: kind, title: title, subtitle: subtitle,
                               deletedAt: Self.nowStamp(), payload: payload,
                               context: context, mediaKeys: mediaKeys)
        trash.insert(entry, at: 0)
        push(StateKey.trash, trash)
    }

    /// Recycle a body photo: move the file aside, keep the cloud copy, log it.
    ///
    /// The cloud copy is the part that is easy to get wrong. Deleting it here
    /// would look tidy and would quietly make the bin a lie — a photo restored
    /// on the phone after being deleted on the Mac has to come from somewhere,
    /// and for a body photo that somewhere is the bucket.
    func recycleProgressPhoto(_ photo: ProgressPhoto) {
        ProgressPhotoStore.recycle(photo.id)
        recycle(.progressPhoto, id: photo.id, title: Fmt.day(photo.date),
                subtitle: "Body photo", payload: photo.date, context: photo.date)
    }

    /// The bin, newest first, with anything already past its day filtered out so
    /// the UI never shows a row the next sweep is about to take.
    var liveTrash: [TrashEntry] {
        TrashRetention.split(trash, todayKey: todayKey).kept
            .sorted { $0.deletedAt > $1.deletedAt }
    }

    var trashCount: Int { liveTrash.count }

    // MARK: - Restore

    /// Put one thing back.
    ///
    /// A payload that no longer decodes leaves the entry exactly where it is.
    /// The alternative — dropping the row because we could not read it — would
    /// destroy the only remaining copy at the moment the user asked for it back,
    /// which is the worst possible time to be lossy.
    @discardableResult
    func restoreFromTrash(_ entry: TrashEntry) -> Bool {
        guard restorePayload(entry) else { return false }
        trash.removeAll { $0.id == entry.id }
        push(StateKey.trash, trash)
        return true
    }

    private func restorePayload(_ e: TrashEntry) -> Bool {
        switch e.kind {
        case .note:
            guard let v = e.decoded(Note.self) else { return false }
            if !notes.contains(where: { $0.id == v.id }) { notes.insert(v, at: 0) }
            push(StateKey.notes, notes)

        case .event:
            guard let v = e.decoded(EventItem.self) else { return false }
            if !events.contains(where: { $0.id == v.id }) { events.append(v) }
            push(StateKey.events, events)

        case .belonging:
            guard let v = e.decoded(BelongingItem.self) else { return false }
            if !belongings.items.contains(where: { $0.id == v.id }) {
                belongings.items.insert(v, at: 0)
            }
            push(StateKey.belongings, belongings)

        case .watch:
            guard let v = e.decoded(WatchItem.self) else { return false }
            if !watch.contains(where: { $0.id == v.id }) { watch.append(v) }
            push(StateKey.watch, watch)

        case .todo:
            // A to-do only means something inside the day it belonged to.
            guard let v = e.decoded(FocusItem.self), let day = e.context else { return false }
            var plan = days[day] ?? DayPlan()
            if !plan.todos.contains(where: { $0.id == v.id }) { plan.todos.append(v) }
            days[day] = plan
            push(StateKey.days, days)

        case .scan:
            guard let v = e.decoded(ScanRecord.self) else { return false }
            if !scans.contains(where: { $0.id == v.id }) { scans.insert(v, at: 0) }
            push(StateKey.scans, scans)

        case .chatThread:
            guard let v = e.decoded(ChatThread.self) else { return false }
            if !chat.threads.contains(where: { $0.id == v.id }) { chat.threads.append(v) }
            push(StateKey.chat, chat)

        case .progressPhoto:
            // Files, not JSON. The local copy comes back out of the photo
            // store's own bin; if this device never had one, the cloud copy is
            // still there — which is exactly why recycling never deleted it —
            // and the next pull brings it down.
            ProgressPhotoStore.restoreFromTrash(e.itemID)

        case .food:
            guard let v = e.decoded(Food.self) else { return false }
            if !nutrition.customFoods.contains(where: { $0.id == v.id }) {
                nutrition.customFoods.append(v)
            }
            push(StateKey.nutrition, nutrition)

        case .exercise:
            guard let v = e.decoded(Exercise.self) else { return false }
            if !training.customExercises.contains(where: { $0.id == v.id }) {
                training.customExercises.append(v)
            }
            push(StateKey.training, training)

        case .program:
            guard let v = e.decoded(WorkoutProgram.self) else { return false }
            if !training.programs.contains(where: { $0.id == v.id }) {
                training.programs.append(v)
            }
            push(StateKey.training, training)
        }
        return true
    }

    // MARK: - Purge

    /// Remove one entry for good, and release whatever it was holding open.
    func purgeFromTrash(_ entry: TrashEntry) {
        trash.removeAll { $0.id == entry.id }
        push(StateKey.trash, trash)
        release(entry)
    }

    /// Empty the bin. Everything it was holding in R2 goes with it.
    func emptyTrash() {
        let going = trash
        trash = []
        push(StateKey.trash, trash)
        going.forEach(release)
    }

    /// Let go of the bytes an entry was keeping alive.
    ///
    /// Failures are deliberately quiet for the R2 side — a key that outlives its
    /// entry is wasted space, not lost data, and the alternative is an error
    /// banner about storage the user never asked about. The photo half tombstones
    /// first and retries on the next sync, which is `ProgressPhotoSync`'s own
    /// contract.
    private func release(_ entry: TrashEntry) {
        if entry.kind == .progressPhoto {
            ProgressPhotoStore.purgeFromTrash(entry.itemID)
            Task { await ProgressPhotoSync.delete(id: entry.itemID) }
        }
        let keys = entry.mediaKeys.filter { !$0.isEmpty }
        guard !keys.isEmpty else { return }
        Task { [api] in
            for key in keys { try? await api.deleteEventMedia(id: key) }
        }
    }

    // MARK: - The sweep

    /// Take everything that has run out of days, and make this device's photo
    /// folder agree with the bin.
    ///
    /// Runs on hydrate and whenever the app comes back to the front. Cheap: an
    /// integer comparison per entry, and the photo reconciliation only touches
    /// stems that are actually out of step.
    func sweepTrash() {
        reconcileRecycledPhotos()

        let (kept, expired) = TrashRetention.split(trash, todayKey: todayKey)
        guard !expired.isEmpty else { return }
        trash = kept
        push(StateKey.trash, trash)
        expired.forEach(release)
        Log.sync.info("trash: purged \(expired.count, privacy: .public) expired entries")
    }

    /// The bin syncs; the photo files do not.
    ///
    /// So a photo recycled on the Mac arrives on the phone as a bin entry while
    /// the phone is still showing the picture — its cloud copy is deliberately
    /// still there, so nothing else would ever take it down. This makes the two
    /// agree in both directions: anything the bin holds gets moved aside here
    /// too, and anything restored elsewhere comes back here.
    private func reconcileRecycledPhotos() {
        let binned = Set(trash.filter { $0.kind == .progressPhoto }.map(\.itemID))

        for photo in ProgressPhotoStore.list() where binned.contains(photo.id) {
            ProgressPhotoStore.recycle(photo.id)
        }
        for stem in ProgressPhotoStore.recycledIds where !binned.contains(stem) {
            ProgressPhotoStore.restoreFromTrash(stem)
        }
    }
}
