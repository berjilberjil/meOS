import SwiftUI
#if os(macOS)
import AppKit
#endif

struct TodayView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openURL) private var openURL
    var go: (NavTab) -> Void

    @State private var newFocus = ""
    @FocusState private var focusFieldActive: Bool
    @State private var expandedNews: Set<String> = []

    private let cols = [GridItem(.adaptive(minimum: 168), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header.knRise(0)

            // KPI row
            LazyVGrid(columns: cols, spacing: 12) {
                StatTile(label: "Journal streak",
                         value: "\(state.journalStreak)d",
                         accent: Palette.brand)
            }
            .knRise(1)

            if !state.nextEvents.isEmpty { comingUpCard.knRise(2) }
            suggestionsCard.knRise(2)
            newsCard.knRise(3)
            focusCard.knRise(4)
            habitsCard.knRise(5)

            // Module snapshots
            SectionTitle(text: "Jump back in").knRise(6)
            LazyVGrid(columns: cols, spacing: 12) {
                snapshot("Fitness", Palette.blue, "figure.run",
                         line1: weightLine, line2: proteinLine) { go(.fitness) }
                snapshot("Journal", Palette.purple, "book.closed.fill",
                         line1: journalLine, line2: moodLine) { go(.journal) }
                snapshot("Notes", Palette.amber, "note.text",
                         line1: "\(state.notes.count) notes", line2: "Capture an idea") { go(.notes) }
            }
            .knRise(7)
        }
        .task {
            if state.suggestions == nil { await state.fetchSuggestions() }
            if state.news == nil { await state.fetchNews() }
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
                        .buttonStyle(KGhostButtonStyle())
                }
                ForEach(state.nextEvents) { e in
                    Button { go(.events) } label: { eventLine(e) }
                        .buttonStyle(KPressStyle())
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
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(color)
                .frame(width: 30, height: 30)
                .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if e.special { Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(Palette.amber) }
                    Text(e.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.text).lineLimit(1)
                }
                Text(eventCountdown(e)).font(.system(size: 11, weight: .heavy, design: .rounded)).foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.faint)
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
                    Image(systemName: "newspaper.fill").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.blue)
                    SectionTitle(text: "Tech & finance news")
                    Spacer()
                    Button { Task { await state.fetchNews() } } label: {
                        HStack(spacing: 5) {
                            if state.newsBusy { ProgressView().controlSize(.small) }
                            Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .bold))
                        }
                    }
                    .buttonStyle(KGhostButtonStyle())
                    .disabled(state.newsBusy)
                }
                if let n = state.news, !n.items.isEmpty {
                    HStack(alignment: .top, spacing: 18) {
                        newsColumn("Tech", tint: Palette.purple, icon: "cpu.fill",
                                   items: n.items.filter { techCats.contains($0.category) })
                        Rectangle().fill(Palette.border).frame(width: 1)
                        newsColumn("Finance", tint: Palette.green, icon: "indianrupeesign.circle.fill",
                                   items: n.items.filter { financeCats.contains($0.category) })
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    Text("Surfaced with AI · Google Search · tap a story for more")
                        .font(.system(size: 9)).foregroundStyle(Palette.faint)
                } else if state.newsBusy {
                    HStack(spacing: 8) { ProgressView().controlSize(.small)
                        Text("Getting today's news…").font(.system(size: 13)).foregroundStyle(Palette.muted) }
                        .padding(.vertical, 6)
                } else if let err = state.newsError {
                    Label(err, systemImage: "exclamationmark.triangle.fill").font(.system(size: 12)).foregroundStyle(Palette.amber)
                } else {
                    Button { Task { await state.fetchNews() } } label: { Label("Get today's news", systemImage: "newspaper") }
                        .buttonStyle(KSecondaryButtonStyle())
                }
            }
        }
    }

    private func newsColumn(_ title: String, tint: Color, icon: String, items: [NewsResult.Item]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 11, weight: .bold)).foregroundStyle(tint)
                Text(title.uppercased()).font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(0.6).foregroundStyle(tint)
            }
            if items.isEmpty {
                Text("Nothing today.").font(.system(size: 12)).foregroundStyle(Palette.faint)
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
                            .font(.system(size: 8, weight: .heavy, design: .rounded)).tracking(0.5)
                            .foregroundStyle(newsColor(item.category))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(newsColor(item.category).opacity(0.15), in: Capsule())
                        if let t = item.time, !t.isEmpty {
                            Text(t).font(.system(size: 9, weight: .medium)).foregroundStyle(Palette.faint)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: open ? "chevron.up" : "chevron.down")
                            .font(.system(size: 8, weight: .bold)).foregroundStyle(Palette.faint)
                    }
                    Text(item.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.text)
                        .fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                    Text(item.summary).font(.system(size: 12)).foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(KPressStyle())

            if open {
                if let d = item.detail, !d.isEmpty {
                    Text(d).font(.system(size: 12)).foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                }
                HStack(spacing: 8) {
                    if let s = item.source, !s.isEmpty {
                        Button {
                            if let u = item.url, let url = URL(string: u) { openURL(url) }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "link").font(.system(size: 9, weight: .bold))
                                Text(s).font(.system(size: 10, weight: .heavy, design: .rounded)).lineLimit(1)
                                if item.url != nil { Image(systemName: "arrow.up.right").font(.system(size: 8, weight: .bold)) }
                            }
                            .foregroundStyle(tint)
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(tint.opacity(0.14), in: Capsule())
                        }
                        .buttonStyle(KPressStyle())
                        .disabled(item.url == nil)
                        .help(item.url ?? s)
                    }
                    Button { askAboutNews(item) } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles").font(.system(size: 9, weight: .bold))
                            Text("Ask AI").font(.system(size: 10, weight: .heavy, design: .rounded))
                        }
                        .foregroundStyle(Palette.brand)
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(Palette.brand.opacity(0.14), in: Capsule())
                    }
                    .buttonStyle(KPressStyle())
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
                    Image(systemName: "sparkles").font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Palette.brand)
                    SectionTitle(text: "What to do now")
                    Spacer()
                    Button { Task { await state.fetchSuggestions() } } label: {
                        HStack(spacing: 5) {
                            if state.suggestBusy { ProgressView().controlSize(.small) }
                            Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .bold))
                        }
                    }
                    .buttonStyle(KGhostButtonStyle())
                    .disabled(state.suggestBusy)
                    .help("Refresh suggestions")
                }

                if let s = state.suggestions {
                    if !s.headline.isEmpty {
                        Text(s.headline).font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(Array(s.suggestions.enumerated()), id: \.element.id) { i, item in
                        suggestionRow(index: i + 1, item: item)
                    }
                } else if state.suggestBusy {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Reading your day…").font(.system(size: 13)).foregroundStyle(Palette.muted)
                    }
                    .padding(.vertical, 6)
                } else if let err = state.suggestError {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(err, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 12)).foregroundStyle(Palette.amber)
                        Button("Try again") { Task { await state.fetchSuggestions() } }
                            .buttonStyle(KSecondaryButtonStyle())
                    }
                } else {
                    Button { Task { await state.fetchSuggestions() } } label: {
                        Label("Get today's read", systemImage: "sparkles")
                    }
                    .buttonStyle(KPrimaryButtonStyle())
                }
            }
        }
    }

    private func suggestionRow(index: Int, item: SuggestResult.Item) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: areaIcon(item.area))
                .font(.system(size: 13, weight: .bold)).foregroundStyle(areaColor(item.area))
                .frame(width: 30, height: 30)
                .background(areaColor(item.area).opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(item.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                    impactTag(item.impact)
                }
                Text(item.why).font(.system(size: 12)).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }

    private func impactTag(_ impact: String) -> some View {
        let color: Color = impact == "high" ? Palette.red : (impact == "medium" ? Palette.amber : Palette.faint)
        return Text(impact.uppercased())
            .font(.system(size: 8, weight: .heavy, design: .rounded)).tracking(0.5)
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(greeting + ", " + state.profile.name)
                .font(.system(size: 24, weight: .semibold)).foregroundStyle(Palette.text)
            Text(prettyDate).font(.system(size: 13)).foregroundStyle(Palette.muted)
        }
    }

    private var focusCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(text: "Today's focus")
                let items = state.todayPlan().focus
                if items.isEmpty {
                    Text("What are the 1–3 things that matter today?")
                        .font(.system(size: 13)).foregroundStyle(Palette.faint)
                }
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    HStack(spacing: 10) {
                        Image(systemName: "circle").font(.system(size: 12)).foregroundStyle(Palette.brand)
                        Text(item).font(.system(size: 14)).foregroundStyle(Palette.text)
                        Spacer()
                        Button {
                            var f = items; f.remove(at: idx); state.setFocus(f)
                        } label: {
                            Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                        }
                        .buttonStyle(KIconButtonStyle(size: 22))
                    }
                }
                if items.count < 3 {
                    HStack(spacing: 8) {
                        TextField("", text: $newFocus,
                                  prompt: Text("Add a priority…").foregroundColor(Palette.faint))
                            .textFieldStyle(.plain).font(.system(size: 14)).foregroundStyle(Palette.text)
                            .focused($focusFieldActive)
                            .onSubmit(addFocus)
                        Button(action: addFocus) {
                            Image(systemName: "arrow.up.circle.fill").font(.system(size: 18))
                                .foregroundStyle(Palette.brand)
                        }
                        .buttonStyle(KPressStyle())
                        .opacity(newFocus.isEmpty ? 0.35 : 1)
                        .disabled(newFocus.isEmpty)
                    }
                    .knField(focused: focusFieldActive)
                }
            }
        }
    }

    private var habitsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionTitle(text: "Habits")
                    Spacer()
                    Text("\(state.habitsDoneToday())/\(state.profile.habits.count)")
                        .font(.system(size: 11, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(Palette.muted)
                }
                FlowHabits(habits: state.profile.habits,
                           done: state.todayPlan().habits) { state.toggleHabit($0) }
            }
        }
    }

    private func snapshot(_ title: String, _ color: Color, _ icon: String,
                          line1: String, line2: String, tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            Card(padding: 15) {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 9) {
                        Image(systemName: icon)
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(color)
                            .frame(width: 20, height: 20)
                            .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.text)
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Palette.faint)
                    }
                    Text(line1).font(.system(size: 13)).foregroundStyle(Palette.muted)
                    Text(line2).font(.system(size: 12)).foregroundStyle(Palette.faint)
                }
            }
        }
        .buttonStyle(KPressStyle())
        .knHoverLift()
    }

    // Snapshot lines
    private var weightLine: String {
        if let w = state.fitnessDay(state.todayKey).weightKg { return "\(Fmt.trimKg(w)) kg today" }
        return "No weight logged"
    }
    private var proteinLine: String {
        let p = state.consumed(state.todayKey).protein
        return "\(Int(p)) g protein"
    }
    private var journalLine: String {
        let e = state.journalEntry(state.todayKey)
        let done = !e.morning.isEmpty || !e.night.isEmpty
        return done ? "Journalled today" : "Not journalled yet"
    }
    private var moodLine: String {
        if let m = state.journalEntry(state.todayKey).mood { return "Mood \(m)/5" }
        return "Log your mood"
    }

    private func addFocus() {
        let t = newFocus.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        var f = state.todayPlan().focus; f.append(t); state.setFocus(f)
        newFocus = ""
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
    private var prettyDate: String {
        let f = DateFormatter(); f.dateFormat = "EEEE, d MMMM"
        return f.string(from: Date())
    }
}

/// Simple wrapping habit chips with hover + press feedback.
struct FlowHabits: View {
    let habits: [String]
    let done: [String: Bool]
    let toggle: (String) -> Void
    private let cols = [GridItem(.adaptive(minimum: 110), spacing: 8)]
    var body: some View {
        LazyVGrid(columns: cols, alignment: .leading, spacing: 8) {
            ForEach(habits, id: \.self) { h in
                HabitChip(title: h, done: done[h] ?? false) { toggle(h) }
            }
        }
    }
}

private struct HabitChip: View {
    let title: String
    let done: Bool
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12))
                Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1)
            }
            .foregroundStyle(done ? Palette.green : (hover ? Palette.text : Palette.muted))
            .padding(.horizontal, 11).padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(done ? Palette.green.opacity(0.13)
                             : (hover ? Palette.surface2 : Palette.surface2.opacity(0.6)),
                        in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        }
        .buttonStyle(KPressStyle())
        .onHover { h in hover = h; cursor(h) }
        .animation(.knFast, value: hover)
        .animation(.knFast, value: done)
    }
}
