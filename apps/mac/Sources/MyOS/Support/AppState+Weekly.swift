import Foundation

// The Friday report. Body photos are sealed on this device, so nothing can build
// this on a server while the app is shut — generation runs here, in-app, with the
// vault open, and only then does the notification go out.

extension AppState {

    /// Inclusive day keys across a range, capped so a malformed window can't loop.
    static func dayKeys(_ range: ClosedRange<String>, limit: Int = 31) -> [String] {
        guard range.lowerBound <= range.upperBound else { return [] }
        var out: [String] = []
        var cursor = range.lowerBound
        while cursor <= range.upperBound && out.count < limit {
            out.append(cursor)
            cursor = addDays(1, to: cursor)
        }
        return out
    }

    /// What was actually eaten on every day of the given windows.
    func intakeByDay(across ranges: [ClosedRange<String>]) -> [String: Macros] {
        var out: [String: Macros] = [:]
        for key in ranges.flatMap({ Self.dayKeys($0) }) { out[key] = consumed(key) }
        return out
    }

    /// Run it if Friday 6pm has passed and this week has no report yet. Called on
    /// launch and on every return to the foreground; cheap when nothing is due.
    func generateWeeklyReportIfDue() async {
        guard isHydrated, vault.isUnlocked, !weeklyBusy else { return }
        let now = Date()
        guard WeeklyReportMath.isDue(now: now, lastReportWeek: weekly.first?.id) else { return }
        // A failed run (no network, AI down) would otherwise retry every single
        // time the app came forward.
        if let last = lastWeeklyAttempt, now.timeIntervalSince(last) < 1800 { return }
        lastWeeklyAttempt = now
        await generateWeeklyReport(notify: true)
    }

    /// Build this week's report. `notify` is false when he asked for it by hand —
    /// he is already looking at the screen it lands on.
    @discardableResult
    func generateWeeklyReport(notify: Bool) async -> WeeklyReport? {
        guard !weeklyBusy else { return nil }
        weeklyBusy = true
        weeklyError = nil
        defer { weeklyBusy = false }

        let now = Date()
        let key = WeeklyReportMath.weekKey(now)
        let (thisRange, lastRange) = WeeklyReportMath.windows(now: now)
        let all = ProgressPhotoStore.list()
        let lastPhotos = WeeklyReportMath.pick(all, in: lastRange)
        let thisPhotos = WeeklyReportMath.pick(all, in: thisRange)

        // Last week first, then this week — the prompt reads them in that order.
        let images = (lastPhotos + thisPhotos).compactMap(Self.encode)

        let brief = WeeklyBrief.text(
            name: profile.name,
            goal: fitnessProfile.goal,
            targetWeightKg: fitnessProfile.targetWeightKg,
            calorieTarget: fitnessProfile.calorieTargetKcal ?? calorieTargets().map { Double($0.goalCalories) },
            proteinTarget: fitnessProfile.proteinTargetG ?? calorieTargets().map { Double($0.proteinG) },
            fitness: fitness,
            training: training,
            // The real totals — the meal log merged with the AI quick-log — so
            // a week logged entirely through the Fitness checklist is not
            // reported to the model as "calories: not logged".
            intake: intakeByDay(across: [lastRange, thisRange]),
            lastWeek: .init(label: "LAST WEEK", range: lastRange, photos: lastPhotos.count),
            thisWeek: .init(label: "THIS WEEK", range: thisRange, photos: thisPhotos.count))

        var report = WeeklyReport(id: key,
                                  at: Self.nowStamp(),
                                  weekStart: thisRange.lowerBound,
                                  weekEnd: thisRange.upperBound,
                                  photosThisWeek: thisPhotos.count,
                                  photosLastWeek: lastPhotos.count)

        // No photo in one of the weeks is a real answer, not an error — say it
        // without spending a vision call to be told the same thing.
        if lastPhotos.isEmpty || thisPhotos.isEmpty {
            report.verdict = WeeklyReport.Verdict.unknown.rawValue
            report.needsPhotos = true
            report.headline = "No two weeks to compare yet."
            report.read = lastPhotos.isEmpty && thisPhotos.isEmpty
                ? "There are no progress photos in either week. One photo a week is all this needs."
                : (thisPhotos.isEmpty ? "Last week has photos, this week doesn't. Take one and I'll have something to measure."
                                      : "This week has photos, last week doesn't — next Friday there will be two weeks to compare.")
            report.cheer = "Take the photo. It's the whole input."
            save(report)
            if notify { WeeklyNotify.ready(headline: report.headline) }
            return report
        }

        do {
            let dto = try await api.weeklyReport(imagesBase64: images, context: brief)
            report.verdict = dto.verdict
            report.percent = dto.percent
            report.headline = dto.headline
            report.read = dto.read
            report.workouts = dto.workouts
            report.diet = dto.diet
            report.cheer = dto.cheer
            report.needsPhotos = dto.needsPhotos
            save(report)
            if notify { WeeklyNotify.ready(headline: report.headline) }
            return report
        } catch {
            weeklyError = (error as? APIError)?.message ?? error.localizedDescription
            return nil
        }
    }

    func markWeeklyReportSeen(_ id: String) {
        guard let i = weekly.firstIndex(where: { $0.id == id }), !weekly[i].seen else { return }
        weekly[i].seen = true
        push(StateKey.weekly, weekly)
    }

    var unseenWeeklyReport: WeeklyReport? { weekly.first { !$0.seen } }

    /// Newest first, one per week, capped.
    private func save(_ report: WeeklyReport) {
        var next = weekly.filter { $0.id != report.id }
        next.insert(report, at: 0)
        if next.count > WeeklyReport.cap { next = Array(next.prefix(WeeklyReport.cap)) }
        weekly = next
        push(StateKey.weekly, weekly)
    }

    /// Progress photos are full-resolution camera files; 512px is plenty for
    /// "is the belly bigger" and keeps eight of them inside one request.
    private static func encode(_ photo: ProgressPhoto) -> String? {
        guard let raw = try? Data(contentsOf: photo.url) else { return nil }
        let small = MediaJPEG.downscale(raw, maxSide: 512, quality: 0.6) ?? raw
        return small.base64EncodedString()
    }
}
