import SwiftUI
import AppKit
import AVKit
import UniformTypeIdentifiers

/// The Events tab — a **memory log**. Log anything that happened or is coming up: a trip,
/// a wedding, a visit home, a small win. Past, present, or future — each with tags and
/// photos/videos. The calendar is the surface; a list of that month's memories always
/// sits below it. Tap any day to log a new one; hover a day to peek what's on it.
struct EventsView: View {
    @EnvironmentObject var state: AppState
    @State private var editTarget: EventEditTarget?
    @State private var mode: Mode = .month
    @State private var viewYear = 0
    @State private var viewMonth = 0
    @State private var selectedDay: String? = nil
    @State private var showTags = false
    @State private var viewer: EventMedia?

    enum Mode: String, CaseIterable, Hashable {
        case month, year
        var label: String { rawValue.capitalized }
    }

    private var eventsByDay: [String: [EventItem]] { Dictionary(grouping: state.events, by: { $0.date }) }

    /// Precomputed once per render — the dot colour for each day. Cheap O(1) lookups keep
    /// the Year view (12 mini-months × ~40 cells) from rebuilding this per cell.
    private var dayColors: [String: Color] {
        var m: [String: Color] = [:]
        for (day, evs) in eventsByDay {
            if evs.contains(where: { $0.special }) { m[day] = Palette.attention }
            else if let first = evs.first, let t = state.primaryTag(for: first) { m[day] = t.color }
            else { m[day] = Palette.action }
        }
        return m
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                ScreenTitle(text: "Events")
                Spacer()
                Picker("", selection: $mode) { ForEach(Mode.allCases.map { ($0, $0.label) }, id: \.0) { opt in Text(opt.1).tag(opt.0) } }.pickerStyle(.segmented).labelsHidden()
                Button { showTags = true } label: { Label("Tags", systemImage: "tag") }
                    .buttonStyle(.borderless)
                Button { editTarget = EventEditTarget(event: nil) } label: {
                    Label("Add event", systemImage: "plus")
                }
                .buttonStyle(.borderless).tint(Palette.action)
            }
            .knRise(0)

            Group {
                switch mode {
                case .month: monthView
                case .year:  yearView
                }
            }
            .knRise(1)
        }
        .onAppear {
            if viewYear == 0 {
                let c = CalMath.cal.dateComponents([.year, .month], from: Date())
                viewYear = c.year ?? 2026; viewMonth = c.month ?? 1
            }
        }
        .sheet(item: $editTarget) { t in EventEditor(target: t) }
        .sheet(isPresented: $showTags) { TagManagerSheet() }
        .sheet(item: $viewer) { MediaViewer(media: $0) }
    }

    // MARK: - Month calendar + always-visible month list

    private var monthView: some View {
        let byDay = eventsByDay
        let colors = dayColors
        return VStack(alignment: .leading, spacing: 16) {
            Card {
                VStack(spacing: 16) {
                    KMonthHeader(year: viewYear, month: viewMonth,
                                 onPrev: { shiftMonth(-1) }, onNext: { shiftMonth(1) }, onToday: goToday)
                    KMonthGrid(year: viewYear, month: viewMonth, selected: selectedDay, big: true,
                               dot: { colors[$0] }, holiday: { Holidays.name($0) },
                               hoverCard: { dayCard(for: $0, byDay: byDay) }) { key in
                        selectedDay = key
                        editTarget = EventEditTarget(event: nil, presetDate: AppState.date(fromKey: key))
                    }
                }
            }
            monthList(byDay: byDay)
        }
    }

    private func monthList(byDay: [String: [EventItem]]) -> some View {
        let prefix = String(format: "%04d-%02d", viewYear, viewMonth)
        let days = byDay.keys.filter { $0.hasPrefix(prefix) }.sorted()
        let count = days.reduce(0) { $0 + (byDay[$1]?.count ?? 0) }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                SectionTitle(text: "\(CalMath.monthName(viewMonth)) memories")
                if count > 0 {
                    Text("\(count)").font(.caption2.weight(.heavy)).foregroundStyle(Palette.faint)
                }
                Spacer()
            }
            if days.isEmpty {
                Card {
                    Text("Nothing logged this month yet — tap a day above to add a memory.")
                        .font(.footnote).foregroundStyle(Palette.faint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Card {
                    VStack(spacing: 6) {
                        ForEach(days, id: \.self) { day in
                            dayGroup(items: byDay[day] ?? [])
                            if day != days.last { Divider().overlay(Palette.border) }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Year overview (12 mini months) + always-visible year list

    private var yearView: some View {
        let byDay = eventsByDay
        let colors = dayColors
        let cols = [GridItem(.adaptive(minimum: 150), spacing: 14)]
        return VStack(alignment: .leading, spacing: 16) {
            Card {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text(String(viewYear)).font(.body.weight(.heavy)).foregroundStyle(Palette.text)
                        Spacer()
                        Button { withAnimation(.knFast) { viewYear -= 1 } } label: { Image(systemName: "chevron.left").font(.caption.weight(.bold)) }
                            .buttonStyle(.borderless)
                        Button { withAnimation(.knFast) { viewYear += 1 } } label: { Image(systemName: "chevron.right").font(.caption.weight(.bold)) }
                            .buttonStyle(.borderless)
                    }
                    LazyVGrid(columns: cols, spacing: 16) {
                        ForEach(1...12, id: \.self) { m in
                            VStack(spacing: 7) {
                                Text(CalMath.monthName(m, short: true).uppercased())
                                    .font(.caption2.weight(.heavy)).foregroundStyle(Palette.muted)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                KMonthGrid(year: viewYear, month: m, compact: true, dot: { colors[$0] }, onTap: { _ in
                                    withAnimation(.knPop) { viewMonth = m; mode = .month }
                                })
                            }
                            .padding(9)
                            .background(Palette.surfaceElevated.opacity(0.3), in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                        }
                    }
                }
            }
            yearList(byDay: byDay)
        }
    }

    private func yearList(byDay: [String: [EventItem]]) -> some View {
        let months = (1...12).compactMap { m -> (Int, [String])? in
            let mp = String(format: "%04d-%02d", viewYear, m)
            let days = byDay.keys.filter { $0.hasPrefix(mp) }.sorted()
            return days.isEmpty ? nil : (m, days)
        }
        return VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: "\(viewYear) memories")
            if months.isEmpty {
                Card {
                    Text("No memories logged in \(String(viewYear)) yet.")
                        .font(.footnote).foregroundStyle(Palette.faint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ForEach(months, id: \.0) { (m, days) in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(CalMath.monthName(m)).font(.caption.weight(.heavy)).foregroundStyle(Palette.muted)
                        Card {
                            VStack(spacing: 6) {
                                ForEach(days, id: \.self) { day in
                                    dayGroup(items: byDay[day] ?? [])
                                    if day != days.last { Divider().overlay(Palette.border) }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Shared bits

    private func dayGroup(items: [EventItem]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(items) { e in
                EventRow(event: e, tags: state.tags(for: e),
                         open: { viewer = $0 },
                         edit: { editTarget = EventEditTarget(event: e) },
                         delete: { state.deleteEvent(e.id) })
            }
        }
    }

    /// The floating card shown when hovering a day that has memories.
    private func dayCard(for key: String, byDay: [String: [EventItem]]) -> AnyView? {
        guard let evs = byDay[key], !evs.isEmpty else { return nil }
        return AnyView(
            VStack(alignment: .leading, spacing: 10) {
                Text(Fmt.day(key)).font(.caption2.weight(.heavy)).foregroundStyle(Palette.faint)
                ForEach(evs) { e in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            if e.special { Image(systemName: "star.fill").font(.caption2).foregroundStyle(Palette.attention) }
                            if let t = state.primaryTag(for: e) {
                                Image(systemName: t.symbol).font(.caption2.weight(.bold)).foregroundStyle(t.color)
                            }
                            Text(e.title).font(.footnote.weight(.semibold)).foregroundStyle(Palette.text)
                                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        }
                        if !e.media.isEmpty {
                            HStack(spacing: 4) {
                                ForEach(e.media.prefix(4)) { m in MediaThumb(media: m, size: 34) }
                            }
                        }
                    }
                }
            }
            .padding(13).frame(minWidth: 190, maxWidth: 280, alignment: .leading)
            .background(Palette.elevated)
        )
    }

    private func shiftMonth(_ d: Int) {
        let (y, m) = CalMath.addMonth(year: viewYear, month: viewMonth, delta: d)
        withAnimation(.knFast) { viewYear = y; viewMonth = m }
    }
    private func goToday() {
        let c = CalMath.cal.dateComponents([.year, .month], from: Date())
        withAnimation(.knFast) { viewYear = c.year ?? viewYear; viewMonth = c.month ?? viewMonth; selectedDay = CalMath.todayKey() }
    }
}

// MARK: - Row

private struct EventRow: View {
    let event: EventItem
    let tags: [EventTag]
    let open: (EventMedia) -> Void
    let edit: () -> Void
    let delete: () -> Void
    @State private var hover = false
    @State private var showConfirm = false

    var body: some View {
        HStack(spacing: 12) {
            dateBadge
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    if event.special {
                        Image(systemName: "star.fill").font(.caption2).foregroundStyle(Palette.attention)
                    }
                    Text(event.title).font(.footnote.weight(.semibold)).foregroundStyle(Palette.text)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    ForEach(tags) { t in tagChip(t) }
                }
                if !event.note.isEmpty {
                    Text(event.note).font(.caption2).foregroundStyle(Palette.faint).lineLimit(1)
                }
                if !event.media.isEmpty { mediaStrip }
            }
            Spacer(minLength: 0)
            Button(action: edit) { Image(systemName: "pencil").font(.caption2.weight(.bold)) }
                .buttonStyle(.borderless).opacity(hover ? 1 : 0.001).help("Edit")
            Button { showConfirm = true } label: { Image(systemName: "trash").font(.caption2.weight(.bold)) }
                .buttonStyle(.borderless).tint(Palette.warning).opacity(hover ? 1 : 0.001).help("Delete")
                .holdToDelete(isPresented: $showConfirm, title: "Delete this memory?",
                              message: "\(event.title) — this can't be undone.") { delete() }
        }
        .padding(.horizontal, 8).padding(.vertical, 8)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { edit() }
        .onHover { h in hover = h }
        .animation(.knFast, value: hover)
    }

    private var rowBackground: Color {
        if event.special { return Palette.attention.opacity(hover ? 0.12 : 0.07) }
        return hover ? Palette.surfaceElevated.opacity(0.5) : .clear
    }

    private var accent: Color { tags.first?.color ?? Palette.action }

    private var dateBadge: some View {
        VStack(spacing: 0) {
            Text(dayNumber).font(.callout.weight(.heavy)).monospacedDigit()
                .foregroundStyle(Palette.text)
            Text(monthLabel.uppercased()).font(.caption2.weight(.heavy)).tracking(0.4)
                .foregroundStyle(accent)
        }
        .frame(width: 42, height: 42)
        .background(accent.opacity(0.14), in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).strokeBorder(accent.opacity(0.35), lineWidth: 1))
    }

    private func tagChip(_ t: EventTag) -> some View {
        HStack(spacing: 4) {
            Image(systemName: t.symbol).font(.caption2.weight(.bold))
            Text(t.name).font(.caption2.weight(.heavy))
        }
        .foregroundStyle(t.color)
        .padding(.horizontal, 7).padding(.vertical, 2)
        .background(t.color.opacity(0.14), in: Capsule())
    }

    private var mediaStrip: some View {
        HStack(spacing: 5) {
            ForEach(event.media.prefix(5)) { m in
                MediaThumb(media: m, size: 30, onOpen: open)
            }
            if event.media.count > 5 {
                Text("+\(event.media.count - 5)").font(.caption2.weight(.heavy))
                    .foregroundStyle(Palette.faint)
            }
        }
        .padding(.top, 2)
    }

    private var dayNumber: String {
        guard let d = AppState.date(fromKey: event.date) else { return "?" }
        let f = DateFormatter(); f.dateFormat = "d"; return f.string(from: d)
    }
    private var monthLabel: String {
        guard let d = AppState.date(fromKey: event.date) else { return "" }
        let f = DateFormatter(); f.dateFormat = "MMM"; return f.string(from: d)
    }
}

// MARK: - Media thumbnail + in-app viewer

private struct MediaThumb: View {
    let media: EventMedia
    var size: CGFloat = 72
    var onRemove: (() -> Void)? = nil
    var onOpen: ((EventMedia) -> Void)? = nil
    @State private var hover = false
    /// Media fetched from R2 lands asynchronously; observing the store is what
    /// turns the placeholder into the real thumbnail.
    @ObservedObject private var mediaStore = EventMediaStore.shared

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let img = EventMediaIO.image(media) {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Rectangle().fill(Palette.surfaceElevated)
                        .overlay(Image(systemName: media.kind == .video ? "film" : "photo").foregroundStyle(Palette.faint))
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
            .overlay {
                if media.kind == .video {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: size * 0.32))
                        .foregroundStyle(.white.opacity(0.9)).shadow(radius: 3)
                }
            }

            if let onRemove, hover {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill").font(.subheadline).foregroundStyle(.white, Palette.warning)
                }
                .buttonStyle(.plain).padding(3)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onOpen?(media) }
        .onHover { hover = $0 }
        .help(onOpen == nil ? "" : (media.kind == .video ? "Open video" : "Open photo"))
    }
}

/// Resolve media to an image / a temp file URL for playback. Bytes come from
/// `EventMediaStore` — inline base64 for un-migrated items, R2 otherwise.
enum EventMediaIO {
    @MainActor static func image(_ m: EventMedia) -> NSImage? {
        guard let d = EventMediaStore.shared.poster(for: m) else { return nil }
        return NSImage(data: d)
    }
    @MainActor static func tempURL(_ m: EventMedia) -> URL? {
        guard let d = EventMediaStore.shared.data(for: m) else { return nil }
        let ext = m.kind == .video ? "mp4" : "jpg"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
        do { try d.write(to: url); return url } catch { return nil }
    }
}

/// Full media viewer — shown in-app. Images fit the window; videos play via AVKit.
private struct MediaViewer: View {
    let media: EventMedia
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Palette.background
            content.padding(24)
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.white.opacity(0.85))
            }
            .buttonStyle(.plain).padding(14).keyboardShortcut(.cancelAction)
        }
        .frame(minWidth: 720, minHeight: 520)
        .onAppear(perform: start)
        .onDisappear { player?.pause() }
    }

    @ViewBuilder private var content: some View {
        if media.kind == .video {
            if let player { VideoPlayer(player: player) }
            else { ProgressView().tint(Palette.action) }
        } else if let img = EventMediaIO.image(media) {
            Image(nsImage: img).resizable().scaledToFit()
        } else {
            Text("Couldn't load this media.").font(.footnote).foregroundStyle(Palette.faint)
        }
    }

    private func start() {
        guard media.kind == .video, let url = EventMediaIO.tempURL(media) else { return }
        let p = AVPlayer(url: url); player = p; p.play()
    }
}

// MARK: - Editor

struct EventEditTarget: Identifiable {
    let id = UUID()
    var event: EventItem?
    var presetDate: Date? = nil
}

/// A media import in flight — shows a live % (real transcode progress for video).
private struct MediaUpload: Identifiable {
    let id = UUID()
    let kind: EventMedia.Kind
    var progress: Double = 0
    var failed = false
}

private struct EventEditor: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let target: EventEditTarget

    @State private var title = ""
    @State private var date = Date()
    @State private var selectedTags: Set<String> = []
    @State private var special = false
    @State private var note = ""
    @State private var media: [EventMedia] = []
    @State private var uploads: [MediaUpload] = []
    @State private var showCal = false
    @State private var showTags = false
    @State private var dropTargeted = false
    @State private var mediaError: String?
    @State private var viewerMedia: EventMedia?

    private var isNew: Bool { target.event == nil }
    private var prettyDate: String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US"); f.dateFormat = "EEE, MMM d, yyyy"
        return f.string(from: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isNew ? "Log a memory" : "Edit memory")
                .font(.body.weight(.heavy)).foregroundStyle(Palette.text)

            KLabeledField(label: "What happened?", placeholder: "Trip home, a wedding, a small win…", text: $title)

            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    KFieldLabel(text: "Date")
                    Button { showCal.toggle() } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "calendar").font(.caption.weight(.bold)).foregroundStyle(Palette.action)
                            Text(prettyDate).font(.footnote.weight(.semibold)).foregroundStyle(Palette.text)
                            Image(systemName: "chevron.down").font(.caption2.weight(.bold)).foregroundStyle(Palette.faint)
                        }
                        .padding(.horizontal, 13).padding(.vertical, 10)
                        .background(Palette.background, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(showCal ? Palette.action : Palette.border, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showCal, arrowEdge: .bottom) {
                        KDatePicker(date: $date).frame(width: 264).padding(8).background(Palette.elevated)
                    }
                }
                Spacer()
                Button { special.toggle() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: special ? "star.fill" : "star").font(.caption)
                        Text("Special").font(.caption.weight(.heavy))
                    }
                    .foregroundStyle(special ? .white : Palette.attention)
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(special ? Palette.attention : Palette.attention.opacity(0.14), in: Capsule())
                }
                .buttonStyle(.plain)
                .help("Mark the big, once-in-a-lifetime ones")
            }

            VStack(alignment: .leading, spacing: 6) {
                KFieldLabel(text: "Tags")
                FlowLayout(spacing: 7, runSpacing: 7) {
                    ForEach(state.eventTags) { tag in tagChip(tag) }
                    Button { showTags = true } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus").font(.caption2.weight(.heavy))
                            Text("New tag").font(.caption.weight(.heavy))
                        }
                        .foregroundStyle(Palette.muted)
                        .padding(.horizontal, 11).padding(.vertical, 8)
                        .background(Palette.surfaceElevated.opacity(0.6), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            mediaSection

            KLabeledField(label: "Note", placeholder: "Optional detail", text: $note)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.borderless)
                Button(isNew ? "Log it" : "Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || !uploads.filter { !$0.failed }.isEmpty)
            }
        }
        .padding(24).frame(width: 470)
        .background(Palette.elevated)
        .onAppear { load() }
        .sheet(isPresented: $showTags) { TagManagerSheet() }
        .sheet(item: $viewerMedia) { MediaViewer(media: $0) }
        // Dropping anywhere on the editor lands in the media list, not just on the grid.
        .onDrop(of: Self.dropTypes, isTargeted: $dropTargeted) { handleDrop($0) }
    }

    /// Everything we accept from a drag: a real file (Finder, Photos export) or
    /// raw bytes (a drag straight out of a browser or Preview).
    private static let dropTypes: [UTType] = [.fileURL, .image, .movie, .video, .png, .jpeg, .heic]

    private var mediaSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                KFieldLabel(text: "Photos & videos")
                Text(dropTargeted ? "drop to add" : "drag them in, or click Add")
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(dropTargeted ? Palette.action : Palette.faint)
            }
            FlowLayout(spacing: 8, runSpacing: 8) {
                ForEach(media) { m in
                    MediaThumb(media: m, size: 72, onRemove: { media.removeAll { $0.id == m.id } }, onOpen: { viewerMedia = $0 })
                }
                ForEach(uploads) { u in uploadTile(u) }
                Button { chooseFiles() } label: {
                    VStack(spacing: 5) {
                        Image(systemName: "plus").font(.callout.weight(.bold))
                        Text("Add").font(.caption2.weight(.heavy))
                    }
                    .foregroundStyle(dropTargeted ? Palette.action : Palette.muted)
                    .frame(width: 72, height: 72)
                    .background(Palette.background.opacity(0.5), in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        .foregroundStyle(dropTargeted ? Palette.action : Palette.border))
                }
                .buttonStyle(.plain)
                .help("Choose photos or videos")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
            .background(dropTargeted ? Palette.action.opacity(0.08) : .clear,
                        in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .onDrop(of: Self.dropTypes, isTargeted: $dropTargeted) { handleDrop($0) }
            .animation(.knFast, value: dropTargeted)
            if let mediaError {
                Text(mediaError).font(.caption2).foregroundStyle(Palette.warning)
            }
        }
    }

    private func uploadTile(_ u: MediaUpload) -> some View {
        VStack(spacing: 5) {
            if u.failed {
                Image(systemName: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(Palette.warning)
                Text("Failed").font(.caption2.weight(.heavy)).foregroundStyle(Palette.warning)
            } else {
                ZStack {
                    Circle().stroke(Palette.surfaceElevated, lineWidth: 3)
                    Circle().trim(from: 0, to: max(0.02, u.progress))
                        .stroke(Palette.action, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(Int(u.progress * 100))").font(.caption2.weight(.heavy)).foregroundStyle(Palette.text)
                }
                .frame(width: 34, height: 34)
                Text(u.kind == .video ? "Video" : "Photo").font(.caption2.weight(.heavy)).foregroundStyle(Palette.faint)
            }
        }
        .frame(width: 72, height: 72)
        .background(Palette.background.opacity(0.5), in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
        .animation(.knFast, value: u.progress)
        .help(u.failed ? "Tap to dismiss" : "\(Int(u.progress * 100))% uploaded")
        .onTapGesture { if u.failed { uploads.removeAll { $0.id == u.id } } }
    }

    private func tagChip(_ tag: EventTag) -> some View {
        let on = selectedTags.contains(tag.id)
        return Button {
            if on { selectedTags.remove(tag.id) } else { selectedTags.insert(tag.id) }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: tag.symbol).font(.caption2.weight(.bold))
                Text(tag.name).font(.caption.weight(.heavy))
            }
            .foregroundStyle(on ? .white : tag.color)
            .padding(.horizontal, 11).padding(.vertical, 8)
            .background(on ? tag.color : tag.color.opacity(0.14), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    /// The Add button. A plain NSOpenPanel, run modally over the editor sheet —
    /// SwiftUI's `.fileImporter` never opened from inside this nested sheet.
    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image, .movie, .video]
        panel.message = "Choose photos or videos for this memory"
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        importMedia(panel.urls)
    }

    /// Resolve every dragged item to a file on disk, then run the normal import.
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }
        mediaError = nil
        Task { @MainActor in
            var urls: [URL] = []
            for p in providers {
                if let u = await Self.fileURL(from: p) { urls.append(u) }
            }
            if urls.isEmpty {
                mediaError = "Couldn't read what you dropped — try a file from Finder."
            } else {
                importMedia(urls)
            }
        }
        return true
    }

    private static func fileURL(from provider: NSItemProvider) async -> URL? {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            let url: URL? = await withCheckedContinuation { cont in
                _ = provider.loadObject(ofClass: URL.self) { url, _ in cont.resume(returning: url) }
            }
            if let url, url.isFileURL { return url }
        }
        // Raw bytes (dragged out of a browser, Photos, Preview) — spill to a temp file.
        for type in [UTType.movie, .video, .image]
        where provider.hasItemConformingToTypeIdentifier(type.identifier) {
            if let url = await spill(provider, type: type) { return url }
        }
        return nil
    }

    /// `loadFileRepresentation`'s temp file is deleted the moment the callback
    /// returns, so copy it somewhere we own before handing it on.
    private static func spill(_ provider: NSItemProvider, type: UTType) async -> URL? {
        await withCheckedContinuation { cont in
            provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, _ in
                guard let url else { cont.resume(returning: nil); return }
                let ext = url.pathExtension.isEmpty
                    ? (type.preferredFilenameExtension ?? "dat") : url.pathExtension
                let dest = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
                try? FileManager.default.copyItem(at: url, to: dest)
                cont.resume(returning: FileManager.default.fileExists(atPath: dest.path) ? dest : nil)
            }
        }
    }

    private func importMedia(_ urls: [URL]) {
        mediaError = nil
        for url in urls {
            // Fall back to the extension: a temp file spilled from a drag often has
            // no content-type resource value yet.
            let type = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)
                ?? UTType(filenameExtension: url.pathExtension)
            let isImage = type?.conforms(to: .image) ?? false
            let isVideo = (type?.conforms(to: .movie) ?? false) || (type?.conforms(to: .video) ?? false)
            guard isImage || isVideo else {
                mediaError = "\(url.lastPathComponent) isn't a photo or a video."
                continue
            }
            let up = MediaUpload(kind: isImage ? .image : .video)
            uploads.append(up)
            let id = up.id
            Task { @MainActor in
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                if isImage {
                    setProgress(id, 0.5)
                    if let img = NSImage(contentsOf: url), let b64 = NoteImage.encode(img) {
                        media.append(EventMedia(kind: .image, data: b64))
                        uploads.removeAll { $0.id == id }
                    } else {
                        markFailed(id); mediaError = "Couldn't read that image."
                    }
                } else {
                    do {
                        let m = try await VideoMedia.encode(from: url) { p in setProgress(id, p) }
                        media.append(m)
                        uploads.removeAll { $0.id == id }
                    } catch {
                        markFailed(id); mediaError = error.localizedDescription
                    }
                }
            }
        }
    }

    private func setProgress(_ id: UUID, _ p: Double) {
        if let i = uploads.firstIndex(where: { $0.id == id }) { uploads[i].progress = p }
    }
    private func markFailed(_ id: UUID) {
        if let i = uploads.firstIndex(where: { $0.id == id }) { uploads[i].failed = true }
    }

    private func load() {
        if let e = target.event {
            title = e.title
            date = AppState.date(fromKey: e.date) ?? Date()
            selectedTags = Set(e.tagIDs)
            special = e.special
            note = e.note
            media = e.media
        } else if let pd = target.presetDate {
            date = pd
        }
    }

    private func save() {
        let t = title.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        let key = AppState.dateKey(date)
        let tagIDs = state.eventTags.filter { selectedTags.contains($0.id) }.map { $0.id }
        if let e = target.event {
            var ev = e
            ev.date = key; ev.title = t; ev.tagIDs = tagIDs; ev.note = note; ev.special = special; ev.media = media
            state.updateEvent(ev)
        } else {
            state.addEvent(date: key, title: t, tagIDs: tagIDs, note: note, special: special, media: media)
        }
        dismiss()
    }
}

// MARK: - Tag manager

private struct TagManagerSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var editing: EventTag?
    @State private var isAdding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Tags").font(.body.weight(.heavy)).foregroundStyle(Palette.text)
                Spacer()
                Button { isAdding = true; editing = EventTag(name: "", symbol: "star.fill", colorHex: "1CB0F6") } label: {
                    Label("New tag", systemImage: "plus")
                }.buttonStyle(.borderless).tint(Palette.action)
            }

            if let editing {
                TagEditForm(tag: editing, isNew: isAdding,
                            onCancel: { self.editing = nil; isAdding = false },
                            onSave: { t in
                                if isAdding { state.addTag(name: t.name, symbol: t.symbol, colorHex: t.colorHex) }
                                else { state.updateTag(t) }
                                self.editing = nil; isAdding = false
                            })
            }

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(state.eventTags) { tag in tagRow(tag) }
                }
            }
            .frame(height: 260)

            HStack {
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.borderedProminent)
            }
        }
        .padding(24).frame(width: 460)
        .background(Palette.elevated)
    }

    private func tagRow(_ tag: EventTag) -> some View {
        HStack(spacing: 12) {
            Image(systemName: tag.symbol).font(.footnote.weight(.semibold)).foregroundStyle(tag.color)
                .frame(width: 34, height: 34)
                .background(tag.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            Text(tag.name).font(.footnote.weight(.semibold)).foregroundStyle(Palette.text)
            if tag.builtIn {
                Text("built-in").font(.caption2.weight(.heavy)).foregroundStyle(Palette.faint)
                    .padding(.horizontal, 6).padding(.vertical, 2).background(Palette.surfaceElevated, in: Capsule())
            }
            Spacer()
            Button { editing = tag; isAdding = false } label: { Image(systemName: "pencil").font(.caption2.weight(.bold)) }
                .buttonStyle(.borderless).help("Edit")
            if !tag.builtIn {
                Button { state.deleteTag(tag.id) } label: { Image(systemName: "trash").font(.caption2.weight(.bold)) }
                    .buttonStyle(.borderless).tint(Palette.warning).help("Delete tag")
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(Palette.surfaceElevated.opacity(0.35), in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }
}

private struct TagEditForm: View {
    @State var tag: EventTag
    let isNew: Bool
    let onCancel: () -> Void
    let onSave: (EventTag) -> Void

    private let swatches = ["58CC02", "1CB0F6", "FFC800", "CE82FF", "FF9600", "FF4B4B", "84D8FF", "9A9A9A"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            KLabeledField(label: "Name", placeholder: "Birthday, Anniversary…", text: $tag.name)
            VStack(alignment: .leading, spacing: 5) {
                KFieldLabel(text: "Colour")
                HStack(spacing: 8) {
                    ForEach(swatches, id: \.self) { hex in
                        Circle().fill(Color(hexString: hex)).frame(width: 24, height: 24)
                            .overlay(Circle().strokeBorder(.white, lineWidth: tag.colorHex == hex ? 2 : 0))
                            .onTapGesture { tag.colorHex = hex }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                KFieldLabel(text: "Icon")
                SymbolPicker(selection: $tag.symbol, tint: Color(hexString: tag.colorHex))
            }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel).buttonStyle(.borderless)
                Button(isNew ? "Add tag" : "Save") { onSave(tag) }
                    .buttonStyle(.borderedProminent)
                    .disabled(tag.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(14)
        .background(Palette.background.opacity(0.5), in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }
}

private struct SymbolPicker: View {
    @Binding var selection: String
    var tint: Color

    private let symbols = [
        "star.fill", "heart.fill", "gift.fill", "airplane", "house.fill", "briefcase.fill",
        "person.fill", "person.2.fill", "figure.2.and.child.holdinghands", "flag.fill", "bell.fill",
        "calendar", "birthday.cake.fill", "graduationcap.fill", "cross.case.fill", "stethoscope",
        "fork.knife", "cup.and.saucer.fill", "gamecontroller.fill", "music.note", "film.fill",
        "camera.fill", "book.fill", "pencil", "paintbrush.fill", "hammer.fill", "car.fill",
        "tram.fill", "bicycle", "figure.run", "dumbbell.fill", "sportscourt.fill", "trophy.fill",
        "leaf.fill", "pawprint.fill", "sun.max.fill", "moon.stars.fill", "flame.fill",
        "sparkles", "party.popper.fill", "balloon.fill", "hands.clap.fill", "dollarsign.circle.fill",
        "creditcard.fill", "phone.fill", "envelope.fill", "mappin.and.ellipse", "globe"
    ]
    private let cols = [GridItem(.adaptive(minimum: 38), spacing: 6)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: cols, spacing: 6) {
                ForEach(symbols, id: \.self) { s in
                    let on = selection == s
                    Button { selection = s } label: {
                        Image(systemName: s).font(.subheadline.weight(.semibold))
                            .foregroundStyle(on ? .white : tint)
                            .frame(width: 38, height: 38)
                            .background(on ? tint : tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
        }
        .frame(height: 132)
    }
}

// Color(hexString:) + EventTag.color now live in Support/CategoryStyle.swift —
// TodayView needs EventTag's color for the "next events" strip without pulling
// in the rest of this AppKit-heavy file (shared with iOS).
