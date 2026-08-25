import SwiftUI
import Charts

/// The deep view: where the time actually went.
///
/// Today's card answers "what am I doing and what next". This answers a
/// different question — "where did my time go, am I wasting it, what pattern is
/// hurting me" — so it deliberately does not repeat the Today card. The one
/// thing both show is the single recommendation, because that is the point of
/// the whole feature.
///
/// Every number on screen comes from ONE `Read`, computed once per render and
/// passed down. It used to be a set of computed properties, which meant a body
/// pass rebuilt the whole day — or, on the week and month ranges, walked thirty
/// days of sessions — six or seven times over. That is what made the tab lurch
/// every time a session ticked.
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

    /// One render's worth of numbers. Whichever range is showing, exactly one
    /// of `day` and `week` is real and everything else reads off it.
    private struct Read {
        var range: ActivityRange
        var day: ActivitySummary
        var week: ActivityWeekSummary
        var dayKeys: [String]

        var isToday: Bool { range == .today }
        var totalSeconds: Int { isToday ? day.totalSeconds : week.totalSeconds }
        var isEmpty: Bool { totalSeconds == 0 }
        var apps: [AppUsage] { isToday ? day.apps : week.apps }
        func seconds(_ p: ProductivityType) -> Int { isToday ? day.seconds(p) : week.seconds(p) }
        func seconds(_ d: DeviceType) -> Int { isToday ? day.seconds(d) : week.seconds(d) }
    }

    private func read() -> Read {
        let keys = (0..<range.days).reversed().map { AppState.addDays(-$0, to: state.todayKey) }
        let filter = device.wrappedValue
        // Only the one the range actually needs is computed; the other is empty.
        let day = range == .today
            ? state.activitySummaryLive(state.todayKey, device: filter)
            : ActivitySummary(day: state.todayKey)
        let week = range == .today
            ? ActivityWeekSummary()
            : ActivityEngine.weekSummary(doc: state.activity, days: keys, device: filter)
        return Read(range: range, day: day, week: week, dayKeys: keys)
    }

    var body: some View {
        let read = read()
        return VStack(alignment: .leading, spacing: Gap.screen) {
            header(read)
            if !coordinator.enabled && state.activity.events.isEmpty {
                offState
            } else if read.isEmpty {
                emptyState
            } else {
                content(read)
            }
        }
        .sheet(item: $editingApp) { usage in
            AppRuleSheet(usage: usage)
                .environmentObject(state)
        }
    }

    // MARK: Chrome

    /// No "Productivity" heading here. The tab is already called Productivity
    /// in the sidebar and again as the screen title — a third one in the same
    /// column read as a duplicated header, which it was.
    private func header(_ read: Read) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionLabel(text: "Screen time", accent: .activity)
            HStack(alignment: .firstTextBaseline, spacing: Space.md) {
                Text(Fmt.duration(read.totalSeconds))
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
    private func content(_ read: Read) -> some View {
        if read.isToday {
            screenTimeCard(read)
        } else {
            devices(read)
            breakdown(read)
            dailyCard(read)
            appsCard(read)
        }
        timeManagement(read)
        verdictCard(read)
    }

    /// Today gets the full Screen Time read in one card — device, hours, worth,
    /// kinds of time, and the apps themselves — because that is one question
    /// asked at four resolutions, not four cards.
    private func screenTimeCard(_ read: Read) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Gap.row) {
                SectionTitle(text: "Where the time went")
                ScreenTimeBreakdown(summary: read.day,
                                    device: device,
                                    appLimit: 10,
                                    chartHeight: 140,
                                    showsCategories: true,
                                    onApp: { editingApp = $0 })
                if device.wrappedValue != .mac && read.day.seconds(.iphone) == 0 {
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

    private func devices(_ read: Read) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Gap.row) {
                SectionTitle(text: "Devices")
                DeviceSplit(mac: read.seconds(.mac), iphone: read.seconds(.iphone))
                if read.seconds(.iphone) == 0 {
                    Text("iPhone activity needs a Shortcuts automation per app — iOS gives no app permission to read another app's usage. Set it up in Settings.")
                        .font(.myCaption)
                        .foregroundStyle(Palette.faint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Breakdown

    private func breakdown(_ read: Read) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Gap.row) {
                SectionTitle(text: "Productive vs not")
                WorthBreakdown(productive: read.seconds(.productive),
                               neutral: read.seconds(.neutral),
                               distracting: read.seconds(.distracting))
            }
        }
    }

    /// Week and month get a day-by-day bar instead of an hour-by-hour one —
    /// same shape of question at a different resolution.
    private func dailyCard(_ read: Read) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Gap.row) {
                SectionTitle(text: range == .week ? "Day by day" : "Last 30 days")
                Chart {
                    ForEach(read.dayKeys, id: \.self) { day in
                        let total = read.week.dailyTotals[day] ?? 0
                        let productive = read.week.dailyProductive[day] ?? 0
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

    private func appsCard(_ read: Read) -> some View {
        let shown = Array(read.apps.prefix(10))
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
                if read.apps.count > shown.count {
                    Text("+ \(read.apps.count - shown.count) more")
                        .font(.myCaption).foregroundStyle(Palette.faint)
                }
            }
        }
    }

    // MARK: Time management

    @ViewBuilder
    private func timeManagement(_ read: Read) -> some View {
        let insights = read.isToday ? ActivityInsights.insights(read.day) : weekInsights(read)
        if !insights.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: Gap.screen) {
                    SectionTitle(text: "Time management")
                    ForEach(insights) { TimeInsightRow(insight: $0) }
                }
            }
        }
    }

    /// Over a week or a month the useful observations are different ones — a
    /// single day's strongest hour is noise at that scale.
    private func weekInsights(_ read: Read) -> [TimeInsight] {
        let week = read.week
        let intelligence = ActivityInsights.weekIntelligence(this: week, previous: nil)
        var out: [TimeInsight] = []
        if let leak = intelligence.biggestLeak { out.append(leak) }
        if let window = intelligence.bestWindow { out.append(window) }
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
    private func verdictCard(_ read: Read) -> some View {
        if read.isToday {
            let intelligence = ActivityInsights.dayIntelligence(summary: read.day,
                                                                current: state.liveActivity,
                                                                todos: state.todayPriorities,
                                                                now: Date())
            if let verdict = intelligence.verdict {
                Card {
                    VStack(alignment: .leading, spacing: Gap.row) {
                        VerdictBlock(heading: "Today's verdict", verdict: verdict, line: intelligence.verdictLine)
                        if let action = intelligence.action { ActionCallout(action: action) }
                    }
                }
            }
        } else {
            let intelligence = ActivityInsights.weekIntelligence(this: read.week, previous: nil)
            if let verdict = intelligence.verdict {
                Card {
                    VStack(alignment: .leading, spacing: Gap.row) {
                        VerdictBlock(heading: range == .week ? "This week's verdict" : "This month's verdict",
                                     verdict: verdict, line: intelligence.verdictLine)
                        if !intelligence.nextWeek.isEmpty {
                            ActionCallout(action: ActivityAction(kind: .nextMove, text: intelligence.nextWeek))
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
