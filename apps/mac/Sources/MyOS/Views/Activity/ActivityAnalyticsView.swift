import SwiftUI
import Charts

/// The deep view: where the time actually went.
///
/// Today's card answers "what am I doing and what next". This answers a
/// different question — "where did my time go, am I wasting it, what pattern is
/// hurting me" — so it deliberately does not repeat the Today card. The one
/// thing both show is the single recommendation, because that is the point of
/// the whole feature.
struct ActivityAnalyticsView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var coordinator = ActivityCoordinator.shared
    @State private var range: ActivityRange = .today
    @State private var editingApp: AppUsage?
    /// Shared with the Today card, so switching device in one place does not
    /// disagree with the other.
    @AppStorage("myos.activity.deviceFilter") private var deviceRaw = ActivityDeviceFilter.all.rawValue

    private var device: Binding<ActivityDeviceFilter> {
        Binding(get: { ActivityDeviceFilter(rawValue: deviceRaw) ?? .all },
                set: { deviceRaw = $0.rawValue })
    }

    enum ActivityRange: String, CaseIterable, Identifiable {
        case today, week, month
        var id: String { rawValue }
        var label: String {
            switch self {
            case .today: return "Today"
            case .week:  return "Week"
            case .month: return "Month"
            }
        }
        var days: Int {
            switch self {
            case .today: return 1
            case .week:  return 7
            case .month: return 30
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Gap.screen) {
            header
            if !coordinator.enabled && state.activity.events.isEmpty {
                offState
            } else if isEmpty {
                emptyState
            } else {
                content
            }
        }
        .sheet(item: $editingApp) { usage in
            AppRuleSheet(usage: usage)
                .environmentObject(state)
        }
    }

    // MARK: Data

    private var dayKeys: [String] {
        (0..<range.days).reversed().map { AppState.addDays(-$0, to: state.todayKey) }
    }

    private var daySummary: ActivitySummary {
        state.activitySummaryLive(state.todayKey, device: device.wrappedValue)
    }
    private var multiDay: ActivityWeekSummary {
        ActivityEngine.weekSummary(doc: state.activity, days: dayKeys, device: device.wrappedValue)
    }

    private var totalSeconds: Int { range == .today ? daySummary.totalSeconds : multiDay.totalSeconds }
    private var isEmpty: Bool { totalSeconds == 0 }

    private func seconds(_ p: ProductivityType) -> Int {
        range == .today ? daySummary.seconds(p) : multiDay.seconds(p)
    }
    private func seconds(_ d: DeviceType) -> Int {
        range == .today ? daySummary.seconds(d) : multiDay.seconds(d)
    }
    private var apps: [AppUsage] { range == .today ? daySummary.apps : multiDay.apps }

    // MARK: Chrome

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionLabel(text: "Productivity", accent: .activity)
            HStack(alignment: .firstTextBaseline, spacing: Space.md) {
                Text(Fmt.duration(totalSeconds))
                    .font(.myDisplay).monospacedDigit()
                    .foregroundStyle(Palette.text)
                Text(range.label)
                    .font(.myBody)
                    .foregroundStyle(Palette.muted)
                Spacer(minLength: 0)
            }
            Picker("", selection: $range) {
                ForEach(ActivityRange.allCases) { r in Text(r.label).tag(r) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if range != .today {
                Picker("Device", selection: device) {
                    ForEach(ActivityDeviceFilter.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if range == .today {
            screenTimeCard
        } else {
            devices
            breakdown
            dailyCard
            appsCard
        }
        timeManagement
        verdictCard
    }

    /// Today gets the full Screen Time read in one card — device, hours, worth,
    /// kinds of time, and the apps themselves — because that is one question
    /// asked at four resolutions, not four cards.
    private var screenTimeCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Gap.row) {
                SectionTitle(text: "Where the time went")
                ScreenTimeBreakdown(summary: daySummary,
                                    device: device,
                                    appLimit: 10,
                                    chartHeight: 140,
                                    showsCategories: true,
                                    onApp: { editingApp = $0 })
                if device.wrappedValue != .mac && daySummary.seconds(.iphone) == 0 {
                    Text("iPhone activity needs a Shortcuts automation per app — iOS gives no app permission to read another app's usage. Set it up in Settings.")
                        .font(.myCaption)
                        .foregroundStyle(Palette.faint)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Tap an app to change what it counts as.")
                    .font(.myCaption).foregroundStyle(Palette.faint)
            }
        }
    }

    // MARK: Devices

    private var devices: some View {
        Card {
            VStack(alignment: .leading, spacing: Gap.row) {
                SectionTitle(text: "Devices")
                DeviceSplit(mac: seconds(.mac), iphone: seconds(.iphone))
                if seconds(.iphone) == 0 {
                    Text("iPhone activity needs a Shortcuts automation per app — iOS gives no app permission to read another app's usage. Set it up in Settings.")
                        .font(.myCaption)
                        .foregroundStyle(Palette.faint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Breakdown

    private var breakdown: some View {
        Card {
            VStack(alignment: .leading, spacing: Gap.row) {
                SectionTitle(text: "Productivity")
                WorthBreakdown(productive: seconds(.productive),
                               neutral: seconds(.neutral),
                               distracting: seconds(.distracting))
            }
        }
    }

    /// Week and month get a day-by-day bar instead of an hour-by-hour one —
    /// same shape of question at a different resolution.
    private var dailyCard: some View {
        let week = multiDay
        return Card {
            VStack(alignment: .leading, spacing: Gap.row) {
                SectionTitle(text: range == .week ? "Day by day" : "Last 30 days")
                Chart {
                    ForEach(dayKeys, id: \.self) { day in
                        let total = week.dailyTotals[day] ?? 0
                        let productive = week.dailyProductive[day] ?? 0
                        BarMark(x: .value("Day", day),
                                y: .value("Minutes", max(0, total - productive) / 60))
                            .foregroundStyle(Palette.muted.opacity(0.45))
                        BarMark(x: .value("Day", day),
                                y: .value("Minutes", productive / 60))
                            .foregroundStyle(Palette.productive)
                    }
                }
                .chartYAxis { AxisMarks(position: .leading) }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: range == .week ? 7 : 5)) { value in
                        AxisValueLabel {
                            if let day = value.as(String.self) {
                                Text(range == .week ? Fmt.weekdayInitial(day) : String(day.suffix(2)))
                                    .font(.myCaption)
                                    .foregroundStyle(Palette.faint)
                            }
                        }
                    }
                }
                .frame(height: 150)
                Text("Green is productive time. The rest is everything else.")
                    .font(.myCaption).foregroundStyle(Palette.faint)
            }
        }
    }

    // MARK: Apps

    private var appsCard: some View {
        let shown = Array(apps.prefix(10))
        let peak = shown.first?.seconds ?? 0
        return Card {
            VStack(alignment: .leading, spacing: Gap.row) {
                HStack {
                    SectionTitle(text: "Apps")
                    Spacer()
                    Text("Tap to reclassify")
                        .font(.myCaption).foregroundStyle(Palette.faint)
                }
                ForEach(shown) { usage in
                    Button { editingApp = usage } label: {
                        AppUsageRow(usage: usage, peak: peak).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if apps.count > shown.count {
                    Text("+ \(apps.count - shown.count) more")
                        .font(.myCaption).foregroundStyle(Palette.faint)
                }
            }
        }
    }

    // MARK: Time management

    private var timeManagement: some View {
        let insights = range == .today ? ActivityInsights.insights(daySummary) : weekInsights
        return Group {
            if !insights.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: Gap.screen) {
                        SectionTitle(text: "Time management")
                        ForEach(insights) { TimeInsightRow(insight: $0) }
                    }
                }
            }
        }
    }

    /// Over a week or a month the useful observations are different ones — a
    /// single day's strongest hour is noise at that scale.
    private var weekInsights: [TimeInsight] {
        let week = multiDay
        let read = ActivityInsights.weekIntelligence(this: week, previous: nil)
        var out: [TimeInsight] = []
        if let leak = read.biggestLeak { out.append(leak) }
        if let window = read.bestWindow { out.append(window) }
        if let longest = week.longestFocus {
            out.append(TimeInsight(title: "Longest focus block",
                                   detail: "\(Fmt.duration(longest.seconds)) in \(longest.appName).",
                                   productivity: .productive))
        }
        if week.daysTracked > 0 {
            let perDay = week.switches / max(1, week.daysTracked)
            out.append(TimeInsight(title: "Context switching",
                                   detail: "\(week.switches) app switches across \(week.daysTracked) tracked days — about \(perDay) a day.",
                                   productivity: perDay >= 40 ? .distracting : .neutral))
        }
        return out
    }

    // MARK: Verdict + the one action

    @ViewBuilder
    private var verdictCard: some View {
        if range == .today {
            let read = ActivityInsights.dayIntelligence(summary: daySummary,
                                                        current: state.liveActivity,
                                                        todos: state.todayPriorities,
                                                        now: Date())
            if let verdict = read.verdict {
                Card {
                    VStack(alignment: .leading, spacing: Gap.row) {
                        VerdictBlock(heading: "Today's verdict", verdict: verdict, line: read.verdictLine)
                        if let action = read.action { ActionCallout(action: action) }
                    }
                }
            }
        } else {
            let read = ActivityInsights.weekIntelligence(this: multiDay, previous: nil)
            if let verdict = read.verdict {
                Card {
                    VStack(alignment: .leading, spacing: Gap.row) {
                        VerdictBlock(heading: range == .week ? "This week's verdict" : "This month's verdict",
                                     verdict: verdict, line: read.verdictLine)
                        if !read.nextWeek.isEmpty {
                            ActionCallout(action: ActivityAction(kind: .nextMove, text: read.nextWeek))
                        }
                    }
                }
            }
        }
    }

    // MARK: Empty states

    private var offState: some View {
        Card {
            VStack(alignment: .leading, spacing: Gap.row) {
                SectionTitle(text: "Not tracking yet")
                Text("MyOS records which app is in front of you on this Mac, and for how long — the app, never what's in it. Nothing is recorded until you turn it on.")
                    .font(.myBody).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Start tracking") { coordinator.setEnabled(true) }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.action)
                    .foregroundStyle(Accent.green.ink)
            }
        }
    }

    private var emptyState: some View {
        Card {
            VStack(alignment: .leading, spacing: Space.sm) {
                SectionTitle(text: "Nothing recorded")
                Text(range == .today
                     ? "Nothing recorded yet today."
                     : "No activity recorded in the last \(range.days) days.")
                    .font(.myBody).foregroundStyle(Palette.faint)
            }
        }
    }
}

/// Reclassify one app, permanently. What MyOS guesses is a starting point; what
/// Berjil says an app is worth wins, and applies backwards over what is already
/// recorded so the breakdown does not disagree with the rule.
struct AppRuleSheet: View {
    let usage: AppUsage
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var category: ActivityCategory
    @State private var productivity: ProductivityType

    init(usage: AppUsage) {
        self.usage = usage
        _category = State(initialValue: usage.category)
        _productivity = State(initialValue: usage.productivity)
    }

    var body: some View {
        let content = ScrollView {
            VStack(alignment: .leading, spacing: Gap.screen) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(usage.appName).font(.myDisplay).foregroundStyle(Palette.text)
                    Text(Fmt.duration(usage.seconds)).font(.myBody).foregroundStyle(Palette.muted)
                }

                VStack(alignment: .leading, spacing: Space.sm) {
                    SectionTitle(text: "Counts as")
                    Picker("", selection: $productivity) {
                        ForEach(ProductivityType.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden()
                }

                VStack(alignment: .leading, spacing: Space.sm) {
                    SectionTitle(text: "Category")
                    Picker("", selection: $category) {
                        ForEach(ActivityCategory.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                }

                PrimaryButton(title: "Save") {
                    state.setAppRule(appId: usage.appId, appName: usage.appName,
                                     category: category, productivity: productivity)
                    dismiss()
                }
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.faint)
                    .frame(maxWidth: .infinity)
            }
            .padding(Space.xl)
        }
        .background(Palette.background)

        #if os(iOS)
        content.presentationDetents([.medium, .large])
        #else
        content.frame(width: 420, height: 460)
        #endif
    }
}
