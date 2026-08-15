import SwiftUI

/// Fold dashboard — a read-only view of the money picture pulled from the Fold app.
/// Fold-home styled: a net-worth hero with a green sparkline + liquid/investments/
/// spend rollup, then accounts and top spends. Reads a local snapshot (`fold.json`
/// in Application Support on Mac, or bundled with the app on iOS); shows a
/// "Connect Fold" state until one exists.
struct FoldView: View {
    @Environment(\.openURL) private var openURL
    @State private var fold: FoldData? = FoldData.load()

    private let cols = [GridItem(.adaptive(minimum: 170), spacing: 12)]
    private let setupURL = URL(string: "https://fold.money/mcp")!

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Text("Fold").font(.system(size: 24, weight: .semibold)).foregroundStyle(Palette.text)
                Spacer()
                if fold == nil {
                    Button { openURL(setupURL) } label: { Label("Connect Fold", systemImage: "link") }
                        .buttonStyle(KPrimaryButtonStyle())
                }
            }
            .knRise(0)

            if let f = fold { dashboard(f) } else { connectState }
        }
        .onAppear { fold = FoldData.load() }
    }

    // MARK: - Connected: the real dashboard

    @ViewBuilder private func dashboard(_ f: FoldData) -> some View {
        // Hero — net worth + sparkline + rollup, Fold-home style.
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(inr(f.netWorth))
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(Palette.text)
                        Text("Net worth").font(.system(size: 13)).foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    if f.changeValue != 0 { changeChip(f) }
                }
                if f.history.count > 1 {
                    Sparkline(values: f.history).frame(height: 92)
                    if !f.changeLabel.isEmpty {
                        Text("Last \(f.changeLabel)")
                            .font(.system(size: 10, weight: .semibold)).tracking(0.5)
                            .foregroundStyle(Palette.faint)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                Divider().overlay(Palette.border)
                HStack(spacing: 0) {
                    heroStat("Liquid", inr(f.liquid))
                    heroStat("Investments", inr(f.investments))
                    heroStat("Spent · mo", inr(f.spentThisMonth))
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
                            Text(b.name).font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.text)
                            Text("••\(b.last4)").font(.system(size: 11)).foregroundStyle(Palette.faint)
                            Spacer()
                            Text(inr(b.balance)).font(.system(size: 13, weight: .semibold)).monospacedDigit()
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
                    ForEach(f.topSpends) { s in
                        HStack {
                            Text(s.category).font(.system(size: 13)).foregroundStyle(Palette.text)
                            Spacer()
                            Text(inr(s.amount)).font(.system(size: 13, weight: .semibold)).monospacedDigit()
                                .foregroundStyle(Palette.muted)
                        }
                    }
                }
            }
            .knRise(3)
        }

        HStack(spacing: 6) {
            Image(systemName: "circle.fill").font(.system(size: 6)).foregroundStyle(Palette.green)
            Text("From Fold · \(f.asOf)").font(.system(size: 11))
        }
        .foregroundStyle(Palette.faint)
        .knRise(4)
    }

    private func changeChip(_ f: FoldData) -> some View {
        let up = f.changeValue >= 0
        let c = up ? Palette.green : Palette.red
        return HStack(spacing: 3) {
            Image(systemName: up ? "arrow.up.right" : "arrow.down.right").font(.system(size: 10, weight: .bold))
            Text(inr(abs(f.changeValue))).font(.system(size: 12, weight: .semibold)).monospacedDigit()
            Text("· \(Int((abs(f.changePercent) * 100).rounded()))%").font(.system(size: 11)).opacity(0.85)
        }
        .foregroundStyle(c)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(c.opacity(0.14), in: Capsule())
    }

    private func heroStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased()).font(.system(size: 9, weight: .heavy, design: .rounded)).tracking(0.6)
                .foregroundStyle(Palette.faint)
            Text(value).font(.system(size: 15, weight: .semibold, design: .rounded)).monospacedDigit()
                .foregroundStyle(Palette.text).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Not connected yet

    @ViewBuilder private var connectState: some View {
        LazyVGrid(columns: cols, spacing: 12) {
            FoldTile(label: "Net worth", accent: Palette.brand)
            FoldTile(label: "Bank balance", accent: Palette.green)
            FoldTile(label: "Investments", accent: Palette.blue)
            FoldTile(label: "Spent this month", accent: Palette.red)
        }
        .knRise(1)

        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(text: "Connect your Fold account")
                Text("MyOS no longer tracks money by hand — Fold does it for you. Once connected, your net worth, accounts, balances and spends appear here.")
                    .font(.system(size: 13)).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Button { openURL(setupURL) } label: {
                    Label("Set up the Fold connection", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(KGhostButtonStyle())
            }
        }
        .knRise(2)
    }

    private func inr(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_IN")
        f.maximumFractionDigits = 0
        return "₹" + (f.string(from: NSNumber(value: v.rounded())) ?? "0")
    }
}

/// A minimal green area sparkline (Fold-home style).
private struct Sparkline: View {
    let values: [Double]
    var color: Color = Palette.brand

    var body: some View {
        GeometryReader { geo in
            let minV = values.min() ?? 0
            let maxV = values.max() ?? 1
            let range = max(maxV - minV, 1)
            let stepX = values.count > 1 ? geo.size.width / CGFloat(values.count - 1) : geo.size.width
            let pts = values.enumerated().map { i, v in
                CGPoint(x: CGFloat(i) * stepX,
                        y: geo.size.height * (1 - CGFloat((v - minV) / range)))
            }
            ZStack {
                Path { p in
                    guard let first = pts.first else { return }
                    p.move(to: CGPoint(x: first.x, y: geo.size.height))
                    p.addLine(to: first)
                    for pt in pts.dropFirst() { p.addLine(to: pt) }
                    p.addLine(to: CGPoint(x: pts.last!.x, y: geo.size.height))
                    p.closeSubpath()
                }
                .fill(LinearGradient(colors: [color.opacity(0.22), color.opacity(0.0)],
                                     startPoint: .top, endPoint: .bottom))
                Path { p in
                    guard let first = pts.first else { return }
                    p.move(to: first)
                    for pt in pts.dropFirst() { p.addLine(to: pt) }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

/// The snapshot Fold writes to `fold.json` (Application Support on Mac, bundled on iOS).
struct FoldData: Codable {
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

    struct Bank: Codable, Identifiable {
        var id = UUID()
        var name: String
        var last4: String
        var balance: Double
        enum CodingKeys: String, CodingKey { case name, last4, balance }
    }
    struct Spend: Codable, Identifiable {
        var id = UUID()
        var category: String
        var amount: Double
        enum CodingKeys: String, CodingKey { case category, amount }
    }

    static func load() -> FoldData? {
        let dec = JSONDecoder()
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        if let url = base?.appendingPathComponent("MyOS/fold.json"),
           let d = try? Data(contentsOf: url),
           let data = try? dec.decode(FoldData.self, from: d) { return data }
        if let url = Bundle.main.url(forResource: "fold", withExtension: "json"),
           let d = try? Data(contentsOf: url),
           let data = try? dec.decode(FoldData.self, from: d) { return data }
        return nil
    }
}

/// A dashboard stat placeholder — a labelled empty value used only in the connect state.
private struct FoldTile: View {
    let label: String
    var accent: Color = Palette.brand

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Text(label.uppercased())
                    .font(.system(size: 11, weight: .heavy, design: .rounded)).tracking(0.5)
                    .foregroundStyle(Palette.faint)
                Text("—").font(.system(size: 22, weight: .semibold, design: .rounded)).foregroundStyle(accent)
                Text("Connect Fold").font(.system(size: 11)).foregroundStyle(Palette.faint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
