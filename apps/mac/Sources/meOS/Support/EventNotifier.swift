import Foundation
import UserNotifications

/// One reminder meOS intends the system to deliver.
///
/// A value type rather than a `UNNotificationRequest` so the deciding — which
/// occurrence, how far ahead, what it says, and which ones get dropped when
/// there is not room for all of them — is testable without a device and without
/// asking anyone for notification permission.
struct EventReminderPlan: Equatable, Hashable, Sendable {
    let id: String
    let eventID: String
    let lead: ReminderLead
    let title: String
    let body: String
    /// The `yyyy-MM-dd` the banner appears on.
    let day: String
    let hour: Int
    let minute: Int
    /// The event day it is warning about.
    let occurrence: String

    /// Sortable to the minute — how the soonest ones are chosen.
    var fireStamp: String { String(format: "%@T%02d:%02d", day, hour, minute) }
}

/// Works out which event reminders should be pending right now.
///
/// The hard constraint driving the design: **iOS delivers at most 64 pending
/// local notifications per app**, and anything past that is silently dropped.
/// A single yearly birthday with all seven leads set is seven of them; thirty
/// birthdays would be two hundred and ten, and the ones that got scheduled
/// would be whichever happened to be added first — not the soonest.
///
/// So only the *next* fire per (event, lead) is ever scheduled, the set is
/// sorted by when it fires and trimmed, and the whole thing is rebuilt every
/// time the app comes to the front. A reminder a year out does not need to be
/// pending today; it needs to be pending by the time it is due.
enum EventNotifier {
    /// Every event reminder id starts with this, which is how the reschedule
    /// knows what is its to remove.
    static let idPrefix = "myos.event."

    /// Under iOS's 64, with headroom for the five daily reminders and the
    /// one-off banners (focus timer, step goal, weekly report).
    static let limit = 48

    /// When an all-day event's reminders fire. Nine in the morning is early
    /// enough to act on and late enough not to be the thing that wakes you.
    static let defaultHour = 9
    static let defaultMinute = 0

    static func identifier(eventID: String, lead: ReminderLead) -> String {
        "\(idPrefix)\(eventID).\(lead.rawValue)"
    }

    /// `HH:mm` → minutes past midnight. `nil` for anything that is not a time.
    static func minutes(fromTime time: String?) -> Int? {
        guard let time else { return nil }
        let f = time.split(separator: ":")
        guard f.count == 2, let h = Int(f[0]), let m = Int(f[1]),
              (0...23).contains(h), (0...59).contains(m) else { return nil }
        return h * 60 + m
    }

    /// The time of day this event's reminders fire at.
    static func fireTime(_ event: EventItem) -> (hour: Int, minute: Int) {
        guard let mins = minutes(fromTime: event.time) else { return (defaultHour, defaultMinute) }
        return (mins / 60, mins % 60)
    }

    /// What should be pending, soonest first.
    ///
    /// - Parameters:
    ///   - nowMinutes: minutes past midnight on `todayKey`. A reminder due at
    ///     09:00 is not scheduled at 09:05 — the system would fire it instantly,
    ///     which is how you get a "30 days before" banner for something that is
    ///     already tomorrow.
    static func plan(events: [EventItem],
                     todayKey: String,
                     nowMinutes: Int,
                     limit: Int = limit) -> [EventReminderPlan] {
        var out: [EventReminderPlan] = []

        for event in events {
            guard !event.reminders.isEmpty, !event.title.isEmpty || !event.date.isEmpty else { continue }
            let (hour, minute) = fireTime(event)
            let fireMinutes = hour * 60 + minute

            // De-duplicated: the same lead twice is one reminder, and two
            // requests sharing an identifier would silently replace each other.
            for lead in Set(event.reminders).sorted(by: { $0.days < $1.days }) {
                // The soonest occurrence far enough out that its warning has not
                // already passed. Two tries is enough — occurrences only ever
                // increase, so if the first one's warning is behind us the next
                // one's cannot also be.
                var probe = EventVoice.key(addingDays: lead.days, to: todayKey)
                for _ in 0..<2 {
                    guard let occurrence = EventRecurrence.next(event, onOrAfter: probe) else { break }
                    let day = EventVoice.key(addingDays: -lead.days, to: occurrence)
                    let inFuture = day > todayKey || (day == todayKey && fireMinutes > nowMinutes)
                    if inFuture {
                        out.append(EventReminderPlan(
                            id: identifier(eventID: event.id, lead: lead),
                            eventID: event.id,
                            lead: lead,
                            title: title(event),
                            body: body(event, lead: lead, occurrence: occurrence),
                            day: day, hour: hour, minute: minute,
                            occurrence: occurrence))
                        break
                    }
                    probe = EventVoice.key(addingDays: 1, to: occurrence)
                }
            }
        }

        out.sort { $0.fireStamp == $1.fireStamp ? $0.id < $1.id : $0.fireStamp < $1.fireStamp }
        return Array(out.prefix(limit))
    }

    /// How many were dropped for want of room — worth logging rather than
    /// letting the system quietly deliver a subset.
    static func overflow(events: [EventItem], todayKey: String, nowMinutes: Int) -> Int {
        let all = plan(events: events, todayKey: todayKey, nowMinutes: nowMinutes, limit: .max)
        return max(0, all.count - limit)
    }

    // MARK: - Wording

    static func title(_ event: EventItem) -> String {
        let t = event.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "Event" : t
    }

    /// "tomorrow at 6:30 pm", "in 30 days · 12 Mar", "today · 61st".
    ///
    /// The lead is not repeated back at you — a banner saying "30 days before"
    /// makes you do the arithmetic. It says when the thing is.
    static func body(_ event: EventItem, lead: ReminderLead, occurrence: String) -> String {
        let day = EventVoice.key(addingDays: -lead.days, to: occurrence)
        var parts: [String] = []

        let phrase = EventVoice.relativePhrase(from: day, to: occurrence)
        if let mins = minutes(fromTime: event.time) {
            parts.append("\(phrase.capitalizedFirst) at \(clock(mins))")
        } else {
            parts.append(phrase.capitalizedFirst)
        }

        if lead.days > 1 { parts.append(Fmt.day(occurrence)) }

        if let n = EventRecurrence.ordinal(event, on: occurrence) {
            parts.append(EventRecurrence.ordinalLabel(n))
        }
        return parts.joined(separator: " · ")
    }

    /// 12-hour clock, the way a phone shows it.
    static func clock(_ minutesPastMidnight: Int) -> String {
        let h24 = minutesPastMidnight / 60, m = minutesPastMidnight % 60
        let suffix = h24 < 12 ? "am" : "pm"
        var h = h24 % 12
        if h == 0 { h = 12 }
        return m == 0 ? "\(h) \(suffix)" : String(format: "%d:%02d %@", h, m, suffix)
    }
}

private extension String {
    var capitalizedFirst: String {
        guard let f = first else { return self }
        return f.uppercased() + dropFirst()
    }
}

// MARK: - Actually scheduling them

/// Puts the plan in front of the system, and takes back whatever it replaced.
@MainActor
enum EventScheduler {

    /// Replace every pending event reminder with the current plan.
    ///
    /// Only ids under `EventNotifier.idPrefix` are removed. `ReminderStore` used
    /// to call `removeAllPendingNotificationRequests()` on every change to a
    /// daily reminder, which would have wiped every event reminder in the app
    /// each time a meal time was nudged by a minute — a bug that would only have
    /// shown up as birthdays quietly not arriving.
    static func reschedule(events: [EventItem],
                           todayKey: String,
                           nowMinutes: Int,
                           sound: ReminderSound,
                           enabled: Bool) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix(EventNotifier.idPrefix) }
        if !ours.isEmpty { center.removePendingNotificationRequests(withIdentifiers: ours) }

        guard enabled else { return }

        let plans = EventNotifier.plan(events: events, todayKey: todayKey, nowMinutes: nowMinutes)
        for plan in plans {
            guard let parts = EventRecurrence.parts(plan.day) else { continue }
            let content = UNMutableNotificationContent()
            content.title = plan.title
            content.body = plan.body
            content.sound = sound.notificationSound
            content.userInfo = ["route": NotifRoute.events.rawValue, "event": plan.eventID]

            var comps = DateComponents()
            comps.year = parts.y; comps.month = parts.m; comps.day = parts.d
            comps.hour = plan.hour; comps.minute = plan.minute
            // Not repeating: the *next* occurrence is scheduled each time the app
            // comes to the front. A repeating trigger cannot express "every year
            // on the 29th of February, except the 28th when there isn't one".
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: plan.id,
                                                        content: content, trigger: trigger))
        }

        let dropped = EventNotifier.overflow(events: events, todayKey: todayKey, nowMinutes: nowMinutes)
        if dropped > 0 {
            Log.sync.notice("event reminders: scheduled \(plans.count, privacy: .public), \(dropped, privacy: .public) beyond the cap will be picked up as they come closer")
        }
    }
}
