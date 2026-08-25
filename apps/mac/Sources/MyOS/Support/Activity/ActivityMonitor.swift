import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// This device, stably. The id is generated once and kept in UserDefaults so a
/// Mac and an iPhone stay distinguishable in the combined model across relaunches.
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

/// Watches which application is in front, and for how long.
///
/// This is the only real sensor MyOS has. `NSWorkspace` publishes activations to
/// any app, with no entitlement and no accessibility prompt — it reports the
/// application, never what you typed or which document is open, which is the
/// line this deliberately does not cross.
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

    /// How often the current session is checked and extended.
    private static let tick: TimeInterval = 20

    private var currentApp: (id: String, name: String)?
    private var startedAt: Date?
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
        for o in observers { center.removeObserver(o); distributed.removeObserver(o) }
        observers = []
        onLiveChange?(nil)
    }

    private enum CloseReason { case switched, stopped }

    /// Seconds since the last keyboard or mouse event, system-wide. Needs no
    /// permission — it is a timestamp, not the events themselves.
    private var systemIdle: TimeInterval {
        guard let anyEvent = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: anyEvent)
    }

    private func pulse() {
        if systemIdle < Self.idleThreshold {
            lastActive = Date()
            onLiveChange?(liveSession())
        } else if startedAt != nil {
            // Idle: bank what was real and wait for the machine to come back.
            close(reason: .stopped)
        }
    }

    private func switched(to app: NSRunningApplication?) {
        close(reason: .switched)
        guard let app,
              let name = app.localizedName ?? app.bundleIdentifier else { return }
        // MyOS looking at itself is not activity worth reporting.
        let id = app.bundleIdentifier ?? ActivityCatalog.slug(name)
        currentApp = (id, name)
        startedAt = Date()
        lastActive = Date()
        onLiveChange?(liveSession())
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
            if reason == .stopped { currentApp = nil; startedAt = nil }
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

    private func event(app: (id: String, name: String), started: Date, ended: Date, seconds: Int) -> ActivityEvent {
        let classified = ActivityCatalog.classify(appId: app.id, appName: app.name, rules: rules)
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
                             source: .macFrontmost)
    }
}

#endif
