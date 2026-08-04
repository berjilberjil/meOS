import SwiftUI

/// Today's eating — macros vs targets, meals with foods, add from the library or a
/// custom food, and a weekly meal plan. Lives inside the Fitness tab's "Food" sub.
struct FoodView: View {
    @EnvironmentObject var state: AppState
    @State private var addingTo: MealKey?
    @State private var editingFood: Food?
    @State private var newFood = false
    @State private var showPlan = false

    private var key: String { state.todayKey }
    private var log: MealLog { state.mealLog(key) }
    private var consumed: Macros { state.consumed(key) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            totalsCard.knRise(0)

            ForEach(Array(MealKey.allCases.enumerated()), id: \.element) { idx, meal in
                mealCard(meal).knRise(idx + 1)
            }

            HStack(spacing: 10) {
                Button { showPlan = true } label: { Label("Weekly meal plan", systemImage: "calendar") }
                    .buttonStyle(KSecondaryButtonStyle())
                Button { newFood = true } label: { Label("New food", systemImage: "plus") }
                    .buttonStyle(KGhostButtonStyle())
            }
            .knRise(6)
        }
        .sheet(item: $addingTo) { meal in
            FoodPickerSheet(meal: meal) { food, qty in
                state.addFoodToMeal(date: key, meal: meal, foodId: food.id, quantity: qty)
            } newCustom: { newFood = true }
        }
        .sheet(isPresented: $newFood) { FoodEditor(food: nil) }
        .sheet(item: $editingFood) { f in FoodEditor(food: f) }
        .sheet(isPresented: $showPlan) { MealPlanSheet() }
    }

    // MARK: - Totals vs targets

    private var totalsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    SectionTitle(text: "Today's macros")
                    Spacer()
                    if state.mealLog(key).meals.isEmpty, !state.mealPlan(state.todayWeekday).isEmpty {
                        Button { state.applyMealPlanToToday() } label: {
                            Label("Use my plan", systemImage: "wand.and.stars")
                        }
                        .buttonStyle(KGhostButtonStyle())
                    }
                }
                let t = targets
                HStack(spacing: 10) {
                    macroMeter("Calories", consumed.calories, t?.calories, "kcal", Palette.amber)
                    macroMeter("Protein", consumed.protein, t?.protein, "g", Palette.green)
                    macroMeter("Carbs", consumed.carbs, t?.carbs, "g", Palette.blue)
                    macroMeter("Fat", consumed.fats, t?.fats, "g", Palette.red)
                }
            }
        }
    }

    /// Macro targets from the computed calorie picture (falls back to protein/cal on the profile).
    private var targets: Macros? {
        if let c = state.calorieTargets() {
            return Macros(calories: Double(c.goalCalories), protein: Double(c.proteinG),
                          carbs: Double(c.carbG), fiber: 30, fats: Double(c.fatG))
        }
        if let cal = state.fitnessProfile.calorieTargetKcal {
            return Macros(calories: cal, protein: state.fitnessProfile.proteinTargetG ?? 0, carbs: 0, fiber: 0, fats: 0)
        }
        return nil
    }

    private func macroMeter(_ label: String, _ have: Double, _ target: Double?, _ unit: String, _ tint: Color) -> some View {
        VStack(spacing: 6) {
            Text("\(Int(have.rounded()))")
                .font(.system(size: 20, weight: .heavy, design: .rounded)).monospacedDigit()
                .foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.6)
            if let target, target > 0 {
                MeterBar(fraction: min(1, have / target), tint: tint, height: 6)
                Text("of \(Int(target)) \(unit)").font(.system(size: 9)).foregroundStyle(Palette.faint)
            } else {
                Text(unit).font(.system(size: 9)).foregroundStyle(Palette.faint)
            }
            Text(label.uppercased()).font(.system(size: 8, weight: .heavy, design: .rounded)).tracking(0.5)
                .foregroundStyle(Palette.faint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - A meal

    private func mealCard(_ meal: MealKey) -> some View {
        let items = log.items(meal)
        let mealMacros = items.reduce(Macros.zero) { acc, item in
            acc + (state.food(item.foodId)?.perServing.scaled(item.quantity) ?? .zero)
        }
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(meal.label, systemImage: meal.icon)
                        .font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundStyle(Palette.text)
                    Spacer()
                    if !items.isEmpty {
                        Text("\(Int(mealMacros.calories)) kcal · \(Int(mealMacros.protein))g P")
                            .font(.system(size: 11, weight: .semibold)).monospacedDigit().foregroundStyle(Palette.muted)
                    }
                }
                if items.isEmpty {
                    Text("Nothing logged.").font(.system(size: 12)).foregroundStyle(Palette.faint)
                }
                ForEach(items) { item in foodRow(meal: meal, item: item) }
                Button { addingTo = meal } label: { Label("Add food", systemImage: "plus.circle.fill") }
                    .buttonStyle(KGhostButtonStyle(color: Palette.brand))
            }
        }
    }

    private func foodRow(meal: MealKey, item: PlanItem) -> some View {
        let food = state.food(item.foodId)
        let m = food?.perServing.scaled(item.quantity) ?? .zero
        return HStack(spacing: 10) {
            FoodIcon(category: food?.category ?? .other, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(food?.name ?? "Unknown").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.text).lineLimit(1)
                Text("\(Fmt.trimKg(item.quantity)) × \(food?.servingLabel ?? "") · \(Int(m.calories)) kcal")
                    .font(.system(size: 11)).foregroundStyle(Palette.faint).lineLimit(1)
            }
            Spacer()
            HStack(spacing: 4) {
                qtyBtn("minus") { state.setMealItemQty(date: key, meal: meal, itemId: item.id, quantity: item.quantity - 0.5) }
                Text(Fmt.trimKg(item.quantity)).font(.system(size: 12, weight: .bold)).monospacedDigit()
                    .foregroundStyle(Palette.text).frame(minWidth: 26)
                qtyBtn("plus") { state.setMealItemQty(date: key, meal: meal, itemId: item.id, quantity: item.quantity + 0.5) }
            }
            Button { state.removeMealItem(date: key, meal: meal, itemId: item.id) } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(KIconButtonStyle(size: 22))
        }
    }

    private func qtyBtn(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.text)
                .frame(width: 24, height: 22)
                .background(Palette.surface2, in: RoundedRectangle(cornerRadius: Radius.xs, style: .continuous))
        }
        .buttonStyle(KPressStyle(scale: 0.9))
    }
}

// MARK: - Category icon (no emoji — SF Symbol per category)

struct FoodIcon: View {
    let category: FoodCategory
    var size: CGFloat = 30
    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size * 0.42, weight: .bold)).foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
    }
    private var icon: String {
        switch category {
        case .protein: return "fish.fill"
        case .carb: return "birthday.cake.fill"
        case .veg: return "leaf.fill"
        case .dairy: return "drop.fill"
        case .fruit: return "applelogo"
        case .drink: return "cup.and.saucer.fill"
        case .junk: return "takeoutbag.and.cup.and.straw.fill"
        case .other: return "circle.grid.2x2.fill"
        }
    }
    private var color: Color {
        switch category {
        case .protein: return Palette.red
        case .carb: return Palette.amber
        case .veg: return Palette.green
        case .dairy: return Palette.blue
        case .fruit: return Palette.purple
        case .drink: return Palette.blue
        case .junk: return Palette.flame
        case .other: return Palette.muted
        }
    }
}

// MARK: - Food picker

struct FoodPickerSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let meal: MealKey
    let add: (Food, Double) -> Void
    let newCustom: () -> Void
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private var results: [Food] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let all = state.allFoods
        return q.isEmpty ? all : all.filter { $0.name.lowercased().contains(q) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Add to \(meal.label)").font(.system(size: 17, weight: .heavy, design: .rounded)).foregroundStyle(Palette.text)
                Spacer()
                Button { dismiss(); newCustom() } label: { Label("New food", systemImage: "plus") }
                    .buttonStyle(KGhostButtonStyle())
            }
            .padding(16)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Palette.faint)
                TextField("", text: $query, prompt: Text("Search foods…").foregroundColor(Palette.faint))
                    .textFieldStyle(.plain).foregroundStyle(Palette.text).focused($searchFocused)
            }
            .knField(focused: searchFocused).padding(.horizontal, 16)
            Divider().overlay(Palette.border).padding(.top, 12)
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(results) { f in
                        Button { add(f, 1); dismiss() } label: {
                            HStack(spacing: 10) {
                                FoodIcon(category: f.category, size: 30)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(f.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.text)
                                    Text("\(f.servingLabel) · \(Int(f.perServing.calories)) kcal · \(Int(f.perServing.protein))g P")
                                        .font(.system(size: 11)).foregroundStyle(Palette.faint)
                                }
                                Spacer()
                                if !f.isDefault {
                                    Text("CUSTOM").font(.system(size: 8, weight: .heavy)).foregroundStyle(Palette.brand)
                                }
                                Image(systemName: "plus.circle.fill").font(.system(size: 16)).foregroundStyle(Palette.brand)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(KPressStyle())
                        .onHover { h in cursor(h) }
                    }
                }
                .padding(16)
            }
            .frame(maxHeight: 420)
        }
        .frame(width: 460)
        .background(Palette.elevated)
    }
}

// MARK: - Custom food editor

struct FoodEditor: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let food: Food?
    @State private var draft: Food

    init(food: Food?) {
        self.food = food
        _draft = State(initialValue: food ?? Food(name: "", category: .other, servingLabel: "1 serving", perServing: .zero))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(food == nil ? "New food" : "Edit food")
                .font(.system(size: 18, weight: .heavy, design: .rounded)).foregroundStyle(Palette.text)
            KLabeledField(label: "Name", placeholder: "e.g. Grilled chicken", text: $draft.name)
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    KFieldLabel(text: "Category")
                    Menu {
                        ForEach(FoodCategory.allCases, id: \.self) { c in
                            Button(c.label) { draft.category = c }
                        }
                    } label: {
                        HStack { Text(draft.category.label).foregroundStyle(Palette.text)
                            Spacer(); Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(Palette.faint) }
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 13).padding(.vertical, 10)
                        .background(Palette.bg, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Palette.border, lineWidth: 2))
                    }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden)
                }
                KLabeledField(label: "Serving", placeholder: "1 cup / 100 g", text: $draft.servingLabel)
            }
            KFieldLabel(text: "Macros per serving")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
                macroField("Calories", \.calories)
                macroField("Protein (g)", \.protein)
                macroField("Carbs (g)", \.carbs)
                macroField("Fiber (g)", \.fiber)
                macroField("Fat (g)", \.fats)
            }
            HStack {
                if let food, !food.isDefault {
                    Button("Delete", role: .destructive) { state.deleteFood(food.id); dismiss() }
                        .buttonStyle(KGhostButtonStyle(color: Palette.red))
                }
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(KGhostButtonStyle())
                Button("Save") {
                    if food == nil { state.addFood(draft) } else { state.updateFood(draft) }
                    dismiss()
                }
                .buttonStyle(KPrimaryButtonStyle())
                .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24).frame(width: 480)
        .background(Palette.elevated)
    }

    private func macroField(_ label: String, _ kp: WritableKeyPath<Macros, Double>) -> some View {
        KLabeledNumberField(label: label, placeholder: "0", decimals: 1,
                            value: Binding(get: { draft.perServing[keyPath: kp] },
                                           set: { draft.perServing[keyPath: kp] = $0 ?? 0 }))
    }
}

// MARK: - Weekly meal plan

struct MealPlanSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var weekday: String = ""
    @State private var addingTo: MealKey?

    private let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Weekly meal plan").font(.system(size: 18, weight: .heavy, design: .rounded)).foregroundStyle(Palette.text)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 13, weight: .bold)) }
                    .buttonStyle(KIconButtonStyle(size: 28))
            }
            .padding(16)
            Segmented(options: (0..<7).map { (String($0), dayNames[$0]) }, selection: $weekday)
                .padding(.horizontal, 16)
            Divider().overlay(Palette.border).padding(.top, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(MealKey.allCases, id: \.self) { meal in mealSection(meal) }
                }
                .padding(16)
            }
            .frame(maxHeight: 460)
        }
        .frame(width: 520)
        .background(Palette.elevated)
        .onAppear { if weekday.isEmpty { weekday = state.todayWeekday } }
        .sheet(item: $addingTo) { meal in
            FoodPickerSheet(meal: meal, add: { food, qty in
                state.addFoodToPlan(weekday: weekday, meal: meal, foodId: food.id, quantity: qty)
            }, newCustom: {})
        }
    }

    private func mealSection(_ meal: MealKey) -> some View {
        let items = state.planItems(weekday, meal)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(meal.label, systemImage: meal.icon)
                    .font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundStyle(Palette.text)
                Spacer()
                Button { addingTo = meal } label: { Image(systemName: "plus").font(.system(size: 12, weight: .bold)) }
                    .buttonStyle(KIconButtonStyle(size: 24))
            }
            if items.isEmpty {
                Text("No foods planned.").font(.system(size: 12)).foregroundStyle(Palette.faint)
            }
            ForEach(items) { item in
                HStack(spacing: 10) {
                    FoodIcon(category: state.food(item.foodId)?.category ?? .other, size: 26)
                    Text("\(Fmt.trimKg(item.quantity)) × \(state.food(item.foodId)?.name ?? "?")")
                        .font(.system(size: 12)).foregroundStyle(Palette.text)
                    Spacer()
                    Button { state.removePlanItem(weekday: weekday, meal: meal, itemId: item.id) } label: {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                    }
                    .buttonStyle(KIconButtonStyle(size: 20))
                }
            }
            Divider().overlay(Palette.border)
        }
    }
}
