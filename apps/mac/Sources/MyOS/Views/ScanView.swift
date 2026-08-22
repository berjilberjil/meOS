import SwiftUI

/// Camera tab — food gets macros; anything else gets a wanted / useful verdict
/// from Catherine, grounded in the user's own data.
struct ScanView: View {
    @EnvironmentObject var state: AppState
    @State private var result: ScanInsight?
    @State private var logged = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                ScreenTitle(text: "Scan")
                Text("Food logs itself. Anything else — Catherine tells you if you actually want it.")
                    .font(.system(size: 16)).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if state.imageBusy {
                readingCard
            } else if let r = result, !r.failed {
                resultCard(r)
                Button("Scan another") { reset() }
                    .buttonStyle(KSecondaryButtonStyle(fullWidth: true))
            } else if let err = state.imageError {
                failCard(err)
            } else {
                cameraHero
            }
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
            state.imageError = nil
            Task { result = await state.analyzeScan(imagesBase64: images, mediaType: media) }
        }
    }

    private var readingCard: some View {
        Card(padding: 28) {
            VStack(spacing: 14) {
                ProgressView().controlSize(.large).tint(Palette.teal)
                Text("Reading…")
                    .font(.system(size: 22, weight: .semibold)).foregroundStyle(Palette.text)
                Text("Catherine is looking at the photo.")
                    .font(.system(size: 15)).foregroundStyle(Palette.muted)
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
                        .font(.system(size: 32, weight: .semibold)).foregroundStyle(Palette.amber)
                    Text("Couldn’t read that")
                        .font(.system(size: 22, weight: .semibold)).foregroundStyle(Palette.text)
                    Text(err)
                        .font(.system(size: 15)).foregroundStyle(Palette.muted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            Button("Try again") { reset() }
                .buttonStyle(KPrimaryButtonStyle(tint: Palette.teal, fullWidth: true))
        }
    }

    private func reset() {
        result = nil
        logged = false
        state.imageError = nil
    }

    @ViewBuilder
    private func resultCard(_ r: ScanInsight) -> some View {
        Card(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                if r.kind == .food {
                    foodCard(r)
                } else if let o = r.object {
                    objectCard(o, summary: r.summary)
                }
            }
        }
    }

    @ViewBuilder
    private func foodCard(_ r: ScanInsight) -> some View {
        Text("FOOD").font(.system(size: 12, weight: .heavy, design: .rounded)).tracking(0.8).foregroundStyle(Palette.green)
        Text(r.summary).font(.system(size: 18, weight: .semibold)).foregroundStyle(Palette.text)
        ForEach(r.foods, id: \.name) { f in
            VStack(alignment: .leading, spacing: 8) {
                Text(f.name).font(.system(size: 17, weight: .semibold))
                Text(f.serving).font(.system(size: 13)).foregroundStyle(Palette.muted)
                HStack {
                    macro("\(Int(f.calories))", "kcal")
                    macro("\(Int(f.protein))g", "protein")
                    macro("\(Int(f.carbs))g", "carbs")
                    macro("\(Int(f.fats))g", "fat")
                }
            }
        }
        Button(logged ? "Logged" : "Log this meal") { logFoods(r) }
            .buttonStyle(KPrimaryButtonStyle())
            .disabled(logged || r.foods.isEmpty)
    }

    @ViewBuilder
    private func objectCard(_ o: ScanInsight.Object, summary: String) -> some View {
        Text(wantedLabel(o.needed).uppercased())
            .font(.system(size: 12, weight: .heavy, design: .rounded)).tracking(0.7)
            .foregroundStyle(wantedColor(o.needed))
        Text(o.name)
            .font(.system(size: 24, weight: .semibold)).foregroundStyle(Palette.text)
        if !summary.isEmpty, summary != o.name {
            Text(summary).font(.system(size: 15)).foregroundStyle(Palette.muted)
        }

        VStack(alignment: .leading, spacing: 6) {
            Text("WANTED FOR YOU")
                .font(.system(size: 11, weight: .heavy, design: .rounded)).tracking(0.6)
                .foregroundStyle(Palette.faint)
            Text(wantedBlurb(o.needed))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(wantedColor(o.needed))
        }

        if !o.why.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("WHY")
                    .font(.system(size: 11, weight: .heavy, design: .rounded)).tracking(0.6)
                    .foregroundStyle(Palette.faint)
                Text(o.why).font(.system(size: 16)).foregroundStyle(Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        if !o.useful.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(o.needed == .no ? "DO THIS INSTEAD" : "HOW IT HELPS")
                    .font(.system(size: 11, weight: .heavy, design: .rounded)).tracking(0.6)
                    .foregroundStyle(Palette.faint)
                Text(o.useful).font(.system(size: 16)).foregroundStyle(Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func wantedLabel(_ n: ScanInsight.Needed) -> String {
        switch n {
        case .yes: return "Wanted"
        case .no: return "Not wanted"
        case .maybe: return "Maybe useful"
        }
    }
    private func wantedBlurb(_ n: ScanInsight.Needed) -> String {
        switch n {
        case .yes: return "Yes — this fits your life."
        case .no: return "No — skip it."
        case .maybe: return "Only if you actually use it."
        }
    }
    private func wantedColor(_ n: ScanInsight.Needed) -> Color {
        switch n {
        case .yes: return Palette.green
        case .no: return Palette.red
        case .maybe: return Palette.amber
        }
    }

    private func macro(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 15, weight: .semibold)).monospacedDigit()
            Text(label).font(.system(size: 10)).foregroundStyle(Palette.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Palette.surface2, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
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
    }
}
