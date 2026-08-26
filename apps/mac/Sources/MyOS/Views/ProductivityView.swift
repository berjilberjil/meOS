import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// The Productivity tab — a log of YouTube videos watched, as a thumbnail grid.
/// Paste a link, the app pulls the title/channel/thumbnail, and each video gets a
/// category + a "what I learned" takeaway that feeds the Teach-Everything habit.
struct ProductivityView: View {
    @EnvironmentObject var state: AppState

    @State private var urlInput = ""
    @State private var addError: String?
    @FocusState private var urlFocused: Bool
    @State private var filter: WatchCategory? = nil
    @State private var selected: WatchItem?
    @State private var dayFilter: String? = nil
    @State private var showCal = false
    /// Seeded from today — see the note in `FocusCalendarPanel`. Starting at 0/0
    /// and fixing it in `.onAppear` flashed a bogus month on first paint.
    @State private var calYear = CalMath.cal.component(.year, from: Date())
    @State private var calMonth = CalMath.cal.component(.month, from: Date())
    @State private var mode: ViewMode = .log

    enum ViewMode: String, CaseIterable, Hashable {
        case log, calendar
        var label: String { self == .log ? "Log" : "Calendar" }
    }

    private let cols = [GridItem(.adaptive(minimum: 210), spacing: 14)]

    private var categoryFiltered: [WatchItem] {
        guard let f = filter else { return state.sortedWatch }
        return state.sortedWatch.filter { $0.category == f }
    }
    /// Videos grouped by the day they were logged, newest day first — the log view.
    private var displayGroups: [(String, [WatchItem])] {
        var items = categoryFiltered
        if let d = dayFilter { items = items.filter { String($0.addedAt.prefix(10)) == d } }
        return Dictionary(grouping: items, by: { String($0.addedAt.prefix(10)) }).sorted { $0.key > $1.key }
    }
    private var daysWithVideos: Set<String> { Set(state.watch.map { String($0.addedAt.prefix(10)) }) }
    /// Videos logged on each day, for the calendar's dots, counts and hover peek.
    private var byDay: [String: [WatchItem]] {
        Dictionary(grouping: categoryFiltered, by: { String($0.addedAt.prefix(10)) })
    }
    private var toNoteCount: Int { state.watch.filter { $0.watched && $0.takeaway.trimmingCharacters(in: .whitespaces).isEmpty }.count }

    var body: some View {
        #if os(iOS)
        // The log field is what you open this tab to use, so it sticks to the
        // bottom instead of scrolling away above a month of history.
        ScrollView {
            stack
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom) {
            addCard
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.bar)
        }
        .sheet(item: $selected) { item in WatchDetailSheet(item: item) }
        #else
        stack
            .sheet(item: $selected) { item in WatchDetailSheet(item: item) }
        #endif
    }

    private var stack: some View {
        VStack(alignment: .leading, spacing: Gap.screen) {
            #if os(macOS)   // iOS: the navigation bar owns the title
            ScreenTitle(text: "Productivity").knRise(0)
            #endif

            // Where the time actually went. This is the tab's headline now; the
            // watch log keeps everything it had, underneath.
            ActivityAnalyticsView().knRise(1)

            Divider().overlay(Palette.divider).padding(.vertical, Space.sm)

            HStack(spacing: Space.sm) {
                SectionTitle(text: "Watch log")
                Spacer()
                Text("\(state.watch.count) videos").font(.myCaption).foregroundStyle(Palette.faint)
                if !state.watch.isEmpty {
                    Picker("", selection: $mode) { ForEach(ViewMode.allCases.map { ($0, $0.label) }, id: \.0) { opt in Text(opt.1).tag(opt.0) } }.pickerStyle(.segmented).labelsHidden()
                        .frame(maxWidth: 220)
                }
            }
            .knRise(2)

            #if os(macOS)
            addCard.knRise(2)
            #endif
            if !state.watch.isEmpty { filterRow.knRise(2) }
            Group {
                switch mode {
                case .log:      content
                case .calendar: calendarView
                }
            }
            .id(mode)
            .knRise(3)
        }
    }

    // MARK: - Add

    private var addCard: some View {
        #if os(iOS)
        // Pinned over the tab bar, so it is an input BAR: one rounded field and
        // a send button. The boxed card below belongs on Mac, where it sits
        // inline in the page instead of hovering over the chrome.
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                TextField("Paste a YouTube link", text: $urlInput)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .submitLabel(.done)
                    .focused($urlFocused)
                    .onSubmit(addVideo)
                Button(action: addVideo) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
                .disabled(urlInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let err = addError {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2).foregroundStyle(Palette.warning)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        #else
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(text: "Log a video")
                HStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "link").font(.caption.weight(.bold)).foregroundStyle(Palette.faint)
                        TextField("", text: $urlInput,
                                  prompt: Text("Paste a YouTube link…").foregroundColor(Palette.faint))
                            .textFieldStyle(.plain).font(.footnote).foregroundStyle(Palette.text)
                            .focused($urlFocused)
                            .onSubmit(addVideo)
                    }
                    .padding(.horizontal, 13).padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.background, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(urlFocused ? Palette.action : Palette.border, lineWidth: 2))
                    .animation(.knFast, value: urlFocused)

                    Button("Add", action: addVideo)
                        .buttonStyle(.borderedProminent)
                        .disabled(urlInput.trimmingCharacters(in: .whitespaces).isEmpty)
                        .opacity(urlInput.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
                }
                if let err = addError {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2).foregroundStyle(Palette.warning)
                }
            }
        }
        #endif
    }

    // MARK: - Filter

    private var filterRow: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Button { showCal.toggle() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar").font(.caption2.weight(.bold))
                        Text(dayFilter == nil ? "All days" : Fmt.day(dayFilter!))
                            .font(.caption.weight(.heavy))
                    }
                    .foregroundStyle(dayFilter == nil ? Palette.muted : Palette.action)
                    .padding(.horizontal, 11).padding(.vertical, 7)
                    .background(dayFilter == nil ? Palette.surfaceElevated.opacity(0.6) : Palette.action.opacity(0.16), in: Capsule())
                    .overlay(Capsule().strokeBorder(dayFilter == nil ? Palette.border : Palette.action.opacity(0.5), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showCal, arrowEdge: .bottom) { calendarFilterPopover }

                if dayFilter != nil {
                    Button { withAnimation(.knFast) { dayFilter = nil } } label: {
                        Image(systemName: "xmark.circle.fill").font(.subheadline).foregroundStyle(Palette.faint)
                    }
                    .buttonStyle(.plain).help("Clear day filter")
                }
                Spacer()
                if toNoteCount > 0 {
                    Text("\(toNoteCount) need a takeaway")
                        .font(.caption2.weight(.heavy)).foregroundStyle(Palette.activity)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Palette.activity.opacity(0.14), in: Capsule())
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    filterChip(nil, label: "All", color: Palette.muted)
                    ForEach(WatchCategory.allCases, id: \.self) { c in
                        filterChip(c, label: c.label, color: c.color)
                    }
                }
                .padding(.vertical, 1)
            }
        }
    }

    private var calendarFilterPopover: some View {
        VStack(spacing: 10) {
            KMonthHeader(year: calYear, month: calMonth, showToday: false,
                         onPrev: { let (y, m) = CalMath.addMonth(year: calYear, month: calMonth, delta: -1); calYear = y; calMonth = m },
                         onNext: { let (y, m) = CalMath.addMonth(year: calYear, month: calMonth, delta: 1); calYear = y; calMonth = m })
            KMonthGrid(year: calYear, month: calMonth, selected: dayFilter,
                       dot: { daysWithVideos.contains($0) ? Palette.information : nil }, onTap: { key in
                withAnimation(.knFast) { dayFilter = (dayFilter == key ? nil : key) }
                showCal = false
            })
        }
        .padding(12).frame(width: 288).background(Palette.elevated)
    }

    // MARK: - Calendar view

    private var calendarView: some View {
        let groups = byDay
        let day = dayFilter ?? CalMath.todayKey()
        return VStack(alignment: .leading, spacing: 16) {
            Card {
                VStack(spacing: 16) {
                    KMonthHeader(year: calYear, month: calMonth,
                                 onPrev: { shiftCal(-1) }, onNext: { shiftCal(1) },
                                 onToday: {
                                     let c = CalMath.cal.dateComponents([.year, .month], from: Date())
                                     calYear = c.year ?? calYear; calMonth = c.month ?? calMonth
                                     dayFilter = CalMath.todayKey()
                                 })
                    KMonthGrid(year: calYear, month: calMonth, selected: day, big: true,
                               dot: { groups[$0]?.first?.category.color ?? (groups[$0] == nil ? nil : Palette.information) },
                               hoverCard: { key in dayPeek(groups[key]) },
                               onTap: { key in withAnimation(.knFast) { dayFilter = key } })
                }
            }
            monthSummary(groups)
            daySection(day: day, items: groups[day] ?? [])
        }
    }

    private func dayPeek(_ items: [WatchItem]?) -> AnyView? {
        guard let items, !items.isEmpty else { return nil }
        return AnyView(
            VStack(alignment: .leading, spacing: 5) {
                Text("\(items.count) video\(items.count == 1 ? "" : "s")")
                    .font(.caption2.weight(.heavy)).foregroundStyle(Palette.faint)
                ForEach(items.prefix(4)) { v in
                    Text(v.title.isEmpty ? "Untitled video" : v.title)
                        .font(.caption.weight(.medium)).foregroundStyle(Palette.text)
                        .lineLimit(1)
                }
                if items.count > 4 {
                    Text("+\(items.count - 4) more").font(.caption2).foregroundStyle(Palette.faint)
                }
            }
        )
    }

    private func monthSummary(_ groups: [String: [WatchItem]]) -> some View {
        let prefix = String(format: "%04d-%02d", calYear, calMonth)
        let days = groups.keys.filter { $0.hasPrefix(prefix) }
        let count = days.reduce(0) { $0 + (groups[$1]?.count ?? 0) }
        return HStack(spacing: 8) {
            Text("\(count) video\(count == 1 ? "" : "s") over \(days.count) day\(days.count == 1 ? "" : "s")")
                .font(.caption.weight(.heavy)).foregroundStyle(Palette.muted)
            Spacer()
        }
    }

    private func daySection(day: String, items: [WatchItem]) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                Text(Fmt.day(day)).font(.footnote.weight(.heavy)).foregroundStyle(Palette.text)
                if !items.isEmpty {
                    Text("· \(items.count) video\(items.count == 1 ? "" : "s")")
                        .font(.caption).foregroundStyle(Palette.faint)
                }
                Spacer()
            }
            if items.isEmpty {
                Card {
                    Text("Nothing logged on \(Fmt.day(day)). Pick another day above.")
                        .font(.footnote).foregroundStyle(Palette.faint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                LazyVGrid(columns: cols, spacing: 14) {
                    ForEach(items) { item in WatchCard(item: item) { selected = item } }
                }
            }
        }
    }

    private func shiftCal(_ d: Int) {
        let (y, m) = CalMath.addMonth(year: calYear, month: calMonth, delta: d)
        withAnimation(.knFast) { calYear = y; calMonth = m }
    }

    private func filterChip(_ c: WatchCategory?, label: String, color: Color) -> some View {
        let on = filter == c
        return Button { withAnimation(.knFast) { filter = c } } label: {
            Text(label).font(.caption.weight(.heavy))
                .foregroundStyle(on ? .white : color)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(on ? color : color.opacity(0.14), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Grid

    @ViewBuilder private var content: some View {
        if state.watch.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No videos yet").font(.subheadline.weight(.heavy)).foregroundStyle(Palette.text)
                    Text("Paste a YouTube link above. The thumbnail, title and channel fill in automatically, the AI tags it — then add what you learned.")
                        .font(.footnote).foregroundStyle(Palette.faint).fixedSize(horizontal: false, vertical: true)
                }
            }
        } else if displayGroups.isEmpty {
            Text("Nothing matches. Clear a filter to see more.").font(.footnote).foregroundStyle(Palette.faint)
        } else {
            // A daily log — one dated section per day, newest first.
            VStack(alignment: .leading, spacing: 22) {
                ForEach(displayGroups, id: \.0) { day, dayItems in
                    VStack(alignment: .leading, spacing: 11) {
                        HStack(spacing: 8) {
                            Text(Fmt.day(day)).font(.footnote.weight(.heavy)).foregroundStyle(Palette.text)
                            Text("· \(dayItems.count) video\(dayItems.count == 1 ? "" : "s")")
                                .font(.caption).foregroundStyle(Palette.faint)
                            Spacer()
                        }
                        LazyVGrid(columns: cols, spacing: 14) {
                            ForEach(dayItems) { item in WatchCard(item: item) { selected = item } }
                        }
                    }
                }
            }
        }
    }

    private func addVideo() {
        let raw = urlInput.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return }
        guard let id = YouTube.videoID(from: raw) else {
            addError = "That doesn't look like a YouTube link."
            return
        }
        if state.watch.contains(where: { $0.videoId == id }) {
            addError = "That video's already in your list."
            urlInput = ""
            return
        }
        addError = nil
        let saved = state.addWatchItem(WatchItem(url: raw, videoId: id, thumbUrl: YouTube.thumbURL(id)))
        urlInput = ""
        urlFocused = true
        // Fill title/channel/thumbnail from oEmbed, then the category.
        Task { @MainActor in
            // Merged into the live row, never a snapshot from before these
            // awaits — the lookup takes seconds, and ticking "watched" or typing
            // a takeaway on the new card in that window was being reverted.
            let meta = await YouTube.fetchMeta(id: id)
            state.enrichWatchItem(id: saved.id, title: meta.title, channel: meta.channel,
                                  thumbUrl: meta.thumbUrl.isEmpty ? nil : meta.thumbUrl)
            // AI picks the category automatically (free model) — best-effort.
            if let cat = await state.categorizeVideo(title: meta.title, channel: meta.channel) {
                state.enrichWatchItem(id: saved.id, category: cat)
            }
        }
    }
}

// MARK: - Grid card

private struct WatchCard: View {
    let item: WatchItem
    let open: () -> Void
    @State private var hover = false

    private var needsTakeaway: Bool { item.watched && item.takeaway.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 0) {
                thumbnail
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title.isEmpty ? "Untitled video" : item.title)
                        .font(.footnote.weight(.semibold)).foregroundStyle(Palette.text)
                        .lineLimit(2).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        if !item.channel.isEmpty {
                            Text(item.channel).font(.caption2).foregroundStyle(Palette.muted).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        categoryChip
                    }
                }
                .padding(12)
            }
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(Palette.border, lineWidth: 2))
            .knShadow()
        }
        .buttonStyle(.plain)
        .knHoverLift()
    }

    /// The true-16:9 thumbnail (mqdefault) so the whole frame shows with no crop.
    private var displayThumb: String {
        item.videoId.isEmpty ? item.thumbUrl : "https://i.ytimg.com/vi/\(item.videoId)/mqdefault.jpg"
    }

    private var thumbnail: some View {
        ZStack(alignment: .topTrailing) {
            Color.black
            AsyncImage(url: URL(string: displayThumb)) { phase in
                switch phase {
                case .success(let img): img.resizable().aspectRatio(contentMode: .fill)
                case .empty: ProgressView().controlSize(.small).tint(Palette.faint)
                default: Image(systemName: "play.rectangle.fill").font(.title).foregroundStyle(Palette.faint)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            // watched / takeaway badges
            HStack(spacing: 5) {
                if item.watched { badge(icon: "checkmark", tint: Palette.green) }
                if needsTakeaway { badge(icon: "pencil", tint: Palette.activity) }
            }
            .padding(8)
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: Radius.lg, topTrailingRadius: Radius.lg, style: .continuous))
    }

    private func badge(icon: String, tint: Color) -> some View {
        Image(systemName: icon).font(.caption2.weight(.heavy))
            .foregroundStyle(.white).frame(width: 20, height: 20)
            .background(tint, in: Circle())
            .overlay(Circle().strokeBorder(.black.opacity(0.15), lineWidth: 1))
    }

    private var categoryChip: some View {
        HStack(spacing: 4) {
            Image(systemName: item.category.icon).font(.caption2.weight(.bold))
            Text(item.category.label).font(.caption2.weight(.heavy))
        }
        .foregroundStyle(item.category.color)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(item.category.color.opacity(0.14), in: Capsule())
    }
}

// MARK: - Detail sheet

private struct WatchDetailSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var draft: WatchItem
    @State private var showConfirm = false
    @FocusState private var takeawayFocused: Bool

    init(item: WatchItem) { _draft = State(initialValue: item) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            AsyncImage(url: URL(string: draft.thumbUrl)) { phase in
                if case .success(let img) = phase { img.resizable().aspectRatio(contentMode: .fill) }
                else { Palette.surfaceElevated }
            }
            .frame(height: 200).frame(maxWidth: .infinity).clipped()
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))

            Text(draft.title.isEmpty ? "Untitled video" : draft.title)
                .font(.body.weight(.heavy)).foregroundStyle(Palette.text)
                .fixedSize(horizontal: false, vertical: true)
            if !draft.channel.isEmpty {
                Text(draft.channel).font(.footnote).foregroundStyle(Palette.muted)
            }

            HStack(spacing: 10) {
                Button {
                    if let u = URL(string: draft.url) {
                        #if os(macOS)
                        NSWorkspace.shared.open(u)
                        #else
                        UIApplication.shared.open(u)
                        #endif
                    }
                } label: {
                    Label("Open in YouTube", systemImage: "play.fill")
                }
                .buttonStyle(.bordered)
                Button { draft.watched.toggle() } label: {
                    Label(draft.watched ? "Watched" : "Mark watched",
                          systemImage: draft.watched ? "checkmark.circle.fill" : "circle")
                }
                .buttonStyle(.bordered)
                .tint(draft.watched ? Palette.accent : Palette.muted)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                KFieldLabel(text: "Category")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(WatchCategory.allCases, id: \.self) { c in catChip(c) }
                    }.padding(.vertical, 1)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                KFieldLabel(text: "What I learned")
                TextEditor(text: $draft.takeaway)
                    .font(.footnote).foregroundStyle(Palette.text)
                    .scrollContentBackground(.hidden)
                    .frame(height: 90).padding(8)
                    .background(Palette.background, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(takeawayFocused ? Palette.action : Palette.border, lineWidth: 2))
                    .focused($takeawayFocused)
            }

            HStack {
                Button { showConfirm = true } label: { Label("Delete", systemImage: "trash") }
                    .buttonStyle(.borderless).tint(Palette.warning)
                    .holdToDelete(isPresented: $showConfirm, title: "Delete this video?",
                                  message: "It'll be removed from your log — this can't be undone.") {
                        state.deleteWatchItem(draft.id); dismiss()
                    }
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.borderedProminent)
            }
        }
        .padding(22).frame(width: 460)
        .background(Palette.elevated)
        // Persist any change (watched / category / takeaway) as it happens.
        .onChange(of: draft) { _, _ in state.updateWatchItem(draft) }
    }

    private func catChip(_ c: WatchCategory) -> some View {
        let on = draft.category == c
        return Button { draft.category = c } label: {
            HStack(spacing: 4) {
                Image(systemName: c.icon).font(.caption2.weight(.bold))
                Text(c.label).font(.caption2.weight(.heavy))
            }
            .foregroundStyle(on ? .white : c.color)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(on ? c.color : c.color.opacity(0.14), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Category styling

extension WatchCategory {
    var color: Color {
        switch self {
        case .finance:   return Palette.green
        case .business:  return Palette.attention
        case .investing: return Palette.action
        case .economy:   return Palette.blue
        case .content:   return Palette.information
        case .mindset:   return Palette.activity
        case .tech:      return Palette.information
        case .other:     return Palette.muted
        }
    }
    var icon: String {
        switch self {
        case .finance:   return "indianrupeesign.circle.fill"
        case .business:  return "building.2.fill"
        case .investing: return "chart.line.uptrend.xyaxis"
        case .economy:   return "banknote.fill"
        case .content:   return "play.rectangle.fill"
        case .mindset:   return "brain.head.profile"
        case .tech:      return "cpu.fill"
        case .other:     return "square.grid.2x2.fill"
        }
    }
}

/// Type-erased ButtonStyle so a view can pick between two styles at runtime.
struct AnyButtonStyle: ButtonStyle {
    private let makeBodyClosure: (Configuration) -> AnyView
    init<S: ButtonStyle>(_ style: S) {
        makeBodyClosure = { config in AnyView(style.makeBody(configuration: config)) }
    }
    func makeBody(configuration: Configuration) -> some View { makeBodyClosure(configuration) }
}
