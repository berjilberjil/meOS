import Foundation

/// Keeping the system's idea of what is coming up in step with ours.
@MainActor
extension AppState {

    /// Minutes past midnight, right now — what tells the planner that a 09:00
    /// reminder is already behind us at 09:05.
    private var nowMinutes: Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let c = cal.dateComponents([.hour, .minute], from: Date())
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    /// Rebuild every pending event reminder from the current events.
    ///
    /// Called after anything that could change what is due — adding, editing or
    /// deleting an event, restoring one from the bin — and on every foreground,
    /// because only the *next* occurrence of each reminder is ever pending and
    /// the day rolls over whether the app is open or not.
    func rescheduleEventReminders() {
        let store = ReminderStore.shared
        // Rides on the same permission and master switch as the daily reminders.
        // A separate switch would be a second thing to discover and a second way
        // for a birthday to go quietly unannounced.
        let on = store.enabled && store.authorized
        Task { [events, todayKey, nowMinutes] in
            await EventScheduler.reschedule(events: events, todayKey: todayKey,
                                            nowMinutes: nowMinutes,
                                            sound: store.eventSound, enabled: on)
        }
    }
}
