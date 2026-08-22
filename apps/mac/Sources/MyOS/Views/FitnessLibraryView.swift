import SwiftUI

/// The unified Library — browse every food and every exercise, add custom ones.
/// One place for the "show all / add new" that food and workout used to duplicate.
struct FitnessLibraryView: View {
    enum LibMode: String, Hashable { case foods, workouts }
    @State private var mode: LibMode = .foods

    var body: some View {
        VStack(alignment: .leading, spacing: Gap.screen) {
            Segmented(options: [(LibMode.foods, "Foods"), (LibMode.workouts, "Workouts")], selection: $mode)
                .knRise(0)
            Group {
                if mode == .foods { FoodLibrarySection() } else { WorkoutLibrarySection() }
            }
            .knRise(1)
            .id(mode)
        }
    }
}
