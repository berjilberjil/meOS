import SwiftUI

/// Camera tab — food gets macros; anything else gets a wanted / useful verdict
/// from Catherine, grounded in the user's own data.
struct ScanView: View {
    @EnvironmentObject var state: AppState
    @State private var result: ScanInsight?
    @State private var logged = false
    /// The history record for the scan on screen, so logging the meal marks it.
    @State private var savedID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                ScreenTitle(text: "Scan")
                Text("Food logs itself. Anything else — Catherine tells you if you actually want it.")
                    .font(.callout).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if state.imageBusy {
                readingCard
            } else if let r = result, !r.failed {
                resultCard(r)
                Button("Scan another") { reset() }
                    .buttonStyle(.bordered).controlSize(.large).frame(maxWidth: .infinity)
            } else if let err = state.imageError {
                failCard(err)
            } else {
                cameraHero
            }

            ScanHistoryList()
        }
    }

    private var cameraHero: some View {
        ImageDropZone(
            title: "Take a photo",
            subtitle: "A meal, a pack, or whatever’s in front of you.",
            tint: Palette.teal,
            busy: state.imageBusy,
            startWithCamera: true
        ) { images, media in
            logged = false
            result = nil
            savedID = nil
            state.imageError = nil
            Task {
                let insight = await state.analyzeScan(imagesBase64: images, mediaType: media)
                result = insight
                // Only real reads are worth keeping — a failed one has nothing
                // in it to look back at.
                guard !insight.failed else { return }
                let photo = images.first.flatMap { Data(base64Encoded: $0) }
                savedID = state.saveScan(insight, photo: photo).id
            }
        }
    }

    private var readingCard: some View {
        Card(padding: 28) {
            VStack(spacing: 14) {
                ProgressView().controlSize(.large).tint(Palette.teal)
                Text("Reading…")
                    .font(.title2.weight(.semibold)).foregroundStyle(Palette.text)
                Text("Catherine is looking at the photo.")
                    .font(.subheadline).foregroundStyle(Palette.muted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        }
    }

    private func failCard(_ err: String) -> some View {
        VStack(spacing: 16) {
            Card(padding: 24) {
                VStack(spacing: 12) {
                    Image(systemName: "viewfinder")
                        .font(.largeTitle.weight(.semibold)).foregroundStyle(Palette.amber)
                    Text("Couldn’t read that")
                        .font(.title2.weight(.semibold)).foregroundStyle(Palette.text)
                    Text(err)
                        .font(.subheadline).foregroundStyle(Palette.muted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            Button("Try again") { reset() }
                .buttonStyle(.borderedProminent).tint(Palette.teal).controlSize(.large).frame(maxWidth: .infinity)
        }
    }

    private func reset() {
        result = nil
        logged = false
        savedID = nil
        state.imageError = nil
    }

    @ViewBuilder
    private func resultCard(_ r: ScanInsight) -> some View {
        Card(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                ScanVerdictView(insight: r)
                if r.kind == .food {
                    Button(logged ? "Logged" : "Log this meal") { logFoods(r) }
                        .buttonStyle(.borderedProminent)
                        .disabled(logged || r.foods.isEmpty)
                }
            }
        }
    }

    private func logFoods(_ r: ScanInsight) {
        for f in r.foods {
            let food = state.addFood(Food(name: f.name, category: .other,
                                          servingLabel: f.serving,
                                          perServing: Macros(calories: f.calories, protein: f.protein,
                                                             carbs: f.carbs, fiber: 0, fats: f.fats),
                                          vitamins: f.detail.isEmpty ? nil : f.detail))
            state.addFoodToMeal(date: state.todayKey, meal: .snacks, foodId: food.id)
        }
        logged = true
        if let id = savedID { state.markScanLogged(id) }
    }
}
