import SwiftUI

/// Shared mood ramp (1 rough → 5 great), used by the slider and the calendar dots.
func moodTint(_ m: Int) -> Color {
    [Palette.red, Color(hex: 0xF59E0B), Palette.amber, Color(hex: 0x7DD37D), Palette.green][max(1, min(5, m)) - 1]
}

/// Which 1...5 mood stop a horizontal position `x` (0..<width) falls on. Pure so
/// it is unit-testable.
func moodStop(atX x: CGFloat, width: CGFloat) -> Int {
    guard width > 0 else { return 1 }
    return max(1, min(5, Int((x / width) * 5) + 1))
}

struct JournalView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var signals = UISignals.shared

    @State private var viewedDate: String = AppState.dateKey(Date())
    @State private var showCalendar = false

    private var entry: JournalEntry { state.journalEntry(viewedDate) }
    private var isToday: Bool { viewedDate == state.todayKey }

    #if os(iOS)
    enum JSeg: String, CaseIterable, Hashable { case events, journal }
    @State private var jseg: JSeg = .events
    @State private var showPresets = false
    #endif

    var body: some View {
        #if os(iOS)
        VStack(alignment: .leading, spacing: Gap.screen) {
            HStack {
                ScreenTitle(text: jseg == .events ? "Events" : "Journal").lineLimit(1)
                Spacer()
                if jseg == .journal {
                    Button { showPresets = true } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.muted)
                    }
                }
            }
            HStack(spacing: 10) {
                Segmented(options: JSeg.allCases.map { ($0, $0.rawValue.capitalized) }, selection: $jseg)
                Spacer(minLength: 8)
                // "Today" lives on the same row as the Events/Journal tabs, right-aligned.
                if jseg == .journal && !isToday {
                    Button { withAnimation(.knFast) { viewedDate = state.todayKey } } label: { Text("Today") }
                        .buttonStyle(.bordered).tint(Palette.brand)
                }
            }
            if jseg == .events { EventsView() } else { journalBody }
        }
        .sheet(isPresented: $showPresets) {
            NavigationStack {
                ScrollView {
                    Card {
                        VStack(alignment: .leading, spacing: 14) {
                            SectionTitle(text: "Journal quick-add chips")
                            JournalPresetsEditor()
                        }
                    }
                    .padding(16)
                }
                .background(Palette.bg.ignoresSafeArea())
                .navigationTitle("Journal presets")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        // A double-tap on the Journal tab jumps to Events so its editor can open.
        .onChange(of: signals.pendingNewEvent) { _, now in if now { jseg = .events } }
        .onChange(of: signals.pendingJournalDate) { _, key in consumeJournalDate(key) }
        .onAppear { consumeJournalDate(signals.pendingJournalDate) }
        #else
        VStack(alignment: .leading, spacing: 18) {
            header.knRise(0)
            dayContent
        }
        .onChange(of: signals.pendingJournalDate) { _, key in consumeJournalDate(key) }
        .onAppear { consumeJournalDate(signals.pendingJournalDate) }
        #endif
    }

    private func consumeJournalDate(_ key: String?) {
        guard let key, !key.isEmpty else { return }
        UISignals.shared.pendingJournalDate = nil
        viewedDate = key
        #if os(iOS)
        jseg = .journal
        #endif
    }

    #if os(iOS)
    /// The journaling half of the tab (streak / mood / reflections) with its own date nav.
    private var journalBody: some View {
        VStack(alignment: .leading, spacing: 18) {
            // The Today pill now sits on the Events/Journal segmented row above;
            // this row keeps just the day browser.
            HStack(spacing: 10) {
                dateNavigator
                Spacer()
            }
            dayContent
        }
    }
    #endif

    // The title + Today pill + calendar nav. On iOS the nav drops to its own row
    // under the title so a long title never gets squeezed into wrapping.
    @ViewBuilder private var header: some View {
        #if os(iOS)
        VStack(alignment: .leading, spacing: 10) {
            ScreenTitle(text: "Journal")
                .lineLimit(1)
            HStack(spacing: 10) {
                if !isToday {
                    Button { withAnimation(.knFast) { viewedDate = state.todayKey } } label: {
                        Text("Today")
                    }
                    .buttonStyle(.bordered).tint(Palette.brand)
                    .help("Back to today")
                }
                dateNavigator
                Spacer()
            }
        }
        #else
        HStack(spacing: 10) {
            ScreenTitle(text: "Journal")
                .lineLimit(1).layoutPriority(1)
            Spacer()
            if !isToday {
                Button { withAnimation(.knFast) { viewedDate = state.todayKey } } label: {
                    Text("Today")
                }
                .buttonStyle(.bordered).tint(Palette.brand)
                .help("Back to today")
            }
            dateNavigator
        }
        #endif
    }

    @ViewBuilder private var dayContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            StreakCard().knRise(1)

            moodCard.knRise(2)
            reflectionCard(title: "Morning reflection",
                           text: Binding(get: { entry.morning },
                                         set: { v in state.updateJournal(viewedDate) { $0.morning = v } }),
                           prompt: "What matters today? How do you want to show up?",
                           presets: state.journalPresets.morning, tint: Palette.amber).knRise(3)
            reflectionCard(title: "Night reflection",
                           text: Binding(get: { entry.night },
                                         set: { v in state.updateJournal(viewedDate) { $0.night = v } }),
                           prompt: "How did today actually go?",
                           presets: state.journalPresets.night, tint: Palette.blue).knRise(4)

            listCard(title: "Wins", color: Palette.green, items: entry.wins,
                     presets: state.journalPresets.wins,
                     add: { s in state.updateJournal(viewedDate) { $0.wins.append(s) } },
                     remove: { i in state.updateJournal(viewedDate) { $0.wins.remove(at: i) } }).knRise(5)
            listCard(title: "Mistakes", color: Palette.red, items: entry.mistakes,
                     presets: state.journalPresets.mistakes,
                     add: { s in state.updateJournal(viewedDate) { $0.mistakes.append(s) } },
                     remove: { i in state.updateJournal(viewedDate) { $0.mistakes.remove(at: i) } }).knRise(6)
            listCard(title: "Lessons", color: Palette.blue, items: entry.lessons,
                     presets: state.journalPresets.lessons,
                     add: { s in state.updateJournal(viewedDate) { $0.lessons.append(s) } },
                     remove: { i in state.updateJournal(viewedDate) { $0.lessons.remove(at: i) } }).knRise(7)
            listCard(title: "Gratitude", color: Palette.purple, items: entry.gratitude,
                     presets: state.journalPresets.gratitude,
                     add: { s in state.updateJournal(viewedDate) { $0.gratitude.append(s) } },
                     remove: { i in state.updateJournal(viewedDate) { $0.gratitude.remove(at: i) } }).knRise(8)
        }
    }

    // MARK: - Date navigator

    private var dateNavigator: some View {
        HStack(spacing: 4) {
            Button { withAnimation(.knFast) { viewedDate = AppState.addDays(-1, to: viewedDate) } } label: {
                Image(systemName: "chevron.left").font(.caption2.weight(.bold))
            }
            .buttonStyle(.borderless)
            .help("Previous day")

            Button { showCalendar = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "calendar").font(.caption2)
                    Text(dateLabel).font(.caption.weight(.semibold))
                }
                .foregroundStyle(Palette.text)
                .padding(.horizontal, 11).padding(.vertical, 6)
                .background(Palette.surface2, in: Capsule())
                .overlay(Capsule().strokeBorder(Palette.border, lineWidth: 1))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Open calendar")
            .popover(isPresented: $showCalendar, arrowEdge: .bottom) {
                StreakCalendar(viewedDate: $viewedDate, isPresented: $showCalendar)
                    .environmentObject(state)
            }

            Button { withAnimation(.knFast) { viewedDate = AppState.addDays(1, to: viewedDate) } } label: {
                Image(systemName: "chevron.right").font(.caption2.weight(.bold))
            }
            .buttonStyle(.borderless)
            .disabled(isToday)
            .opacity(isToday ? 0.3 : 1)
            .help("Next day")
        }
    }

    private var dateLabel: String {
        if isToday { return "Today" }
        if viewedDate == AppState.addDays(-1, to: state.todayKey) { return "Yesterday" }
        guard let d = AppState.date(fromKey: viewedDate) else { return viewedDate }
        let out = DateFormatter()
        out.calendar = Calendar(identifier: .gregorian)
        out.locale = Locale(identifier: "en_US")
        out.dateFormat = viewedDate.prefix(4) == state.todayKey.prefix(4) ? "EEE, d MMM" : "EEE, d MMM yyyy"
        return out.string(from: d)
    }

    // MARK: - Cards

    private var moodCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(text: isToday ? "Mood today" : "Mood")
                MoodSlider(mood: entry.mood) { m in
                    state.updateJournal(viewedDate) { $0.mood = m }
                }
            }
        }
    }

    private func reflectionCard(title: String, text: Binding<String>, prompt: String,
                                presets: [String], tint: Color) -> some View {
        ReflectionEditor(title: title, text: text, prompt: prompt, presets: presets, tint: tint)
    }

    private func listCard(title: String, color: Color, items: [String], presets: [String],
                          add: @escaping (String) -> Void, remove: @escaping (Int) -> Void) -> some View {
        JournalListCard(title: title, color: color, items: items, presets: presets, add: add, remove: remove)
    }
}

// MARK: - Streak card (Duolingo-style: lit fire per day, frozen fire on saved misses)

/// A small flame that renders one day's streak state.
struct StreakFlame: View {
    let day: AppState.StreakDay
    var size: CGFloat = 14

    var body: some View {
        switch day {
        case .done:
            Image(systemName: "flame.fill")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(colors: [Palette.amber, Palette.flame],
                                   startPoint: .top, endPoint: .bottom)
                )
        case .frozen:
            Image(systemName: "flame.fill")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(colors: [Palette.ice, Palette.blue],
                                   startPoint: .top, endPoint: .bottom)
                )
        case .none:
            Circle()
                .fill(Palette.surface2)
                .frame(width: size * 0.55, height: size * 0.55)
        }
    }
}

private struct StreakCard: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        let info = state.journalStreakInfo
        let todayDone = state.journalHasContent(state.todayKey)

        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text("\(info.count)")
                        .font(.largeTitle.weight(.bold)).monospacedDigit()
                        .foregroundStyle(info.count > 0 ? Palette.text : Palette.faint)
                    Text("day streak")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(info.count > 0 ? Palette.muted : Palette.faint)
                    Spacer(minLength: 0)
                }
                Text(subtitle(count: info.count, todayDone: todayDone))
                    .font(.caption)
                    .foregroundStyle(Palette.muted)

                weekStrip
            }
        }
    }

    private func subtitle(count: Int, todayDone: Bool) -> String {
        if todayDone { return "Fire lit for today. Keep stacking." }
        if count > 0 { return "Journal today to keep the fire alive." }
        return "Write one line today to start a new streak."
    }

    /// Current week, Monday-first — each day gets its flame / frozen flame.
    private var weekStrip: some View {
        let today = state.todayKey
        let letters = ["M", "T", "W", "T", "F", "S", "S"]
        let monday = mondayOfCurrentWeek()
        return HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { i in
                let key = AppState.addDays(i, to: monday)
                let isToday = key == today
                let isFuture = key > today
                VStack(spacing: 6) {
                    Text(letters[i])
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(isToday ? Palette.amber : Palette.faint)
                    Group {
                        if isFuture {
                            Circle().fill(Palette.surface2.opacity(0.5))
                                .frame(width: 8, height: 8)
                        } else if isToday && state.journalStreakDay(key) == .none {
                            // Outline flame under today so the highlight and the
                            // fire sit on the same column (not under yesterday).
                            Image(systemName: "flame")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Palette.amber.opacity(0.85))
                        } else {
                            StreakFlame(day: state.journalStreakDay(key), size: isToday ? 16 : 14)
                        }
                    }
                    .frame(height: 18)
                }
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(
                    isToday
                    ? Palette.amber.opacity(0.12)
                    : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
            }
        }
        .padding(.vertical, 12).padding(.horizontal, 8)
        .background(Palette.surface2.opacity(0.45),
                    in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(Palette.border, lineWidth: 1))
    }

    private func mondayOfCurrentWeek() -> String {
        let cal = Calendar(identifier: .gregorian)
        guard let d = AppState.date(fromKey: state.todayKey) else { return state.todayKey }
        let weekday = cal.component(.weekday, from: d)      // 1 = Sun ... 7 = Sat
        return AppState.addDays(-((weekday + 5) % 7), to: state.todayKey)
    }
}

// MARK: - Month calendar popover

/// Month grid of fire / freeze days. Compact popover on Journal; wide sheet from Today.
struct StreakCalendar: View {
    @EnvironmentObject var state: AppState
    @Binding var viewedDate: String
    @Binding var isPresented: Bool
    var wide: Bool = false
    var onSelect: ((String) -> Void)? = nil
    @State private var monthAnchor: String   // first-of-month key, yyyy-MM-01

    init(viewedDate: Binding<String>, isPresented: Binding<Bool>,
         wide: Bool = false, onSelect: ((String) -> Void)? = nil) {
        _viewedDate = viewedDate
        _isPresented = isPresented
        self.wide = wide
        self.onSelect = onSelect
        _monthAnchor = State(initialValue: String(viewedDate.wrappedValue.prefix(7)) + "-01")
    }

    private static let cal = Calendar(identifier: .gregorian)

    var body: some View {
        VStack(spacing: 10) {
            header
            weekdayRow
            grid
            legend
        }
        .padding(wide ? 18 : 14)
        .frame(width: wide ? nil : 268)
        .frame(maxWidth: wide ? .infinity : nil)
        .background(wide ? Palette.bg : Palette.elevated)
    }

    /// What the flames mean — lit vs frozen.
    private var legend: some View {
        HStack(spacing: 14) {
            HStack(spacing: 5) {
                StreakFlame(day: .done, size: 10)
                Text("Journalled").font(.caption2.weight(.medium)).foregroundStyle(Palette.muted)
            }
            HStack(spacing: 5) {
                StreakFlame(day: .frozen, size: 10)
                Text("Streak freeze").font(.caption2.weight(.medium)).foregroundStyle(Palette.muted)
            }
            Spacer()
            HStack(spacing: 4) {
                Image(systemName: "flame.fill").font(.caption2).foregroundStyle(Palette.flame)
                Text("\(state.journalStreak)d")
                    .font(.caption2.weight(.bold)).monospacedDigit()
                    .foregroundStyle(Palette.text)
            }
        }
        .padding(.top, 2)
    }

    private var header: some View {
        HStack {
            Button { shiftMonth(-1) } label: {
                Image(systemName: "chevron.left").font(.caption2.weight(.bold))
            }
            .buttonStyle(.borderless)
            Spacer()
            Text(monthTitle)
                .font(.footnote.weight(.semibold)).foregroundStyle(Palette.text)
            Spacer()
            Button { shiftMonth(1) } label: {
                Image(systemName: "chevron.right").font(.caption2.weight(.bold))
            }
            .buttonStyle(.borderless)
            .disabled(isCurrentMonth)
            .opacity(isCurrentMonth ? 0.3 : 1)
        }
    }

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { _, d in
                Text(d)
                    .font(.caption2.weight(.semibold)).foregroundStyle(Palette.faint)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var grid: some View {
        let cells = monthCells
        return VStack(spacing: 3) {
            ForEach(0..<((cells.count + 6) / 7), id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { col in
                        let i = row * 7 + col
                        Group {
                            if i < cells.count, let key = cells[i] {
                                dayCell(key)
                            } else {
                                Color.clear.frame(height: 38)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private func dayCell(_ key: String) -> some View {
        let dayNum = Int(key.suffix(2)) ?? 0
        let today = state.todayKey
        let isViewed = key == viewedDate
        let isToday = key == today
        let isFuture = key > today
        let day = state.journalStreakDay(key)

        return Button {
            if let onSelect { onSelect(key) }
            else { viewedDate = key }
            isPresented = false
        } label: {
            VStack(spacing: 3) {
                Text("\(dayNum)")
                    .font(.caption.weight(isViewed ? .bold : .medium)).monospacedDigit()
                    .foregroundStyle(isViewed ? .white : (isFuture ? Palette.faint : Palette.text))
                Group {
                    if isViewed && day != .none {
                        Image(systemName: "flame.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                    } else {
                        StreakFlame(day: day, size: 9)
                            .opacity(day == .none ? 0 : 1)
                    }
                }
                .frame(height: 10)
            }
            .frame(width: 32, height: 38)
            .background(isViewed ? Palette.brand : .clear,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                if isToday && !isViewed {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Palette.brand.opacity(0.6), lineWidth: 1)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .opacity(isFuture ? 0.35 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
    }

    // MARK: Month math (POSIX/gregorian keys only)

    /// Day keys of the shown month, prefixed by nils to align the 1st under its
    /// weekday (Monday-first).
    private var monthCells: [String?] {
        guard let first = AppState.date(fromKey: monthAnchor) else { return [] }
        let dayCount = Self.cal.range(of: .day, in: .month, for: first)?.count ?? 30
        let weekday = Self.cal.component(.weekday, from: first)   // 1 = Sun ... 7 = Sat
        let lead = (weekday + 5) % 7                              // Monday-first offset
        let prefix = String(monthAnchor.prefix(8))                // "yyyy-MM-"
        return Array(repeating: nil, count: lead)
            + (1...dayCount).map { prefix + String(format: "%02d", $0) }
    }

    private var monthTitle: String {
        guard let d = AppState.date(fromKey: monthAnchor) else { return "" }
        let f = DateFormatter()
        f.calendar = Self.cal
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "MMMM yyyy"
        return f.string(from: d)
    }

    private var isCurrentMonth: Bool {
        monthAnchor.prefix(7) == state.todayKey.prefix(7)
    }

    private func shiftMonth(_ n: Int) {
        guard let d = AppState.date(fromKey: monthAnchor),
              let moved = Self.cal.date(byAdding: .month, value: n, to: d) else { return }
        monthAnchor = String(AppState.dateKey(moved).prefix(7)) + "-01"
    }
}

/// Mood as a sliding 1–5 scale (rough → great) with haptic detents. Defaults to
/// "Rough" until you slide to reflect the day; each stop crossed taps a haptic.
private struct MoodSlider: View {
    let mood: Int?
    let set: (Int) -> Void

    private let words = ["Rough", "Low", "Okay", "Good", "Great"]
    @State private var dragging: Int? = nil

    private var value: Int { dragging ?? mood ?? 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geo in
                let w = geo.size.width
                let centerX = (CGFloat(value) - 0.5) / 5 * w
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.surface2).frame(height: 10)
                    Capsule().fill(moodTint(value)).frame(width: max(13, centerX), height: 10)
                    Circle().fill(.white)
                        .frame(width: 26, height: 26)
                        .overlay(Circle().strokeBorder(moodTint(value), lineWidth: 3))
                        .knShadow()
                        .offset(x: min(max(0, centerX - 13), w - 26))
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            let m = moodStop(atX: g.location.x, width: w)
                            if m != value { Haptics.selection() }
                            dragging = m
                        }
                        .onEnded { g in
                            let m = moodStop(atX: g.location.x, width: w)
                            dragging = nil
                            set(m)
                        }
                )
                .animation(.knFast, value: value)
            }
            .frame(height: 30)

            HStack(spacing: 0) {
                ForEach(1...5, id: \.self) { m in
                    Text("\(m)")
                        .font(.caption2.weight(.bold)).monospacedDigit()
                        .foregroundStyle(m == value ? moodTint(m) : Palette.faint)
                        .frame(maxWidth: .infinity)
                }
            }

            Text(mood == nil ? "Slide to set — \(words[value - 1])" : words[value - 1])
                .font(.caption.weight(.medium))
                .foregroundStyle(mood == nil ? Palette.faint : moodTint(value))
        }
    }
}

/// A reflection text area with focus-reactive styling.
private struct ReflectionEditor: View {
    let title: String
    @Binding var text: String
    let prompt: String
    var presets: [String] = []
    var tint: Color = Palette.brand
    @FocusState private var focused: Bool

    var body: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(text: title)
                TextEditor(text: $text)
                    .font(.footnote).foregroundStyle(Palette.text)
                    .scrollContentBackground(.hidden)
                    .focused($focused)
                    .frame(minHeight: 56)
                    .padding(10)
                    .background(Palette.surface2.opacity(0.6),
                                in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(focused ? Palette.brand.opacity(0.7) : Palette.border, lineWidth: 1))
                    .overlay(alignment: .topLeading) {
                        if text.isEmpty {
                            Text(prompt).font(.footnote).foregroundStyle(Palette.faint)
                                .padding(.horizontal, 15).padding(.vertical, 18).allowsHitTesting(false)
                        }
                    }
                    .animation(.knFast, value: focused)

                // Tap a chip to drop the phrase in; typing still works.
                if !presets.isEmpty {
                    FlowLayout(spacing: 7, runSpacing: 7) {
                        ForEach(presets, id: \.self) { p in
                            PresetChip(text: p, tint: tint) { insert(p) }
                        }
                    }
                }
            }
        }
    }

    private func insert(_ phrase: String) {
        if text.isEmpty { text = phrase }
        else if text.hasSuffix(" ") || text.hasSuffix("\n") { text += phrase }
        else { text += " " + phrase }
    }
}

private struct JournalListCard: View {
    let title: String
    let color: Color
    let items: [String]
    var presets: [String] = []
    let add: (String) -> Void
    let remove: (Int) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    /// Preset chips minus the ones already added — no accidental duplicates.
    private var openPresets: [String] { presets.filter { !items.contains($0) } }

    var body: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(text: title)
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    HStack(spacing: 9) {
                        Circle().fill(color).frame(width: 6, height: 6)
                        Text(item).font(.footnote).foregroundStyle(Palette.text)
                        Spacer()
                        Button { remove(i) } label: {
                            Image(systemName: "xmark").font(.caption2.weight(.bold))
                        }
                        .buttonStyle(.borderless)
                    }
                }
                HStack(spacing: 8) {
                    TextField("", text: $text, prompt: Text("Add to \(title.lowercased())…").foregroundColor(Palette.faint))
                        .textFieldStyle(.plain).font(.footnote).foregroundStyle(Palette.text)
                        .focused($focused)
                        .onSubmit(commit)
                    Button(action: commit) {
                        Image(systemName: "plus.circle.fill").font(.body).foregroundStyle(color)
                    }
                    .buttonStyle(.plain)
                    .opacity(text.isEmpty ? 0.35 : 1)
                    .disabled(text.isEmpty)
                }
                .knField(focused: focused)
                // No-data-loss: unsubmitted text is saved on blur / tab switch.
                .onChange(of: focused) { _, now in if !now { commit() } }
                .onDisappear { commit() }

                // Tap a chip to add it instantly; typing still works.
                if !openPresets.isEmpty {
                    FlowLayout(spacing: 7, runSpacing: 7) {
                        ForEach(openPresets, id: \.self) { p in
                            PresetChip(text: p, tint: color) { add(p) }
                        }
                    }
                }
            }
        }
    }

    private func commit() {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        add(t); text = ""
    }
}
