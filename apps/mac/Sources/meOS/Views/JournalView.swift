import SwiftUI

/// Shared mood ramp (1 rough → 5 great), used by the slider and the calendar dots.
func moodTint(_ m: Int) -> Color {
    // A ramp needs five distinguishable stops, so this is one of the few
    // places allowed to name a colour outside the design system: rough is the
    // warning orange, great is the accent green, and the middle is neutral.
    [Palette.warning, Palette.dataTint(0xF59E0B), Palette.muted, Palette.dataTint(0x7DD37D), Palette.green][max(1, min(5, m)) - 1]
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
            HStack(spacing: 10) {
                Picker("", selection: $jseg) { ForEach(JSeg.allCases.map { ($0, $0.rawValue.capitalized) }, id: \.0) { opt in Text(opt.1).tag(opt.0) } }.pickerStyle(.segmented).labelsHidden()
                Spacer(minLength: 8)
                // "Today" lives on the same row as the Events/Journal tabs, right-aligned.
                if jseg == .journal && !isToday {
                    Button { withAnimation(.knFast) { viewedDate = state.todayKey } } label: { Text("Today") }
                        .buttonStyle(.bordered).tint(Palette.action)
                }
            }
            if jseg == .events { EventsView() } else { journalBody }
        }
        .navigationTitle(jseg == .events ? "Events" : "Journal")
        // One place for the screen's action, on both halves of the tab, and it
        // is the place iOS puts it. Before this, Events had a filled "New"
        // button floating in its content under the segmented picker and Journal
        // had a bare glyph a row higher — two different controls at two
        // different heights that swapped as you switched segment.
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if jseg == .events {
                    Button { signals.pendingNewEvent = true } label: {
                        Label("New event", systemImage: "plus")
                    }
                    .accessibilityLabel("New event")
                } else {
                    Button { showPresets = true } label: {
                        Label("Journal presets", systemImage: "slider.horizontal.3")
                    }
                    .accessibilityLabel("Journal presets")
                }
            }
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
                .background(Palette.background)
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
            // No title here: on iOS the navigation bar draws it.
            HStack(spacing: 10) {
                if !isToday {
                    Button { withAnimation(.knFast) { viewedDate = state.todayKey } } label: {
                        Text("Today")
                    }
                    .buttonStyle(.bordered).tint(Palette.action)
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
                .buttonStyle(.bordered).tint(Palette.action)
                .help("Back to today")
            }
            dateNavigator
        }
        #endif
    }

    @ViewBuilder private var dayContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            moodCard.knRise(2)
            // Six cards do NOT get six colours. A reflection is not a colour and
            // neither is gratitude — these read as one page because they are one
            // page. Only the two that carry a judgement keep an accent: wins are
            // green because they went well, mistakes orange because they didn't.
            reflectionCard(title: "Morning reflection",
                           text: Binding(get: { entry.morning },
                                         set: { v in state.updateJournal(viewedDate) { $0.morning = v } }),
                           prompt: "What matters today? How do you want to show up?",
                           presets: state.journalPresets.morning, tint: Palette.muted).knRise(3)
            reflectionCard(title: "Night reflection",
                           text: Binding(get: { entry.night },
                                         set: { v in state.updateJournal(viewedDate) { $0.night = v } }),
                           prompt: "How did today actually go?",
                           presets: state.journalPresets.night, tint: Palette.muted).knRise(4)

            listCard(title: "Wins", color: Palette.success, items: entry.wins,
                     presets: state.journalPresets.wins,
                     add: { s in state.updateJournal(viewedDate) { $0.wins.append(s) } },
                     remove: { i in state.updateJournal(viewedDate) { $0.wins.remove(at: i) } }).knRise(5)
            listCard(title: "Mistakes", color: Palette.warning, items: entry.mistakes,
                     presets: state.journalPresets.mistakes,
                     add: { s in state.updateJournal(viewedDate) { $0.mistakes.append(s) } },
                     remove: { i in state.updateJournal(viewedDate) { $0.mistakes.remove(at: i) } }).knRise(6)
            listCard(title: "Lessons", color: Palette.muted, items: entry.lessons,
                     presets: state.journalPresets.lessons,
                     add: { s in state.updateJournal(viewedDate) { $0.lessons.append(s) } },
                     remove: { i in state.updateJournal(viewedDate) { $0.lessons.remove(at: i) } }).knRise(7)
            listCard(title: "Gratitude", color: Palette.muted, items: entry.gratitude,
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
                .background(Palette.surfaceElevated, in: Capsule())
                .overlay(Capsule().strokeBorder(Palette.border, lineWidth: 1))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Open calendar")
            .popover(isPresented: $showCalendar, arrowEdge: .bottom) {
                // A dot on the days that have an entry — a way to find a day,
                // not a scoreboard. Journaling is no longer a streak: writing
                // one line to keep a number alive is a reason to write nothing
                // worth reading.
                MonthCalendar(viewedDate: $viewedDate, isPresented: $showCalendar) { key in
                    AnyView(
                        Circle()
                            .fill(state.journalHasContent(key) ? Palette.action : Color.clear)
                            .frame(width: 5, height: 5)
                    )
                }
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
        // Keyed to the day. The card holds its draft in @State while the `add`
        // closure resolves `viewedDate` at call time, so typing a win without
        // pressing Enter and then paging to another day committed it to *that*
        // day — and left the stale text sitting in the new day's box.
        JournalListCard(title: title, color: color, items: items, presets: presets, add: add, remove: remove)
            .id(viewedDate)
    }
}


/// Mood as a sliding 1–5 scale (rough → great) with haptic detents. Defaults to
/// "Rough" until you slide to reflect the day; each stop crossed taps a haptic.
private struct MoodSlider: View {
    let mood: Int?
    let set: (Int) -> Void

    private let words = ["Rough", "Low", "Okay", "Good", "Great"]
    @State private var dragging: Int? = nil

    /// Clamped: `words[value - 1]` indexes a five-element array, and `mood` is
    /// whatever the AI quick-log wrote or sync delivered — `applyParse` takes the
    /// model's integer verbatim. "mood was a 7 out of 10" stored a 7, and from
    /// then on opening the Journal tab crashed, on both devices, for good.
    private var value: Int { max(1, min(5, dragging ?? mood ?? 1)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geo in
                let w = geo.size.width
                let centerX = (CGFloat(value) - 0.5) / 5 * w
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.surfaceElevated).frame(height: 10)
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
    var tint: Color = Palette.action
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
                    .background(Palette.surfaceElevated.opacity(0.6),
                                in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(focused ? Palette.action.opacity(0.7) : Palette.border, lineWidth: 1))
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
