import XCTest
@testable import MyOS

/// Which reminders end up pending, and which get left out when there is not
/// room for all of them.
///
/// All of this is decided before anything touches `UNUserNotificationCenter`,
/// which is the point — a scheduling bug here would otherwise only show up as a
/// birthday that quietly did not arrive.
final class EventNotifierTests: XCTestCase {

    private let today = "2026-08-30"
    private let morning = 8 * 60          // 08:00

    private func event(_ id: String, _ date: String,
                       _ unit: Recurrence.Unit = .none,
                       reminders: [ReminderLead],
                       time: String? = nil,
                       title: String = "Amma's birthday") -> EventItem {
        EventItem(id: id, date: date, title: title, time: time,
                  recurrence: Recurrence(unit: unit), reminders: reminders)
    }

    // MARK: - Which day it fires

    func testAReminderFiresItsLeadBeforeTheEvent() {
        let e = event("a", "2026-09-10", reminders: [.oneWeek])
        let plans = EventNotifier.plan(events: [e], todayKey: today, nowMinutes: morning)
        XCTAssertEqual(plans.count, 1)
        XCTAssertEqual(plans[0].day, "2026-09-03")
        XCTAssertEqual(plans[0].occurrence, "2026-09-10")
    }

    func testEveryChosenLeadGetsItsOwnReminder() {
        let e = event("a", "2026-09-10", reminders: [.sameDay, .oneDay, .oneWeek, .thirtyDays])
        let plans = EventNotifier.plan(events: [e], todayKey: today, nowMinutes: morning)
        // 30 days before 10 Sep is 11 Aug, already past — the rest are ahead.
        XCTAssertEqual(plans.map(\.day), ["2026-09-03", "2026-09-09", "2026-09-10"])
    }

    /// A one-off whose warning has already gone by does not get a late banner.
    func testALeadThatHasAlreadyPassedIsNotScheduledForAOneOff() {
        let e = event("a", "2026-09-01", reminders: [.thirtyDays])
        XCTAssertTrue(EventNotifier.plan(events: [e], todayKey: today, nowMinutes: morning).isEmpty)
    }

    /// But for a repeating event it rolls on to the occurrence after.
    func testALeadThatHasPassedRollsToTheNextOccurrence() {
        let e = event("a", "1965-09-01", .yearly, reminders: [.thirtyDays])
        let plans = EventNotifier.plan(events: [e], todayKey: today, nowMinutes: morning)
        XCTAssertEqual(plans.count, 1)
        // 30 days before 1 Sep 2026 is 2 Aug, gone — so next year's.
        XCTAssertEqual(plans[0].occurrence, "2027-09-01")
        XCTAssertEqual(plans[0].day, "2027-08-02")
    }

    // MARK: - Time of day

    func testAnAllDayEventFiresAtTheDefaultHour() {
        let e = event("a", "2026-09-10", reminders: [.oneDay])
        let plans = EventNotifier.plan(events: [e], todayKey: today, nowMinutes: morning)
        XCTAssertEqual(plans[0].hour, EventNotifier.defaultHour)
        XCTAssertEqual(plans[0].minute, EventNotifier.defaultMinute)
    }

    func testAnEventWithATimeFiresAtThatTime() {
        let e = event("a", "2026-09-10", reminders: [.oneDay], time: "18:30")
        let plans = EventNotifier.plan(events: [e], todayKey: today, nowMinutes: morning)
        XCTAssertEqual(plans[0].hour, 18)
        XCTAssertEqual(plans[0].minute, 30)
    }

    /// The reason `nowMinutes` exists: a 09:00 reminder asked for at 09:05 would
    /// otherwise be handed to the system with a trigger in the past and fire at
    /// once — a "30 days before" banner for something that is already tomorrow.
    func testTodaysReminderIsSkippedOnceItsTimeHasPassed() {
        let e = event("a", "2026-08-31", reminders: [.oneDay])   // fires today at 09:00
        let early = EventNotifier.plan(events: [e], todayKey: today, nowMinutes: 8 * 60)
        XCTAssertEqual(early.count, 1, "08:00 is before 09:00 — still to come")

        let late = EventNotifier.plan(events: [e], todayKey: today, nowMinutes: 9 * 60 + 5)
        XCTAssertTrue(late.isEmpty, "09:05 is past it — a one-off has no next occurrence")
    }

    func testAPassedReminderTodayRollsForwardForARepeatingEvent() {
        let e = event("a", "2020-08-31", .yearly, reminders: [.oneDay])
        let late = EventNotifier.plan(events: [e], todayKey: today, nowMinutes: 9 * 60 + 5)
        XCTAssertEqual(late.first?.occurrence, "2027-08-31")
    }

    func testBadTimeStringsFallBackRatherThanCrash() {
        XCTAssertNil(EventNotifier.minutes(fromTime: "25:00"))
        XCTAssertNil(EventNotifier.minutes(fromTime: "9"))
        XCTAssertNil(EventNotifier.minutes(fromTime: "ab:cd"))
        XCTAssertNil(EventNotifier.minutes(fromTime: nil))
        XCTAssertEqual(EventNotifier.minutes(fromTime: "18:30"), 1110)
        let e = event("a", "2026-09-10", reminders: [.oneDay], time: "99:99")
        XCTAssertEqual(EventNotifier.plan(events: [e], todayKey: today, nowMinutes: morning)[0].hour,
                       EventNotifier.defaultHour)
    }

    // MARK: - Identity

    func testIdentifiersAreStableAndNamespaced() {
        let id = EventNotifier.identifier(eventID: "abc", lead: .thirtyDays)
        XCTAssertEqual(id, "myos.event.abc.thirtyDays")
        XCTAssertTrue(id.hasPrefix(EventNotifier.idPrefix))
    }

    /// Two requests sharing an identifier replace each other, so the same lead
    /// listed twice must not become two plans.
    func testADuplicatedLeadIsOneReminder() {
        let e = event("a", "2026-09-10", reminders: [.oneDay, .oneDay, .oneDay])
        XCTAssertEqual(EventNotifier.plan(events: [e], todayKey: today, nowMinutes: morning).count, 1)
    }

    func testEventsWithNoRemindersScheduleNothing() {
        let e = event("a", "2026-09-10", reminders: [])
        XCTAssertTrue(EventNotifier.plan(events: [e], todayKey: today, nowMinutes: morning).isEmpty)
    }

    // MARK: - The cap

    /// iOS drops pending local notifications past 64 without a word, so the
    /// choice of *which* ones survive has to be ours: the soonest.
    func testThePlanIsTrimmedToTheCapSoonestFirst() {
        let events = (0..<40).map { i in
            event("e\(i)", EventVoice.key(addingDays: 40 + i, to: today),
                  reminders: ReminderLead.ordered, title: "Event \(i)")
        }
        let plans = EventNotifier.plan(events: events, todayKey: today, nowMinutes: morning)
        XCTAssertEqual(plans.count, EventNotifier.limit)
        XCTAssertLessThanOrEqual(plans.count, 64)
        XCTAssertEqual(plans.map(\.fireStamp), plans.map(\.fireStamp).sorted(),
                       "the survivors must be the soonest, not whichever came first")
    }

    func testOverflowReportsWhatDidNotFit() {
        let events = (0..<40).map { i in
            event("e\(i)", EventVoice.key(addingDays: 40 + i, to: today),
                  reminders: ReminderLead.ordered, title: "Event \(i)")
        }
        let dropped = EventNotifier.overflow(events: events, todayKey: today, nowMinutes: morning)
        XCTAssertGreaterThan(dropped, 0)
    }

    func testASmallSetIsNotTrimmed() {
        let e = event("a", "2026-09-10", reminders: [.oneDay, .oneWeek])
        XCTAssertEqual(EventNotifier.plan(events: [e], todayKey: today, nowMinutes: morning).count, 2)
    }

    // MARK: - Wording

    func testTheBodySaysWhenTheThingIsNotHowFarAheadTheReminderIs() {
        let e = event("a", "2026-09-10", reminders: [.oneDay])
        let plan = EventNotifier.plan(events: [e], todayKey: today, nowMinutes: morning)[0]
        XCTAssertEqual(plan.body, "Tomorrow")
        XCTAssertFalse(plan.body.contains("1 day before"))
    }

    func testTheBodyCarriesTheTimeWhenThereIsOne() {
        let e = event("a", "2026-09-10", reminders: [.sameDay], time: "18:30")
        let plan = EventNotifier.plan(events: [e], todayKey: today, nowMinutes: morning)[0]
        XCTAssertEqual(plan.body, "Today at 6:30 pm")
    }

    func testALongLeadNamesTheDate() {
        let e = event("a", "2026-09-30", reminders: [.thirtyDays])
        let plan = EventNotifier.plan(events: [e], todayKey: today, nowMinutes: morning)[0]
        XCTAssertTrue(plan.body.hasPrefix("In 30 days · "), plan.body)
    }

    func testABirthdaySaysWhichOneItIs() {
        let e = event("a", "1965-09-10", .yearly, reminders: [.oneDay])
        let plan = EventNotifier.plan(events: [e], todayKey: today, nowMinutes: morning)[0]
        XCTAssertTrue(plan.body.contains("61st"), plan.body)
    }

    func testClockReadsLikeAPhone() {
        XCTAssertEqual(EventNotifier.clock(0), "12 am")
        XCTAssertEqual(EventNotifier.clock(9 * 60), "9 am")
        XCTAssertEqual(EventNotifier.clock(12 * 60), "12 pm")
        XCTAssertEqual(EventNotifier.clock(13 * 60 + 5), "1:05 pm")
        XCTAssertEqual(EventNotifier.clock(18 * 60 + 30), "6:30 pm")
    }

    func testAnUntitledEventStillHasATitleToShow() {
        let e = event("a", "2026-09-10", reminders: [.oneDay], title: "")
        XCTAssertEqual(EventNotifier.plan(events: [e], todayKey: today, nowMinutes: morning)[0].title,
                       "Event")
    }

    // MARK: - Prefixes must not collide

    /// The two schedulers each clear only their own, so their prefixes must not
    /// overlap — otherwise one would take out the other's, which is the bug this
    /// whole split exists to prevent.
    func testTheTwoSchedulersOwnDisjointNamespaces() {
        XCTAssertFalse(EventNotifier.idPrefix.hasPrefix(ReminderStore.idPrefix))
        XCTAssertFalse(ReminderStore.idPrefix.hasPrefix(EventNotifier.idPrefix))
        let eventID = EventNotifier.identifier(eventID: "x", lead: .sameDay)
        XCTAssertFalse(eventID.hasPrefix(ReminderStore.idPrefix))
        XCTAssertTrue("\(ReminderStore.idPrefix)lunch".hasPrefix(ReminderStore.idPrefix))
        XCTAssertFalse("\(ReminderStore.idPrefix)lunch".hasPrefix(EventNotifier.idPrefix))
    }
}
