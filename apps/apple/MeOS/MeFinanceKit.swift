import SwiftUI
import Charts

// MARK: - Finance interface kit
//
// Finance has its own surface language inside MeOS: near-black page, charcoal
// cards separated by a hairline, white content, and only three semantic
// accents. It deliberately reuses the existing Palette, DS spring and type
// roles so it still reads as one operating system.

enum FinStyle {
    static let radius: CGFloat = 16
    static let radiusSmall: CGFloat = 10
    static let pageMax: CGFloat = 1180
    static let cardPadding: CGFloat = 18
    static let gap: CGFloat = 14

    static var surface: Color { Palette.surface }
    static var elevated: Color { Palette.surfaceElevated }
    static var surfaceElevated: Color { Palette.surfaceElevated }
    static var border: Color { Palette.border }
    static var positive: Color { Palette.green }
    static var negative: Color { Palette.negative }
    static var info: Color { Palette.blue }
    static var warning: Color { Palette.orange }

    static func moneyColor(_ value: Int64) -> Color {
        if value > 0 { return Palette.text }
        if value < 0 { return Palette.negative }
        return Palette.muted
    }

    static func changeColor(_ value: Double?) -> Color {
        guard let value else { return Palette.muted }
        if value > 0 { return Palette.green }
        if value < 0 { return Palette.negative }
        return Palette.muted
    }

    static func toneColor(_ tone: FinInsightTone) -> Color {
        switch tone {
        case .positive: Palette.green
        case .negative: Palette.negative
        case .neutral: Palette.muted
        case .information: Palette.blue
        }
    }

    static func certaintyColor(_ certainty: FinCertainty) -> Color {
        switch certainty {
        case .verified: Palette.green
        case .calculated: Palette.blue
        case .estimated: Palette.orange
        case .unknown: Palette.muted
        }
    }

    /// A restrained categorical ramp for charts. Green carries the main series;
    /// the rest are ink opacity steps and the two other semantic accents.
    static func sliceColor(_ index: Int) -> Color {
        let colors: [Color] = [
            Palette.green,
            Palette.blue,
            Palette.orange,
            Palette.text.opacity(0.72),
            Palette.text.opacity(0.46),
            Palette.text.opacity(0.28),
            Palette.green.opacity(0.55),
            Palette.blue.opacity(0.5),
        ]
        return colors[index % colors.count]
    }
}

// MARK: - Page scaffold

struct FinPage<Content: View>: View {
    let title: String
    var sub: String?
    var badge: String?
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                #if os(macOS)
                MacBack()
                #endif
                header
                content
            }
            .padding(.horizontal, DS.pad)
            .padding(.top, 18)
            .padding(.bottom, 52)
            .frame(maxWidth: FinStyle.pageMax, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .scrollIndicators(.hidden)
        .pageBackground()
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 31, weight: .bold))
                        .tracking(-0.6)
                    if let badge {
                        FinBadge(text: badge, tint: FinStyle.warning)
                    }
                }
                if let sub {
                    Text(sub)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
        }
        .padding(.bottom, 4)
    }
}

// MARK: - Cards

struct FinCard<Content: View>: View {
    var padding: CGFloat = FinStyle.cardPadding
    var elevated: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(elevated ? FinStyle.elevated : FinStyle.surface,
                        in: RoundedRectangle(cornerRadius: FinStyle.radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: FinStyle.radius, style: .continuous)
                    .strokeBorder(FinStyle.border, lineWidth: 1)
            }
    }
}

struct FinCardHeader: View {
    let title: String
    var sub: String?
    var icon: String?
    var trailing: AnyView?

    init(_ title: String, sub: String? = nil, icon: String? = nil) {
        self.title = title; self.sub = sub; self.icon = icon; self.trailing = nil
    }

    init<T: View>(_ title: String, sub: String? = nil, icon: String? = nil, @ViewBuilder trailing: () -> T) {
        self.title = title; self.sub = sub; self.icon = icon; self.trailing = AnyView(trailing())
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.muted)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .semibold))
                if let sub {
                    Text(sub).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.muted)
                }
            }
            Spacer(minLength: 8)
            if let trailing { trailing }
        }
    }
}

// MARK: - Metrics

struct FinStatTile: View {
    let label: String
    let value: String
    var sub: String?
    var delta: Double?
    var deltaLabel: String?
    var tone: FinInsightTone = .neutral
    var icon: String?
    var emphasis: Bool = false
    var valueTint: Color? = nil

    var body: some View {
        FinCard {
            HStack(alignment: .top, spacing: 8) {
                Text(label.uppercased())
                    .font(.system(size: 9.5, weight: .bold))
                    .tracking(0.9)
                    .foregroundStyle(Palette.faint)
                Spacer(minLength: 4)
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.faint)
                }
            }
            Text(value)
                .font(.system(size: emphasis ? 31 : 22, weight: .bold, design: .rounded))
                .tracking(-0.7)
                .monospacedDigit()
                .foregroundStyle(valueTint ?? FinStyle.moneyColor(0))
                .contentTransition(.numericText())
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            HStack(spacing: 6) {
                if let delta {
                    Image(systemName: delta > 0 ? "arrow.up.right" : delta < 0 ? "arrow.down.right" : "minus")
                        .font(.system(size: 9, weight: .bold))
                    Text(FinanceFormat.signedPercent(delta))
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                }
                if let sub {
                    Text(sub).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.muted).lineLimit(1)
                } else if let deltaLabel, delta != nil {
                    Text(deltaLabel).font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
            }
            .foregroundStyle(delta != nil ? FinStyle.changeColor(delta) : Palette.muted)
        }
    }
}

struct FinMoneyText: View {
    let paise: Int64
    var showSign: Bool = false
    var size: CGFloat = 15
    var weight: Font.Weight = .semibold
    var color: Color?

    var body: some View {
        Text(FinanceFormat.inr(paise, showSign: showSign))
            .font(.system(size: size, weight: weight, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(color ?? FinStyle.moneyColor(paise))
    }
}

struct FinBadge: View {
    let text: String
    var tint: Color = Palette.muted
    var filled: Bool = false
    var icon: String?

    var body: some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.system(size: 8, weight: .bold)) }
            Text(text.uppercased())
                .font(.system(size: 8.5, weight: .bold))
                .tracking(0.7)
        }
        .foregroundStyle(filled ? Palette.legibleInk(on: tint) : tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(filled ? tint : tint.opacity(0.10),
                    in: Capsule())
        .overlay {
            if !filled { Capsule().strokeBorder(tint.opacity(0.22), lineWidth: 1) }
        }
    }
}

struct FinChipButton: View {
    let text: String
    var on: Bool = false
    var tint: Color = Palette.text
    var icon: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon { Image(systemName: icon).font(.system(size: 10, weight: .semibold)) }
                Text(text).font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(on ? Palette.background : (tint == Palette.text ? Palette.text : tint))
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(on ? (tint == Palette.text ? Palette.text : tint) : Color.clear,
                        in: Capsule())
            .overlay {
                Capsule().strokeBorder(on ? Color.clear : FinStyle.border, lineWidth: 1)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.press)
    }
}

struct FinRangeBar: View {
    @Binding var selection: FinRangePreset
    var presets: [FinRangePreset] = [.m1, .m3, .m6, .y1, .y3, .y5, .all]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(presets) { preset in
                Button {
                    withAnimation(DS.spring) { selection = preset }
                } label: {
                    Text(preset.label)
                        .font(.system(size: 10.5, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(selection == preset ? Palette.background : Palette.muted)
                        .frame(minWidth: 30)
                        .frame(height: 26)
                        .padding(.horizontal, 5)
                        .background(selection == preset ? Palette.text : Color.clear, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(FinStyle.surfaceElevated, in: Capsule())
    }
}

struct FinProgressBar: View {    let progress: Double
    var tint: Color = Palette.green
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { g in
            Capsule().fill(Palette.text.opacity(0.08))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(tint)
                        .frame(width: max(4, g.size.width * min(max(progress, 0), 1)))
                }
        }
        .frame(height: height)
    }
}

struct FinSectionTitle: View {
    let text: String
    var detail: String?
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text.uppercased())
                .font(.system(size: 9.5, weight: .bold))
                .tracking(1.0)
                .foregroundStyle(Palette.faint)
            Spacer()
            if let detail {
                Text(detail).font(.system(size: 10.5, weight: .medium)).foregroundStyle(Palette.faint)
            }
        }
        .padding(.top, 4)
    }
}

struct FinEmptyState<Actions: View>: View {
    let icon: String
    let title: String
    let detail: String
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Palette.faint)
            Text(title).font(.system(size: 17, weight: .semibold))
            Text(detail)
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            HStack(spacing: 10) { actions }.padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 42)
        .padding(.horizontal, 20)
    }
}

extension FinEmptyState where Actions == EmptyView {
    init(icon: String, title: String, detail: String) {
        self.init(icon: icon, title: title, detail: detail) { EmptyView() }
    }
}

// MARK: - Form fields

struct FinField: View {
    let label: String
    var placeholder: String = ""
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var secure: Bool = false
    var multiline: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(Palette.faint)
            HStack(spacing: 8) {
                if multiline {
                    TextField(placeholder, text: $text, axis: .vertical)
                        .lineLimit(2...5)
                        .font(.system(size: 14))
                        .textFieldStyle(.plain)
                } else if secure {
                    SecureField(placeholder, text: $text)
                        .font(.system(size: 14)).textFieldStyle(.plain)
                } else {
                    TextField(placeholder, text: $text)
                        .font(.system(size: 14)).textFieldStyle(.plain)
                        .keyboardType(keyboard)
                        .textInputAutocapitalization(keyboard == .default ? .sentences : .never)
                        .autocorrectionDisabled(keyboard != .default)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, multiline ? 10 : 0)
            .frame(minHeight: multiline ? 64 : 40)
            .background(FinStyle.elevated, in: RoundedRectangle(cornerRadius: FinStyle.radiusSmall, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: FinStyle.radiusSmall, style: .continuous)
                    .strokeBorder(FinStyle.border, lineWidth: 1)
            }
        }
    }
}

struct FinPickerCard<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(Palette.faint)
            content
                .font(.system(size: 14))
                .padding(.horizontal, 12)
                .frame(height: 40)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(FinStyle.elevated, in: RoundedRectangle(cornerRadius: FinStyle.radiusSmall, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: FinStyle.radiusSmall, style: .continuous)
                        .strokeBorder(FinStyle.border, lineWidth: 1)
                }
        }
    }
}

struct FinToggleRow: View {
    let label: String
    var detail: String?
    @Binding var isOn: Bool
    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 13, weight: .semibold))
                if let detail { Text(detail).font(.system(size: 11)).foregroundStyle(Palette.muted) }
            }
        }
        .tint(Palette.green)
    }
}

struct FinSheetHeader: View {
    let title: String
    var sub: String?
    var saveTitle: String = "Save"
    var canSave: Bool = true
    var destructive: Bool = false
    let save: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button { dismiss() } label: {
                Text("Cancel").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.muted)
            }
            .buttonStyle(.plain)
            Spacer()
            VStack(spacing: 1) {
                Text(title).font(.system(size: 15, weight: .semibold))
                if let sub { Text(sub).font(.system(size: 10)).foregroundStyle(Palette.muted) }
            }
            Spacer()
            Button(action: save) {
                Text(saveTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(destructive ? Palette.negative : Palette.green)
                    .opacity(canSave ? 1 : 0.35)
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Palette.surface)
        .overlay(alignment: .bottom) { Rectangle().fill(FinStyle.border).frame(height: 1) }
    }
}

struct FinDefinitionList: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(FinanceEngine.definitions, id: \.0) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.0).font(.system(size: 12, weight: .semibold))
                    Text(item.1).font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
            }
        }
    }
}

// MARK: - Controls

struct FinSearchBar: View {
    @Binding var text: String
    var placeholder: String = "Search"
    var focusRequest: Int = 0
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.muted)
            TextField(placeholder, text: $text)
                .font(.system(size: 13))
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .focused($focused)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.muted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(FinStyle.elevated, in: Capsule())
        .overlay { Capsule().strokeBorder(FinStyle.border, lineWidth: 1) }
        .onChange(of: focusRequest) { _, _ in focused = true }
    }
}

struct FinPrimaryButton: View {
    let title: String
    var icon: String?
    var enabled: Bool = true
    var tone: Color = Palette.text
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon).font(.system(size: 11, weight: .semibold)) }
                Text(title).font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(Palette.background)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(tone, in: Capsule())
            .opacity(enabled ? 1 : 0.35)
        }
        .buttonStyle(.press)
        .disabled(!enabled)
    }
}

struct FinURLBox: Identifiable {
    let id = UUID()
    let url: URL
}

struct FinShareSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 16) {
            FinSheetHeader(title: "Export ready", sub: url.lastPathComponent, saveTitle: "Done", save: { dismiss() })
            VStack(spacing: 12) {
                Image(systemName: "doc.text")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(Palette.muted)
                Text("CSV written from the records currently in view. No derived values are included.")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.center)
                ShareLink(item: url) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Share / Save file")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.background)
                    .padding(.horizontal, 18).frame(height: 40)
                    .background(Palette.text, in: Capsule())
                }
            }
            .padding(24)
            Spacer()
        }
        .padding(.top, 1)
        .background(Palette.background)
        .frame(minWidth: 380, minHeight: 300)
    }
}

// MARK: - Charts

struct FinNetWorthChart: View {
    let points: [FinNetWorthPoint]
    var height: CGFloat = 220
    @State private var selected: Date?

    private func date(_ key: String) -> Date { FinanceCal.date(key) ?? Date() }

    private var selectedPoint: FinNetWorthPoint? {
        guard let selected else { return nil }
        return points.min { abs(date($0.date).timeIntervalSince(selected)) < abs(date($1.date).timeIntervalSince(selected)) }
    }

    var body: some View {
        if points.count < 2 {
            FinEmptyState(icon: "chart.xyaxis.line",
                          title: "Not enough history yet",
                          detail: "Add an account and a few transactions. Month-end net worth is then calculated from those records.")
                .frame(height: height)
        } else {
            Chart {
                ForEach(points) { p in
                    AreaMark(x: .value("Date", date(p.date)),
                             y: .value("Net worth", Double(p.netPaise) / 100))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(
                            LinearGradient(colors: [Palette.green.opacity(0.20), Palette.green.opacity(0.01)],
                                           startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Date", date(p.date)),
                             y: .value("Net worth", Double(p.netPaise) / 100))
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .foregroundStyle(Palette.green)
                }
                if let selected, let p = selectedPoint {
                    RuleMark(x: .value("Selected", date(p.date)))
                        .foregroundStyle(Palette.text.opacity(0.25))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(FinanceCal.display(p.date)).font(.system(size: 9, weight: .semibold)).foregroundStyle(Palette.muted)
                                Text(FinanceFormat.inr(p.netPaise)).font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.text)
                            }
                            .padding(7)
                            .background(Palette.surfaceElevated, in: RoundedRectangle(cornerRadius: 8))
                            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(FinStyle.border) }
                        }
                }
            }
            .chartXSelection(value: $selected)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(Palette.text.opacity(0.06))
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(FinanceFormat.compact(Int64(v * 100)))
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(Palette.faint)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { value in
                    AxisGridLine().foregroundStyle(Palette.text.opacity(0.04))
                    AxisValueLabel {
                        if let d = value.as(Date.self) {
                            Text(d.formatted(.dateTime.month(.abbreviated).year(.twoDigits)))
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(Palette.faint)
                        }
                    }
                }
            }
            .frame(height: height)
        }
    }
}

struct FinCashflowChart: View {
    let points: [FinMonthPoint]
    var height: CGFloat = 200

    var body: some View {
        if points.allSatisfy({ $0.incomePaise == 0 && $0.expensePaise == 0 }) {
            FinEmptyState(icon: "chart.bar", title: "No cash flow yet",
                          detail: "Income and expenses appear here once transactions exist.")
                .frame(height: height)
        } else {
            Chart {
                ForEach(points) { p in
                    BarMark(x: .value("Month", FinanceCal.shortMonth(p.month)),
                            y: .value("Amount", Double(p.incomePaise) / 100))
                        .foregroundStyle(by: .value("Kind", "Income"))
                        .position(by: .value("Kind", "Income"))
                        .cornerRadius(3)
                    BarMark(x: .value("Month", FinanceCal.shortMonth(p.month)),
                            y: .value("Amount", Double(p.expensePaise) / 100))
                        .foregroundStyle(by: .value("Kind", "Expenses"))
                        .position(by: .value("Kind", "Expenses"))
                        .cornerRadius(3)
                }
            }
            .chartForegroundStyleScale(["Income": Palette.green, "Expenses": Palette.orange])
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(Palette.text.opacity(0.06))
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(FinanceFormat.compact(Int64(v * 100)))
                                .font(.system(size: 9)).foregroundStyle(Palette.faint)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let s = value.as(String.self) {
                            Text(s).font(.system(size: 9)).foregroundStyle(Palette.faint)
                        }
                    }
                }
            }
            .chartLegend(position: .top, alignment: .leading, spacing: 12)
            .frame(height: height)
        }
    }
}

struct FinDonutChart: View {
    let slices: [FinCategorySlice]
    var height: CGFloat = 190

    var body: some View {
        if slices.isEmpty {
            FinEmptyState(icon: "chart.pie", title: "No spending", detail: "Category spending will appear here.")
                .frame(height: height)
        } else {
            Chart(Array(slices.prefix(8).enumerated()), id: \.element.id) { index, slice in
                SectorMark(angle: .value("Amount", slice.paise),
                           innerRadius: .ratio(0.62),
                           angularInset: 1.5)
                    .cornerRadius(3)
                    .foregroundStyle(FinStyle.sliceColor(index))
            }
            .chartLegend(.hidden)
            .frame(height: height)
            .overlay {
                VStack(spacing: 1) {
                    Text("SPENT").font(.system(size: 8, weight: .bold)).tracking(0.8).foregroundStyle(Palette.faint)
                    Text(FinanceFormat.compact(slices.reduce(0) { $0 + $1.paise }))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(Palette.text)
                }
                .allowsHitTesting(false)
            }
        }
    }
}

struct FinMiniLine: View {
    let values: [Int64]
    var tint: Color = Palette.green
    var height: CGFloat = 36

    var body: some View {
        if values.count < 2 {
            Rectangle().fill(Palette.text.opacity(0.05)).frame(height: height).clipShape(Capsule())
        } else {
            Chart(Array(values.enumerated()), id: \.offset) { i, v in
                LineMark(x: .value("i", i), y: .value("v", Double(v) / 100))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                    .foregroundStyle(tint)
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: height)
        }
    }
}

// MARK: - Shared rows

struct FinAccountLine: View {
    let summary: FinAccountSummary
    var showInstitution: Bool = true

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: summary.account.type.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(summary.account.type.isLiability ? Palette.negative : Palette.muted)
                .frame(width: 28, height: 28)
                .background(FinStyle.elevated, in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.account.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                HStack(spacing: 5) {
                    if showInstitution, !summary.account.institution.isEmpty {
                        Text(summary.account.institution).lineLimit(1)
                    }
                    if summary.account.type.isLiability {
                        Text("debt")
                    }
                    if summary.account.isDemo {
                        Text("demo")
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 8)
            FinMoneyText(paise: summary.balance.paise, size: 13)
        }
        .contentShape(.rect)
    }
}

struct FinStatusDot: View {
    let color: Color
    var body: some View {
        Circle().fill(color).frame(width: 6, height: 6)
    }
}

// MARK: - Export

enum FinExport {
    static func write(_ text: String, name: String) -> URL? {
        let safe = name.replacingOccurrences(of: " ", with: "-").lowercased()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safe)-\(FinanceCal.today()).csv")
        do {
            try text.data(using: .utf8)?.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}

