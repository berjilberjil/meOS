import Foundation
import UserNotifications

/// One daily reminder — a fixed set of ids (wake / breakfast / lunch / workout /
/// dinner); the user can move the time or switch each off. Device-local.
struct Reminder: Codable, Identifiable, Hashable {
    var id: String
    var label: String
    var body: String
    var hour: Int
    var minute: Int
    var enabled: Bool
}

/// The default reminder set + pure merge logic (kept off the @MainActor store so
/// it is unit-testable).
enum ReminderDefaults {
    static func all() -> [Reminder] {
        [
            Reminder(id: "wake", label: "Start the day",
                     body: "Log your weight, journal, and check MyOS.", hour: 6, minute: 0, enabled: true),
            Reminder(id: "breakfast", label: "Breakfast",
                     body: "Time to eat — log your breakfast.", hour: 8, minute: 0, enabled: true),
            Reminder(id: "lunch", label: "Lunch",
                     body: "Lunch time — log what you eat.", hour: 12, minute: 30, enabled: true),
            Reminder(id: "workout", label: "Workout",
                     body: "Time to train. Log it after.", hour: 16, minute: 0, enabled: true),
            Reminder(id: "dinner", label: "Dinner",
                     body: "Dinner time — log your meal.", hour: 19, minute: 0, enabled: true)
        ]
    }

    /// The canonical set, but with each reminder's time + enabled taken from the
    /// saved copy when present. Keeps labels/bodies current and drops unknown ids.
    static func merged(saved: [Reminder]) -> [Reminder] {
        all().map { def in
            guard let s = saved.first(where: { $0.id == def.id }) else { return def }
            var out = def
            out.hour = s.hour; out.minute = s.minute; out.enabled = s.enabled
            return out
        }
    }
}

/// Device-local reminder settings + local-notification scheduling. Mirrors the
/// ThemeStore pattern; shared by both platforms (local notifications need no push
/// entitlement).
@MainActor
final class ReminderStore: ObservableObject {
    static let shared = ReminderStore()

    private let kEnabled = "myos.reminders.enabled"
    private let kList = "myos.reminders.list"

    @Published var enabled: Bool { didSet { persist(); Task { await reschedule() } } }
    @Published var reminders: [Reminder] { didSet { persist(); Task { await reschedule() } } }
    @Published var authorized = false

    private init() {
        enabled = UserDefaults.standard.object(forKey: kEnabled) as? Bool ?? false
        if let d = UserDefaults.standard.data(forKey: kList),
           let list = try? JSONDecoder().decode([Reminder].self, from: d), !list.isEmpty {
            reminders = ReminderDefaults.merged(saved: list)
        } else {
            reminders = ReminderDefaults.all()
        }
    }

    /// Ask for notification permission; on grant, enable + schedule.
    func requestAuthorization() async {
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        authorized = granted
        enabled = granted   // didSet reschedules (or clears if denied)
    }

    func refreshAuthorization() async {
        let s = await UNUserNotificationCenter.current().notificationSettings()
        authorized = s.authorizationStatus == .authorized || s.authorizationStatus == .provisional
    }

    /// Re-sync stored settings after launch (system triggers persist, but this
    /// recovers them after a reinstall or a settings change on this device).
    func syncOnLaunch() async {
        await refreshAuthorization()
        if enabled && authorized { await reschedule() }
    }

    /// Replace all pending reminder notifications with the current enabled set.
    func reschedule() async {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        guard enabled else { return }
        for r in reminders where r.enabled {
            let content = UNMutableNotificationContent()
            content.title = r.label
            content.body = r.body
            content.sound = .default
            var comps = DateComponents(); comps.hour = r.hour; comps.minute = r.minute
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            let req = UNNotificationRequest(identifier: "myos.reminder.\(r.id)", content: content, trigger: trigger)
            try? await center.add(req)
        }
    }

    func setTime(id: String, hour: Int, minute: Int) {
        guard let i = reminders.firstIndex(where: { $0.id == id }) else { return }
        reminders[i].hour = hour; reminders[i].minute = minute
    }

    func setEnabled(id: String, _ on: Bool) {
        guard let i = reminders.firstIndex(where: { $0.id == id }) else { return }
        reminders[i].enabled = on
    }

    private func persist() {
        UserDefaults.standard.set(enabled, forKey: kEnabled)
        if let d = try? JSONEncoder().encode(reminders) { UserDefaults.standard.set(d, forKey: kList) }
    }
}

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// The one notification the focus timer fires. Not scheduled and not a
/// `Reminder` — it goes out the moment a block ends, and only when nobody is
/// looking at the app. Uses whatever authorization the reminders already have;
/// it never prompts on its own.
@MainActor
enum FocusNotify {
    static let id = "myos.focus.timesup"

    static func timesUp(task: String) {
        guard !appIsFrontmost else { return }
        let c = UNMutableNotificationContent()
        c.title = "Time's up"
        c.body = task.trimmingCharacters(in: .whitespaces).isEmpty
            ? "Your focus block is done." : task
        c.sound = .default
        UNUserNotificationCenter.current()
            .add(UNNotificationRequest(identifier: id, content: c, trigger: nil))
    }

    private static var appIsFrontmost: Bool {
        #if os(macOS)
        return NSApplication.shared.isActive
        #else
        return UIApplication.shared.applicationState == .active
        #endif
    }
}

/// The Friday report's notification. Fired only once the report actually exists —
/// the app builds it first, because the photos are sealed on this device.
@MainActor
enum WeeklyNotify {
    static let id = "myos.weekly.ready"
    static let route = "weekly"

    static func ready(headline: String) {
        let c = UNMutableNotificationContent()
        c.title = "Your week, read back"
        c.body = headline.isEmpty ? "The Friday report is ready." : headline
        c.sound = .default
        c.userInfo = ["route": route]
        UNUserNotificationCenter.current()
            .add(UNNotificationRequest(identifier: id, content: c, trigger: nil))
    }
}

/// Routes a tapped notification to the screen it belongs to. Shared by both
/// platforms' app delegates.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationRouter()

    /// Show it even when MyOS is open — the report is generated in-app, so the
    /// moment it lands he is usually looking at something else in the app.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async
    -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let route = response.notification.request.content.userInfo["route"] as? String
        guard route == WeeklyNotify.route else { return }
        await MainActor.run { UISignals.shared.openWeeklyReport = true }
    }
}
