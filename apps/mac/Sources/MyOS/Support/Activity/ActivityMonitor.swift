import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// This device, stably. The id is generated once and kept in UserDefaults, so a
/// Mac keeps its identity across relaunches and two Macs never merge into one
/// row in the devices list.
enum ActivityDeviceIdentity {
    private static let key = "myos.activity.deviceId"

    static var deviceId: String {
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let fresh = UUID().uuidString.lowercased()
        UserDefaults.standard.set(fresh, forKey: key)
        return fresh
    }

    static var deviceType: DeviceType {
        #if os(macOS)
        return .mac
        #else
        return .iphone
        #endif
    }

    static var deviceName: String {
        #if os(macOS)
        return Host.current().localizedName ?? "Mac"
        #else
        return UIDevice.current.name
        #endif
    }

    static var platform: String {
        #if os(macOS)
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(v.majorVersion).\(v.minorVersion)"
        #else
        return "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
        #endif
    }
}

#if os(macOS)

/// Watches what is in front, and for how long.
///
/// This is the only real sensor MyOS has. `NSWorkspace` publishes activations to
/// any app with no permission at all, and that alone answers "which app" — but
/// "Chrome, 2 hours" is not an answer, because Chrome is where the work happens
/// *and* where the day leaks. So a second, optional pass reads the frontmost
/// window through Accessibility: its title, and for a browser the domain in the
/// address bar. Deny the permission and everything here still works; it just
/// cannot tell github.com from youtube.com.
///
/// The line: the title bar and the host. Never the page, never the path, never
/// a keystroke.
///
/// Three things end a session besides switching app: going idle at the keyboard,
/// locking the screen, and the machine sleeping. Without those, walking away for
/// lunch would be recorded as an hour of deep work in whatever was in front.
@MainActor
final class MacActivityMonitor {

    /// Sessions shorter than this are dropped. Alt-tabbing through three windows
    /// to reach the fourth is not three sessions.
    static let minimumSessionSeconds = 10

    /// No keyboard or mouse for this long and the clock stops.
    static let idleThreshold: TimeInterval = 120

    /// How often the sensor looks. Fast enough that a tab change is caught
    /// while it still is one — at the old 20 seconds a quick look at something
    /// was credited to whatever came before it.
    private static let tick: TimeInterval = 5

    /// The live card does not need to be told the same thing every five
    /// seconds; it is redrawn on a change, or on this.
    private static let liveEmitInterval: TimeInterval = 20

    /// A session that has been running this long is banked and immediately
    /// restarted. Nothing about the day changes — `ActivityJournal` merges the
    /// two halves straight back together — but it means a crash, a force-quit
    /// or a power cut can never cost more than this, instead of costing however
    /// long you had been heads-down in one app.
    private static let bankInterval: TimeInterval = 5 * 60

    private var currentApp: (id: String, name: String, pid: pid_t, bundleId: String?)?
    /// What was in front *inside* the app — the domain, the document. Part of
    /// the session's identity: a new site is a new session, not a footnote on
    /// the old one.
    private var context: WindowContext = .none
    private var startedAt: Date?
    private var lastLiveEmit: Date = .distantPast
    /// When we last saw real input, so an idle stretch can be trimmed off the
    /// end of the session rather than counted.
    private var lastActive: Date = Date()
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var running = false

    /// Called with each finished session. The caller decides what to do with it.
    var onSession: ((ActivityEvent) -> Void)?
    /// Called whenever the live session changes, so Today can show it without
    /// waiting for the session to end.
    var onLiveChange: ((ActivityEvent?) -> Void)?

    /// Rules, so a session is classified the way Berjil said rather than the way
    /// the catalogue guessed.
    var rules: [String: AppRule] = [:]

    /// Whether window titles are recorded. Domains are read either way — a host
    /// is where you were, a title can be the name of a document.
    var recordsTitles: Bool = true

    func start() {
        guard !running else { return }
        running = true

        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                            object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.switched(to: app) }
        })
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.close(reason: .stopped) }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.switched(to: NSWorkspace.shared.frontmostApplication) }
        })

        // Lock/unlock is a distributed notification, not a workspace one.
        let distributed = DistributedNotificationCenter.default()
        observers.append(distributed.addObserver(forName: .init("com.apple.screenIsLocked"),
                                                 object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.close(reason: .stopped) }
        })
        observers.append(distributed.addObserver(forName: .init("com.apple.screenIsUnlocked"),
                                                 object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.switched(to: NSWorkspace.shared.frontmostApplication) }
        })

        // Quitting is the most common way a session used to be lost: the app
        // goes away mid-session and the clock is simply never stopped.
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.close(reason: .stopped) }
            })

        timer = Timer.scheduledTimer(withTimeInterval: Self.tick, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pulse() }
        }
        switched(to: NSWorkspace.shared.frontmostApplication)
    }

    func stop() {
        guard running else { return }
        running = false
        close(reason: .stopped)
        timer?.invalidate(); timer = nil
        let center = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        for o in observers {
            center.removeObserver(o)
            distributed.removeObserver(o)
            NotificationCenter.default.removeObserver(o)
        }
        observers = []
        onLiveChange?(nil)
        WindowProbe.forgetAll()
    }

    private enum CloseReason { case switched, stopped }

    /// Seconds since the last keyboard or mouse event, system-wide. Needs no
    /// permission — it is a timestamp, not the events themselves.
    private var systemIdle: TimeInterval {
        guard let anyEvent = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: anyEvent)
    }

    private func pulse() {
        let idle = systemIdle
        guard idle < Self.idleThreshold else {
            // Idle: bank what was real and wait for the machine to come back.
            if startedAt != nil { close(reason: .stopped) }
            return
        }
        // The moment of the last *input*, not of this pulse. Recording the pulse
        // time made `close`'s idle trim — `min(Date(), lastActive)` — remove
        // nothing, so every idle transition credited the app with the full two
        // minutes it took to notice nobody was there. Step away fifteen times a
        // day and half an hour of nothing went into the day's total, the app
        // breakdown, and the productive share the verdict is built on.
        lastActive = Date().addingTimeInterval(-idle)

        // Back at the keyboard after being away. Idle cleared the current app,
        // and `NSWorkspace` only speaks when the frontmost app *changes* — so
        // without this the clock stays stopped until the next app switch. Come
        // back from lunch to the same window you left and the whole afternoon
        // used to go unrecorded. This is the single biggest reason the numbers
        // were wrong.
        if currentApp == nil {
            switched(to: NSWorkspace.shared.frontmostApplication)
            return
        }

        if let started = startedAt, Date().timeIntervalSince(started) >= Self.bankInterval {
            bankLive()
            return
        }

        // The app has not changed, but what is in front of you inside it may
        // have. This is the whole browser story: one Chrome activation can be
        // an hour of GitHub followed by forty minutes of YouTube, and without
        // this it is one undifferentiated hour and forty minutes of "Chrome".
        let fresh = probeContext()
        if fresh != context {
            contextChanged(to: fresh)
            return
        }

        if Date().timeIntervalSince(lastLiveEmit) >= Self.liveEmitInterval { emitLive() }
    }

    /// Read the frontmost window, if Accessibility allows it.
    private func probeContext() -> WindowContext {
        guard let app = currentApp else { return .none }
        let fresh = WindowProbe.read(pid: app.pid, bundleId: app.bundleId,
                                     appName: app.name, titles: recordsTitles)
        return WindowSense.settling(fresh, after: context,
                                    isBrowser: WindowSense.isBrowser(bundleId: app.bundleId,
                                                                     appName: app.name))
    }

    /// A new domain or a new document, in the same app.
    ///
    /// If the stretch that just ended is too short to be a row of its own, the
    /// session is *relabelled* rather than split. Closing it would drop it under
    /// the minimum and delete the seconds outright — and time that vanishes
    /// because you glanced at a second tab is exactly the kind of quiet
    /// inaccuracy this whole file exists to avoid.
    private func contextChanged(to fresh: WindowContext) {
        guard let app = currentApp, let started = startedAt else { context = fresh; return }
        if Date().timeIntervalSince(started) < TimeInterval(Self.minimumSessionSeconds) {
            context = fresh
            emitLive()
            return
        }
        close(reason: .switched)
        currentApp = app
        context = fresh
        startedAt = Date()
        lastActive = Date()
        emitLive()
    }

    private func emitLive() {
        lastLiveEmit = Date()
        onLiveChange?(liveSession())
    }

    /// Close the running session and start a fresh one in the same app, so the
    /// time so far is on disk. The journal merges them back into one row.
    private func bankLive() {
        guard let app = currentApp else { return }
        let held = context
        close(reason: .switched)
        currentApp = app
        context = held
        startedAt = Date()
        lastActive = Date()
        emitLive()
    }

    private func switched(to app: NSRunningApplication?) {
        close(reason: .switched)
        guard let app,
              let name = app.localizedName ?? app.bundleIdentifier else { return }
        let id = app.bundleIdentifier ?? ActivityCatalog.slug(name)
        // The cached address-bar element belongs to the window that just went
        // away; a stale one reads the wrong tab.
        WindowProbe.forget(pid: app.processIdentifier)
        currentApp = (id, name, app.processIdentifier, app.bundleIdentifier)
        startedAt = Date()
        lastActive = Date()
        // Cleared first: `probeContext` holds a browser's last known site across
        // an unreadable moment, and that must never carry over from the app we
        // just left.
        context = .none
        context = probeContext()
        emitLive()
    }

    /// The session as it stands right now, for the live card.
    func liveSession() -> ActivityEvent? {
        guard let app = currentApp, let started = startedAt else { return nil }
        let end = min(Date(), lastActive)
        let seconds = max(0, Int(end.timeIntervalSince(started)))
        guard seconds > 0 else { return nil }
        return event(app: app, started: started, ended: end, seconds: seconds)
    }

    private func close(reason: CloseReason) {
        defer {
            if reason == .stopped {
                currentApp = nil; startedAt = nil; context = .none
                // Say out loud that nothing is running. Without this the last
                // emitted live session stuck around after idle, sleep, a screen
                // lock or termination — so `activitySummaryLive` added it on top
                // of the real session that had just been banked (up to five
                // minutes double-counted), and `refreshLiveNote` kept re-stamping
                // it, leaving the iPhone showing "Focusing now — Xcode" with a
                // rising counter for minutes after the Mac went to sleep.
                onLiveChange?(nil)
            }
        }
        guard let app = currentApp, let started = startedAt else { return }
        // Idle time at the end of a session is not time spent in the app.
        let end = min(Date(), lastActive)
        let seconds = Int(end.timeIntervalSince(started))
        currentApp = nil
        startedAt = nil
        guard seconds >= Self.minimumSessionSeconds else { return }
        onSession?(event(app: app, started: started, ended: end, seconds: seconds))
    }

    private func event(app: (id: String, name: String, pid: pid_t, bundleId: String?),
                       started: Date, ended: Date, seconds: Int) -> ActivityEvent {
        let classified = ActivityCatalog.classify(appId: app.id, appName: app.name,
                                                  site: context.site, rules: rules)
        return ActivityEvent(deviceId: ActivityDeviceIdentity.deviceId,
                             deviceType: .mac,
                             platform: ActivityDeviceIdentity.platform,
                             appId: app.id,
                             appName: app.name,
                             category: classified.category,
                             startedAt: ActivityTime.stamp(started),
                             endedAt: ActivityTime.stamp(ended),
                             duration: seconds,
                             productivity: classified.productivity,
                             source: .macFrontmost,
                             site: context.site,
                             title: context.title)
    }
}

#endif
