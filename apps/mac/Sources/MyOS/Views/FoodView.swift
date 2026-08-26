import SwiftUI

/// The food Library — browse every food (seed + custom), filter by category, and
/// add/edit custom foods. The "show all / add new" surface; logging happens on the
/// Fitness Today checklist, planning in the weekly planner.
struct FoodLibrarySection: View {
    @EnvironmentObject var state: AppState
    @State private var query = ""
    @State private var category: FoodCategory?
    @State private var newFood = false
    @State private var editingFood: Food?
    @FocusState private var searchFocused: Bool

    private var results: [Food] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        return state.allFoods.filter { f in
            (category == nil || f.category == category) &&
            (q.isEmpty || f.name.lowercased().contains(q))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Palette.faint)
                    TextField("", text: $query, prompt: Text("Search all foods…").foregroundColor(Palette.faint))
                        .textFieldStyle(.plain).foregroundStyle(Palette.text).focused($searchFocused)
                }
                .knField(focused: searchFocused)
                Button { newFood = true } label: { Label("New", systemImage: "plus") }
                    .buttonStyle(.borderless)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    catChip(nil, "All")
                    ForEach(FoodCategory.allCases, id: \.self) { c in catChip(c, c.label) }
                }
                .padding(.vertical, 1)
            }
            ForEach(FoodCategory.allCases, id: \.self) { cat in
                let items = results.filter { $0.category == cat }
                if !items.isEmpty {
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionTitle(text: "\(cat.label) · \(items.count)")
                            ForEach(items) { f in libRow(f) }
                        }
                    }
                }
            }
            if results.isEmpty {
                Card { Text("No foods match.").font(.footnote).foregroundStyle(Palette.faint) }
            }
        }
        .sheet(isPresented: $newFood) { FoodEditor(food: nil) }
        .sheet(item: $editingFood) { f in FoodEditor(food: f) }
    }

    private func catChip(_ c: FoodCategory?, _ label: String) -> some View {
        let on = category == c
        return Button { category = c } label: {
            Text(label).font(.caption.weight(on ? .semibold : .medium))
                .foregroundStyle(on ? Palette.text : Palette.muted)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(on ? Palette.surfaceElevated : .clear, in: Capsule())
                .overlay(Capsule().strokeBorder(on ? Palette.borderStrong : Palette.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .onHover { h in cursor(h) }
    }

    private func libRow(_ f: Food) -> some View {
        HStack(spacing: 11) {
            FoodIcon(category: f.category, name: f.name, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(f.name).font(.footnote.weight(.semibold)).foregroundStyle(Palette.text).lineLimit(1)
                Text("\(FoodServing.display(f.servingLabel)) · \(Int(f.perServing.calories)) kcal · \(Int(f.perServing.protein))g protein")
                    .font(.caption2).foregroundStyle(Palette.faint).lineLimit(1)
            }
            Spacer(minLength: 6)
            if !f.isDefault { Text("custom").font(.caption2.weight(.semibold)).foregroundStyle(Palette.faint) }
        }
        .padding(.vertical, 3)
        .frame(minHeight: 44)          // still a comfortable tap target
        .contentShape(Rectangle())
        .onTapGesture { editingFood = f }
    }
}

// MARK: - Category icon (no emoji — SF Symbol per category)

struct FoodIcon: View {
    let category: FoodCategory
    var name: String = ""
    var size: CGFloat = 30
    var body: some View {
        Text(FoodGlyph.emoji(name: name, category: category))
            .font(.system(size: size * 0.52))
            .frame(width: size, height: size)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
    }
    private var color: Color {
        switch category {
        case .protein: return Palette.nutrition
        case .carb: return Palette.attention
        case .veg: return Palette.green
        case .dairy: return Palette.blue
        case .fruit: return Palette.information
        case .drink: return Palette.blue
        case .junk: return Palette.warning
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
                Text("Add to \(meal.label)").font(.body.weight(.heavy)).foregroundStyle(Palette.text)
                Spacer()
                Button { dismiss(); newCustom() } label: { Label("New food", systemImage: "plus") }
                    .buttonStyle(.borderless)
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
                                FoodIcon(category: f.category, name: f.name, size: 30)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(f.name).font(.footnote.weight(.semibold)).foregroundStyle(Palette.text)
                                    Text("\(FoodServing.display(f.servingLabel)) · \(Int(f.perServing.calories)) kcal · \(Int(f.perServing.protein))g P")
                                        .font(.caption2).foregroundStyle(Palette.faint)
                                }
                                Spacer()
                                if !f.isDefault {
                                    Text("custom").font(.caption2.weight(.semibold)).foregroundStyle(Palette.faint)
                                }
                                Image(systemName: "plus.circle.fill").font(.callout).foregroundStyle(Palette.action)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .onHover { h in cursor(h) }
                    }
                }
                .padding(16)
            }
            .frame(maxHeight: 420)
        }
        #if os(macOS)
        .frame(width: 460)
        #else
        .frame(maxWidth: .infinity)
        #endif
        .background(Palette.elevated)
    }
}

// MARK: - Custom food editor

struct FoodEditor: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let food: Food?
    @State private var draft: Food
    @State private var showDelete = false

    init(food: Food?) {
        self.food = food
        _draft = State(initialValue: food ?? Food(name: "", category: .other, servingLabel: "1 serving", perServing: .zero))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(food == nil ? "New food" : "Edit food")
                .font(.body.weight(.heavy)).foregroundStyle(Palette.text)
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
                            Spacer(); Image(systemName: "chevron.down").font(.caption2.weight(.bold)).foregroundStyle(Palette.faint) }
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 13).padding(.vertical, 10)
                        .background(Palette.background, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
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
                    Button("Delete") { showDelete = true }
                        .buttonStyle(.borderless).tint(Palette.warning)
                        .holdToDelete(isPresented: $showDelete, title: "Delete \(food.name)?",
                                      message: "Removes it from your food library.") {
                            state.deleteFood(food.id); dismiss()
                        }
                }
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.borderless)
                Button("Save") {
                    if food == nil { state.addFood(draft) } else { state.updateFood(draft) }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        #if os(macOS)
        .frame(width: 480)
        #else
        .frame(maxWidth: .infinity)
        #endif
        .background(Palette.elevated)
    }

    private func macroField(_ label: String, _ kp: WritableKeyPath<Macros, Double>) -> some View {
        KLabeledNumberField(label: label, placeholder: "0", decimals: 1,
                            value: Binding(get: { draft.perServing[keyPath: kp] },
                                           set: { draft.perServing[keyPath: kp] = $0 ?? 0 }))
    }
}

// MARK: - Scan a food photo

/// Payload handed from the scan sheet to the review sheet.
struct FoodScanPayload: Identifiable {
    let id = UUID()
    let summary: String
    let foods: [Food]
    var defaultMeal: MealKey = .snacks
}

/// Drop/paste a photo of a packaged food's label (or a menu item) and let AI read
/// it into one or more draft Foods, reviewed next in `FoodScanReviewSheet`.
struct FoodScanSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let onRead: (String, [Food]) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Scan a food photo").font(.body.weight(.heavy)).foregroundStyle(Palette.text)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").font(.footnote.weight(.bold)) }
                    .buttonStyle(.borderless)
            }
            ImageDropZone(
                title: "Drop a nutrition label or product photo",
                subtitle: "A packaged snack, a menu item, anything with visible macros. AI adds it to your food library and you confirm before it's logged.",
                tint: Palette.action,
                busy: state.imageBusy
            ) { imgs, mt in
                Task { @MainActor in
                    let r = await state.analyzeFood(imagesBase64: imgs, mediaType: mt)
                    if state.imageError == nil {
                        onRead(r.summary, r.drafts)
                        dismiss()
                    }
                }
            }
            if let err = state.imageError {
                Text(err).font(.caption).foregroundStyle(Palette.warning)
            }
        }
        .padding(20)
        #if os(macOS)
        .frame(width: 440)
        #else
        .frame(maxWidth: .infinity)
        #endif
        .background(Palette.elevated)
    }
}

/// Review-then-save for scanned foods: confirm/edit the extracted macros, pick
/// which meal to file each under, then save — this both adds the food to the
/// library and logs it for `logDate` in one step.
struct FoodScanReviewSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let summary: String
    let logDate: String
    let defaultMeal: MealKey
    @State private var drafts: [DraftScanFood]

    init(summary: String, foods: [Food], logDate: String, defaultMeal: MealKey = .snacks) {
        self.summary = summary
        self.logDate = logDate
        self.defaultMeal = defaultMeal
        _drafts = State(initialValue: foods.map { DraftScanFood(food: $0, meal: defaultMeal) })
    }

    private var included: [DraftScanFood] { drafts.filter { $0.include } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Review \(drafts.count) \(drafts.count == 1 ? "food" : "foods")")
                    .font(.body.weight(.heavy)).foregroundStyle(Palette.text)
                if !summary.isEmpty {
                    Text(summary).font(.caption).foregroundStyle(Palette.muted)
                }
            }
            .padding(20)

            Divider().overlay(Palette.border)

            if drafts.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "text.magnifyingglass").font(.title).foregroundStyle(Palette.faint)
                    Text("Couldn't read a food from that image.").font(.footnote).foregroundStyle(Palette.muted)
                    Text("Try a clearer, closer photo of the label.").font(.caption).foregroundStyle(Palette.faint)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 40)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach($drafts) { $d in ScanFoodRow(draft: $d) }
                    }
                    .padding(16)
                }
                .frame(maxHeight: 460)
            }

            Divider().overlay(Palette.border)

            VStack(spacing: 12) {
                HStack {
                    Text("\(included.count) selected").font(.footnote.weight(.semibold)).foregroundStyle(Palette.muted)
                    Spacer()
                    Button("Cancel") { dismiss() }.buttonStyle(.borderless)
                }
                if included.isEmpty {
                    Text("Select at least one.").font(.footnote).foregroundStyle(Palette.faint)
                } else {
                    SlideToConfirm(label: "Slide to log \(included.count)", tint: Palette.action) {
                        for d in included {
                            let saved = state.addFood(d.food)
                            state.addFoodToMeal(date: logDate, meal: d.meal, foodId: saved.id, quantity: d.quantity)
                        }
                        dismiss()
                    }
                }
            }
            .padding(20)
        }
        #if os(macOS)
        .frame(width: 560)
        #else
        .frame(maxWidth: .infinity)
        #endif
        .background(Palette.elevated)
    }
}

/// One extracted food, editable before it's saved to the library and logged.
struct DraftScanFood: Identifiable {
    let id = UUID()
    var food: Food
    var meal: MealKey = .snacks
    var quantity: Double = 1
    var include = true
}

private struct ScanFoodRow: View {
    @Binding var draft: DraftScanFood

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button { draft.include.toggle() } label: {
                    Image(systemName: draft.include ? "checkmark.circle.fill" : "circle")
                        .font(.body)
                        .foregroundStyle(draft.include ? Palette.green : Palette.faint)
                }
                .buttonStyle(.plain)
                FoodIcon(category: draft.food.category, name: draft.food.name, size: 28)
                TextField("Name", text: $draft.food.name)
                    .textFieldStyle(.plain).font(.footnote.weight(.semibold)).foregroundStyle(Palette.text)
                Spacer()
                Menu {
                    ForEach(MealKey.allCases, id: \.self) { m in Button(m.label) { draft.meal = m } }
                } label: {
                    Label(draft.meal.label, systemImage: draft.meal.icon).font(.caption2.weight(.semibold))
                }
                .menuStyle(.borderlessButton).fixedSize()
            }
            HStack(spacing: 8) {
                TextField("Serving", text: $draft.food.servingLabel)
                    .textFieldStyle(.plain).font(.caption2).foregroundStyle(Palette.muted)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Palette.background, in: RoundedRectangle(cornerRadius: Radius.xs, style: .continuous))
                Stepper(value: $draft.quantity, in: 0.5...20, step: 0.5) {
                    Text("× \(Fmt.trimKg(draft.quantity)) serving\(draft.quantity == 1 ? "" : "s")")
                        .font(.caption2).foregroundStyle(Palette.muted)
                }
                .fixedSize()
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 8)], spacing: 8) {
                macroField("Cal", \.calories)
                macroField("Protein", \.protein)
                macroField("Carbs", \.carbs)
                macroField("Fiber", \.fiber)
                macroField("Fat", \.fats)
            }
        }
        .padding(11)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(draft.include ? Palette.border : Palette.border.opacity(0.5), lineWidth: 1))
        .opacity(draft.include ? 1 : 0.55)
        .animation(.knFast, value: draft.include)
    }

    private func macroField(_ label: String, _ kp: WritableKeyPath<Macros, Double>) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.caption2).foregroundStyle(Palette.faint)
            // A String binding parsed per keystroke, not `TextField(value:format:)`.
            // The formatted variant only writes back on Return or on losing first
            // responder, and the only way out of this sheet is SlideToConfirm — a
            // drag gesture on a shape that never takes focus. So correcting a
            // scanned "180" to "250" and sliding to log stored 180. FoodEditor in
            // this same file already uses the per-keystroke form.
            TextField("0", text: Binding(
                get: { Fmt.trimKg(draft.food.perServing[keyPath: kp]) },
                set: { draft.food.perServing[keyPath: kp] =
                        KLabeledNumberField.parse(KLabeledNumberField.clean($0, decimals: 1)) ?? 0 }))
                .textFieldStyle(.plain).monospacedDigit().font(.caption.weight(.semibold))
                .foregroundStyle(Palette.text)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(Palette.background, in: RoundedRectangle(cornerRadius: Radius.xs, style: .continuous))
    }
}
