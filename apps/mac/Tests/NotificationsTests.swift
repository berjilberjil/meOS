import XCTest
@testable import meOS

final class NotificationsTests: XCTestCase {
    func testDefaultsHaveTheFiveReminders() {
        let all = ReminderDefaults.all()
        XCTAssertEqual(all.map(\.id), ["wake", "breakfast", "lunch", "workout", "dinner"])
        let lunch = all.first { $0.id == "lunch" }
        XCTAssertEqual(lunch?.hour, 12); XCTAssertEqual(lunch?.minute, 30)
        let wake = all.first { $0.id == "wake" }
        XCTAssertEqual(wake?.hour, 6); XCTAssertEqual(wake?.minute, 0)
    }

    func testMergedHonorsSavedTimeAndEnabledDropsUnknownRestoresLabels() {
        let saved = [
            Reminder(id: "lunch", label: "old", body: "old", hour: 13, minute: 15, enabled: false),
            Reminder(id: "ghost", label: "x", body: "x", hour: 1, minute: 1, enabled: true)
        ]
        let merged = ReminderDefaults.merged(saved: saved)
        XCTAssertEqual(merged.count, 5)                          // all defaults kept, ghost dropped
        let lunch = merged.first { $0.id == "lunch" }!
        XCTAssertEqual(lunch.hour, 13); XCTAssertEqual(lunch.minute, 15)  // saved time honored
        XCTAssertFalse(lunch.enabled)                            // saved enabled honored
        XCTAssertEqual(lunch.label, "Lunch")                    // canonical label restored
        XCTAssertFalse(merged.contains { $0.id == "ghost" })
    }

    // MARK: - Where a tap lands

    /// Every reminder meOS sends knows where it goes. Before this, none of them
    /// carried a route at all and the router dropped anything that was not the
    /// Friday report — so five notifications a day opened the app on whatever
    /// screen it happened to be left on.
    func testEveryReminderKnowsWhereItGoes() {
        XCTAssertEqual(NotifRoute.forReminder("wake"), .weight)
        XCTAssertEqual(NotifRoute.forReminder("breakfast"), .breakfast)
        XCTAssertEqual(NotifRoute.forReminder("lunch"), .lunch)
        XCTAssertEqual(NotifRoute.forReminder("dinner"), .dinner)
        XCTAssertEqual(NotifRoute.forReminder("workout"), .workout)
    }

    func testNoReminderIsLeftWithoutADestination() {
        for r in ReminderDefaults.all() {
            XCTAssertNotNil(NotifRoute(rawValue: NotifRoute.forReminder(r.id).rawValue),
                            "\(r.id) must route somewhere")
        }
    }

    /// The wake reminder's own words are "Log your weight" — so it opens on the
    /// dial, not on the top of a page you then have to scroll.
    func testTheWakeReminderOpensOnTheWeightDial() {
        let wake = ReminderDefaults.all().first { $0.id == "wake" }!
        XCTAssertTrue(wake.body.lowercased().contains("weight"))
        XCTAssertEqual(NotifRoute.forReminder(wake.id), .weight)
    }

    func testAnUnknownReminderFallsBackToTodayRatherThanNowhere() {
        XCTAssertEqual(NotifRoute.forReminder("something-new"), .today)
    }

    func testMealRoutesCarryTheMealTheyOpen() {
        XCTAssertEqual(NotifRoute.breakfast.meal, .breakfast)
        XCTAssertEqual(NotifRoute.lunch.meal, .lunch)
        XCTAssertEqual(NotifRoute.dinner.meal, .dinner)
        XCTAssertNil(NotifRoute.workout.meal)
        XCTAssertNil(NotifRoute.weight.meal)
    }

    /// The raw values travel in `userInfo`, so they are a wire format: a
    /// notification scheduled by yesterday's build is still sitting in the
    /// system waiting to fire against today's.
    ///
    /// Adding a name is safe — an old build simply cannot parse it and drops the
    /// route, which is the same as the no-route behaviour it already had.
    /// Renaming or removing one strands every notification already scheduled
    /// under it, which is what this pins.
    func testRouteNamesAreTheWireFormatAndDoNotChange() {
        let established: Set<String> = ["today", "weight", "breakfast", "lunch",
                                        "dinner", "workout", "steps", "weekly"]
        let current = Set(NotifRoute.allCases.map(\.rawValue))
        XCTAssertTrue(established.isSubset(of: current),
                      "missing: \(established.subtracting(current)) — those are already in flight")
        // And the one added since, so this keeps being an exact list.
        XCTAssertEqual(current, established.union(["events"]))
    }

    /// The two notifications that already set a route by hand have to keep
    /// naming something the router can parse.
    func testTheStepAndWeeklyBannersUseRealRoutes() {
        XCTAssertEqual(NotifRoute(rawValue: StepNotify.route), .steps)
        XCTAssertEqual(NotifRoute(rawValue: WeeklyNotify.route), .weekly)
    }

    /// A section the route names has to exist on Today, or the page scrolls to
    /// an anchor nothing is tagged with and the tap silently does nothing.
    func testTheSectionsRoutesScrollToAreRealSections() {
        XCTAssertNotNil(TodaySection(rawValue: TodaySection.weight.rawValue))
        XCTAssertNotNil(TodaySection(rawValue: TodaySection.activity.rawValue))
    }
}
