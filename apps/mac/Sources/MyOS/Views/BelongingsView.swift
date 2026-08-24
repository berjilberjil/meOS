import SwiftUI
#if os(iOS)
import PhotosUI
import UniformTypeIdentifiers
#else
import UniformTypeIdentifiers
#endif

/// Everything you own — gadgets, clothes, home, books, wheels.
/// Daily cost = price ÷ days you’ve used it. Full ROI = you’ve used it for
/// its expected life. Category totals + monthly burn vs salary.
struct BelongingsView: View {
    @EnvironmentObject var state: AppState
    @State private var editing: BelongingItem?
    /// Long-pressed to see the product photo full size, rather than the card's crop.
    @State private var viewingPhoto: BelongingItem?
    @State private var showNew = false
    @State private var salaryDraft = ""

    private var today: String { state.todayKey }
    private var live: [BelongingItem] { state.belongings.items.filter { !$0.retired } }

    var body: some View {
        VStack(alignment: .leading, spacing: Gap.screen) {
            header
            hero
            ForEach(state.belongingCategories()) { cat in
                let items = live.filter { $0.categoryID == cat.id || ($0.categoryID.isEmpty && $0.kind.rawValue == cat.id) }
                if !items.isEmpty { section(cat, items) }
            }
            if live.isEmpty {
                Card(padding: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Nothing tracked yet.")
                            .font(.body.weight(.semibold)).foregroundStyle(Palette.text)
                        Text("Add a gadget, a tee, a bike — anything you spent on. You’ll see what it costs per day and when it’s paid for itself.")
                            .font(.subheadline).foregroundStyle(Palette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .sheet(isPresented: $showNew) { editor(nil).belongingSheetChrome() }
        .sheet(item: $editing) { editor($0).belongingSheetChrome() }
        .sheet(item: $viewingPhoto) { BelongingPhotoViewer(item: $0) }
        .onAppear { salaryDraft = rupeesString(state.belongings.salaryPaise) }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                #if os(macOS)   // iOS: the navigation bar owns the title
                ScreenTitle(text: "Stuff")
                #endif
                Text("What you own, and what it costs you.").font(.footnote).foregroundStyle(Palette.faint)
            }
            Spacer()
            Button { showNew = true } label: { Label("Add", systemImage: "plus") }
                .buttonStyle(.borderedProminent)
        }
    }

    private var hero: some View {
        let planned = live.map { BelongingMath.snapshot(item: $0, today: today).plannedPerDay }
        let day = planned.reduce(0, +)
        let month = day * 30
        let year = day * 365
        let salary = state.belongings.salaryPaise
        let health = BelongingMath.health(monthlyBurn: month, salary: salary)
        let healthTint: Color = {
            switch health {
            case .good: return Palette.green
            case .tight: return Palette.amber
            case .over: return Palette.red
            }
        }()
        let burn = salary > 0 ? min(1, Double(month) / Double(salary)) : 0
        return Card(padding: 20) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("OWNING ALL THIS")
                            .font(.caption2.weight(.heavy)).tracking(0.8)
                            .foregroundStyle(Palette.muted)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(BelongingINR.format(day, decimals: 0))
                                .font(.largeTitle.weight(.bold))
                                .monospacedDigit()
                                .foregroundStyle(healthTint)
                            Text("/ day")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Palette.muted)
                        }
                    }
                    Spacer()
                    healthChip(health)
                }
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: burn).progressViewStyle(.linear).tint(healthTint)
                    Text(salary > 0
                         ? "\(Int((burn * 100).rounded()))% of monthly salary"
                         : "Set a salary to judge the burn")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.faint)
                }
                HStack(spacing: 8) {
                    heroStat("Month", BelongingINR.format(month), Palette.blue)
                    heroStat("Year", BelongingINR.format(year), Palette.purple)
                    heroStat("Items", "\(live.count)", Palette.amber)
                }
                // Below the line: this is a setting the summary is measured
                // against, not another number in the summary.
                Rectangle().fill(Palette.border.opacity(0.7)).frame(height: 1)
                    .padding(.top, 2)
                HStack(spacing: 10) {
                    Text("Salary")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.faint)
                    TextField("40000", text: $salaryDraft)
                        .textFieldStyle(.plain)
                        .font(.callout.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(Palette.text)
                        .onSubmit(saveSalary)
                    Text("₹ / mo").font(.caption).foregroundStyle(Palette.faint)
                    Spacer()
                    Button("Save", action: saveSalary).buttonStyle(.borderless)
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(Palette.surface2, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            }
        }
    }

    private func healthChip(_ h: SpendHealth) -> some View {
        let (t, c): (String, Color) = {
            switch h {
            case .good: return ("On track", Palette.green)
            case .tight: return ("Tight", Palette.amber)
            case .over: return ("Over salary", Palette.red)
            }
        }()
        return Text(t)
            .font(.caption.weight(.semibold))
            .foregroundStyle(c)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(c.opacity(0.16), in: Capsule())
    }

    private func heroStat(_ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.caption2.weight(.heavy)).tracking(0.4)
                .foregroundStyle(tint)
            Text(value)
                .font(.body.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(Palette.text)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    private func section(_ kind: BelongingCategory, _ items: [BelongingItem]) -> some View {
        let day = items.reduce(0) { $0 + BelongingMath.snapshot(item: $1, today: today).plannedPerDay }
        #if os(iOS)
        let cols = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        #else
        let cols = [GridItem(.adaptive(minimum: 176), spacing: 12)]
        #endif
        let tint = kind.color
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tint.opacity(0.16))
                    Image(systemName: kind.icon).font(.footnote.weight(.semibold)).foregroundStyle(tint)
                }
                .frame(width: 32, height: 32)
                Text(kind.name).font(.body.weight(.semibold)).foregroundStyle(Palette.text)
                Spacer()
                Text(BelongingINR.format(day) + " / day")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(tint.opacity(0.14), in: Capsule())
            }
            LazyVGrid(columns: cols, spacing: 10) {
                ForEach(items) { itemCard($0) }
            }
        }
    }

    private func itemCard(_ item: BelongingItem) -> some View {
        let snap = BelongingMath.snapshot(item: item, today: today)
        let cat = state.belongingCategory(for: item)
        let tint = cat.color
        return Button { editing = item } label: {
            #if os(iOS)
            compactItemCard(item, snap: snap, tint: tint, icon: cat.icon)
            #else
            photoItemCard(item, snap: snap, tint: tint, icon: cat.icon)
            #endif
        }
        .buttonStyle(.plain)
        // Tap edits; press and hold shows the photo you added, full size. Items
        // without one just don't respond — there is nothing to open.
        .onLongPressGesture(minimumDuration: 0.4) {
            guard !item.photoBase64.isEmpty else { return }
            Haptics.selection()
            viewingPhoto = item
        }
    }

    /// Phone: compact 2-col card — photo is a short banner, not a tall square.
    private func compactItemCard(_ item: BelongingItem, snap: BelongingSnapshot, tint: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let img = MediaJPEG.image(fromBase64: item.photoBase64) {
                img.resizable().scaledToFill()
                    .frame(height: 92)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(tint.opacity(0.16))
                    Image(systemName: icon)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(tint)
                }
                .frame(height: 72)
            }
            Text(item.name).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.text)
                .lineLimit(2).multilineTextAlignment(.leading)
            Text(BelongingINR.format(item.pricePaise))
                .font(.footnote).foregroundStyle(Palette.muted)
            Text(BelongingINR.format(snap.actualPerDay, decimals: snap.actualPerDay < 100 ? 2 : 0) + " / day")
                .font(.callout.weight(.bold)).foregroundStyle(tint)
            ProgressView(value: snap.progress).progressViewStyle(.linear).tint(snap.progress >= 1 ? Palette.green : tint)
            Text(snap.daysLeft == 0 ? "Full ROI" : BelongingINR.span(snap.daysLeft))
                .font(.caption).foregroundStyle(snap.daysLeft == 0 ? Palette.green : Palette.faint)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(tint.opacity(0.35), lineWidth: 1.5))
    }

    /// Mac: square well so the whole product photo is visible.
    private func photoItemCard(_ item: BelongingItem, snap: BelongingSnapshot, tint: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            BelongingPhotoWell(base64: item.photoBase64, tint: tint, icon: icon)
            VStack(alignment: .leading, spacing: 7) {
                Text(item.name)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Palette.text)
                    .lineLimit(2).multilineTextAlignment(.leading)
                Text(BelongingINR.format(item.pricePaise))
                    .font(.footnote).foregroundStyle(Palette.muted)
                Text(BelongingINR.format(snap.actualPerDay, decimals: snap.actualPerDay < 100 ? 2 : 0) + " / day")
                    .font(.body.weight(.bold))
                    .foregroundStyle(tint)
                ProgressView(value: snap.progress).progressViewStyle(.linear).tint(snap.progress >= 1 ? Palette.green : tint)
                Text(snap.daysLeft == 0 ? "Full ROI" : BelongingINR.span(snap.daysLeft))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(snap.daysLeft == 0 ? Palette.green : Palette.faint)
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(tint.opacity(0.45), lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func editor(_ item: BelongingItem?) -> some View {
        BelongingEditor(item: item)
    }

    private func saveSalary() {
        let n = Int(salaryDraft.filter(\.isNumber)) ?? 0
        state.setSalaryPaise(n * 100)
        salaryDraft = rupeesString(state.belongings.salaryPaise)
    }

    private func rupeesString(_ paise: Int) -> String { String(paise / 100) }
}

private struct BelongingEditor: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let item: BelongingItem?

    @State private var name = ""
    @State private var categoryID = BelongingKind.gadgets.rawValue
    @State private var price = ""
    @State private var bought = Date()
    @State private var lifeMonths = 12
    @State private var note = ""
    @State private var link = ""
    @State private var photoBase64 = ""
    @State private var showDelete = false
    @State private var showRemovePhoto = false
    @State private var importing = false
    @State private var showNewCat = false
    @State private var photoBusy = false
    @State private var photoHint = ""
    #if os(iOS)
    @State private var pickItem: PhotosPickerItem?
    #endif

    private var categories: [BelongingCategory] { state.belongingCategories() }
    private var selectedCat: BelongingCategory {
        categories.first { $0.id == categoryID } ?? BelongingKind.gadgets.asCategory
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    photoField
                    field("Name", $name, "AirPods, black tee, Activa…")
                    VStack(alignment: .leading, spacing: 6) {
                        KFieldLabel(text: "Category")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(categories) { k in
                                    let on = categoryID == k.id
                                    Button {
                                        categoryID = k.id
                                        if item == nil { lifeMonths = max(1, k.defaultLifeDays / 30) }
                                    } label: {
                                        HStack(spacing: 5) {
                                            Image(systemName: k.icon).font(.caption.weight(.bold))
                                            Text(k.name)
                                        }
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(on ? Palette.bg : k.color)
                                        .padding(.horizontal, 12).padding(.vertical, 8)
                                        .background(on ? k.color : k.color.opacity(0.16), in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                                Button { showNewCat = true } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: "plus").font(.caption.weight(.bold))
                                        Text("New")
                                    }
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(Palette.text)
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    .background(Palette.surface2, in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    field("Bought for (₹)", $price, "400")
                    VStack(alignment: .leading, spacing: 6) {
                        KFieldLabel(text: "Bought on")
                        DatePicker("", selection: $bought, displayedComponents: .date)
                            .labelsHidden().tint(selectedCat.color)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        KFieldLabel(text: "Payoff period")
                        Stepper("\(lifeMonths) months", value: $lifeMonths, in: 1...120)
                            .font(.callout.weight(.semibold)).foregroundStyle(Palette.text)
                    }
                    field("Product link", $link, "https://www.amazon.in/dp/…")
                    field("Note", $note, "Optional")
                }
                .padding(16)
            }
            .background(Palette.bg.ignoresSafeArea())
            .navigationTitle(item == nil ? "Add item" : "Edit item")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if item != nil {
                    ToolbarItem(placement: .destructiveAction) {
                        Button(role: .destructive) { showDelete = true } label: { Image(systemName: "trash") }
                            .holdToDelete(isPresented: $showDelete,
                                          title: "Delete \(name.isEmpty ? "this item" : name)?",
                                          message: "This can't be undone.") {
                                if let id = item?.id { state.deleteBelonging(id) }
                                dismiss()
                            }
                    }
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.image]) { result in
                applyPickedFile(result)
            }
            .sheet(isPresented: $showNewCat) {
                NewBelongingCategorySheet { cat in
                    state.addBelongingCategory(cat)
                    categoryID = cat.id
                    lifeMonths = max(1, cat.defaultLifeDays / 30)
                }
                .belongingSheetChrome()
            }
            .onAppear {
                if let i = item {
                    name = i.name
                    categoryID = i.categoryID.isEmpty ? i.kind.rawValue : i.categoryID
                    price = String(i.pricePaise / 100)
                    note = i.note; lifeMonths = max(1, i.lifeDays / 30)
                    link = i.link
                    photoBase64 = i.photoBase64
                    if let d = AppState.date(fromKey: i.boughtOn) { bought = d }
                } else {
                    lifeMonths = max(1, selectedCat.defaultLifeDays / 30)
                }
            }
        }
    }

    private var photoField: some View {
        VStack(alignment: .leading, spacing: 8) {
            KFieldLabel(text: "Photo")
            HStack(alignment: .top, spacing: 14) {
                Button { importing = true } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(selectedCat.color.opacity(0.14))
                        if let img = MediaJPEG.image(fromBase64: photoBase64) {
                            img.resizable().scaledToFit().padding(8)
                        } else if photoBusy {
                            ProgressView().tint(selectedCat.color)
                        } else {
                            VStack(spacing: 6) {
                                Image(systemName: "photo.badge.plus")
                                    .font(.title.weight(.semibold))
                                Text("Add").font(.caption.weight(.semibold))
                            }
                            .foregroundStyle(selectedCat.color)
                        }
                    }
                    .frame(width: 132, height: 132)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(selectedCat.color.opacity(0.45), lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .onDrop(of: [.image], isTargeted: nil) { providers in
                    Task { await dropPhoto(providers) }
                    return true
                }

                VStack(alignment: .leading, spacing: 8) {
                    #if os(iOS)
                    PhotosPicker(selection: $pickItem, matching: .images) {
                        Label(photoBase64.isEmpty ? "Choose photo" : "Change photo", systemImage: "photo.badge.plus")
                            .font(.footnote.weight(.semibold)).foregroundStyle(selectedCat.color)
                    }
                    .onChange(of: pickItem) { _, item in Task { await loadPicked(item) } }
                    #else
                    Button { importing = true } label: {
                        Label(photoBase64.isEmpty ? "Choose photo" : "Change photo", systemImage: "photo.badge.plus")
                            .font(.footnote.weight(.semibold)).foregroundStyle(selectedCat.color)
                    }
                    .buttonStyle(.borderless)
                    #endif
                    if !photoBase64.isEmpty {
                        Button { showRemovePhoto = true } label: {
                            Text("Remove photo").font(.footnote.weight(.semibold)).foregroundStyle(Palette.red)
                        }
                        .buttonStyle(.plain)
                        .holdToDelete(isPresented: $showRemovePhoto, title: "Remove this photo?",
                                      message: "The item stays. Only the picture is dropped.") {
                            photoBase64 = ""; photoHint = ""
                        }
                    }
                    Text(photoBusy ? "Catherine is reading the photo…"
                         : (photoHint.isEmpty ? "Drop a photo and Catherine fills the name, shelf and price." : photoHint))
                        .font(.footnote).foregroundStyle(Palette.faint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    #if os(iOS)
    private func loadPicked(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self),
              let jpeg = MediaJPEG.downscale(data) else { return }
        await MainActor.run { adoptPhoto(jpeg) }
    }
    #endif

    private func applyPickedFile(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url),
              let jpeg = MediaJPEG.downscale(data) else { return }
        adoptPhoto(jpeg)
    }

    private func dropPhoto(_ providers: [NSItemProvider]) async {
        for p in providers {
            let data: Data? = await withCheckedContinuation { cont in
                _ = p.loadDataRepresentation(for: .image) { data, _ in
                    cont.resume(returning: data)
                }
            }
            if let data, let jpeg = MediaJPEG.downscale(data) {
                await MainActor.run { adoptPhoto(jpeg) }
                return
            }
        }
    }

    private func adoptPhoto(_ jpeg: Data) {
        photoBase64 = jpeg.base64EncodedString()
        photoHint = ""
        Task { await identifyFromPhoto() }
    }

    private func identifyFromPhoto() async {
        guard !photoBase64.isEmpty else { return }
        await MainActor.run { photoBusy = true }
        let ids = categories.map(\.id)
        let guess = await state.identifyBelonging(photoBase64: photoBase64, categoryIDs: ids)
        await MainActor.run {
            photoBusy = false
            guard let g = guess else {
                photoHint = "Couldn’t name that. Type the name — photo still saved."
                return
            }
            if name.trimmingCharacters(in: .whitespaces).isEmpty || !BelongingGuess.isProductTitle(name) {
                name = g.name
            }
            if categories.contains(where: { $0.id == g.categoryID }) {
                categoryID = g.categoryID
                if item == nil { lifeMonths = max(1, g.lifeMonths) }
            }
            if g.priceInr > 0 { price = String(g.priceInr) }
            photoHint = g.summary
        }
    }

    private func field(_ label: String, _ text: Binding<String>, _ hint: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            KFieldLabel(text: label)
            TextField("", text: text, prompt: Text(hint).foregroundColor(Palette.faint))
                .textFieldStyle(.plain).font(.body).foregroundStyle(Palette.text)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(Palette.bg, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: 1))
        }
    }

    private func save() {
        let rupees = Int(price.filter(\.isNumber)) ?? 0
        let key = AppState.dateKey(bought)
        let kind = BelongingKind(rawValue: categoryID) ?? .other
        var next = item ?? BelongingItem(name: name, kind: kind, pricePaise: rupees * 100,
                                         boughtOn: key, categoryID: categoryID)
        next.name = name.trimmingCharacters(in: .whitespaces)
        next.kind = kind
        next.categoryID = categoryID
        next.pricePaise = rupees * 100
        next.boughtOn = key
        next.lifeDays = lifeMonths * 30
        next.note = note
        next.link = link.trimmingCharacters(in: .whitespacesAndNewlines)
        next.photoBase64 = photoBase64
        if item == nil { state.addBelonging(next) } else { state.updateBelonging(next) }
        dismiss()
    }
}

/// Square well that shows the whole photo (fit, never a thin crop).
private struct BelongingPhotoWell: View {
    let base64: String
    let tint: Color
    let icon: String
    var body: some View {
        ZStack {
            tint.opacity(0.14)
            if let img = MediaJPEG.image(fromBase64: base64) {
                img.resizable()
                    .scaledToFit()
                    .padding(10)
            } else {
                Image(systemName: icon)
                    .font(.title.weight(.semibold))
                    .foregroundStyle(tint)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .clipped()
    }
}

extension BelongingKind {
    var color: Color { Color(hex: tintHex) }
}

extension BelongingCategory {
    var color: Color { Color(hex: tintHex) }
}

extension View {
    func belongingSheetChrome() -> some View {
        #if os(macOS)
        self.frame(minWidth: 540, idealWidth: 560, minHeight: 680)
        #else
        self
        #endif
    }
}

private struct NewBelongingCategorySheet: View {
    @Environment(\.dismiss) private var dismiss
    var onSave: (BelongingCategory) -> Void

    @State private var name = ""
    @State private var icon = "tag.fill"
    @State private var tint: UInt32 = 0xB98CFF

    private let icons = [
        "headphones", "earbuds", "tshirt.fill", "shoe.fill", "bag.fill",
        "applewatch", "iphone", "laptopcomputer", "desktopcomputer", "camera.fill",
        "gamecontroller.fill", "tv.fill", "sofa.fill", "lamp.desk.fill", "refrigerator.fill",
        "book.fill", "newspaper.fill", "bicycle", "car.fill", "airplane",
        "gift.fill", "paintbrush.fill", "music.note", "key.fill", "wrench.and.screwdriver.fill",
        "cube.fill", "shippingbox.fill", "sparkles", "heart.fill", "star.fill", "tag.fill"
    ]
    private let colors: [UInt32] = [
        0x4AA8FF, 0xB98CFF, 0xFFC24B, 0xFF8A3D, 0x7FD1FF,
        0x56BB06, 0xFF5A5F, 0xFF6B9A, 0x2DD4BF, 0xF5C451, 0xFF7A59
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        KFieldLabel(text: "Name")
                        TextField("", text: $name, prompt: Text("Shoes, cameras, watches…").foregroundColor(Palette.faint))
                            .textFieldStyle(.plain).font(.body).foregroundStyle(Palette.text)
                            .padding(.horizontal, 14).padding(.vertical, 12)
                            .background(Palette.bg, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .strokeBorder(Palette.border, lineWidth: 1))
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        KFieldLabel(text: "Icon")
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 8)], spacing: 8) {
                            ForEach(icons, id: \.self) { s in
                                Button { icon = s } label: {
                                    Image(systemName: s)
                                        .font(.callout.weight(.semibold))
                                        .foregroundStyle(icon == s ? Palette.bg : Color(hex: tint))
                                        .frame(width: 44, height: 44)
                                        .background(icon == s ? Color(hex: tint) : Color(hex: tint).opacity(0.16),
                                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        KFieldLabel(text: "Pill color")
                        HStack(spacing: 8) {
                            ForEach(colors, id: \.self) { hex in
                                Button { tint = hex } label: {
                                    Circle().fill(Color(hex: hex))
                                        .frame(width: 28, height: 28)
                                        .overlay(Circle().strokeBorder(Palette.text.opacity(tint == hex ? 0.9 : 0), lineWidth: 2))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    HStack(spacing: 8) {
                        Image(systemName: icon).font(.footnote.weight(.bold))
                        Text(name.isEmpty ? "Preview" : name)
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.bg)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Color(hex: tint), in: Capsule())
                }
                .padding(16)
            }
            .background(Palette.bg.ignoresSafeArea())
            .navigationTitle("New category")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onSave(BelongingCategory(name: name, icon: icon, tintHex: tint))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}


/// The product photo, full size, on black. Reached by pressing and holding a
/// card in Stuff.
private struct BelongingPhotoViewer: View {
    let item: BelongingItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let content = ZStack {
            Color.black.ignoresSafeArea()
            if let img = MediaJPEG.image(fromBase64: item.photoBase64) {
                img.resizable().scaledToFit()
            } else {
                Text("No photo on this one.")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
            }
            VStack {
                HStack(alignment: .top) {
                    Text(item.name)
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                        .lineLimit(2)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(.black.opacity(0.45), in: Capsule())
                    Spacer(minLength: 8)
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.footnote.weight(.bold)).foregroundStyle(.white)
                            .padding(9)
                            .background(.black.opacity(0.45), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
                Spacer()
            }
        }

        #if os(iOS)
        content.presentationBackground(.black)
        #else
        content.frame(width: 620, height: 620)
        #endif
    }
}
