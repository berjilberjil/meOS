import SwiftUI
import PhotosUI
import Charts
import AVKit

// MARK: - Camera

#if os(iOS)
struct CameraPicker: UIViewControllerRepresentable {
    let done: (UIImage?) -> Void
    func makeCoordinator() -> C { C(done: done) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        p.delegate = context.coordinator
        return p
    }
    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}
    final class C: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let done: (UIImage?) -> Void
        init(done: @escaping (UIImage?) -> Void) { self.done = done }
        func imagePickerController(_ p: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            done(info[.originalImage] as? UIImage); p.dismiss(animated: true)
        }
        func imagePickerControllerDidCancel(_ p: UIImagePickerController) { done(nil); p.dismiss(animated: true) }
    }
}
#endif

/// Camera + library in two big buttons; hands back a JPEG.
struct PhotoSource: View {
    let busy: Bool
    let pick: (Data) -> Void
    @State private var camera = false
    @State private var item: PhotosPickerItem?
    var body: some View {
        HStack(spacing: DS.gap) {
            Button { camera = true } label: {
                VStack(spacing: 14) { Image(systemName: "camera.fill").font(.system(size: 34)); Text("Camera").font(.headline) }
                    .frame(maxWidth: .infinity).frame(height: 150).foregroundStyle(Color.paper).background(Color.ink, in: .rect(cornerRadius: DS.radius))
            }
            .buttonStyle(.press)
            PhotosPicker(selection: $item, matching: .images) {
                VStack(spacing: 14) { Image(systemName: "photo.on.rectangle").font(.system(size: 34)); Text("Library").font(.headline) }
                    .frame(maxWidth: .infinity).frame(height: 150).background(Color.card, in: .rect(cornerRadius: DS.radius))
            }
            .buttonStyle(.press)
        }
        .disabled(busy).opacity(busy ? 0.4 : 1)
        .overlay { if busy { ProgressView().controlSize(.large) } }
        .fullScreenCover(isPresented: $camera) { CameraPicker { img in if let d = img.flatMap(Self.jpeg) { pick(d) } }.ignoresSafeArea() }
        .onChange(of: item) { _, it in
            Task { if let d = try? await it?.loadTransferable(type: Data.self), let img = UIImage(data: d), let j = Self.jpeg(img) { pick(j) }; item = nil }
        }
    }
    static func jpeg(_ img: UIImage) -> Data? {
        guard let s = MeInlineImage.encode(img, maxDimension: 1600) else { return nil }
        return Data(base64Encoded: s)
    }
}

// MARK: - Scan

struct MeScan: View {
    @EnvironmentObject var state: AppState
    @State private var result: ScanInsight?
    @State private var savedID: String?
    @State private var logged = false
    @State private var photo: Data?

    var body: some View {
        Screen(title: "Scan", sub: "Food or anything") {
            if let photo, let img = UIImage(data: photo) {
                Image(uiImage: img).resizable().scaledToFill().frame(height: 260).frame(maxWidth: .infinity).clipShape(.rect(cornerRadius: DS.radius))
                    .transition(.scale(0.95).combined(with: .opacity))
            }
            PhotoSource(busy: state.imageBusy) { data in
                photo = data; result = nil; logged = false; state.imageError = nil
                Task {
                    let r = await state.analyzeScan(imagesBase64: [data.base64EncodedString()], mediaType: "image/jpeg")
                    withAnimation(DS.spring) { result = r }
                    if !r.failed { savedID = state.saveScan(r, photo: data).id }
                }
            }
            if let err = state.imageError { Text(err).font(.subheadline.weight(.semibold)) }
            if let r = result, !r.failed { card(r).transition(.move(edge: .bottom).combined(with: .opacity)) }
            if !state.scans.isEmpty {
                MLabel("History")
                ForEach(state.scans.sorted { $0.at > $1.at }.prefix(40)) { s in
                    MCard {
                        HStack(spacing: 14) {
                            BigIcon(name: s.kind == "food" ? "fork.knife" : "shippingbox", size: 20)
                            VStack(alignment: .leading) {
                                Text(s.kind == "food" ? s.foods.map(\.name).joined(separator: ", ") : (s.object?.name ?? "Item")).font(.headline).lineLimit(1)
                                Text("\(Fmt.day(s.date)) · \(s.summary)").font(.subheadline).foregroundStyle(Color.dim).lineLimit(2)
                            }
                        }
                    }
                    .contextMenu { Button("Delete", role: .destructive) { state.deleteScan(s.id) } }
                }
            }
        }
    }

    @ViewBuilder private func card(_ r: ScanInsight) -> some View {
        if r.kind == .food {
            MCard(inverted: true) {
                Text(r.summary).font(.headline).opacity(0.75)
                ForEach(r.foods.indices, id: \.self) { i in
                    let f = r.foods[i]
                    HStack { Text(f.name).font(.title3.bold()); Spacer(); Text("\(Int(f.calories)) kcal").font(.headline) }
                    Text("\(f.serving) · P\(Int(f.protein)) C\(Int(f.carbs)) F\(Int(f.fats))").font(.subheadline).opacity(0.6)
                }
                Button { log(r) } label: {
                    Text(logged ? "Logged" : "Log this meal").font(.headline).frame(maxWidth: .infinity).frame(height: 52)
                        .foregroundStyle(Color.ink).background(Color.paper, in: .rect(cornerRadius: 16))
                }
                .buttonStyle(.press).disabled(logged)
            }
        } else if let o = r.object {
            MCard(inverted: true) {
                Text(o.name).font(.system(size: 30, weight: .bold))
                Text(o.needed == .yes ? "Wanted" : o.needed == .no ? "Not wanted" : "Maybe").font(.title2.bold())
                Text(o.why).opacity(0.8)
                if !o.useful.isEmpty { Text(o.useful).font(.subheadline).opacity(0.6) }
            }
        }
    }

    private func log(_ r: ScanInsight) {
        for f in r.foods {
            let food = state.addFood(Food(name: f.name, category: .other, servingLabel: f.serving,
                                          perServing: Macros(calories: f.calories, protein: f.protein, carbs: f.carbs, fiber: 0, fats: f.fats),
                                          vitamins: f.detail.isEmpty ? nil : f.detail))
            state.addFoodToMeal(date: state.todayKey, meal: .snacks, foodId: food.id)
        }
        Haptics.success()
        withAnimation(DS.spring) { logged = true }
        if let id = savedID { state.markScanLogged(id) }
    }
}

// MARK: - Productivity

struct MeProductivity: View {
    @EnvironmentObject var state: AppState
    @State private var month = Date.now

    var body: some View {
        let today = state.todayKey
        let s = state.activitySummary(today)
        let todos = state.plan(for: today).todos
        Screen(title: "Productivity", sub: "Focus & screen time") {
            HStack(spacing: DS.gap) {
                MCard(inverted: true) { Stat(value: "\(state.focusStreak())", label: "clean-day streak") }
                MCard { Stat(value: "\(FocusRecord.focusedMinutes(todos))m", label: "focused today") }
            }
            MCard {
                Text("Focus record").font(.title3.bold())
                calendar
                HStack(spacing: 14) {
                    Label("Done", systemImage: "square.fill"); Label("Partial", systemImage: "square.lefthalf.filled"); Label("Missed", systemImage: "square")
                }
                .font(.caption).foregroundStyle(Color.dim)
            }
            if s.isEmpty {
                MCard { Label("Screen time comes from your Mac", systemImage: "desktopcomputer").font(.headline)
                        Text("Nothing recorded today yet.").foregroundStyle(Color.dim) }
            } else {
                MCard {
                    HStack(alignment: .firstTextBaseline) {
                        Stat(value: Fmt.duration(s.totalSeconds), label: "tracked today")
                        Spacer()
                        if let (v, line) = ActivityInsights.verdict(s) { VStack(alignment: .trailing) { Text(v.label).font(.title3.bold()); Text(line).font(.caption).foregroundStyle(Color.dim).multilineTextAlignment(.trailing) } }
                    }
                    ForEach(ProductivityType.allCases) { p in
                        let sec = s.byProductivity[p] ?? 0
                        HStack { Text(p.rawValue.capitalized).font(.headline); Spacer(); Text(Fmt.duration(sec)).font(.headline).monospacedDigit() }
                        Bar(progress: Double(sec) / Double(max(1, s.totalSeconds)))
                    }
                }
                MCard {
                    Text("Top apps").font(.title3.bold())
                    ForEach(s.apps.prefix(6), id: \.appId) { a in
                        HStack { Text(a.appName).font(.headline); Spacer(); Text(Fmt.duration(a.seconds)).monospacedDigit().foregroundStyle(Color.dim) }
                    }
                }
                ForEach(ActivityInsights.insights(s)) { i in
                    MCard { Text(i.title).font(.headline); Text(i.detail).foregroundStyle(Color.dim) }
                }
            }
        }
    }

    private var calendar: some View {
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.year, .month], from: month))!
        let count = cal.range(of: .day, in: .month, for: start)!.count
        let lead = (cal.component(.weekday, from: start) + 6) % 7
        return VStack(spacing: 10) {
            HStack {
                Text(month.formatted(.dateTime.month(.wide).year())).font(.headline)
                Spacer()
                Button { withAnimation(DS.spring) { month = cal.date(byAdding: .month, value: -1, to: month)! } } label: { Image(systemName: "chevron.left").frame(width: 36, height: 36) }
                Button { withAnimation(DS.spring) { month = cal.date(byAdding: .month, value: 1, to: month)! } } label: { Image(systemName: "chevron.right").frame(width: 36, height: 36) }
            }
            .buttonStyle(.press)
            LazyVGrid(columns: Array(repeating: .init(spacing: 6), count: 7), spacing: 6) {
                ForEach(0..<lead, id: \.self) { _ in Color.clear.frame(height: 34) }
                ForEach(1...count, id: \.self) { d in
                    let k = AppState.dateKey(cal.date(byAdding: .day, value: d - 1, to: start)!)
                    let todos = state.plan(for: k).todos
                    let v = todos.isEmpty ? nil : FocusRecord.verdict(todos)
                    Text("\(d)").font(.caption.weight(.semibold)).frame(maxWidth: .infinity).frame(height: 34)
                        .foregroundStyle(v == .done ? Color.paper : .ink)
                        .background(v == .done ? Color.ink : v == .partial ? Color.dim.opacity(0.4) : Color.clear, in: .rect(cornerRadius: 10))
                        .overlay { if v == .missed { RoundedRectangle(cornerRadius: 10).stroke(Color.hairline, lineWidth: 1.5) } }
                }
            }
        }
    }
}


// MARK: - Stuff

struct MeStuff: View {
    @EnvironmentObject var state: AppState
    @State private var adding = false
    @State private var editingSalary = false
    @State private var salary = ""

    var body: some View {
        let live = state.belongings.items.filter { !$0.retired }
        let burn = BelongingMath.monthlyBurnPaise(items: live.map { ($0.pricePaise, $0.lifeDays) })
        let health = BelongingMath.health(monthlyBurn: burn, salary: state.belongings.salaryPaise)
        let perDay = live.reduce(0) { $0 + BelongingMath.snapshot(item: $1, today: state.todayKey).plannedPerDay }
        Screen(title: "Stuff", sub: "\(live.count) things you own") {
            MCard(inverted: true) {
                Stat(value: BelongingINR.format(perDay, decimals: 2), label: "per day", big: true)
                HStack {
                    Text("\(BelongingINR.format(burn))/mo · \(health.rawValue.capitalized)").font(.headline)
                    Spacer()
                    Button("Salary") { salary = String(state.belongings.salaryPaise / 100); editingSalary = true }.font(.headline).opacity(0.7)
                }
            }
            ForEach(state.belongings.items.sorted { !$0.retired && $1.retired }) { item in
                let snap = BelongingMath.snapshot(item: item, today: state.todayKey)
                let cat = state.belongingCategory(for: item)
                MCard {
                    HStack(spacing: 14) {
                        if let d = Data(base64Encoded: item.photoBase64), let img = UIImage(data: d) {
                            Image(uiImage: img).resizable().scaledToFill().frame(width: 56, height: 56).clipShape(.rect(cornerRadius: 16))
                        } else { BigIcon(name: cat.icon, size: 22) }
                        VStack(alignment: .leading) {
                            Text(item.name).font(.title3.bold()).strikethrough(item.retired)
                            Text("\(BelongingINR.format(item.pricePaise)) · \(BelongingINR.format(snap.actualPerDay, decimals: 2))/day").font(.subheadline).foregroundStyle(Color.dim)
                        }
                        Spacer()
                        Text(snap.progress >= 1 ? "Full ROI" : "\(snap.daysLeft)d").font(.headline)
                    }
                    Bar(progress: snap.progress)
                }
                .opacity(item.retired ? 0.5 : 1)
                .contextMenu {
                    Button(item.retired ? "Unretire" : "Retire", systemImage: "archivebox") { var i = item; i.retired.toggle(); state.updateBelonging(i) }
                    Button("Delete", systemImage: "trash", role: .destructive) { state.deleteBelonging(item.id) }
                }
            }
        }
        .meActions { Button { adding = true } label: { Image(systemName: "plus") } }
        .sheet(isPresented: $adding) { MeAddStuff().presentationDetents([.large]) }
        .alert("Monthly salary (₹)", isPresented: $editingSalary) {
            TextField("Salary", text: $salary).keyboardType(.numberPad)
            Button("Save") { if let v = Int(salary) { state.setSalaryPaise(v * 100) } }
            Button("Cancel", role: .cancel) {}
        }
    }
}

struct MeAddStuff: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var price = ""
    @State private var months = 36
    @State private var bought = Date.now
    @State private var catID = ""
    @State private var photo = ""
    @State private var note = ""
    @State private var guessing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("New thing").font(.largeTitle.bold()).padding(.top, 24)
                if let d = Data(base64Encoded: photo), let img = UIImage(data: d) {
                    Image(uiImage: img).resizable().scaledToFill().frame(height: 200).frame(maxWidth: .infinity).clipShape(.rect(cornerRadius: DS.radius))
                }
                PhotoSource(busy: guessing) { data in
                    photo = data.base64EncodedString(); guessing = true
                    Task {
                        if let g = await state.identifyBelonging(photoBase64: photo, categoryIDs: state.belongingCategories().map(\.id)) {
                            withAnimation(DS.spring) { name = g.name; catID = g.categoryID; price = String(g.priceInr); months = g.lifeMonths }
                        }
                        guessing = false
                    }
                }
                MField(icon: "tag", placeholder: "Name", text: $name)
                MField(icon: "indianrupeesign", placeholder: "Price", text: $price).keyboardType(.numberPad)
                ScrollView(.horizontal) {
                    HStack { ForEach(state.belongingCategories()) { c in Button { catID = c.id; months = max(1, c.defaultLifeDays / 30) } label: { Chip(text: c.name, on: catID == c.id) } } }
                }
                .scrollIndicators(.hidden).buttonStyle(.press)
                MCard {
                    DatePicker("Bought on", selection: $bought, displayedComponents: .date).font(.headline)
                    BigStepper(label: "Pays off in", value: "\(months) mo", minus: { months = max(1, months - 1) }, plus: { months += 1 })
                }
                MField(icon: "text.alignleft", placeholder: "Note", text: $note)
                MButton(title: "Save", icon: "checkmark") {
                    let cat = catID.isEmpty ? state.belongingCategories().first?.id : catID
                    state.addBelonging(BelongingItem(name: name, kind: .other, pricePaise: (Int(price) ?? 0) * 100, boughtOn: AppState.dateKey(bought),
                                                     lifeDays: BelongingMath.lifeDays(months: months), note: note, photoBase64: photo, categoryID: cat))
                    Haptics.success(); dismiss()
                }
                .disabled(name.isEmpty || Int(price) == nil).opacity(name.isEmpty || Int(price) == nil ? 0.3 : 1)
            }
            .padding(DS.pad)
        }
    }
}

// MARK: - Money (Fold)

struct MeMoney: View {
    @EnvironmentObject var state: AppState
    @AppStorage("meos.money.hidden") private var hidden = false
    @State private var phone = ""
    @State private var otp = ""
    @State private var sent = false

    var body: some View {
        Screen(title: "Money", sub: state.fold.map { "Fold · \(Fmt.day(String($0.asOf.prefix(10))))" } ?? "Fold") {
            if !state.foldLinked {
                Empty(icon: "indianrupeesign.circle", text: "Connect Fold to see your money here. Read-only.")
                MField(icon: "phone", placeholder: "Phone number", text: $phone).keyboardType(.phonePad)
                if sent { MField(icon: "number", placeholder: "OTP", text: $otp).keyboardType(.numberPad) }
                MButton(title: sent ? "Verify" : "Send OTP", icon: "arrow.right") {
                    Task {
                        if sent { if await state.verifyFoldOTP(phone, otp: otp) { await state.refreshFold() } }
                        else { await state.sendFoldOTP(phone); withAnimation(DS.spring) { sent = state.foldError == nil } }
                    }
                }
                .disabled(state.foldBusy)
            } else if let f = state.fold {
                MCard(inverted: true) {
                    Stat(value: amt(f.netWorth), label: "net worth", big: true)
                    if !f.changeLabel.isEmpty { Text("\(f.changeValue >= 0 ? "+" : "")\(amt(f.changeValue)) \(f.changeLabel)").font(.headline).opacity(0.7) }
                    if f.history.count > 1 {
                        Chart(Array(f.history.enumerated()), id: \.offset) { i, v in
                            LineMark(x: .value("i", i), y: .value("v", v)).foregroundStyle(Color.paper).interpolationMethod(.catmullRom)
                        }
                        .chartXAxis(.hidden).chartYAxis(.hidden).chartYScale(domain: .automatic(includesZero: false)).frame(height: 60)
                    }
                }
                LazyVGrid(columns: [.init(spacing: DS.gap), .init()], spacing: DS.gap) {
                    MCard { Stat(value: amt(f.liquid), label: "cash") }
                    MCard { Stat(value: amt(f.investments), label: "invested") }
                    MCard { Stat(value: amt(f.spentThisMonth), label: "spent this month") }
                    MCard { Stat(value: amt(f.debt), label: "debt") }
                    MCard { Stat(value: amt(f.stocksValue), label: "stocks") }
                    MCard { Stat(value: amt(f.mfValue), label: "mutual funds") }
                }
                if !f.banks.isEmpty {
                    MCard {
                        Text("Banks").font(.title3.bold())
                        ForEach(f.banks) { b in HStack { Text("\(b.name) ··\(b.last4)").font(.headline); Spacer(); Text(amt(b.balance)).font(.headline).monospacedDigit() } }
                    }
                }
                if !f.topSpends.isEmpty {
                    MCard {
                        Text("Top spends").font(.title3.bold())
                        let top = f.topSpends.prefix(6)
                        ForEach(Array(top)) { s in
                            HStack { Text(s.category).font(.headline); Spacer(); Text(amt(s.amount)).monospacedDigit() }
                            Bar(progress: s.amount / max(1, top.first?.amount ?? 1))
                        }
                    }
                }
            }
            if let err = state.foldError { Text(err).font(.subheadline) }
            if state.foldLinked {
                Button("Disconnect Fold", role: .destructive) { state.disconnectFold() }.font(.headline).frame(maxWidth: .infinity)
            }
        }
        .refreshable { await state.refreshFold() }
        .meActions { Button { withAnimation(DS.spring) { hidden.toggle() } } label: { Image(systemName: hidden ? "eye.slash" : "eye") } }
        .task { if state.foldLinked { await state.refreshFold() } }
    }
    private func amt(_ v: Double) -> String { hidden ? "₹ ••••" : "₹" + Int(v).formatted(.number.locale(Locale(identifier: "en_IN"))) }
}

// MARK: - Macro

struct MeMacro: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        Screen(title: "Macro", sub: state.macro.map { "As of \(Fmt.day($0.date))" } ?? "Economy") {
            if let m = state.macro {
                LazyVGrid(columns: [.init(spacing: DS.gap), .init()], spacing: DS.gap) {
                    ForEach(m.regime) { s in
                        MCard(inverted: s.state == "risk") { Stat(value: "\(s.score)", label: s.label) }
                    }
                }
                if let b = m.brief {
                    MCard {
                        Text("Brief").font(.title3.bold())
                        ForEach(b.changed, id: \.metric) { c in Text("· \(c.metric): \(c.move)").font(.subheadline) }
                        MLabel("Why"); Text(b.why)
                        MLabel("Why it matters"); Text(b.matters)
                        if !b.watch.isEmpty { MLabel("Watch"); ForEach(b.watch, id: \.self) { Text("· " + $0) } }
                    }
                }
                ForEach(m.metrics.filter(\.available)) { x in
                    MCard {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(x.name).font(.headline)
                                Text(x.quality.capitalized).font(.caption).foregroundStyle(Color.dim)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(format(x)).font(.title3.bold()).monospacedDigit()
                                if let d = x.change1D { Text(String(format: "%+.2f%%", d.pct)).font(.subheadline).foregroundStyle(Color.dim) }
                            }
                        }
                        if x.history.count > 2 {
                            Chart(Array(x.history.enumerated()), id: \.offset) { i, p in
                                LineMark(x: .value("i", i), y: .value("v", p.v)).foregroundStyle(Color.ink)
                            }
                            .chartXAxis(.hidden).chartYAxis(.hidden).chartYScale(domain: .automatic(includesZero: false)).frame(height: 44)
                        }
                    }
                }
            } else if state.macroBusy {
                ProgressView().frame(maxWidth: .infinity).padding(40)
            } else {
                Empty(icon: "chart.line.uptrend.xyaxis", text: state.macroError ?? "No data yet.")
            }
        }
        .refreshable { await state.loadMacro(date: state.todayKey, refresh: true) }
        .task { if state.macro == nil { await state.loadMacro(date: state.todayKey) } }
    }
    private func format(_ x: MacroMetric) -> String {
        guard let v = x.value else { return "—" }
        return x.isRate ? String(format: "%.2f%%", v) : v >= 1000 ? Int(v).formatted() : String(format: "%.2f", v)
    }
}

// MARK: - Gallery

struct MeGallery: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var media = EventMediaStore.shared
    @State private var filter: GalleryItem.Source?
    @State private var open: GalleryItem?

    var body: some View {
        let all = GalleryFeed.items(events: state.events, scans: state.scans, notes: state.notes, progress: ProgressPhotoStore.list())
        let items = all.filter { filter == nil || $0.source == filter }
        Screen(title: "Gallery", sub: "\(all.count) items") {
            ScrollView(.horizontal) {
                HStack {
                    Button { withAnimation(DS.spring) { filter = nil } } label: { Chip(text: "All", on: filter == nil) }
                    ForEach(GalleryItem.Source.allCases) { s in Button { withAnimation(DS.spring) { filter = s } } label: { Chip(text: s.label, on: filter == s) } }
                }
            }
            .scrollIndicators(.hidden).buttonStyle(.press)
            if items.isEmpty { Empty(icon: "photo.on.rectangle", text: "Nothing here yet.") }
            ForEach(GalleryFeed.months(items), id: \.month) { group in
                MLabel(GalleryFeed.monthLabel(group.month))
                LazyVGrid(columns: Array(repeating: .init(spacing: 6), count: 3), spacing: 6) {
                    ForEach(group.items) { it in
                        Button { open = it } label: {
                            GalleryThumb(item: it).aspectRatio(1, contentMode: .fill).clipShape(.rect(cornerRadius: 14))
                                .overlay(alignment: .topTrailing) { if it.kind == .video { Image(systemName: "play.fill").font(.caption).foregroundStyle(.white).padding(6) } }
                        }
                        .buttonStyle(.press)
                    }
                }
            }
        }
        .fullScreenCover(item: $open) { it in GalleryViewer(item: it) }
    }
}

struct GalleryThumb: View {
    let item: GalleryItem
    @ObservedObject private var media = EventMediaStore.shared
    var body: some View {
        GeometryReader { g in
            Group {
                if let img = image { Image(uiImage: img).resizable().scaledToFill() } else { Color.hairline }
            }
            .frame(width: g.size.width, height: g.size.height).clipped()
        }
    }
    private var image: UIImage? {
        switch item.location {
        case let .sealed(key, poster): return (media.data(key: poster ?? key)).flatMap(UIImage.init(data:))
        case let .inline(b64, poster): return Data(base64Encoded: poster ?? b64).flatMap(UIImage.init(data:))
        case let .file(url): return UIImage(contentsOfFile: url.path)?.preparingThumbnail(of: CGSize(width: 400, height: 400))
        }
    }
}

struct GalleryViewer: View {
    @Environment(\.dismiss) private var dismiss
    let item: GalleryItem
    @ObservedObject private var media = EventMediaStore.shared
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if item.kind == .video, let url = videoURL { VideoPlayer(player: AVPlayer(url: url)).ignoresSafeArea() }
            else if let img = full { Image(uiImage: img).resizable().scaledToFit() }
            VStack(alignment: .trailing) {
                Button { dismiss() } label: { Image(systemName: "xmark").font(.title3.bold()).foregroundStyle(.white).frame(width: 48, height: 48) }
                Spacer()
                Text("\(item.title) · \(Fmt.day(item.day))").font(.headline).foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading).padding()
            }
        }
        .gesture(DragGesture().onEnded { if $0.translation.height > 120 { dismiss() } })
    }
    private var bytes: Data? {
        switch item.location {
        case let .sealed(key, _): return media.data(key: key)
        case let .inline(b64, _): return Data(base64Encoded: b64)
        case let .file(url): return try? Data(contentsOf: url)
        }
    }
    private var full: UIImage? { bytes.flatMap(UIImage.init(data:)) }
    private var videoURL: URL? {
        guard let d = bytes else { return nil }
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("\(item.id).mp4")
        try? d.write(to: u); return u
    }
}

// MARK: - Recycle bin

struct MeBin: View {
    @EnvironmentObject var state: AppState
    @State private var confirmEmpty = false
    var body: some View {
        Screen(title: "Recycle bin", sub: "Kept for 30 days") {
            if state.liveTrash.isEmpty { Empty(icon: "trash", text: "The bin is empty.") }
            ForEach(state.liveTrash) { e in
                MCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.title.isEmpty ? e.kind.label : e.title).font(.headline).lineLimit(1)
                            Text("\(e.kind.label) · \(TrashRetention.daysLeft(e, todayKey: state.todayKey)) days left").font(.subheadline).foregroundStyle(Color.dim)
                        }
                        Spacer()
                        Button("Restore") { withAnimation(DS.spring) { _ = state.restoreFromTrash(e) }; Haptics.success() }.font(.headline)
                    }
                }
                .contextMenu { Button("Delete forever", role: .destructive) { withAnimation(DS.spring) { state.purgeFromTrash(e) } } }
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
            if !state.liveTrash.isEmpty {
                Button("Empty bin", role: .destructive) { confirmEmpty = true }.font(.headline).frame(maxWidth: .infinity)
            }
        }
        .confirmationDialog("Delete everything in the bin forever?", isPresented: $confirmEmpty, titleVisibility: .visible) {
            Button("Empty bin", role: .destructive) { withAnimation(DS.spring) { state.emptyTrash() } }
        }
    }
}

// MARK: - Calendar (events month view)

struct MeCalendar: View {
    @EnvironmentObject var state: AppState
    @State private var month = Date.now
    @State private var picked: String?
    @State private var adding: String?

    var body: some View {
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.year, .month], from: month))!
        let count = cal.range(of: .day, in: .month, for: start)!.count
        let lead = (cal.component(.weekday, from: start) + 6) % 7
        let keys = (1...count).map { AppState.dateKey(cal.date(byAdding: .day, value: $0 - 1, to: start)!) }
        let occ: [String: [EventItem]] = Dictionary(grouping: state.events.flatMap { e in
            EventRecurrence.occurrences(e, from: keys.first!, to: keys.last!).map { ($0, e) }
        }, by: \.0).mapValues { $0.map(\.1) }
        Screen(title: month.formatted(.dateTime.month(.wide)), sub: month.formatted(.dateTime.year())) {
            HStack {
                Button { withAnimation(DS.spring) { month = cal.date(byAdding: .month, value: -1, to: month)! } } label: { BigIcon(name: "chevron.left", size: 18) }
                Spacer()
                Button { withAnimation(DS.spring) { month = .now } } label: { Chip(text: "Today") }
                Spacer()
                Button { withAnimation(DS.spring) { month = cal.date(byAdding: .month, value: 1, to: month)! } } label: { BigIcon(name: "chevron.right", size: 18) }
            }
            .buttonStyle(.press).sensoryFeedback(.selection, trigger: month)
            LazyVGrid(columns: Array(repeating: .init(spacing: 6), count: 7), spacing: 6) {
                ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { Text($0.element).font(.caption.bold()).foregroundStyle(Color.dim) }
                ForEach(0..<lead, id: \.self) { _ in Color.clear.frame(height: 48) }
                ForEach(Array(keys.enumerated()), id: \.offset) { i, k in
                    let evs = occ[k] ?? []
                    let isToday = k == state.todayKey
                    Button { withAnimation(DS.spring) { picked = k } } label: {
                        VStack(spacing: 3) {
                            Text("\(i + 1)").font(.headline)
                            HStack(spacing: 2) { ForEach(0..<min(evs.count, 3), id: \.self) { _ in Circle().frame(width: 5, height: 5) } }.frame(height: 5)
                        }
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .foregroundStyle(picked == k || isToday ? Color.paper : .ink)
                        .background(picked == k ? Color.ink : isToday ? Color.dim : Color.clear, in: .rect(cornerRadius: 14))
                    }
                    .buttonStyle(.press)
                }
            }
            if let k = picked {
                MLabel(Fmt.day(k))
                ForEach(occ[k] ?? []) { e in NavigationLink { MeEventDetail(id: e.id) } label: { Row(icon: e.special ? "star.fill" : "calendar", title: e.title) }.buttonStyle(.press) }
                Button { adding = k } label: { Row(icon: "plus", title: "Add a memory") }.buttonStyle(.press)
            }
        }
        .sheet(item: Binding(get: { adding.map { IDBox(id: $0) } }, set: { adding = $0?.id })) { b in MeAddEvent(initialDate: AppState.date(fromKey: b.id) ?? .now) }
    }
}

// MARK: - Event detail (photos, note, tags)

struct MeEventDetail: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var media = EventMediaStore.shared
    let id: String
    @State private var pick: [PhotosPickerItem] = []
    @State private var viewing: EventMedia?
    @State private var note = ""

    var body: some View {
        if let e = state.events.first(where: { $0.id == id }) {
            Screen(title: e.title, sub: Fmt.day(e.date) + (e.recurrence.repeats ? " · \(EventRecurrence.describe(e.recurrence))" : "")) {
                if !e.media.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 10) {
                            ForEach(e.media, id: \.id) { m in
                                Button { viewing = m } label: {
                                    Group {
                                        if let d = media.poster(for: m) ?? media.data(for: m), let img = UIImage(data: d) { Image(uiImage: img).resizable().scaledToFill() } else { Color.hairline }
                                    }
                                    .frame(width: 220, height: 280).clipShape(.rect(cornerRadius: 24))
                                    .overlay { if m.kind == .video { Image(systemName: "play.circle.fill").font(.largeTitle).foregroundStyle(.white) } }
                                }
                                .buttonStyle(.press)
                            }
                        }
                    }
                    .scrollIndicators(.hidden).scrollClipDisabled()
                }
                PhotosPicker(selection: $pick, maxSelectionCount: 10, matching: .images) { Row(icon: "photo.badge.plus", title: "Add photos") }.buttonStyle(.press)
                HStack {
                    ForEach(state.tags(for: e)) { t in Chip(text: t.name, on: true) }
                    Spacer()
                    Button { var x = e; x.special.toggle(); state.updateEvent(x) } label: { BigIcon(name: e.special ? "star.fill" : "star", size: 18) }.buttonStyle(.press)
                }
                MCard {
                    Text("Note").font(.title3.bold())
                    TextField("Write about it…", text: $note, axis: .vertical).font(.title3).lineLimit(3...12)
                        .onSubmit { save(e) }
                }
                Button("Delete event", role: .destructive) { state.deleteEvent(e.id) }.font(.headline).frame(maxWidth: .infinity)
            }
            .onAppear { note = e.note }
            .onDisappear { save(e) }
            .onChange(of: pick) { _, items in
                Task {
                    var x = state.events.first { $0.id == id } ?? e
                    for it in items {
                        if let d = try? await it.loadTransferable(type: Data.self), let img = UIImage(data: d), let j = PhotoSource.jpeg(img) {
                            x.media.append(EventMedia(kind: .image, data: j.base64EncodedString()))
                        }
                    }
                    state.updateEvent(x); pick = []
                    await state.migrateEventMediaToR2()
                }
            }
            .fullScreenCover(item: $viewing) { m in
                GalleryViewer(item: GalleryItem(id: m.id, source: .events, kind: m.kind == .video ? .video : .image, day: e.date, title: e.title,
                                                location: m.r2Key.map { .sealed(key: $0, posterKey: m.posterKey) } ?? .inline(base64: m.data, poster: m.poster), ownerID: e.id))
            }
        }
    }
    private func save(_ e: EventItem) {
        guard var x = state.events.first(where: { $0.id == id }), x.note != note else { return }
        x.note = note; state.updateEvent(x)
    }
}

// MARK: - Voice call

struct MeVoiceCall: View {
    let onEnd: () -> Void
    @EnvironmentObject private var state: AppState
    @StateObject private var listener = SpeechListener()
    @State private var phase: Phase = .starting
    @State private var said = ""
    @State private var router: VoiceRouter?
    @State private var turn: Task<Void, Never>?
    @State private var authorized = false
    @State private var failures = 0
    @State private var pulse = false
    enum Phase { case starting, listening, thinking, speaking, blocked, failed }

    var body: some View {
        VStack(spacing: 30) {
            HStack { Spacer(); Button { finish(); onEnd() } label: { BigIcon(name: "xmark", size: 18) }.buttonStyle(.press) }
            Spacer()
            Circle().fill(Color.ink)
                .frame(width: 180, height: 180)
                .scaleEffect(phase == .speaking ? (pulse ? 1.12 : 0.96) : phase == .listening ? (pulse ? 1.04 : 1) : 0.9)
                .animation(.easeInOut(duration: phase == .speaking ? 0.45 : 1.2).repeatForever(autoreverses: true), value: pulse)
                .overlay { Image(systemName: icon).font(.system(size: 54, weight: .semibold)).foregroundStyle(Color.paper).contentTransition(.symbolEffect(.replace)) }
                .onTapGesture { interrupt() }
                .onAppear { pulse = true }
            Text(AgentConfig.shared.displayName).font(.largeTitle.bold())
            Text(status).font(.title3).foregroundStyle(Color.dim).multilineTextAlignment(.center).lineLimit(5).padding(.horizontal)
            Spacer()
            MButton(title: "End call", icon: "phone.down.fill") { finish(); onEnd() }
        }
        .padding(DS.pad)
        .task { await begin() }
        .onDisappear(perform: finish)
    }

    private var icon: String {
        switch phase { case .listening: "waveform"; case .thinking: "ellipsis"; case .speaking: "speaker.wave.2.fill"; case .blocked, .failed: "mic.slash"; case .starting: "mic" }
    }
    private var status: String {
        switch phase {
        case .starting: return "Connecting…"
        case .listening: return listener.partial.isEmpty ? "Listening" : listener.partial
        case .thinking: return "Thinking…"
        case .speaking: return said
        case .blocked: return "Microphone or speech access is off. Turn it on in Settings."
        case .failed: return "Couldn't reach the assistant. Try again later."
        }
    }

    private static let directive = "YOU ARE BEING SPOKEN ALOUD ON A PHONE CALL. Reply in at most two or three short sentences, the way a person actually talks. Never use markdown, lists or headings. Pick the single most important thing and say that."

    private func begin() async {
        guard await listener.requestAuthorization() else { phase = .blocked; return }
        authorized = true
        VoiceAudioSession.begin()
        router = VoiceRouter(remote: AuraSynth(api: state.api), local: SystemSynth())
        listener.onFinal = { text in answer(text) }
        do { try listener.start(); phase = .listening } catch { phase = .blocked }
    }

    private func answer(_ text: String) {
        turn?.cancel()
        phase = .thinking
        turn = Task {
            let a = AgentConfig.shared
            let info = APIClient.AgentInfo(name: a.displayName, tone: a.tone.directive,
                                           custom: Self.directive + " " + a.custom.trimmingCharacters(in: .whitespacesAndNewlines))
            state.appendVoiceTurn(role: "user", content: text)
            let turns = state.voiceTurns()
            state.chatBusy = true
            defer { state.chatBusy = false }
            var reply: String
            do {
                let out = try await state.runCatrineTurn(query: text, turns: turns, agent: info, maxRounds: 2, timeout: 25)
                if Task.isCancelled { return }
                reply = ChatAction.parse(out.reply).visible
                failures = 0
            } catch is CancellationError { return } catch {
                if Task.isCancelled { return }
                failures += 1
                if failures >= 2 { phase = .failed; return }
                reply = (error as? APIError)?.message ?? error.localizedDescription
            }
            state.appendVoiceTurn(role: "assistant", content: reply)
            said = reply; phase = .speaking
            listener.isMuted = true
            await router?.speak(reply: reply)
            listener.isMuted = false
            if !Task.isCancelled { phase = .listening }
        }
    }

    private func interrupt() {
        guard phase == .speaking || phase == .thinking else { return }
        turn?.cancel(); router?.stop(); listener.isMuted = false; phase = .listening
    }

    private func finish() {
        turn?.cancel(); router?.stop(); listener.stop()
        if authorized { VoiceAudioSession.end(); authorized = false }
    }
}

// MARK: - Settings screens

struct MeProfile: View {
    @EnvironmentObject var state: AppState
    @State private var p = Profile()
    @State private var loaded = false
    @State private var photo: PhotosPickerItem?

    var body: some View {
        Screen(title: p.name.isEmpty ? "Profile" : p.name, sub: [p.role, p.city].filter { !$0.isEmpty }.joined(separator: " · ")) {
            PhotosPicker(selection: $photo, matching: .images) {
                Group {
                    if let d = Data(base64Encoded: p.photoBase64), let img = UIImage(data: d) { Image(uiImage: img).resizable().scaledToFill() }
                    else { Text(p.initials.isEmpty ? "?" : p.initials).font(.system(size: 44, weight: .bold)).foregroundStyle(Color.paper).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.ink) }
                }
                .frame(width: 120, height: 120).clipShape(.circle)
            }
            .frame(maxWidth: .infinity)
            MLabel("About")
            field("person", "Name", \.name); field("briefcase", "Role", \.role); field("text.alignleft", "What you do", \.work)
            field("mappin", "City", \.city); field("house", "Hometown", \.hometown); field("graduationcap", "Education", \.education)
            field("envelope", "Email", \.email); field("phone", "Phone", \.phone)
            MCard {
                Text("About me (the AI reads this)").font(.headline)
                TextField("A few lines about you…", text: $p.about, axis: .vertical).lineLimit(3...10)
            }
            MLabel("Body")
            MCard {
                Picker("Blood group", selection: $p.bloodGroup) { Text("—").tag(""); ForEach(Profile.bloodGroupOptions, id: \.self) { Text($0).tag($0) } }.font(.headline)
                BigStepper(label: "Height", value: p.heightCm.map { "\(Int($0)) cm" } ?? "—", minus: { p.heightCm = (p.heightCm ?? 170) - 1 }, plus: { p.heightCm = (p.heightCm ?? 170) + 1 })
                TextField("Health notes", text: $p.healthNotes, axis: .vertical).lineLimit(2...6)
            }
            MLabel("Goals")
            goals("Short term", \.goalsShort); goals("Mid term", \.goalsMid); goals("Long term", \.goalsLong)
            MLabel("Links")
            field("globe", "Website", \.website); field("camera", "Instagram", \.instagram); field("chevron.left.forwardslash.chevron.right", "GitHub", \.github)
            MButton(title: "Save", icon: "checkmark") { let v = p; state.updateProfile { $0 = v }; Haptics.success() }
        }
        .onAppear { if !loaded { p = state.profile; loaded = true } }
        .onChange(of: photo) { _, it in
            Task { if let d = try? await it?.loadTransferable(type: Data.self), let img = UIImage(data: d) { p.photoBase64 = MeInlineImage.encode(img, maxDimension: 400) ?? "" } }
        }
    }
    private func field(_ icon: String, _ ph: String, _ kp: WritableKeyPath<Profile, String>) -> some View {
        MField(icon: icon, placeholder: ph, text: Binding(get: { p[keyPath: kp] }, set: { p[keyPath: kp] = $0 }))
    }
    private func goals(_ title: String, _ kp: WritableKeyPath<Profile, [String]>) -> some View {
        MeListCard(icon: "target", title: title, items: p[keyPath: kp]) { p[keyPath: kp] = $0 }
    }
}

struct MeAI: View {
    @ObservedObject private var agent = AgentConfig.shared
    @ObservedObject private var ai = AISettingsStore.shared
    @State private var provider: AIProvider = .gemini
    @State private var key = ""
    @State private var label = ""

    var body: some View {
        Screen(title: "AI", sub: "Assistant & keys") {
            MField(icon: "sparkles", placeholder: "Assistant name", text: $agent.name)
            HStack { ForEach(AgentTone.allCases) { t in Button { agent.toneRaw = t.rawValue } label: { Chip(text: t.label, on: agent.tone == t) } } }
                .buttonStyle(.press)
            MCard { Text("Style notes").font(.headline); TextField("How should it talk to you?", text: $agent.custom, axis: .vertical).lineLimit(2...6) }
            MLabel("Your keys")
            if ai.keys.isEmpty { Text("No keys. The built-in default model is used.").foregroundStyle(Color.dim) }
            ForEach(ai.keys) { k in
                MCard {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(k.label.isEmpty ? k.provider.capitalized : k.label).font(.headline)
                            Text("\(k.provider) · \(k.masked) · \(k.models.count) models").font(.subheadline).foregroundStyle(Color.dim)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(get: { k.enabled }, set: { v in Task { await ai.setEnabled(k, v) } })).labelsHidden()
                    }
                }
                .contextMenu {
                    Button("Recheck") { Task { await ai.recheck(k) } }
                    Button("Delete", role: .destructive) { Task { await ai.delete(k) } }
                }
            }
            MCard {
                Text("Add a key").font(.headline)
                Picker("Provider", selection: $provider) { ForEach(AIProvider.allCases) { Text($0.label).tag($0) } }.pickerStyle(.segmented)
                TextField("Label (optional)", text: $label)
                SecureField("API key", text: $key)
                Button(ai.busy ? "Checking…" : "Add key") {
                    Task { if await ai.addKey(provider: provider, label: label, key: key) { key = ""; label = "" } }
                }
                .font(.headline).disabled(key.isEmpty || ai.busy)
                if let e = ai.actionError { Text(e).font(.subheadline) }
            }
            if !ai.keys.isEmpty {
                MLabel("Model per feature")
                ForEach(AIFeature.allCases) { f in
                    MCard {
                        HStack {
                            Text(f.label).font(.headline)
                            Spacer()
                            MeModelMenu(feature: f) { Text($0).font(.subheadline.weight(.semibold)).lineLimit(1) }
                        }
                    }
                }
            }
        }
        .task { await ai.loadIfNeeded() }
    }
}

/// Pick the model for one AI feature. Same menu in Settings → AI and in chat,
/// so both always show the same choice.
struct MeModelMenu<L: View>: View {
    let feature: AIFeature
    @ViewBuilder var label: (String) -> L
    @ObservedObject private var ai = AISettingsStore.shared

    var body: some View {
        Menu {
            Button { Task { await ai.setRoute(feature, to: nil) } } label: {
                if ai.route(for: feature) == nil { Label("Default", systemImage: "checkmark") } else { Text("Default") }
            }
            ForEach(ai.enabledKeys) { k in
                Section(k.label.isEmpty ? k.provider.capitalized : k.label) {
                    ForEach(k.models, id: \.self) { m in
                        let ref = APIClient.AIRouteRef(keyId: k.id, model: m)
                        Button { Task { await ai.setRoute(feature, to: ref) } } label: {
                            if ai.route(for: feature) == ref { Label(m, systemImage: "checkmark") } else { Text(m) }
                        }
                    }
                }
            }
        } label: { label(ai.route(for: feature)?.model ?? "Default") }
        .menuIndicator(.hidden)
        .task { await ai.loadIfNeeded() }
    }
}

/// Connect an online AI app (Wajo, Claude, ChatGPT…) to your notes over MCP.
/// Read-only; locked notes are never shared. Each app gets its own token,
/// revocable here.
struct MeConnections: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var store = MCPConnectionsStore.shared
    @State private var name = ""

    var body: some View {
        Screen(title: "AI connections", sub: "Let an AI app read your notes") {
            MCard {
                Text("Read-only. Your AI can list, search and read notes — never change or delete them. Locked notes are never shared.")
                    .font(.subheadline).foregroundStyle(Color.dim)
            }
            if let fresh = store.fresh {
                MCard(inverted: true) {
                    Text("“\(fresh.name)” is connected").font(.headline)
                    Text("Copy the token now — it won't be shown again. Anyone with it can read your notes until you remove the connection.")
                        .font(.subheadline)
                    copyRow("Server URL", store.endpoint)
                    copyRow("Token (Bearer)", fresh.token)
                    copyRow("URL only (if the app has no token field)", "\(store.endpoint)/\(fresh.token)")
                    Button("Done") { store.fresh = nil }.font(.headline)
                }
            }
            MLabel("Connected apps")
            if store.loaded && store.connections.isEmpty { Text("None yet.").foregroundStyle(Color.dim) }
            ForEach(store.connections) { c in
                MCard {
                    Text(c.name).font(.headline)
                    Text("Added \(c.createdAt.prefix(10)) · " + (c.lastUsedAt.map { "last used \($0.prefix(10))" } ?? "never used"))
                        .font(.subheadline).foregroundStyle(Color.dim)
                }
                .contextMenu { Button("Remove", role: .destructive) { Task { await store.revoke(c) } } }
            }
            if !store.connections.isEmpty {
                Text("Touch and hold a connection to remove it.").font(.footnote).foregroundStyle(Color.dim)
            }
            MCard {
                Text("New connection").font(.headline)
                TextField("App name, e.g. Wajo", text: $name)
                Button(store.busy ? "Creating…" : "Create") {
                    Task { await store.create(name: name, dek: state.vault.dek); if store.fresh != nil { name = "" } }
                }
                .font(.headline).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || store.busy)
                if let e = store.error { Text(e).font(.subheadline) }
            }
        }
        .task { await store.loadIfNeeded() }
    }

    private func copyRow(_ label: String, _ value: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.footnote.weight(.semibold))
                Text(value).font(.footnote.monospaced()).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Button { UIPasteboard.general.string = value } label: { Chip(text: "Copy") }.buttonStyle(.press)
        }
    }
}

struct MeMemory: View {
    @EnvironmentObject var state: AppState
    @State private var query = ""
    @State private var draft = ""
    @State private var kind: MemoryCategory = .other
    @State private var editing: MemoryItem?

    var body: some View {
        let items = state.memory.items.filter { query.isEmpty || $0.content.localizedCaseInsensitiveContains(query) }
            .sorted { ($0.pinned ? 1 : 0, $0.importance, $0.updatedAt) > ($1.pinned ? 1 : 0, $1.importance, $1.updatedAt) }
        Screen(title: "Memory", sub: "\(state.memory.items.count) things it knows") {
            MField(icon: "magnifyingglass", placeholder: "Search", text: $query)
            MCard {
                TextField("Teach it something…", text: $draft, axis: .vertical).font(.title3)
                ScrollView(.horizontal) { HStack { ForEach(MemoryCategory.allCases) { c in Button { kind = c } label: { Chip(text: c.rawValue.capitalized, on: kind == c) } } } }
                    .scrollIndicators(.hidden).buttonStyle(.press)
                Button("Remember") {
                    _ = state.addMemory(MemoryItem(content: draft, category: kind, importance: 3, source: .stated)); draft = ""
                }
                .font(.headline).disabled(draft.isEmpty)
            }
            ForEach(items) { m in
                MCard(inverted: m.pinned) {
                    HStack(alignment: .top) {
                        Text(m.content).font(.headline)
                        Spacer()
                        if m.pinned { Image(systemName: "pin.fill") }
                    }
                    Text("\(m.category.rawValue.capitalized) · importance \(m.importance)").font(.caption).opacity(0.6)
                }
                .onTapGesture { editing = m }
                .contextMenu {
                    Button(m.pinned ? "Unpin" : "Pin to always in context", systemImage: "pin") { var x = m; x.pinned.toggle(); state.updateMemory(x) }
                    Button("Delete", systemImage: "trash", role: .destructive) { state.deleteMemory(m.id) }
                }
            }
        }
        .sheet(item: $editing) { m in MeMemoryEdit(item: m).presentationDetents([.medium]) }
    }
}

struct MeMemoryEdit: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State var item: MemoryItem
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit memory").font(.title.bold()).padding(.top, 20)
            TextField("", text: $item.content, axis: .vertical).font(.title3).padding(16).background(Color.card, in: .rect(cornerRadius: 20))
            BigStepper(label: "Importance", value: "\(item.importance)", minus: { item.importance = max(1, item.importance - 1) }, plus: { item.importance = min(5, item.importance + 1) })
            Toggle("Always in context", isOn: $item.pinned).font(.headline)
            MButton(title: "Save", icon: "checkmark") { state.updateMemory(item); dismiss() }
        }
        .padding(DS.pad)
    }
}

struct MeReminders: View {
    @ObservedObject private var store = ReminderStore.shared
    var body: some View {
        Screen(title: "Reminders", sub: store.enabled ? "On" : "Off") {
            MCard { Toggle("Reminders", isOn: $store.enabled).font(.title3.weight(.semibold)) }
            if store.permissionRefused {
                MCard { Text("Notifications are off for MeOS in iOS Settings.").font(.headline) }
            }
            ForEach(store.reminders, id: \.id) { r in
                MCard {
                    HStack {
                        VStack(alignment: .leading) { Text(r.label).font(.title3.bold()); Text(r.body).font(.subheadline).foregroundStyle(Color.dim).lineLimit(1) }
                        Spacer()
                        Toggle("", isOn: Binding(get: { r.enabled }, set: { store.setEnabled(id: r.id, $0) })).labelsHidden()
                    }
                    HStack {
                        DatePicker("", selection: Binding(
                            get: { Calendar.current.date(from: DateComponents(hour: r.hour, minute: r.minute)) ?? .now },
                            set: { let c = Calendar.current.dateComponents([.hour, .minute], from: $0); store.setTime(id: r.id, hour: c.hour ?? 0, minute: c.minute ?? 0) }
                        ), displayedComponents: .hourAndMinute).labelsHidden()
                        Spacer()
                        Menu {
                            ForEach(ReminderSound.available, id: \.self) { s in Button(s.label) { store.setSound(id: r.id, s) } }
                        } label: { Label(r.sound.label, systemImage: "speaker.wave.2").font(.subheadline.weight(.semibold)) }
                    }
                }
                .disabled(!store.enabled).opacity(store.enabled ? 1 : 0.4)
            }
            MCard {
                HStack {
                    Text("Event reminders sound").font(.headline)
                    Spacer()
                    Menu { ForEach(ReminderSound.available, id: \.self) { s in Button(s.label) { store.eventSound = s } } } label: { Text(store.eventSound.label).font(.subheadline.weight(.semibold)) }
                }
            }
        }
        .task { await store.refreshAuthorization(); if !store.authorized { await store.requestAuthorization() } }
    }
}
