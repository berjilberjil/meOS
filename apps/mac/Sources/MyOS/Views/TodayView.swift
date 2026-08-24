import SwiftUI
#if os(macOS)
import AppKit
#endif

struct TodayView: View {
    @EnvironmentObject var state: AppState
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

    private let cols = [GridItem(.adaptive(minimum: 168), spacing: 12)]
    private let mealCols = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        let sections = TodaySection.ordered()
        VStack(alignment: .leading, spacing: Gap.screen) {
            header.knRise(0).id(Self.headerAnchor)
            ForEach(Array(sections.enumerated()), id: \.element.id) { idx, section in
                todaySection(section).knRise(idx + 1)
            }
            #if os(macOS)
            settingsCard.knRise(7)
            #endif
        }
        .modifier(ScrollAnchors(enabled: sectionAnchors))
        .dayPager(date: $ownDate, today: state.todayKey, enabled: externalDate == nil)
        .onAppear { if ownDate.isEmpty { ownDate = state.todayKey } }
        .task {
            if state.news == nil { await state.fetchNews() }
        }
        .sheet(item: $editingMeal) { meal in
            MealLogEditorSheet(date: selectedDate, meal: meal,
                               initialItems: state.mealEditorItems(date: selectedDate, meal: meal))
        }
        .sheet(isPresented: $showStreakCal) { streakCalendarSheet }
    }

    @ViewBuilder
    private func todaySection(_ section: TodaySection) -> some View {
        switch section {
        case .activity:
            ActivityStepsCard(day: selectedDate, showsCalendar: false)
        case .intake:
            DayMacroHero(day: selectedDate)
        case .meals:
            mealsCard
        case .workout:
            WorkoutChecklistCard(day: selectedDate)
        case .comingUp:
            comingUpCard
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
            newsCard
        }
    }

    private var mealsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "Meals")
            LazyVGrid(columns: mealCols, spacing: 10) {
                ForEach(MealKey.allCases) { meal in mealTile(meal) }
            }
        }
    }

    private func mealTile(_ meal: MealKey) -> some View {
        let st = state.mealState(selectedDate, meal)
        let items = state.mealDisplayItems(date: selectedDate, meal: meal)
        let names = items.compactMap { state.food($0.foodId)?.name }
        return Button { editingMeal = meal } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: meal.icon).font(.caption.weight(.semibold))
                    Text(meal.label).font(.footnote.weight(.semibold))
                    Spacer(minLength: 0)
                    if st == .logged {
                        Image(systemName: "checkmark.circle.fill").font(.footnote).foregroundStyle(Palette.green)
                    }
                }
                .foregroundStyle(Palette.text)
                Text(mealSubtitle(st, names))
                    .font(.caption2).foregroundStyle(Palette.muted)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 28, alignment: .top)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func mealSubtitle(_ st: MealLog.MealState, _ names: [String]) -> String {
        switch st {
        case .logged: return names.isEmpty ? "Logged" : names.joined(separator: ", ")
        case .skipped: return "Skipped"
        case .unconfirmed: return names.isEmpty ? "Nothing planned — tap to log" : names.joined(separator: ", ")
        }
    }

    // MARK: - Coming up (next life events)

    private var comingUpCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionTitle(text: "Coming up")
                    Spacer()
                    Button { go(.events) } label: { Label("All events", systemImage: "calendar") }
                        .buttonStyle(.borderless)
                }
                if state.nextEvents.isEmpty {
                    Text("Nothing coming up. Tap All events to add one.")
                        .font(.footnote).foregroundStyle(Palette.faint)
                } else {
                    ForEach(state.nextEvents) { e in
                        Button { go(.events) } label: { eventLine(e) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func eventLine(_ e: EventItem) -> some View {
        let tag = state.primaryTag(for: e)
        let color = tag?.color ?? Palette.brand
        let icon = tag?.symbol ?? "calendar"
        return HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.footnote.weight(.semibold)).foregroundStyle(color)
                .frame(width: 30, height: 30)
                .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if e.special { Image(systemName: "star.fill").font(.caption2).foregroundStyle(Palette.amber) }
                    Text(e.title).font(.footnote.weight(.semibold)).foregroundStyle(Palette.text).lineLimit(1)
                }
                Text(eventCountdown(e)).font(.caption2.weight(.heavy)).foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(Palette.faint)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }

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

    private var newsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "newspaper.fill").font(.footnote.weight(.bold)).foregroundStyle(Palette.blue)
                    SectionTitle(text: "Tech & finance news")
                    Spacer()
                    Button { Task { await state.fetchNews() } } label: {
                        HStack(spacing: 5) {
                            if state.newsBusy { ProgressView().controlSize(.small) }
                            Image(systemName: "arrow.clockwise").font(.caption2.weight(.bold))
                        }
                    }
                    .buttonStyle(.borderless)
                    .disabled(state.newsBusy)
                }
                if let n = state.news, !n.items.isEmpty {
                    newsColumns(n)
                    Text("Surfaced with AI · Google Search · tap a story for more")
                        .font(.caption2).foregroundStyle(Palette.faint)
                } else if state.newsBusy {
                    HStack(spacing: 8) { ProgressView().controlSize(.small)
                        Text("Getting today's news…").font(.footnote).foregroundStyle(Palette.muted) }
                        .padding(.vertical, 6)
                } else if let err = state.newsError {
                    Label(err, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(Palette.amber)
                } else {
                    Button { Task { await state.fetchNews() } } label: { Label("Get today's news", systemImage: "newspaper") }
                        .buttonStyle(.bordered)
                }
            }
        }
    }

    @ViewBuilder
    private func newsColumns(_ n: NewsResult) -> some View {
        let tech = newsColumn("Tech", tint: Palette.purple, icon: "cpu.fill",
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
                Image(systemName: icon).font(.caption2.weight(.bold)).foregroundStyle(tint)
                Text(title.uppercased()).font(.caption2.weight(.heavy))
                    .tracking(0.6).foregroundStyle(tint)
            }
            if items.isEmpty {
                Text("Nothing today.").font(.caption).foregroundStyle(Palette.faint)
            } else {
                ForEach(items) { item in newsRow(item, tint: tint) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func newsRow(_ item: NewsResult.Item, tint: Color) -> some View {
        let open = expandedNews.contains(item.id)
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.knFast) {
                    if open { expandedNews.remove(item.id) } else { expandedNews.insert(item.id) }
                }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(item.category.uppercased())
                            .font(.caption2.weight(.heavy)).tracking(0.5)
                            .foregroundStyle(newsColor(item.category))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(newsColor(item.category).opacity(0.15), in: Capsule())
                        if let t = item.time, !t.isEmpty {
                            Text(t).font(.caption2.weight(.medium)).foregroundStyle(Palette.faint)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: open ? "chevron.up" : "chevron.down")
                            .font(.caption2.weight(.bold)).foregroundStyle(Palette.faint)
                    }
                    Text(item.title).font(.footnote.weight(.semibold)).foregroundStyle(Palette.text)
                        .fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                    Text(item.summary).font(.caption).foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if open {
                if let d = item.detail, !d.isEmpty {
                    Text(d).font(.caption).foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                }
                HStack(spacing: 8) {
                    if let s = item.source, !s.isEmpty {
                        Button {
                            if let u = item.url, let url = URL(string: u) { openURL(url) }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "link").font(.caption2.weight(.bold))
                                Text(s).font(.caption2.weight(.heavy)).lineLimit(1)
                                if item.url != nil { Image(systemName: "arrow.up.right").font(.caption2.weight(.bold)) }
                            }
                            .foregroundStyle(tint)
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(tint.opacity(0.14), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(item.url == nil)
                        .help(item.url ?? s)
                    }
                    Button { askAboutNews(item) } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles").font(.caption2.weight(.bold))
                            Text("Ask AI").font(.caption2.weight(.heavy))
                        }
                        .foregroundStyle(Palette.brand)
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(Palette.brand.opacity(0.14), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Chat about this with your mentor")
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface2.opacity(open ? 0.4 : 0.18),
                    in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    private func askAboutNews(_ item: NewsResult.Item) {
        var p = "Explain this news and what it means for me and my finance content: \(item.title). \(item.summary)"
        if let d = item.detail, !d.isEmpty { p += " \(d)" }
        state.askMentor(p)
    }

    private func newsColor(_ cat: String) -> Color {
        switch cat {
        case "ai", "tech": return Palette.purple
        case "markets", "india": return Palette.green
        case "crypto": return Palette.amber
        default: return Palette.blue
        }
    }

    // MARK: - AI "what to do now"

    private var suggestionsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles").font(.footnote.weight(.bold))
                        .foregroundStyle(Palette.brand)
                    SectionTitle(text: "What to do now")
                    Spacer()
                    Button { Task { await state.fetchSuggestions() } } label: {
                        HStack(spacing: 5) {
                            if state.suggestBusy { ProgressView().controlSize(.small) }
                            Image(systemName: "arrow.clockwise").font(.caption2.weight(.bold))
                        }
                    }
                    .buttonStyle(.borderless)
                    .disabled(state.suggestBusy)
                    .help("Refresh suggestions")
                }

                if let s = state.suggestions {
                    if !s.headline.isEmpty {
                        Text(s.headline).font(.footnote.weight(.semibold)).foregroundStyle(Palette.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(Array(s.suggestions.enumerated()), id: \.element.id) { i, item in
                        suggestionRow(index: i + 1, item: item)
                    }
                } else if state.suggestBusy {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Reading your day…").font(.footnote).foregroundStyle(Palette.muted)
                    }
                    .padding(.vertical, 6)
                } else if let err = state.suggestError {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(err, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(Palette.amber)
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
        let color: Color = impact == "high" ? Palette.red : (impact == "medium" ? Palette.amber : Palette.faint)
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
        case "content": return Palette.purple
        case "career": return Palette.amber
        case "mind": return Palette.purple
        default: return Palette.brand
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

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(greeting + ", " + state.profile.name)
                    .font(.subheadline).foregroundStyle(Palette.muted)
                ScreenTitle(text: pagedWeekdayName)
                HStack(spacing: 8) {
                    Text(pagedPrettyDate).font(.footnote).foregroundStyle(Palette.muted)
                    if selectedDate != state.todayKey {
                        // The only affordance for getting home — the page has no
                        // arrows by design, so leaving without one would strand you.
                        Button("Today") { withAnimation(.knNormal) { setDate(state.todayKey) } }
                            .buttonStyle(.plain)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Palette.brand)
                    }
                }
            }
            Spacer(minLength: 8)
            streakChip
        }
    }

    /// `{fire|freeze} {n} days` — tap opens journal, hold opens the calendar.
    private var streakChip: some View {
        let n = state.journalStreak
        let todayDone = state.journalHasContent(state.todayKey)
        let ice = n > 0 && !todayDone
        return Button { go(.journal) } label: {
            HStack(spacing: 8) {
                StreakFlame(day: ice ? .frozen : (n > 0 || todayDone ? .done : .none), size: 20)
                Text("\(n)")
                    .font(.title2.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(Palette.text)
                Text(n == 1 ? "day" : "days")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.muted)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(Palette.surface, in: Capsule())
            .overlay(Capsule().strokeBorder((ice ? Palette.ice : Palette.flame).opacity(0.4), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.4).onEnded { _ in
            Haptics.tap()
            showStreakCal = true
        })
        .accessibilityLabel("Journal streak, \(n) days. Hold for calendar.")
        .help("Tap to journal. Hold for the streak calendar.")
    }

    private var streakCalendarSheet: some View {
        NavigationStack {
            StreakCalendar(
                viewedDate: .constant(state.todayKey),
                isPresented: $showStreakCal,
                wide: true,
                onSelect: { key in
                    UISignals.shared.pendingJournalDate = key
                    showStreakCal = false
                    go(.journal)
                }
            )
            .padding(16)
            #if os(iOS)
            .navigationTitle("Streak")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showStreakCal = false }
                        .font(.body.weight(.semibold)).foregroundStyle(Palette.brand)
                }
            }
            #endif
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        .presentationBackground(Palette.bg)
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
                    Capsule().fill(Palette.surface2).frame(height: 5)
                    Capsule().fill(Palette.text).frame(width: max(4, g.size.width * value), height: 5)
                }
            }
            .frame(height: 5)
        }
    }

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

/// `scrollTargetLayout` only where a pager needs it — applying it on Mac would
/// make every card a scroll target for no reason.
private struct ScrollAnchors: ViewModifier {
    let enabled: Bool
    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled { content.scrollTargetLayout() } else { content }
    }
}
