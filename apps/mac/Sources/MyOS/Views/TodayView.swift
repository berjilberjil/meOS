import SwiftUI
#if os(macOS)
import AppKit
#endif

struct TodayView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var order = TodaySection.OrderSignal.shared
    /// News + suggestions fetch state — observed by those two cards only, so a
    /// refresh or a chat reply never rebuilds the whole page.
    @ObservedObject private var newsUI = NewsUIStore.shared
    @ObservedObject private var suggestUI = SuggestUIStore.shared
    @ObservedObject private var signals = UISignals.shared
    @Environment(\.openURL) private var openURL
    var go: (NavTab) -> Void
    /// Set when something outside owns which day is on screen — on iOS
    /// `TodayPager` gives each day its own page (and its own scroll position),
    /// so the day must come from there. nil means this view owns it and pages
    /// itself, which is what the Mac does with a trackpad swipe.
    var externalDate: Binding<String>? = nil
    /// Marks the header and each section as scroll targets, so a pager can keep
    /// every day lined up on the same section. Off on Mac, which has one page.
    var sectionAnchors = false

    @State private var expandedNews: Set<String> = []
    @State private var editingMeal: MealKey?
    @State private var showStreakCal = false
    /// The day this page is showing when nobody outside is driving it.
    @State private var ownDate: String = ""
    /// `todayKey` is derived from the clock, not published, so midnight is
    /// observed via the system day-change note — not via an `AppState` tick.
    /// (The old 20s live-activity broadcast used to drag this along for free.)
    @State private var lastKnownToday: String = ""

    /// The day the whole page is showing. Every card reads this, so the screen
    /// is always one coherent day rather than cards disagreeing.
    private var selectedDate: String {
        let d = externalDate?.wrappedValue ?? ownDate
        return d.isEmpty ? state.todayKey : d
    }

    private func setDate(_ d: String) {
        if let external = externalDate { external.wrappedValue = d } else { ownDate = d }
    }

    /// Identity of the header as a scroll target. Sections use their own ids.
    static let headerAnchor = "today.header"

    var body: some View {
        let sections = TodaySection.ordered()
        VStack(alignment: .leading, spacing: Gap.screen) {
            todayHeader.knRise(0).id(Self.headerAnchor)
                // Deliberately NOT on the outer stack: two `.sheet` modifiers on
                // the same view means only one of them presents.
                    ForEach(Array(sections.enumerated()), id: \.element.id) { idx, section in
                // Each section hands its own colour and fill down; the card
                // types themselves stay unaware they are on Today.
                Group {
                    if section == .intake {
                        // The hero sits on the canvas with extra air under it
                        // so the rest of the page recedes — wherever reorder
                        // puts it.
                        todaySection(section)
                            .padding(.bottom, Space.section)
                    } else {
                        todaySection(section)
                    }
                }
                .cardAccent(section.accent)
                .knRise(idx + 1)
            }
            #if os(macOS)
            settingsCard.knRise(7)
            #else
            // Settings is the last thing on the page rather than a toolbar gear.
            iosSettingsRow.knRise(7)
            #endif
        }
        .modifier(ScrollAnchors(enabled: sectionAnchors))
        .dayPager(date: $ownDate, today: state.todayKey, enabled: externalDate == nil)
        // Observed so a reorder in Settings redraws immediately; `ordered()` is
        // a plain function call SwiftUI cannot depend on by itself.
        .onChange(of: order.version) { _, _ in }
        .onAppear { if ownDate.isEmpty { ownDate = state.todayKey }; lastKnownToday = state.todayKey }
        // Seeded once and never re-synced, so a Mac left open overnight kept
        // showing — and writing to — yesterday: tapping Breakfast logged the meal
        // against the old key, ticking the workout marked the old day done.
        .onChange(of: state.todayKey) { old, new in
            lastKnownToday = new
            if ownDate == old { ownDate = new }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            let t = state.todayKey
            if ownDate == lastKnownToday { ownDate = t }
            lastKnownToday = t
        }
        .task {
            if newsUI.result == nil { await state.fetchNews() }
        }
        .sheet(item: $editingMeal) { meal in
            MealLogEditorSheet(date: selectedDate, meal: meal,
                               initialItems: state.mealEditorItems(date: selectedDate, meal: meal))
        }
        .sheet(isPresented: $showStreakCal) { streakCalendarSheet }
        // Tapped a meal reminder. On appear as well as on change, because from
        // a killed app the route is delivered before this page exists.
        .onAppear { consumeMeal() }
        .onChange(of: signals.pendingMeal) { _, _ in consumeMeal() }
    }

    /// Open the meal editor a notification asked for.
    ///
    /// Guarded to the live page: the pager keeps three days built at once, so
    /// without this the same tap would raise three sheets — and two of them
    /// would be logging against the wrong day.
    private func consumeMeal() {
        guard selectedDate == state.todayKey, let meal = signals.pendingMeal else { return }
        signals.pendingMeal = nil
        editingMeal = meal
    }

    @ViewBuilder
    private func todaySection(_ section: TodaySection) -> some View {
        switch section {
        case .focusNow:
            ActivityIntelligenceCard(day: selectedDate, go: go)
        case .activity:
            ActivityStepsCard(day: selectedDate, showsCalendar: false)
        case .weight:
            WeightCard(day: selectedDate)
        case .intake:
            DayMacroHero.make(state: state, day: selectedDate)
        case .meals:
            // Snapshot: a meal log rebuilds this grid, nothing else on the page.
            MealsGridView(tiles: MealKey.allCases.map(mealTileData),
                          onTap: { Haptics.tap(); editingMeal = $0 })
        case .workout:
            WorkoutChecklistCard(day: selectedDate)
        case .comingUp:
            ComingUpView(rows: state.nextEvents.map(comingUpRow), onOpen: { go(.events) })
        case .bodyPhotos:
            #if os(iOS)
            BodyPhotosCard()
            #else
            ProgressPhotosCard()
            #endif
        case .watchLog:
            WatchLogCard(day: selectedDate)
        case .focus:
            FocusCard(day: selectedDate, showsCalendar: false)
        case .news:
            NewsSectionView(
                result: newsUI.result, busy: newsUI.busy, error: newsUI.error,
                expanded: expandedNews,
                onToggle: { id in
                    if expandedNews.contains(id) { expandedNews.remove(id) } else { expandedNews.insert(id) }
                },
                onRefresh: { Task { await state.fetchNews() } },
                onAsk: askAboutNews,
                onOpenLink: { openURL($0) }
            )
        }
    }

    private func mealTileData(_ meal: MealKey) -> MealTileData {
        let items = state.mealDisplayItems(date: selectedDate, meal: meal)
        return MealTileData(meal: meal,
                            state: state.mealState(selectedDate, meal),
                            names: items.compactMap { state.food($0.foodId)?.name })
    }

    private func comingUpRow(_ e: EventItem) -> ComingUpRow {
        let tag = state.primaryTag(for: e)
        return ComingUpRow(id: e.id, title: e.title, special: e.special,
                           countdown: eventCountdown(e),
                           icon: tag?.symbol ?? "calendar",
                           tint: tag?.color ?? Palette.action)
    }

    // MARK: - Coming up (next life events)

    private func eventCountdown(_ e: EventItem) -> String {
        guard let d = state.daysUntil(e.date) else { return Fmt.day(e.date) }
        switch d {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case -1: return "Yesterday"
        case let n where n > 1: return "in \(n) days"
        default: return "\(-d) days ago"
        }
    }

    // MARK: - Tech + finance news (two columns, tap a story to expand)

    private let techCats: Set<String> = ["tech", "ai"]
    private let financeCats: Set<String> = ["markets", "india", "finance", "crypto"]

    private func askAboutNews(_ item: NewsResult.Item) {
        var p = "Explain this news and what it means for me and my finance content: \(item.title). \(item.summary)"
        if let d = item.detail, !d.isEmpty { p += " \(d)" }
        state.askMentor(p)
    }

    // MARK: - AI "what to do now"

    private var suggestionsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles").font(.footnote.weight(.bold))
                        .foregroundStyle(Palette.action)
                    SectionTitle(text: "What to do now")
                    Spacer()
                    Button { Task { await state.fetchSuggestions() } } label: {
                        HStack(spacing: 5) {
                            if suggestUI.busy { ProgressView().controlSize(.small) }
                            Image(systemName: "arrow.clockwise").font(.caption2.weight(.bold))
                        }
                    }
                    .buttonStyle(.borderless)
                    .disabled(suggestUI.busy)
                    .help("Refresh suggestions")
                }

                if let s = suggestUI.result {
                    if !s.headline.isEmpty {
                        Text(s.headline).font(.footnote.weight(.semibold)).foregroundStyle(Palette.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(Array(s.suggestions.enumerated()), id: \.element.id) { i, item in
                        suggestionRow(index: i + 1, item: item)
                    }
                } else if suggestUI.busy {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Reading your day…").font(.footnote).foregroundStyle(Palette.muted)
                    }
                    .padding(.vertical, 6)
                } else if let err = suggestUI.error {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(err, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(Palette.attention)
                        Button("Try again") { Task { await state.fetchSuggestions() } }
                            .buttonStyle(.bordered)
                    }
                } else {
                    Button { Task { await state.fetchSuggestions() } } label: {
                        Label("Get today's read", systemImage: "sparkles")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private func suggestionRow(index: Int, item: SuggestResult.Item) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: areaIcon(item.area))
                .font(.footnote.weight(.bold)).foregroundStyle(areaColor(item.area))
                .frame(width: 30, height: 30)
                .background(areaColor(item.area).opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(item.title).font(.footnote.weight(.semibold)).foregroundStyle(Palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                    impactTag(item.impact)
                }
                Text(item.why).font(.caption).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }

    private func impactTag(_ impact: String) -> some View {
        let color: Color = impact == "high" ? Palette.warning : (impact == "medium" ? Palette.muted : Palette.faint)
        return Text(impact.uppercased())
            .font(.caption2.weight(.heavy)).tracking(0.5)
            .foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
    }

    private func areaIcon(_ area: String) -> String {
        switch area {
        case "money": return "indianrupeesign.circle.fill"
        case "fitness": return "figure.run"
        case "content": return "play.rectangle.fill"
        case "career": return "briefcase.fill"
        case "mind": return "brain.head.profile"
        default: return "sparkles"
        }
    }
    private func areaColor(_ area: String) -> Color {
        switch area {
        case "money": return Palette.green
        case "fitness": return Palette.blue
        case "content": return Palette.information
        case "career": return Palette.attention
        case "mind": return Palette.information
        default: return Palette.action
        }
    }

    /// Weekday of the page's date — "Friday", or "Today"/"Yesterday" nearby.
    private var pagedWeekdayName: String {
        let d = selectedDate
        if d == state.todayKey { return weekdayName }
        return DayPaging.label(d, today: state.todayKey)
    }

    private var pagedPrettyDate: String {
        let d = selectedDate
        guard d != state.todayKey, let parsed = AppState.date(fromKey: d) else { return prettyDate }
        let f = DateFormatter(); f.dateFormat = "d MMMM yyyy"
        return f.string(from: parsed)
    }

    /// The header as values: greeting, day, streak snapshot. A data tick that
    /// changes none of it skips the row via `Equatable`.
    private var todayHeader: some View {
        let n = state.stepStreak
        let todayHit = state.steps(on: state.todayKey) >= state.stepGoals.daily
        return TodayHeaderView(
            greeting: greeting,
            name: state.profile.name,
            weekday: pagedWeekdayName,
            prettyDate: pagedPrettyDate,
            isToday: selectedDate == state.todayKey,
            streak: n,
            todayHit: todayHit,
            mark: todayHit ? state.stepDay(state.todayKey) : (n > 0 ? .pending : .none),
            onToday: { withAnimation(.knNormal) { setDate(state.todayKey) } },
            onFitness: { go(.fitness) },
            onCalendar: { showStreakCal = true }
        )
    }

    private var streakCalendarSheet: some View {
        NavigationStack {
            StepStreakCalendar(
                viewedDate: .constant(state.todayKey),
                isPresented: $showStreakCal,
                wide: true,
                onSelect: { _ in
                    showStreakCal = false
                    go(.fitness)
                }
            )
            .padding(16)
            #if os(iOS)
            .navigationTitle("Streak")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showStreakCal = false }
                        .font(.body.weight(.semibold)).foregroundStyle(Palette.action)
                }
            }
            #endif
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        .presentationBackground(Palette.background)
        #else
        .frame(width: 360, height: 420)
        #endif
    }

    private var productivityCard: some View {
        let todayVideos = state.watch.filter { $0.addedAt.hasPrefix(state.todayKey) }
        let openNotes = state.watch.filter { $0.watched && $0.takeaway.trimmingCharacters(in: .whitespaces).isEmpty }.count
        return Button {
            #if os(macOS)
            go(.productivity)
            #endif
        } label: {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        SectionTitle(text: "Today")
                        Spacer()
                        Text("\(todayVideos.count)")
                            .font(.title.weight(.semibold))
                            .foregroundStyle(Palette.text).monospacedDigit()
                    }
                    prodBar(label: "Logged", value: todayVideos.isEmpty ? 0 : 1, detail: todayVideos.isEmpty ? "No videos yet" : "\(todayVideos.count) video\(todayVideos.count == 1 ? "" : "s")")
                    prodBar(label: "Takeaways", value: openNotes == 0 && !state.watch.isEmpty ? 1 : 0,
                            detail: openNotes == 0 ? "Clear" : "\(openNotes) still open")
                    Text("Same log as Productivity on Mac.")
                        .font(.caption2).foregroundStyle(Palette.faint)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func prodBar(label: String, value: Double, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.caption2.weight(.semibold)).foregroundStyle(Palette.muted)
                Spacer()
                Text(detail).font(.caption2).foregroundStyle(Palette.faint)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.surfaceElevated).frame(height: 5)
                    Capsule().fill(Palette.text).frame(width: max(4, g.size.width * value), height: 5)
                }
            }
            .frame(height: 5)
        }
    }

    #if os(iOS)
    /// Bottom-of-Today entry into Settings. A plain labelled row, the way a
    /// grouped settings link reads.
    private var iosSettingsRow: some View {
        Button { UISignals.shared.openSettings = true } label: {
            Card {
                HStack(spacing: 10) {
                    Image(systemName: "gearshape.fill").foregroundStyle(Palette.muted)
                    Text("Settings").font(.myBody).foregroundStyle(Palette.text)
                    Spacer()
                    Image(systemName: "chevron.right").font(.myCaption.weight(.semibold))
                        .foregroundStyle(Palette.faint)
                }
            }
        }
        .fluidPressable(scale: 0.99)
    }
    #endif

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: "Look")
            AppearanceCard()
        }
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Still up"
        }
    }
    private var weekdayName: String {
        let f = DateFormatter(); f.dateFormat = "EEEE"
        return f.string(from: Date())
    }
    private var prettyDate: String {
        let f = DateFormatter(); f.dateFormat = "d MMMM yyyy"
        return f.string(from: Date())
    }
}

// MARK: - Value-driven Today sections
//
// TodayView still observes the store, so its body re-runs on any data tick.
// These sections take snapshots instead: when a tick changes nothing they
// show, `Equatable` skips their bodies — logging a meal rebuilds meals and
// the hero, not news, photos, and the header.

/// Greeting + weekday + streak. Values in, no store reads.
struct TodayHeaderView: View, Equatable {
    let greeting: String
    let name: String
    let weekday: String
    let prettyDate: String
    let isToday: Bool
    let streak: Int
    let todayHit: Bool
    let mark: StepDay
    let onToday: () -> Void
    let onFitness: () -> Void
    let onCalendar: () -> Void

    static func == (lhs: TodayHeaderView, rhs: TodayHeaderView) -> Bool {
        lhs.greeting == rhs.greeting && lhs.name == rhs.name
            && lhs.weekday == rhs.weekday && lhs.prettyDate == rhs.prettyDate
            && lhs.isToday == rhs.isToday && lhs.streak == rhs.streak
            && lhs.todayHit == rhs.todayHit && lhs.mark == rhs.mark
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(greeting + ", " + name)
                    .font(.myBody).foregroundStyle(Palette.muted)
                Text(weekday)
                    .font(.myHeading).foregroundStyle(Palette.text)
                HStack(spacing: 8) {
                    Text(prettyDate).font(.myCaption).foregroundStyle(Palette.muted)
                    if !isToday {
                        // The only affordance for getting home — the page has no
                        // arrows by design, so leaving without one would strand you.
                        Button("Today") { onToday() }
                            .buttonStyle(.plain)
                            .font(.myCaption.weight(.bold))
                            .foregroundStyle(Palette.action)
                    }
                }
            }
            Spacer(minLength: 8)
            Button { onFitness() } label: {
                HStack(spacing: 8) {
                    StepMark(day: mark, size: 20)
                    Text("\(streak)")
                        .font(.title2.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(Palette.text)
                    Text(streak == 1 ? "day" : "days")
                        .font(.myCaption.weight(.semibold))
                        .foregroundStyle(Palette.muted)
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(Palette.surface, in: Capsule())
                .overlay(Capsule().strokeBorder((todayHit ? Palette.complete : Palette.activity).opacity(0.4), lineWidth: 1.5))
            }
            .fluidPressable(scale: 0.99)
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                Haptics.tap()
                onCalendar()
            })
            .accessibilityLabel("Step streak, \(streak) days. Hold for calendar.")
            .help("Tap for steps. Hold for the streak calendar.")
        }
    }
}

/// One meal tile's snapshot. State travels as a value; the tick — not a fill —
/// carries logged vs open.
struct MealTileData: Equatable {
    let meal: MealKey
    let state: MealLog.MealState
    let names: [String]
}

/// The 2×2 meal grid. Body type, press-down tiles, tick-not-fill.
struct MealsGridView: View, Equatable {
    let tiles: [MealTileData]
    let onTap: (MealKey) -> Void

    static func == (lhs: MealsGridView, rhs: MealsGridView) -> Bool {
        lhs.tiles == rhs.tiles
    }

    private let cols = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "Meals")
            LazyVGrid(columns: cols, spacing: 10) {
                ForEach(tiles, id: \.meal) { tile in
                    MealTileView(tile: tile, onTap: { onTap(tile.meal) })
                }
            }
        }
    }
}

private struct MealTileView: View {
    let tile: MealTileData
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: tile.meal.icon).font(.myBody.weight(.semibold))
                    Text(tile.meal.label).font(.myBody.weight(.semibold))
                    Spacer(minLength: 0)
                    if tile.state == .logged {
                        Image(systemName: "checkmark.circle.fill").font(.myBody)
                            .foregroundStyle(Palette.complete)
                    }
                }
                .foregroundStyle(Palette.text)
                Text(MealsGridView.subtitle(tile.state, tile.names))
                    .font(.myCaption).foregroundStyle(Palette.muted)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 30, alignment: .top)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            // State is carried by the tick and the type, not by a fill — a
            // logged meal is not a different kind of thing from a planned one.
            .cardSkin(.plain)
        }
        .fluidPressable()
    }
}

extension MealsGridView {
    fileprivate static func subtitle(_ st: MealLog.MealState, _ names: [String]) -> String {
        switch st {
        case .logged: return names.isEmpty ? "Logged" : names.joined(separator: ", ")
        case .skipped: return "Skipped"
        case .unconfirmed: return names.isEmpty ? "Nothing planned — tap to log" : names.joined(separator: ", ")
        }
    }
}

/// One coming-up row's snapshot.
struct ComingUpRow: Equatable {
    let id: String
    let title: String
    let special: Bool
    let countdown: String
    let icon: String
    let tint: Color
}

/// Coming up, chromeless: a section title plus rows, not another card.
struct ComingUpView: View, Equatable {
    let rows: [ComingUpRow]
    let onOpen: () -> Void

    static func == (lhs: ComingUpView, rhs: ComingUpView) -> Bool {
        lhs.rows == rhs.rows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionTitle(text: "Coming up")
                Spacer()
                Button { onOpen() } label: { Label("All events", systemImage: "calendar") }
                    .buttonStyle(.borderless)
            }
            if rows.isEmpty {
                Text("Nothing coming up. Tap All events to add one.")
                    .font(.myBody).foregroundStyle(Palette.faint)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(rows, id: \.id) { row in
                        Button { onOpen() } label: { ComingUpRowView(row: row) }
                            .buttonStyle(.plain)
                            .fluidPressable(scale: 0.99)
                    }
                }
            }
        }
    }
}

private struct ComingUpRowView: View {
    let row: ComingUpRow

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: row.icon)
                .font(.myBody.weight(.semibold)).foregroundStyle(row.tint)
                .frame(width: 30, height: 30)
                .background(row.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if row.special { Image(systemName: "star.fill").font(.myCaption).foregroundStyle(Palette.attention) }
                    Text(row.title).font(.myBody.weight(.semibold)).foregroundStyle(Palette.text).lineLimit(1)
                }
                Text(row.countdown).font(.myCaption.weight(.heavy)).foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.myCaption.weight(.semibold)).foregroundStyle(Palette.faint)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }
}

/// News, chromeless: section title plus rows. Reads the news store through
/// values, so a data tick that is not news skips it.
struct NewsSectionView: View, Equatable {
    let result: NewsResult?
    let busy: Bool
    let error: String?
    let expanded: Set<String>
    let onToggle: (String) -> Void
    let onRefresh: () -> Void
    let onAsk: (NewsResult.Item) -> Void
    let onOpenLink: (URL) -> Void

    static func == (lhs: NewsSectionView, rhs: NewsSectionView) -> Bool {
        lhs.result == rhs.result && lhs.busy == rhs.busy
            && lhs.error == rhs.error && lhs.expanded == rhs.expanded
    }

    private let techCats: Set<String> = ["tech", "ai"]
    private let financeCats: Set<String> = ["markets", "india", "finance", "crypto"]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "newspaper.fill").font(.myBody.weight(.bold)).foregroundStyle(Palette.blue)
                SectionTitle(text: "Tech & finance news")
                Spacer()
                Button { onRefresh() } label: {
                    HStack(spacing: 5) {
                        if busy { ProgressView().controlSize(.small) }
                        Image(systemName: "arrow.clockwise").font(.myCaption.weight(.bold))
                    }
                }
                .buttonStyle(.borderless)
                .disabled(busy)
            }
            if let n = result, !n.items.isEmpty {
                newsColumns(n)
                Text("Surfaced with AI · Google Search · tap a story for more")
                    .font(.myCaption).foregroundStyle(Palette.faint)
            } else if busy {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Getting today's news…").font(.myBody).foregroundStyle(Palette.muted)
                }
                .padding(.vertical, 6)
            } else if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.myCaption).foregroundStyle(Palette.warning)
            } else {
                Button { onRefresh() } label: { Label("Get today's news", systemImage: "newspaper") }
                    .buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder
    private func newsColumns(_ n: NewsResult) -> some View {
        let tech = newsColumn("Tech", tint: Palette.information, icon: "cpu.fill",
                              items: n.items.filter { techCats.contains($0.category) })
        let finance = newsColumn("Finance", tint: Palette.green, icon: "indianrupeesign.circle.fill",
                                 items: n.items.filter { financeCats.contains($0.category) })
        #if os(iOS)
        VStack(alignment: .leading, spacing: 16) { tech; finance }
        #else
        HStack(alignment: .top, spacing: 18) {
            tech
            Rectangle().fill(Palette.border).frame(width: 1)
            finance
        }
        .fixedSize(horizontal: false, vertical: true)
        #endif
    }

    private func newsColumn(_ title: String, tint: Color, icon: String, items: [NewsResult.Item]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: icon).font(.myCaption.weight(.bold)).foregroundStyle(tint)
                Text(title.uppercased()).font(.myCaption.weight(.heavy))
                    .tracking(0.6).foregroundStyle(tint)
            }
            if items.isEmpty {
                Text("Nothing today.").font(.myCaption).foregroundStyle(Palette.faint)
            } else {
                ForEach(items) { item in
                    NewsRowView(item: item, tint: tint, open: expanded.contains(item.id),
                                onToggle: { onToggle(item.id) },
                                onAsk: { onAsk(item) },
                                onOpenLink: onOpenLink)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func color(for category: String) -> Color {
        switch category {
        case "ai", "tech": return Palette.information
        case "markets", "india": return Palette.green
        case "crypto": return Palette.attention
        default: return Palette.blue
        }
    }
}

private struct NewsRowView: View {
    let item: NewsResult.Item
    let tint: Color
    let open: Bool
    let onToggle: () -> Void
    let onAsk: () -> Void
    let onOpenLink: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.knFast) { onToggle() }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(item.category.uppercased())
                            .font(.myCaption.weight(.heavy)).tracking(0.5)
                            .foregroundStyle(NewsSectionView.color(for: item.category))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(NewsSectionView.color(for: item.category).opacity(0.15), in: Capsule())
                        if let t = item.time, !t.isEmpty {
                            Text(t).font(.myCaption.weight(.medium)).foregroundStyle(Palette.faint)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: open ? "chevron.up" : "chevron.down")
                            .font(.myCaption.weight(.bold)).foregroundStyle(Palette.faint)
                    }
                    Text(item.title).font(.myBody.weight(.semibold)).foregroundStyle(Palette.text)
                        .fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                    Text(item.summary).font(.myCaption).foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if open {
                if let d = item.detail, !d.isEmpty {
                    Text(d).font(.myCaption).foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                }
                HStack(spacing: 8) {
                    if let s = item.source, !s.isEmpty {
                        Button {
                            if let u = item.url, let url = URL(string: u) { onOpenLink(url) }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "link").font(.myCaption.weight(.bold))
                                Text(s).font(.myCaption.weight(.heavy)).lineLimit(1)
                                if item.url != nil { Image(systemName: "arrow.up.right").font(.myCaption.weight(.bold)) }
                            }
                            .foregroundStyle(tint)
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(tint.opacity(0.14), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(item.url == nil)
                        .help(item.url ?? s)
                    }
                    Button(action: onAsk) {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles").font(.myCaption.weight(.bold))
                            Text("Ask AI").font(.myCaption.weight(.heavy))
                        }
                        .foregroundStyle(Palette.action)
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(Palette.action.opacity(0.14), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Chat about this with your mentor")
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surfaceElevated.opacity(open ? 0.4 : 0.18),
                    in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }
}

/// `scrollTargetLayout` only where a pager needs it — applying it on Mac would
/// make every card a scroll target for no reason.
private struct ScrollAnchors: ViewModifier {    let enabled: Bool
    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled { content.scrollTargetLayout() } else { content }
    }
}
