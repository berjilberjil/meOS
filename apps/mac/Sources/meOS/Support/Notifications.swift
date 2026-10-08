import Foundation
import UserNotifications

/// What a reminder sounds like.
///
/// Five reminders that all go "ding" are five reminders you learn to ignore
/// without looking. Giving each one its own voice means the phone in your
/// pocket can tell you it is lunch without you taking it out.
///
/// This used to be lopsided. macOS can name any system sound by name, but iOS
/// resolves a named notification sound *only* against files inside the app
/// bundle — so the phone, which is the device actually in your pocket when a
/// reminder fires, was the one offering three sounds while the Mac offered
/// sixteen. Every sound now ships as a file in `Resources/Sounds`, so both
/// platforms offer the same list and a sound picked on one means the same thing
/// on the other.
enum ReminderSound: String, Codable, CaseIterable, Identifiable, Hashable {
    case standard, drop, silent
    case ping, glass, hero, submarine, funk, tink, pop, sosumi, purr, morse, bottle, blow, frog, basso

    var id: String { rawValue }

    var label: String {
        switch self {
        case .standard: return "Standard"
        case .drop:     return "meOS"
        case .silent:   return "Silent"
        default:        return rawValue.prefix(1).uppercased() + rawValue.dropFirst()
        }
    }

    /// The file this sound ships as, or `nil` for the two that are deliberately
    /// fileless — Standard is the system's own alert and Silent is no sound.
    ///
    /// The fourteen named ones are IMA4 `.caf`, which is one of the handful of
    /// formats `UNNotificationSound` will accept, and about a quarter the size
    /// of the AIFF they came from.
    var bundledFile: (name: String, ext: String)? {
        switch self {
        case .standard, .silent: return nil
        case .drop:              return ("drop", "wav")
        default:                 return (label, "caf")
        }
    }

    /// Every sound, on every platform. Kept as a separate name from `allCases`
    /// because the call sites read better and because this is the seam where a
    /// future platform-specific sound would be filtered out.
    static var available: [ReminderSound] { allCases }

    /// What `UNNotificationContent` should be handed.
    ///
    /// `nil` is not a missing value here — it is how the notification API says
    /// "no sound", which is exactly what Silent means.
    var notificationSound: UNNotificationSound? {
        switch resolved {
        case .silent:   return nil
        case .standard: return .default
        default:
            guard let file = resolved.bundledFile else { return .default }
            return UNNotificationSound(named: UNNotificationSoundName("\(file.name).\(file.ext)"))
        }
    }

    /// Identity, now that every sound exists everywhere.
    ///
    /// Kept rather than deleted because it is the one place a sound gets a
    /// chance to say "not here, use Standard instead", and losing that seam is
    /// how a sound goes silently missing on one device. A file that failed to
    /// ship already degrades safely without it — the notification API falls back
    /// to the default rather than firing mute — so this no longer has to guess.
    var resolved: ReminderSound { self }
}

/// Where a tapped notification should land.
///
/// A notification that opens the app on whatever screen you happened to leave
/// it on is a notification that made you do the work twice. Every one meOS
/// sends now names its destination, and the raw values are what travel in
/// `userInfo` — so they are a wire format and must not be renamed lightly.
enum NotifRoute: String, Codable, Hashable, CaseIterable {
    case today, weight, breakfast, lunch, dinner, workout, steps, weekly, events

    /// Where each of the five daily reminders goes.
    ///
    /// Pure, and tested, because the mapping is a set of small decisions that
    /// are invisible from the outside: the wake reminder's own words are "log
    /// your weight", so it opens on the dial rather than on the top of Today.
    static func forReminder(_ id: String) -> NotifRoute {
        switch id {
        case "wake":      return .weight
        case "breakfast": return .breakfast
        case "lunch":     return .lunch
        case "dinner":    return .dinner
        case "workout":   return .workout
        default:          return .today
        }
    }

    /// The meal editor this route opens, if it is about a meal at all.
    var meal: MealKey? {
        switch self {
        case .breakfast: return .breakfast
        case .lunch:     return .lunch
        case .dinner:    return .dinner
        default:         return nil
        }
    }
}

/// One daily reminder — a fixed set of ids (wake / breakfast / lunch / workout /
/// dinner); the user can move the time, switch each off, and give each its own
/// sound. Device-local.
struct Reminder: Codable, Identifiable, Hashable {
    var id: String
    var label: String
    var body: String
    var hour: Int
    var minute: Int
    var enabled: Bool
    var sound: ReminderSound = .standard

    init(id: String, label: String, body: String, hour: Int, minute: Int,
         enabled: Bool, sound: ReminderSound = .standard) {
        self.id = id; self.label = label; self.body = body
        self.hour = hour; self.minute = minute; self.enabled = enabled; self.sound = sound
    }

    /// Tolerant: reminders saved before sounds existed have no `sound` key.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id      = try c.decode(String.self, forKey: .id)
        label   = try c.decode(String.self, forKey: .label)
        body    = try c.decode(String.self, forKey: .body)
        hour    = try c.decode(Int.self, forKey: .hour)
        minute  = try c.decode(Int.self, forKey: .minute)
        enabled = try c.decode(Bool.self, forKey: .enabled)
        sound   = ReminderSound(rawValue: (try? c.decode(String.self, forKey: .sound)) ?? "") ?? .standard
    }

    enum CodingKeys: String, CodingKey { case id, label, body, hour, minute, enabled, sound }
}

/// The default reminder set + pure merge logic (kept off the @MainActor store so
/// it is unit-testable).
enum ReminderDefaults {
    static func all() -> [Reminder] {
        [
            Reminder(id: "wake", label: "Start the day",
                     body: "Log your weight, journal, and check meOS.", hour: 6, minute: 0, enabled: true,
                     sound: .standard),
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
            out.sound = s.sound
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

    private let kEventSound = "myos.reminders.eventSound"

    @Published var enabled: Bool { didSet { persist(); Task { await reschedule() } } }
    @Published var reminders: [Reminder] { didSet { persist(); Task { await reschedule() } } }
    @Published var authorized = false
    /// One voice for every event reminder.
    ///
    /// Per-event would mean a sound picker inside the event editor, which is a
    /// lot of screen for a choice you would make once. The five daily reminders
    /// each get their own because they are five *fixed* things you learn to tell
    /// apart by ear; events are one kind of thing that happens to be many.
    @Published var eventSound: ReminderSound { didSet { persist() } }

    private init() {
        enabled = UserDefaults.standard.object(forKey: kEnabled) as? Bool ?? false
        if let d = UserDefaults.standard.data(forKey: kList),
           let list = try? JSONDecoder().decode([Reminder].self, from: d), !list.isEmpty {
            reminders = ReminderDefaults.merged(saved: list)
        } else {
            reminders = ReminderDefaults.all()
        }
        eventSound = ReminderSound(rawValue: UserDefaults.standard.string(forKey: kEventSound) ?? "")
            ?? .standard
    }

    /// Ask for notification permission; on grant, enable + schedule.
    /// True after a request that was refused because permission was already
    /// denied at the system level — the prompt does not appear a second time, so
    /// the toggle just springs back with nothing to explain it.
    @Published var permissionRefused = false

    func requestAuthorization() async {
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        authorized = granted
        permissionRefused = !granted
        enabled = granted   // didSet reschedules (or clears if denied)
    }

    func refreshAuthorization() async {
        let s = await UNUserNotificationCenter.current().notificationSettings()
        authorized = s.authorizationStatus == .authorized || s.authorizationStatus == .provisional
        if authorized { permissionRefused = false }
    }

    /// Reminders are switched on in meOS but the system will not deliver them.
    ///
    /// `enabled` lives in UserDefaults and survives permission being revoked in
    /// System Settings, so the card went on showing the master switch on and all
    /// five rows with their times while `syncOnLaunch` quietly skipped
    /// scheduling. Nothing ever fired and nothing said why.
    var isSilentlyOff: Bool { (enabled && !authorized) || permissionRefused }

    /// Re-sync stored settings after launch (system triggers persist, but this
    /// recovers them after a reinstall or a settings change on this device).
    func syncOnLaunch() async {
        await refreshAuthorization()
        if enabled && authorized { await reschedule() }
    }

    /// Every daily reminder id starts with this.
    static let idPrefix = "myos.reminder."

    /// Replace all pending *daily* reminder notifications with the current
    /// enabled set.
    ///
    /// Targeted, not `removeAllPendingNotificationRequests()`. That took out
    /// every pending notification the app had, which was harmless while these
    /// five were the only scheduled ones — and became a silent bug the moment
    /// events could schedule their own: nudging lunch by a minute would have
    /// cancelled every birthday reminder in the app, and nothing would have
    /// said so. Each scheduler now owns its own id prefix and removes only that.
    func reschedule() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix(Self.idPrefix) }
        if !ours.isEmpty { center.removePendingNotificationRequests(withIdentifiers: ours) }
        guard enabled else { return }
        for r in reminders where r.enabled {
            let content = UNMutableNotificationContent()
            content.title = r.label
            content.body = r.body
            content.sound = r.sound.notificationSound
            // Without this every reminder opened the app wherever it was last
            // left. Tapping "Lunch" now opens the lunch editor.
            content.userInfo = ["route": NotifRoute.forReminder(r.id).rawValue]
            var comps = DateComponents(); comps.hour = r.hour; comps.minute = r.minute
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            let req = UNNotificationRequest(identifier: "\(Self.idPrefix)\(r.id)", content: content, trigger: trigger)
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

    func setSound(id: String, _ sound: ReminderSound) {
        guard let i = reminders.firstIndex(where: { $0.id == id }) else { return }
        reminders[i].sound = sound
    }


    private func persist() {
        UserDefaults.standard.set(enabled, forKey: kEnabled)
        UserDefaults.standard.set(eventSound.rawValue, forKey: kEventSound)
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
/// Whether meOS is the thing being looked at. A notification for something the
/// user can already see on screen is noise.
@MainActor
enum AppFocus {
    static var isFrontmost: Bool {
        #if os(macOS)
        return NSApplication.shared.isActive
        #else
        return UIApplication.shared.applicationState == .active
        #endif
    }
}

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
        c.userInfo = ["route": NotifRoute.today.rawValue]
        UNUserNotificationCenter.current()
            .add(UNNotificationRequest(identifier: id, content: c, trigger: nil))
    }

    private static var appIsFrontmost: Bool { AppFocus.isFrontmost }
}

/// A step goal, crossed.
///
/// Only fires when meOS is not the thing in front of you — with the app open,
/// the celebration card and the sound have already said it, and a banner on top
/// of that is the app talking over itself.
@MainActor
enum StepNotify {
    static let id = "myos.steps.goal"
    static let route = "steps"

    static func goalHit(_ c: StepCelebration) {
        // No frontmost guard on iOS. The pedometer is only ever read from
        // `MainView.refreshFeeds`, which runs from `.task` and on scenePhase
        // `.active` — so the app is by definition frontmost at the instant a
        // goal is detected, and this returned every single time. The banner that
        // the whole feature was designed around ("what reaches you when the app
        // is not open — which is most of the time, since the steps happen while
        // walking") was unreachable code on the only platform with a pedometer.
        // Duplication is already prevented by `hailed`, not by this.
        #if os(macOS)
        guard !AppFocus.isFrontmost else { return }
        #endif
        let n = UNMutableNotificationContent()
        n.title = title(c)
        n.body = body(c)
        n.sound = .default
        n.userInfo = ["route": route]
        UNUserNotificationCenter.current()
            .add(UNNotificationRequest(identifier: "\(id).\(c.day).\(c.level)",
                                       content: n, trigger: nil))
    }

    /// Pure, so the wording is pinned by a test rather than read off a phone.
    static func title(_ c: StepCelebration) -> String {
        c.level >= 2 ? "\(c.steps.formatted()) steps — stretch goal"
                     : "\(c.steps.formatted()) steps — goal hit"
    }

    static func body(_ c: StepCelebration) -> String {
        var line = c.quote
        if let remaining = c.remaining, let next = c.next, remaining > 0 {
            line += " \(remaining.formatted()) to go for \(next.formatted())."
        } else if c.streak > 1 {
            line += " Day \(c.streak) of the streak."
        }
        return line
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

    /// Show it even when meOS is open — the report is generated in-app, so the
    /// moment it lands he is usually looking at something else in the app.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async
    -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    /// Hand the tapped route to the UI.
    ///
    /// This used to `guard route == WeeklyNotify.route` and drop everything
    /// else on the floor — which meant the step-goal banner's `"steps"` route
    /// had never once been acted on, and the five daily reminders carried no
    /// route to act on in the first place.
    ///
    /// Nothing is done here beyond parking the destination. A tap can arrive
    /// before there is any UI at all (a cold launch) and before the vault is
    /// unlocked, so the route waits in `UISignals` until a screen is ready to
    /// take it.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let raw = response.notification.request.content.userInfo["route"] as? String
        guard let route = NotifRoute(rawValue: raw ?? "") else { return }
        await MainActor.run { UISignals.shared.pendingRoute = route }
    }
}
