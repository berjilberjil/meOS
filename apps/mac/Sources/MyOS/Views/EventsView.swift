import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// The Events tab — a **memory log**. Log anything that happened or is coming up: a trip,
/// a wedding, a visit home, a small win. Past, present, or future — each with tags and
/// photos/videos. The calendar is the surface; a list of that month's memories always
/// sits below it. Tap any day to log a new one.
struct EventsView: View {
    @EnvironmentObject var state: AppState
    @State private var editTarget: EventEditTarget?
    @State private var mode: Mode = .month
    @State private var viewYear = 0
    @State private var viewMonth = 0
    @State private var selectedDay: String? = nil
    @State private var showTags = false

    enum Mode: String, CaseIterable, Hashable {
        case month, year
        var label: String { rawValue.capitalized }
    }

    private var eventsByDay: [String: [EventItem]] { Dictionary(grouping: state.events, by: { $0.date }) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Text("Events").font(.system(size: 24, weight: .semibold)).foregroundStyle(Palette.text)
                Spacer()
                Segmented(options: Mode.allCases.map { ($0, $0.label) }, selection: $mode)
                Button { showTags = true } label: { Label("Tags", systemImage: "tag") }
                    .buttonStyle(KGhostButtonStyle())
                Button { editTarget = EventEditTarget(event: nil) } label: {
                    Label("Add event", systemImage: "plus")
                }
                .buttonStyle(KGhostButtonStyle(color: Palette.brand))
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
    }

    // MARK: - Month calendar + always-visible month list

    private var monthView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Card {
                VStack(spacing: 16) {
                    KMonthHeader(year: viewYear, month: viewMonth,
                                 onPrev: { shiftMonth(-1) }, onNext: { shiftMonth(1) }, onToday: goToday)
                    KMonthGrid(year: viewYear, month: viewMonth, selected: selectedDay, big: true,
                               dot: dayDot, holiday: { Holidays.name($0) }) { key in
                        selectedDay = key
                        editTarget = EventEditTarget(event: nil, presetDate: AppState.date(fromKey: key))
                    }
                }
            }
            monthList
        }
    }

    private var monthList: some View {
        let prefix = String(format: "%04d-%02d", viewYear, viewMonth)
        let days = eventsByDay.keys.filter { $0.hasPrefix(prefix) }.sorted()
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                SectionTitle(text: "\(CalMath.monthName(viewMonth)) memories")
                let count = days.reduce(0) { $0 + (eventsByDay[$1]?.count ?? 0) }
                if count > 0 {
                    Text("\(count)").font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundStyle(Palette.faint)
                }
                Spacer()
            }
            if days.isEmpty {
                Card {
                    Text("Nothing logged this month yet — tap a day above to add a memory.")
                        .font(.system(size: 13)).foregroundStyle(Palette.faint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Card {
                    VStack(spacing: 6) {
                        ForEach(days, id: \.self) { day in
                            dayGroup(day, items: eventsByDay[day] ?? [])
                            if day != days.last { Divider().overlay(Palette.border) }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Year overview (12 mini months) + always-visible year list

    private var yearView: some View {
        let cols = [GridItem(.adaptive(minimum: 150), spacing: 14)]
        return VStack(alignment: .leading, spacing: 16) {
            Card {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text(String(viewYear)).font(.system(size: 17, weight: .heavy, design: .rounded)).foregroundStyle(Palette.text)
                        Spacer()
                        Button { withAnimation(.knFast) { viewYear -= 1 } } label: { Image(systemName: "chevron.left").font(.system(size: 12, weight: .bold)) }
                            .buttonStyle(KIconButtonStyle(size: 28))
                        Button { withAnimation(.knFast) { viewYear += 1 } } label: { Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)) }
                            .buttonStyle(KIconButtonStyle(size: 28))
                    }
                    LazyVGrid(columns: cols, spacing: 16) {
                        ForEach(1...12, id: \.self) { m in
                            VStack(spacing: 7) {
                                Text(CalMath.monthName(m, short: true).uppercased())
                                    .font(.system(size: 10, weight: .heavy, design: .rounded)).foregroundStyle(Palette.muted)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                KMonthGrid(year: viewYear, month: m, compact: true, dot: dayDot) { _ in
                                    withAnimation(.knPop) { viewMonth = m; mode = .month }
                                }
                            }
                            .padding(9)
                            .background(Palette.surface2.opacity(0.3), in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                        }
                    }
                }
            }
            yearList
        }
    }

    private var yearList: some View {
        let prefix = String(format: "%04d-", viewYear)
        let months = (1...12).compactMap { m -> (Int, [String])? in
            let mp = String(format: "%04d-%02d", viewYear, m)
            let days = eventsByDay.keys.filter { $0.hasPrefix(mp) }.sorted()
            return days.isEmpty ? nil : (m, days)
        }
        return VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: "\(viewYear) memories")
            if months.isEmpty {
                Card {
                    Text("No memories logged in \(String(viewYear)) yet.")
                        .font(.system(size: 13)).foregroundStyle(Palette.faint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ForEach(months, id: \.0) { (m, days) in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(CalMath.monthName(m)).font(.system(size: 12, weight: .heavy, design: .rounded))
                            .foregroundStyle(Palette.muted)
                        Card {
                            VStack(spacing: 6) {
                                ForEach(days, id: \.self) { day in
                                    dayGroup(day, items: eventsByDay[day] ?? [])
                                    if day != days.last { Divider().overlay(Palette.border) }
                                }
                            }
                        }
                    }
                }
            }
        }
        .id(prefix)
    }

    // MARK: - Day group (a date header + its events)

    private func dayGroup(_ day: String, items: [EventItem]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.element.id) { _, e in
                EventRow(event: e, tags: state.tags(for: e),
                         edit: { editTarget = EventEditTarget(event: e) },
                         delete: { state.deleteEvent(e.id) })
            }
        }
    }

    private func dayDot(_ key: String) -> Color? {
        guard let evs = eventsByDay[key], !evs.isEmpty else { return nil }
        if evs.contains(where: { $0.special }) { return Palette.amber }
        if let first = evs.first, let tag = state.primaryTag(for: first) { return tag.color }
        return Palette.brand
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
                        Image(systemName: "star.fill").font(.system(size: 11)).foregroundStyle(Palette.amber)
                    }
                    Text(event.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.text).lineLimit(1)
                    ForEach(tags) { t in tagChip(t) }
                }
                if !event.note.isEmpty {
                    Text(event.note).font(.system(size: 11)).foregroundStyle(Palette.faint).lineLimit(1)
                }
                if !event.media.isEmpty { mediaStrip }
            }
            Spacer(minLength: 0)
            Button(action: edit) { Image(systemName: "pencil").font(.system(size: 11, weight: .bold)) }
                .buttonStyle(KIconButtonStyle(size: 24)).opacity(hover ? 1 : 0.001).help("Edit")
            Button { showConfirm = true } label: { Image(systemName: "trash").font(.system(size: 10, weight: .bold)) }
                .buttonStyle(KIconButtonStyle(size: 24, color: Palette.red)).opacity(hover ? 1 : 0.001).help("Delete")
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
        if event.special { return Palette.amber.opacity(hover ? 0.12 : 0.07) }
        return hover ? Palette.surface2.opacity(0.5) : .clear
    }

    private var accent: Color { tags.first?.color ?? Palette.brand }

    private var dateBadge: some View {
        VStack(spacing: 0) {
            Text(dayNumber).font(.system(size: 16, weight: .heavy, design: .rounded)).monospacedDigit()
                .foregroundStyle(Palette.text)
            Text(monthLabel.uppercased()).font(.system(size: 8, weight: .heavy, design: .rounded)).tracking(0.4)
                .foregroundStyle(accent)
        }
        .frame(width: 42, height: 42)
        .background(accent.opacity(0.14), in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).strokeBorder(accent.opacity(0.35), lineWidth: 1))
    }

    private func tagChip(_ t: EventTag) -> some View {
        HStack(spacing: 4) {
            Image(systemName: t.symbol).font(.system(size: 8, weight: .bold))
            Text(t.name).font(.system(size: 9, weight: .heavy, design: .rounded))
        }
        .foregroundStyle(t.color)
        .padding(.horizontal, 7).padding(.vertical, 2)
        .background(t.color.opacity(0.14), in: Capsule())
    }

    private var mediaStrip: some View {
        HStack(spacing: 5) {
            ForEach(event.media.prefix(5)) { m in
                MediaThumb(media: m, size: 30)
            }
            if event.media.count > 5 {
                Text("+\(event.media.count - 5)").font(.system(size: 10, weight: .heavy, design: .rounded))
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

// MARK: - Media thumbnail

private struct MediaThumb: View {
    let media: EventMedia
    var size: CGFloat = 72
    var onRemove: (() -> Void)? = nil
    @State private var hover = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let img = EventMediaIO.image(media) {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Rectangle().fill(Palette.surface2)
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
                        .foregroundStyle(.white.opacity(0.9))
                        .shadow(radius: 3)
                }
            }

            if let onRemove, hover {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 15))
                        .foregroundStyle(.white, Palette.red)
                }
                .buttonStyle(.plain).padding(3)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { EventMediaIO.open(media) }
        .onHover { hover = $0 }
        .help(media.kind == .video ? "Open video" : "Open photo")
    }
}

/// Decode / open inline base64 media.
enum EventMediaIO {
    static func image(_ m: EventMedia) -> NSImage? {
        let b64 = m.kind == .video ? m.poster : m.data
        guard let b64, let d = Data(base64Encoded: b64) else { return nil }
        return NSImage(data: d)
    }
    static func open(_ m: EventMedia) {
        guard let d = Data(base64Encoded: m.data) else { return }
        let ext = m.kind == .video ? "mp4" : "jpg"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
        try? d.write(to: url)
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Editor

struct EventEditTarget: Identifiable {
    let id = UUID()
    var event: EventItem?
    var presetDate: Date? = nil
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
    @State private var showCal = false
    @State private var showTags = false
    @State private var importing = false
    @State private var busy = false
    @State private var mediaError: String?

    private var isNew: Bool { target.event == nil }
    private var prettyDate: String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US"); f.dateFormat = "EEE, MMM d, yyyy"
        return f.string(from: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isNew ? "Log a memory" : "Edit memory")
                .font(.system(size: 18, weight: .heavy, design: .rounded)).foregroundStyle(Palette.text)

            KLabeledField(label: "What happened?", placeholder: "Trip home, a wedding, a small win…", text: $title)

            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    KFieldLabel(text: "Date")
                    Button { showCal.toggle() } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "calendar").font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.brand)
                            Text(prettyDate).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.text)
                            Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(Palette.faint)
                        }
                        .padding(.horizontal, 13).padding(.vertical, 10)
                        .background(Palette.bg, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(showCal ? Palette.brand : Palette.border, lineWidth: 2))
                    }
                    .buttonStyle(KPressStyle())
                    .popover(isPresented: $showCal, arrowEdge: .bottom) {
                        KDatePicker(date: $date).frame(width: 264).padding(8).background(Palette.elevated)
                    }
                }
                Spacer()
                Button { special.toggle() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: special ? "star.fill" : "star").font(.system(size: 12))
                        Text("Special").font(.system(size: 12, weight: .heavy, design: .rounded))
                    }
                    .foregroundStyle(special ? .white : Palette.amber)
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(special ? Palette.amber : Palette.amber.opacity(0.14), in: Capsule())
                }
                .buttonStyle(KPressStyle())
                .help("Mark the big, once-in-a-lifetime ones")
            }

            VStack(alignment: .leading, spacing: 6) {
                KFieldLabel(text: "Tags")
                FlowLayout(spacing: 7, runSpacing: 7) {
                    ForEach(state.eventTags) { tag in tagChip(tag) }
                    Button { showTags = true } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus").font(.system(size: 9, weight: .heavy))
                            Text("New tag").font(.system(size: 12, weight: .heavy, design: .rounded))
                        }
                        .foregroundStyle(Palette.muted)
                        .padding(.horizontal, 11).padding(.vertical, 8)
                        .background(Palette.surface2.opacity(0.6), in: Capsule())
                    }
                    .buttonStyle(KPressStyle())
                }
            }

            mediaSection

            KLabeledField(label: "Note", placeholder: "Optional detail", text: $note)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(KGhostButtonStyle())
                Button(isNew ? "Log it" : "Save") { save() }
                    .buttonStyle(KPrimaryButtonStyle())
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24).frame(width: 470)
        .background(Palette.elevated)
        .onAppear { load() }
        .sheet(isPresented: $showTags) { TagManagerSheet() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.image, .movie, .video],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { importMedia(urls) }
        }
    }

    private var mediaSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                KFieldLabel(text: "Photos & videos")
                Spacer()
                if busy { ProgressView().controlSize(.small) }
            }
            FlowLayout(spacing: 8, runSpacing: 8) {
                ForEach(media) { m in
                    MediaThumb(media: m, size: 72, onRemove: { media.removeAll { $0.id == m.id } })
                }
                Button { importing = true } label: {
                    VStack(spacing: 5) {
                        Image(systemName: "plus").font(.system(size: 16, weight: .bold))
                        Text("Add").font(.system(size: 10, weight: .heavy, design: .rounded))
                    }
                    .foregroundStyle(Palette.muted)
                    .frame(width: 72, height: 72)
                    .background(Palette.bg.opacity(0.5), in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])).foregroundStyle(Palette.border))
                }
                .buttonStyle(KPressStyle())
            }
            if let mediaError {
                Text(mediaError).font(.system(size: 11)).foregroundStyle(Palette.red)
            }
        }
    }

    private func tagChip(_ tag: EventTag) -> some View {
        let on = selectedTags.contains(tag.id)
        return Button {
            if on { selectedTags.remove(tag.id) } else { selectedTags.insert(tag.id) }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: tag.symbol).font(.system(size: 10, weight: .bold))
                Text(tag.name).font(.system(size: 12, weight: .heavy, design: .rounded))
            }
            .foregroundStyle(on ? .white : tag.color)
            .padding(.horizontal, 11).padding(.vertical, 8)
            .background(on ? tag.color : tag.color.opacity(0.14), in: Capsule())
        }
        .buttonStyle(KPressStyle())
    }

    private func importMedia(_ urls: [URL]) {
        mediaError = nil
        busy = true
        Task {
            for url in urls {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let type = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)
                if let type, type.conforms(to: .image) {
                    if let img = NSImage(contentsOf: url), let b64 = NoteImage.encode(img) {
                        media.append(EventMedia(kind: .image, data: b64))
                    }
                } else {
                    do { media.append(try await VideoMedia.encode(from: url)) }
                    catch { mediaError = error.localizedDescription }
                }
            }
            busy = false
        }
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
                Text("Tags").font(.system(size: 18, weight: .heavy, design: .rounded)).foregroundStyle(Palette.text)
                Spacer()
                Button { isAdding = true; editing = EventTag(name: "", symbol: "star.fill", colorHex: "1CB0F6") } label: {
                    Label("New tag", systemImage: "plus")
                }.buttonStyle(KGhostButtonStyle(color: Palette.brand))
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
                Button("Done") { dismiss() }.buttonStyle(KPrimaryButtonStyle())
            }
        }
        .padding(24).frame(width: 460)
        .background(Palette.elevated)
    }

    private func tagRow(_ tag: EventTag) -> some View {
        HStack(spacing: 12) {
            Image(systemName: tag.symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(tag.color)
                .frame(width: 34, height: 34)
                .background(tag.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            Text(tag.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.text)
            if tag.builtIn {
                Text("built-in").font(.system(size: 9, weight: .heavy, design: .rounded)).foregroundStyle(Palette.faint)
                    .padding(.horizontal, 6).padding(.vertical, 2).background(Palette.surface2, in: Capsule())
            }
            Spacer()
            Button { editing = tag; isAdding = false } label: { Image(systemName: "pencil").font(.system(size: 11, weight: .bold)) }
                .buttonStyle(KIconButtonStyle(size: 26)).help("Edit")
            if !tag.builtIn {
                Button { state.deleteTag(tag.id) } label: { Image(systemName: "trash").font(.system(size: 10, weight: .bold)) }
                    .buttonStyle(KIconButtonStyle(size: 26, color: Palette.red)).help("Delete tag")
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(Palette.surface2.opacity(0.35), in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
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
                Button("Cancel", action: onCancel).buttonStyle(KGhostButtonStyle())
                Button(isNew ? "Add tag" : "Save") { onSave(tag) }
                    .buttonStyle(KPrimaryButtonStyle())
                    .disabled(tag.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(14)
        .background(Palette.bg.opacity(0.5), in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
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
                        Image(systemName: s).font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(on ? .white : tint)
                            .frame(width: 38, height: 38)
                            .background(on ? tint : tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(KPressStyle())
                }
            }
            .padding(2)
        }
        .frame(height: 132)
    }
}

// MARK: - Colour from hex string + tag colour

extension Color {
    /// Parse an "RRGGBB" (or "#RRGGBB") string into a Color via the existing hex init.
    init(hexString: String) {
        let s = hexString.hasPrefix("#") ? String(hexString.dropFirst()) : hexString
        self.init(hex: UInt32(s, radix: 16) ?? 0x9A9A9A)
    }
}

extension EventTag {
    var color: Color { Color(hexString: colorHex) }
}
