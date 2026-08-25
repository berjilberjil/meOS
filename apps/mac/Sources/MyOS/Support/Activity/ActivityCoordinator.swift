import Foundation
import SwiftUI

/// Owns the sensors and feeds `AppState.activity`.
///
/// Split out of `AppState` because it has real lifecycle — a timer, workspace
/// observers, a push throttle — and because the sensors differ per platform
/// while everything above this line does not.
@MainActor
final class ActivityCoordinator: ObservableObject {
    static let shared = ActivityCoordinator()

    /// Whether this device records activity. Per device, deliberately not
    /// synced: turning tracking on for the Mac should not silently turn it on
    /// for the phone.
    private static let enabledKey = "myos.activity.enabled"

    @Published private(set) var enabled: Bool

    /// Sessions land here constantly; the synced blob does not need to hear
    /// about each one. Flushed on this interval, and whenever the app leaves.
    private static let pushInterval: TimeInterval = 120

    private weak var state: AppState?
    private var pendingPush = false
    private var pushTimer: Timer?

    #if os(macOS)
    private let monitor = MacActivityMonitor()
    #endif

    private init() {
        enabled = UserDefaults.standard.bool(forKey: ActivityCoordinator.enabledKey)
    }

    func configure(state: AppState) {
        self.state = state
        #if os(macOS)
        monitor.rules = state.activity.rules
        monitor.onSession = { [weak self] event in
            MainActor.assumeIsolated { self?.record(event) }
        }
        monitor.onLiveChange = { [weak self] live in
            MainActor.assumeIsolated { self?.state?.liveActivity = live }
        }
        #endif
        registerDevice()
        drainInbox()
        if enabled { start() }
    }

    func setEnabled(_ on: Bool) {
        guard on != enabled else { return }
        enabled = on
        UserDefaults.standard.set(on, forKey: Self.enabledKey)
        on ? start() : stop()
    }

    private func start() {
        #if os(macOS)
        monitor.start()
        #endif
        pushTimer?.invalidate()
        pushTimer = Timer.scheduledTimer(withTimeInterval: Self.pushInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.flush() }
        }
    }

    private func stop() {
        #if os(macOS)
        monitor.stop()
        #endif
        pushTimer?.invalidate(); pushTimer = nil
        state?.liveActivity = nil
        flush()
    }

    /// Take one finished session into the document.
    ///
    /// Consecutive sessions in the same app separated by a short gap are merged
    /// rather than appended. Tabbing out to check a notification and coming
    /// straight back is one stretch of work, and keeping it as two would both
    /// inflate the switch count and bloat a blob that syncs on every change.
    func record(_ event: ActivityEvent) {
        guard let state else { return }
        guard event.duration > 0 else { return }
        var doc = state.activity

        if let last = doc.events.last,
           last.appId == event.appId,
           last.deviceId == event.deviceId,
           last.day == event.day,
           gap(from: last.endedAt, to: event.startedAt) <= 90 {
            var merged = last
            merged.endedAt = event.endedAt
            merged.duration += event.duration
            doc.events[doc.events.count - 1] = merged
        } else {
            doc.events.append(event)
        }

        ActivityEngine.compact(&doc, today: state.todayKey)
        state.activity = doc
        pendingPush = true
    }

    private func gap(from end: String, to start: String) -> Int {
        guard let a = ActivityTime.date(end), let b = ActivityTime.date(start) else { return .max }
        return max(0, Int(b.timeIntervalSince(a)))
    }

    /// Fold whatever the iPhone's Shortcuts automations queued into sessions.
    /// Safe to call often — the inbox is emptied only once the sessions are in.
    func drainInbox() {
        guard let state else { return }
        let pings = ActivityInbox.pending()
        guard !pings.isEmpty else { return }
        let sessions = ActivityInbox.sessions(from: pings, rules: state.activity.rules)
        guard !sessions.isEmpty else { ActivityInbox.clear(); return }
        for session in sessions { record(session) }
        ActivityInbox.clear()
        flush()
    }

    /// MyOS's own foreground time on the phone. Honest but small — it is the one
    /// app iOS lets MyOS time directly.
    func recordOwnForeground(from start: Date, to end: Date) {
        let seconds = Int(end.timeIntervalSince(start))
        guard seconds >= 10 else { return }
        record(ActivityEvent(deviceId: ActivityDeviceIdentity.deviceId,
                             deviceType: ActivityDeviceIdentity.deviceType,
                             platform: ActivityDeviceIdentity.platform,
                             appId: "com.berjil.myos",
                             appName: "MyOS",
                             category: .writing,
                             startedAt: ActivityTime.stamp(start),
                             endedAt: ActivityTime.stamp(end),
                             duration: seconds,
                             productivity: .productive,
                             source: .iosForeground))
    }

    private func registerDevice() {
        guard let state else { return }
        var doc = state.activity
        doc.devices[ActivityDeviceIdentity.deviceId] = ActivityDevice(
            deviceId: ActivityDeviceIdentity.deviceId,
            deviceType: ActivityDeviceIdentity.deviceType,
            name: ActivityDeviceIdentity.deviceName,
            lastSeen: ActivityTime.stamp(Date()))
        state.activity = doc
        pendingPush = true
    }

    /// Send what has accumulated. Called on a timer, when tracking stops, and
    /// when the app goes away.
    func flush() {
        guard pendingPush, let state, state.isHydrated else { return }
        pendingPush = false
        state.push(StateKey.activity, state.activity)
    }

    /// Wipe everything recorded. Deliberately total: a partial erase of an
    /// activity log is worse than none, because what survives looks complete.
    func erase() {
        guard let state else { return }
        state.activity = ActivityDoc()
        state.liveActivity = nil
        ActivityInbox.clear()
        registerDevice()
        pendingPush = true
        flush()
    }

    /// Rules changed — the monitor classifies as it records, so it needs them.
    func rulesChanged() {
        #if os(macOS)
        monitor.rules = state?.activity.rules ?? [:]
        #endif
    }
}

// MARK: - Reading

extension AppState {

    /// Today's open to-dos, as plain strings — the context the rules engine uses
    /// to tell "working on the priority" from "working".
    var todayPriorities: [String] {
        (days[todayKey]?.todos ?? []).filter { !$0.done }.map(\.text)
    }

    func activitySummary(_ day: String) -> ActivitySummary {
        ActivityEngine.summary(activity.events, day: day)
    }

    /// The seven days ending on `day`, oldest first.
    func activityWeekDays(endingOn day: String) -> [String] {
        (0..<7).reversed().map { AppState.addDays(-$0, to: day) }
    }

    func activityWeek(endingOn day: String) -> ActivityWeekSummary {
        ActivityEngine.weekSummary(doc: activity, days: activityWeekDays(endingOn: day))
    }

    /// The day's read, including the live session where there is one. Only the
    /// day being viewed *is* today can have a live session — yesterday has no
    /// "right now".
    func activityIntelligence(_ day: String, now: Date = Date()) -> DayIntelligence {
        var summary = activitySummary(day)
        let live = day == todayKey ? liveActivity : nil
        // The live session has not been banked yet, so add it in or the card
        // would show a total that lags reality by up to two minutes.
        if let live {
            summary = ActivityEngine.summary(activity.events + [live], day: day)
        }
        return ActivityInsights.dayIntelligence(summary: summary, current: live,
                                                todos: todayPriorities, now: now)
    }

    /// Summary including the unbanked live session, for the surfaces that show
    /// totals next to "focusing now".
    func activitySummaryLive(_ day: String) -> ActivitySummary {
        if day == todayKey, let live = liveActivity {
            return ActivityEngine.summary(activity.events + [live], day: day)
        }
        return activitySummary(day)
    }

    func eraseActivity() { ActivityCoordinator.shared.erase() }

    /// Override what an app counts as, from the app breakdown.
    func setAppRule(appId: String, appName: String,
                    category: ActivityCategory, productivity: ProductivityType) {
        var doc = activity
        doc.rules[appId] = AppRule(appId: appId, appName: appName,
                                   category: category, productivity: productivity)
        // Reclassify what is already recorded, or the breakdown would disagree
        // with the rule until the events aged out.
        for i in doc.events.indices where doc.events[i].appId == appId {
            doc.events[i].category = category
            doc.events[i].productivity = productivity
        }
        activity = doc
        ActivityCoordinator.shared.rulesChanged()
        push(StateKey.activity, doc)
    }
}
