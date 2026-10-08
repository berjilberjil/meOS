#if os(iOS)
import Foundation
import CoreMotion

/// Today's steps from the iPhone motion coprocessor (same sensor Apple Fitness
/// uses on-device). HealthKit/Watch totals need a HealthKit capability on the
/// App ID — until that's on the profile, this is the live feed.
enum HealthSteps {
    private static let pedometer = CMPedometer()

    /// True once a read was refused because Motion & Fitness is off for meOS.
    /// The Steps card reads this so a refusal never renders as a zero.
    @MainActor private(set) static var accessDenied = false

    @MainActor
    static func syncToday(into state: AppState) async {
        guard CMPedometer.isStepCountingAvailable() else { return }
        let start = Calendar.current.startOfDay(for: Date())
        let n: Int? = await withCheckedContinuation { cont in
            pedometer.queryPedometerData(from: start, to: Date()) { data, _ in
                cont.resume(returning: data?.numberOfSteps.intValue)
            }
        }
        guard let n else { return }
        if state.fitnessDay(state.todayKey).steps != n {
            state.setTodaySteps(n)
        }
    }

    /// Backfill the recent past so the Activity calendar has a record to show.
    /// CoreMotion keeps roughly the last seven days on device — beyond that the
    /// query returns nothing, which is why this doesn't reach further back.
    ///
    /// Only days with no count yet are filled; today is always refreshed.
    @MainActor
    static func syncRecent(into state: AppState, days: Int = 7) async {
        guard CMPedometer.isStepCountingAvailable() else { return }
        // A refusal is not a zero. Only availability was ever checked, so
        // declining the Motion & Fitness prompt — or switching it off later —
        // was indistinguishable from a week of not walking: every screen showed
        // 0 steps, the streak sat at 0 forever, and nothing anywhere said the
        // app had been told it may not look.
        let status = CMPedometer.authorizationStatus()
        accessDenied = status == .denied || status == .restricted
        guard !accessDenied else { return }
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: Date())
        var found: [String: Int] = [:]
        for back in 0..<max(1, days) {
            guard let dayStart = cal.date(byAdding: .day, value: -back, to: startOfToday) else { continue }
            let nextDay = cal.date(byAdding: .day, value: 1, to: dayStart) ?? Date()
            let dayEnd = min(Date(), nextDay)
            guard dayEnd > dayStart else { continue }
            let n: Int? = await withCheckedContinuation { cont in
                pedometer.queryPedometerData(from: dayStart, to: dayEnd) { data, _ in
                    cont.resume(returning: data?.numberOfSteps.intValue)
                }
            }
            if let n, n > 0 { found[AppState.dateKey(dayStart)] = n }
        }
        guard !found.isEmpty else { return }
        state.mergeSteps(found, authoritative: state.todayKey)
    }
}
#endif
