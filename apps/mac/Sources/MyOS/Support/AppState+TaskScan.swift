import Foundation

// Task Mode and scan history. Both are thin layers over state that already
// exists — the day plan's `FocusItem`s and the camera's `ScanInsight` — so they
// live here rather than growing AppState.swift any further.

// MARK: - Task Mode

extension AppState {
    /// This device's label, shown on the *other* device so a mode that appeared
    /// out of nowhere has an explanation.
    static var deviceLabel: String {
        #if os(macOS)
        return "Mac"
        #else
        return "iPhone"
        #endif
    }

    /// Flip the switch everywhere. Writing it locally first means the exit button
    /// works instantly and offline; the push catches the other device up on its
    /// next poll (~15s), or immediately when it comes to the foreground.
    func setTaskMode(_ on: Bool) {
        guard taskMode.on != on else { return }
        taskMode = TaskModeState(on: on,
                                 since: on ? Self.nowStamp() : "",
                                 device: on ? Self.deviceLabel : "")
        push(StateKey.taskMode, taskMode)
    }

    func toggleTaskMode() { setTaskMode(!taskMode.on) }

    /// True when the mode was turned on somewhere else — the phone says so
    /// rather than just going blank on you.
    var taskModeCameFromElsewhere: Bool {
        taskMode.on && !taskMode.device.isEmpty && taskMode.device != Self.deviceLabel
    }
}

// MARK: - Scan history

extension AppState {
    /// Keep a scan. The record lands (and renders) immediately; the photo follows
    /// once it is sealed and in R2, so a slow upload never blocks the result card.
    @discardableResult
    func saveScan(_ insight: ScanInsight, photo: Data?) -> ScanRecord {
        let record = ScanRecord(insight,
                                id: UUID().uuidString.lowercased(),
                                at: Self.nowStamp(),
                                date: todayKey)
        scans = ScanRecord.adding(record, to: scans)
        push(StateKey.scans, scans)
        if let photo, !photo.isEmpty {
            Task { await attachScanPhoto(id: record.id, jpeg: photo) }
        }
        return record
    }

    func markScanLogged(_ id: String) {
        guard let i = scans.firstIndex(where: { $0.id == id }), !scans[i].logged else { return }
        scans[i].logged = true
        push(StateKey.scans, scans)
    }

    func deleteScan(_ id: String) {
        guard let i = scans.firstIndex(where: { $0.id == id }) else { return }
        let gone = scans.remove(at: i)
        push(StateKey.scans, scans)
        dropPhotos(ScanRecord.orphanedKeys([gone]))
    }

    func clearScans() {
        guard !scans.isEmpty else { return }
        let gone = scans
        scans = []
        push(StateKey.scans, scans)
        dropPhotos(ScanRecord.orphanedKeys(gone))
    }

    /// Seal, upload, then stitch the R2 id onto the record. A failure is silent
    /// on purpose: the verdict is the point, the photo is the garnish.
    private func attachScanPhoto(id: String, jpeg: Data) async {
        guard let dek = vault.dek else { return }
        // Full-res camera frames are megabytes; 720px at 0.6 is ~60-90 KB.
        let small = MediaJPEG.downscale(jpeg, maxSide: 720, quality: 0.6) ?? jpeg
        do {
            let key = try await EventMediaStore.upload(small, api: api, dek: dek, id: "scan-\(id)")
            guard let i = scans.firstIndex(where: { $0.id == id }) else { return }
            scans[i].photoKey = key
            push(StateKey.scans, scans)
        } catch {
            // Left keyless — the row renders with a glyph instead of a thumbnail.
        }
    }

    private func dropPhotos(_ keys: [String]) {
        guard !keys.isEmpty else { return }
        Task { [api] in
            for k in keys { try? await api.deleteEventMedia(id: k) }
        }
    }
}
