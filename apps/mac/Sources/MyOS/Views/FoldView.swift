import SwiftUI

/// Fold dashboard — a read-only view of the money picture pulled from the Fold app.
/// Fold-home styled: a net-worth hero with a green sparkline + liquid/investments/
/// spend rollup, then accounts and top spends. The snapshot lives in AppState
/// (`myos.fold`) so Mac and iPhone stay in lockstep; Mac also watches
/// Application Support `fold.json` and pushes on every change.
struct FoldView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var prefs = PrefsStore.shared
    @State private var showLogin = false

    private let cols = [GridItem(.adaptive(minimum: 170), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: Gap.screen) {
            HStack(spacing: 8) {
                ScreenTitle(text: "Fold")
                Spacer()
                Button {
                    Task { await state.refreshFold() }
                } label: {
                    if state.foldBusy {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.borderless).tint(Palette.muted)
                .disabled(state.foldBusy)
                .help("Pull latest from Fold")
                if state.fold != nil {
                    Button { prefs.hideFoldNumbers.toggle() } label: {
                        Image(systemName: prefs.hideFoldNumbers ? "eye.slash.fill" : "eye.fill")
                    }
                    .buttonStyle(.borderless).tint(Palette.muted)
                    .help(prefs.hideFoldNumbers ? "Show net worth" : "Hide net worth")
                }
                if state.foldLinked {
                    Button("Sign out") { state.disconnectFold() }
                        .buttonStyle(.borderless)
                } else {
                    Button { showLogin = true } label: { Label("Connect Fold", systemImage: "link") }
                        .buttonStyle(.borderedProminent)
                }
            }
            .knRise(0)

            if let err = state.foldError {
                Text(err).font(.footnote).foregroundStyle(Palette.warning)
            } else if !state.foldLinked, state.fold != nil {
                Text("This is a saved snapshot, not a live pull. Tap Connect Fold, enter the OTP Fold texts you, then refresh. The date only changes after Fold answers.")
                    .font(.footnote).foregroundStyle(Palette.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let f = state.fold { dashboard(f) } else { connectState }
        }
        .onAppear {
            state.restoreFoldIfBare()
            Task { await state.refreshFold() }
        }
        .sheet(isPresented: $showLogin) {
            FoldLoginSheet()
                .environmentObject(state)
                #if os(macOS)
                .frame(width: 420, height: 420)
                #endif
        }
    }

    // MARK: - Connected: the real dashboard

    @ViewBuilder private func dashboard(_ f: FoldData) -> some View {
        // Hero — net worth + sparkline + rollup, Fold-home style. It is the
        // number the tab exists for; that is carried by size and position, not
        // by filling the card with a colour.
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(foldINR(f.netWorth, hidden: prefs.hideFoldNumbers))
                            .font(.largeTitle.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(Palette.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        Text("Net worth").font(.footnote).foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    if f.changeValue != 0 { changeChip(f) }
                }
                if f.history.count > 1 {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(inr(f.history.max() ?? 0))
                                .font(.caption2.weight(.semibold)).monospacedDigit()
                                .foregroundStyle(Palette.faint)
                            Spacer()
                            if !f.changeLabel.isEmpty {
                                Text(f.changeLabel)
                                    .font(.caption2.weight(.semibold)).tracking(0.3)
                                    .foregroundStyle(Palette.faint)
                            }
                        }
                        Sparkline(values: f.history).frame(height: 92)
                        Text(inr(f.history.min() ?? 0))
                            .font(.caption2.weight(.semibold)).monospacedDigit()
                            .foregroundStyle(Palette.faint)
                    }
                }
                Divider().overlay(Palette.border)
                HStack(spacing: 0) {
                    heroStat("Liquid", inr(f.liquid))
                    heroStat("Investments", inr(f.investments))
                    heroStat("This month", inr(f.spentThisMonth))
                }
                // Only show the stocks/MF breakdown when it adds information —
                // identical "Investments" + "Stocks" rows are noise.
                let showStocks = f.stocksValue > 0 && abs(f.stocksValue - f.investments) > 1
                let showMf = f.mfValue > 0
                if f.debt > 0 || showStocks || showMf {
                    HStack(spacing: 0) {
                        if showStocks { heroStat("Stocks", inr(f.stocksValue)) }
                        if showMf { heroStat("Mutual funds", inr(f.mfValue)) }
                        if f.debt > 0 { heroStat("Debt", inr(f.debt)) }
                    }
                }
            }
        }
        .knRise(1)

        if !f.banks.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(text: "Where your money is")
                    ForEach(f.banks) { b in
                        HStack(spacing: 8) {
                            Text(b.name).font(.footnote.weight(.medium)).foregroundStyle(Palette.text)
                            Text("••\(b.last4)").font(.caption2).foregroundStyle(Palette.faint)
                            Spacer()
                            Text(inr(b.balance)).font(.footnote.weight(.semibold)).monospacedDigit()
                                .foregroundStyle(Palette.muted)
                        }
                    }
                }
            }
            
            .knRise(2)
        }

        if !f.topSpends.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(text: "Top spends this month")
                    ForEach(f.topSpends.filter { !FoldSpend.isNonSpend($0.category) }) { s in
                        HStack {
                            Text(s.category).font(.footnote).foregroundStyle(Palette.text)
                            Spacer()
                            Text(inr(s.amount)).font(.footnote.weight(.semibold)).monospacedDigit()
                                .foregroundStyle(Palette.muted)
                        }
                    }
                }
            }
            
            .knRise(3)
        }

        Button { Task { await state.refreshFold() } } label: {
            HStack(spacing: 6) {
                Image(systemName: state.foldBusy ? "arrow.clockwise" : "circle.fill")
                    .font(.system(size: state.foldBusy ? 11 : 6))
                    .foregroundStyle(Palette.green)
                Text(FoldCaption.line(asOf: f.asOf, linked: state.foldLinked, error: state.foldError))
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(Palette.muted)
        }
        .buttonStyle(.plain)
        .knRise(4)
    }

    private func changeChip(_ f: FoldData) -> some View {
        let up = f.changeValue >= 0
        let c = up ? Palette.green : Palette.warning
        return HStack(spacing: 3) {
            Image(systemName: up ? "arrow.up.right" : "arrow.down.right").font(.caption2.weight(.bold))
            Text(inr(abs(f.changeValue))).font(.caption.weight(.semibold)).monospacedDigit()
            Text("· \(Int((abs(f.changePercent) * 100).rounded()))%").font(.caption2).opacity(0.85)
        }
        .foregroundStyle(c)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(c.opacity(0.14), in: Capsule())
    }

    private func heroStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased()).font(.caption2.weight(.heavy)).tracking(0.6)
                .foregroundStyle(Palette.faint)
            Text(value).font(.subheadline.weight(.semibold)).monospacedDigit()
                .foregroundStyle(Palette.text).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Not connected yet

    @ViewBuilder private var connectState: some View {
        LazyVGrid(columns: cols, spacing: 12) {
            FoldTile(label: "Net worth", accent: Palette.action)
            FoldTile(label: "Bank balance", accent: Palette.green)
            FoldTile(label: "Investments", accent: Palette.blue)
            FoldTile(label: "Spent this month", accent: Palette.warning)
        }
        .knRise(1)

        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(text: "Connect your Fold account")
                Text("Sign in with the same phone OTP Fold texts you. Refresh then pulls net worth, banks and this month’s spends.")
                    .font(.footnote).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Button { showLogin = true } label: {
                    Label("Connect with phone OTP", systemImage: "iphone")
                }
                .buttonStyle(.borderless)
            }
        }
        .knRise(2)
    }

    private func inr(_ v: Double) -> String { foldINR(v, hidden: false) }
}

/// Categories Fold may put in the debit rollup that are not real spends.
enum FoldSpend {
    static func isNonSpend(_ category: String) -> Bool {
        let c = category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return c == "returns" || c == "return" || c == "refund" || c == "refunds"
            || c == "cashback" || c == "interest" || c == "dividend"
    }
}

/// Rupee formatter for the Fold dashboard (en_IN grouping). Masks to "₹ ••••"
/// when privacy mode is on. A free function so it is unit-testable.
func foldINR(_ v: Double, hidden: Bool) -> String {
    if hidden { return "₹ ••••" }
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.locale = Locale(identifier: "en_IN")
    f.maximumFractionDigits = 0
    return "₹" + (f.string(from: NSNumber(value: v.rounded())) ?? "0")
}


/// The snapshot Fold writes to `fold.json` (Application Support on Mac, bundled on iOS).
/// Also synced as `myos.fold` so the phone sees the same numbers the Mac just wrote.
struct FoldData: Codable, Equatable {
    var asOf: String = ""
    var currency: String = "INR"
    var netWorth: Double = 0
    var liquid: Double = 0
    var investments: Double = 0
    var debt: Double = 0
    var spentThisMonth: Double = 0
    var stocksValue: Double = 0
    var mfValue: Double = 0
    var changeValue: Double = 0
    var changePercent: Double = 0
    var changeLabel: String = ""
    var history: [Double] = []
    var banks: [Bank] = []
    var topSpends: [Spend] = []

    struct Bank: Codable, Identifiable, Equatable {
        var id = UUID()
        var name: String
        var last4: String
        var balance: Double
        enum CodingKeys: String, CodingKey { case name, last4, balance }
        static func == (l: Bank, r: Bank) -> Bool {
            l.name == r.name && l.last4 == r.last4 && l.balance == r.balance
        }
    }
    struct Spend: Codable, Identifiable, Equatable {
        var id = UUID()
        var category: String
        var amount: Double
        enum CodingKeys: String, CodingKey { case category, amount }
        static func == (l: Spend, r: Spend) -> Bool {
            l.category == r.category && l.amount == r.amount
        }
    }

    static var fileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("MyOS/fold.json")
    }

    static func loadFromDisk() -> FoldData? {
        guard let url = fileURL, let d = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(FoldData.self, from: d)
    }

    static func load() -> FoldData? { loadFromDisk() }

    /// Remove this device's cached snapshot.
    ///
    /// Not part of the state blob, so logging out does not touch it otherwise —
    /// and the path is fixed, not per-account, so the next person to sign in on
    /// this Mac had the previous user's balances loaded straight back off disk
    /// and pushed into their own synced state by `healFoldSnapshot`.
    static func deleteFromDisk() {
        guard let url = fileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static func save(_ data: FoldData) {
        guard let url = fileURL else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let d = try? enc.encode(data) { try? d.write(to: url, options: .atomic) }
    }
}

/// A dashboard stat placeholder — a labelled empty value used only in the connect state.
private struct FoldTile: View {
    let label: String
    var accent: Color = Palette.action

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Text(label.uppercased())
                    .font(.caption2.weight(.heavy)).tracking(0.5)
                    .foregroundStyle(Palette.faint)
                Text("—").font(.title2.weight(.semibold)).foregroundStyle(accent)
                Text("Connect Fold").font(.caption2).foregroundStyle(Palette.faint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Phone OTP against Fold's own auth. Tokens stay in the device Keychain.
private struct FoldLoginSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var phone = FoldClient.linkedPhone.isEmpty ? "+91" : FoldClient.linkedPhone
    @State private var otp = ""
    @State private var sent = false
    @FocusState private var focus: Field?
    private enum Field { case phone, otp }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Fold texts a 6-digit code to this number. Refresh then pulls live balances.")
                    .font(.footnote).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 6) {
                    KFieldLabel(text: "Phone")
                    TextField("+91 98XXXXXXXX", text: $phone)
                        .textFieldStyle(.plain).font(.body).foregroundStyle(Palette.text)
                        .focused($focus, equals: .phone)
                        #if os(iOS)
                        .keyboardType(.phonePad)
                        #endif
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .background(Palette.background, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(Palette.border, lineWidth: 1))
                }
                if sent {
                    VStack(alignment: .leading, spacing: 6) {
                        KFieldLabel(text: "OTP")
                        TextField("123456", text: $otp)
                            .textFieldStyle(.plain).font(.body).foregroundStyle(Palette.text)
                            .focused($focus, equals: .otp)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                            .padding(.horizontal, 14).padding(.vertical, 12)
                            .background(Palette.background, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .strokeBorder(Palette.border, lineWidth: 1))
                    }
                }
                if let err = state.foldError {
                    Text(err).font(.footnote).foregroundStyle(Palette.warning)
                }
                if sent {
                    Button {
                        Task {
                            if await state.verifyFoldOTP(phone, otp: otp) { dismiss() }
                        }
                    } label: { Label(state.foldBusy ? "Checking…" : "Verify & pull", systemImage: "checkmark") }
                    .buttonStyle(.borderedProminent)
                    .disabled(otp.count < 4 || state.foldBusy)
                } else {
                    Button {
                        Task {
                            await state.sendFoldOTP(phone)
                            if state.foldError == nil { sent = true; focus = .otp }
                        }
                    } label: { Label(state.foldBusy ? "Sending…" : "Send OTP", systemImage: "message") }
                    .buttonStyle(.borderedProminent)
                    .disabled(phone.filter(\.isNumber).count < 10 || state.foldBusy)
                }
                Spacer()
            }
            .padding(20)
            .background(Palette.background)
            .navigationTitle("Connect Fold")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}
