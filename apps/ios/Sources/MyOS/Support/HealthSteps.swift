#if os(iOS)
import Foundation
import CoreMotion

/// Today's steps from the iPhone motion coprocessor (same sensor Apple Fitness
/// uses on-device). HealthKit/Watch totals need a HealthKit capability on the
/// App ID — until that's on the profile, this is the live feed.
enum HealthSteps {
    private static let pedometer = CMPedometer()

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
}
#endif
