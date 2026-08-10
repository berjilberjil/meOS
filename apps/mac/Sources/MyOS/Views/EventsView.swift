import SwiftUI

/// The Events tab — an upcoming-life timeline. Normal or special, everything the
/// user wants to see coming: a trip, a wedding, a visit home, a lifetime holiday,
/// or a small "send that email". Sorted by date, grouped by how soon it is.
struct EventsView: View {
    @EnvironmentObject var state: AppState
    @State private var editTarget: EventEditTarget?
    @State private var showPast = false
    @State private var mode: Mode = .month
    @State private var viewYear = 0
    @State private var viewMonth = 0
    @State private var selectedDay: String? = nil

    enum Mode: String, CaseIterable, Hashable {
        case list, month, year
        var label: String { rawValue.capitalized }
    }

    private var eventsByDay: [String: [EventItem]] { Dictionary(grouping: state.events, by: { $0.date }) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Text("Events").font(.system(size: 24, weight: .semibold)).foregroundStyle(Palette.text)
                Spacer()
                Segmented(options: Mode.allCases.map { ($0, $0.label) }, selection: $mode)
                Button { editTarget = EventEditTarget(event: nil) } label: {
                    Label("Add event", systemImage: "plus")
                }
                .buttonStyle(KGhostButtonStyle(color: Palette.brand))
            }
            .knRise(0)

            Group {
                switch mode {
                case .list:  listView
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
    }

    // MARK: - List (timeline)

    @ViewBuilder private var listView: some View {
        if state.sortedEvents.isEmpty && state.doneEvents.isEmpty {
            emptyState
        } else {
            VStack(alignment: .leading, spacing: 18) {
                timeline
                if !state.doneEvents.isEmpty { pastSection }
            }
        }
    }

    // MARK: - Month calendar

    private var monthView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Card {
                VStack(spacing: 14) {
                    KMonthHeader(year: viewYear, month: viewMonth,
                                 onPrev: { shiftMonth(-1) }, onNext: { shiftMonth(1) }, onToday: goToday)
                    KMonthGrid(year: viewYear, month: viewMonth, selected: selectedDay, dot: dayDot) { key in
                        withAnimation(.knFast) { selectedDay = (selectedDay == key ? nil : key) }
                    }
                }
            }
            selectedDayCard
        }
    }

    private func dayDot(_ key: String) -> Color? {
        guard let evs = eventsByDay[key], !evs.isEmpty else { return nil }
        return evs.contains { $0.special } ? Palette.amber : (evs.first?.category.color ?? Palette.brand)
    }

    @ViewBuilder private var selectedDayCard: some View {
        if let day = selectedDay {
            let evs = (eventsByDay[day] ?? []).sorted { !$0.done && $1.done }
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(Fmt.day(day)).font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundStyle(Palette.text)
                        Spacer()
                        Button { editTarget = EventEditTarget(event: nil, presetDate: AppState.date(fromKey: day)) } label: {
                            Label("Add", systemImage: "plus")
                        }.buttonStyle(KGhostButtonStyle(color: Palette.brand))
                    }
                    if evs.isEmpty {
                        Text("Nothing on this day. Add what you're planning.")
                            .font(.system(size: 13)).foregroundStyle(Palette.faint)
                    } else {
                        ForEach(Array(evs.enumerated()), id: \.element.id) { idx, e in
                            EventRow(event: e, days: state.daysUntil(e.date),
                                     toggleDone: { state.toggleEventDone(e.id) },
                                     edit: { editTarget = EventEditTarget(event: e) },
                                     delete: { state.deleteEvent(e.id) })
                            if idx < evs.count - 1 { Divider().overlay(Palette.border) }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Year overview (12 mini months)

    private var yearView: some View {
        let cols = [GridItem(.adaptive(minimum: 150), spacing: 14)]
        return Card {
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
    }

    private func shiftMonth(_ d: Int) {
        let (y, m) = CalMath.addMonth(year: viewYear, month: viewMonth, delta: d)
        withAnimation(.knFast) { viewYear = y; viewMonth = m }
    }
    private func goToday() {
        let c = CalMath.cal.dateComponents([.year, .month], from: Date())
        withAnimation(.knFast) { viewYear = c.year ?? viewYear; viewMonth = c.month ?? viewMonth; selectedDay = CalMath.todayKey() }
    }

    private var emptyState: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("Nothing coming up yet").font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundStyle(Palette.text)
                Text("Add the things you're looking forward to — a trip, a visit home, a wedding, a deadline. You'll see them counting down here.")
                    .font(.system(size: 13)).foregroundStyle(Palette.faint).fixedSize(horizontal: false, vertical: true)
                Button { editTarget = EventEditTarget(event: nil) } label: { Label("Add your first event", systemImage: "plus") }
                    .buttonStyle(KPrimaryButtonStyle()).padding(.top, 4)
            }
        }
    }

    // MARK: - Timeline

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(EventBucket.allCases, id: \.self) { bucket in
                let rows = state.sortedEvents.filter { self.bucket(for: $0) == bucket }
                if !rows.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            SectionTitle(text: bucket.title)
                            Rectangle().fill(bucket.tint).frame(width: 26, height: 3).clipShape(Capsule())
                        }
                        Card {
                            VStack(spacing: 6) {
                                ForEach(Array(rows.enumerated()), id: \.element.id) { idx, e in
                                    EventRow(event: e,
                                             days: state.daysUntil(e.date),
                                             toggleDone: { state.toggleEventDone(e.id) },
                                             edit: { editTarget = EventEditTarget(event: e) },
                                             delete: { state.deleteEvent(e.id) })
                                    if idx < rows.count - 1 { Divider().overlay(Palette.border) }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var pastSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { withAnimation(.knNormal) { showPast.toggle() } } label: {
                HStack(spacing: 8) {
                    Image(systemName: showPast ? "chevron.down" : "chevron.right").font(.system(size: 10, weight: .heavy))
                    SectionTitle(text: "Past & done · \(state.doneEvents.count)")
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(KPressStyle())
            if showPast {
                Card {
                    VStack(spacing: 6) {
                        ForEach(Array(state.doneEvents.enumerated()), id: \.element.id) { idx, e in
                            EventRow(event: e, days: state.daysUntil(e.date),
                                     toggleDone: { state.toggleEventDone(e.id) },
                                     edit: { editTarget = EventEditTarget(event: e) },
                                     delete: { state.deleteEvent(e.id) })
                            if idx < state.doneEvents.count - 1 { Divider().overlay(Palette.border) }
                        }
                    }
                }
            }
        }
    }

    private func bucket(for e: EventItem) -> EventBucket {
        guard let d = state.daysUntil(e.date) else { return .later }
        if d < 0 { return .overdue }
        if d == 0 { return .today }
        if d <= 7 { return .week }
        if d <= 31 { return .month }
        return .later
    }
}

// MARK: - Buckets

enum EventBucket: String, CaseIterable {
    case overdue, today, week, month, later
    var title: String {
        switch self {
        case .overdue: return "Overdue"
        case .today:   return "Today"
        case .week:    return "This week"
        case .month:   return "This month"
        case .later:   return "Later"
        }
    }
    var tint: Color {
        switch self {
        case .overdue: return Palette.red
        case .today:   return Palette.flame
        case .week:    return Palette.brand
        case .month:   return Palette.blue
        case .later:   return Palette.muted
        }
    }
}

// MARK: - Row

private struct EventRow: View {
    let event: EventItem
    let days: Int?
    let toggleDone: () -> Void
    let edit: () -> Void
    let delete: () -> Void
    @State private var hover = false
    @State private var showConfirm = false

    var body: some View {
        HStack(spacing: 12) {
            dateBadge
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    if event.special {
                        Image(systemName: "star.fill").font(.system(size: 11)).foregroundStyle(Palette.amber)
                    }
                    Text(event.title).font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(event.done ? Palette.muted : Palette.text)
                        .strikethrough(event.done, color: Palette.faint)
                        .lineLimit(1)
                    categoryChip
                }
                HStack(spacing: 6) {
                    Text(countdown).font(.system(size: 11, weight: .heavy, design: .rounded)).foregroundStyle(countdownColor)
                    if !event.note.isEmpty {
                        Text("· \(event.note)").font(.system(size: 11)).foregroundStyle(Palette.faint).lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 0)
            Button(action: toggleDone) {
                Image(systemName: event.done ? "arrow.uturn.left" : "checkmark.circle")
                    .font(.system(size: event.done ? 11 : 13, weight: .bold))
            }
            .buttonStyle(KIconButtonStyle(size: 24, color: event.done ? Palette.muted : Palette.green))
            .opacity(hover ? 1 : 0.001)
            .help(event.done ? "Move back to upcoming" : "Mark done")
            Button(action: edit) { Image(systemName: "pencil").font(.system(size: 11, weight: .bold)) }
                .buttonStyle(KIconButtonStyle(size: 24)).opacity(hover ? 1 : 0.001).help("Edit")
            Button { showConfirm = true } label: { Image(systemName: "trash").font(.system(size: 10, weight: .bold)) }
                .buttonStyle(KIconButtonStyle(size: 24, color: Palette.red)).opacity(hover ? 1 : 0.001).help("Delete")
                .holdToDelete(isPresented: $showConfirm, title: "Delete this event?",
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
        if event.special && !event.done { return Palette.amber.opacity(hover ? 0.12 : 0.07) }
        return hover ? Palette.surface2.opacity(0.5) : .clear
    }

    private var dateBadge: some View {
        VStack(spacing: 0) {
            Text(dayNumber).font(.system(size: 16, weight: .heavy, design: .rounded)).monospacedDigit()
                .foregroundStyle(event.done ? Palette.muted : Palette.text)
            Text(monthLabel.uppercased()).font(.system(size: 8, weight: .heavy, design: .rounded)).tracking(0.4)
                .foregroundStyle(event.category.color)
        }
        .frame(width: 42, height: 42)
        .background(event.category.color.opacity(0.14), in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).strokeBorder(event.category.color.opacity(0.35), lineWidth: 1))
    }

    private var categoryChip: some View {
        Text(event.category.label).font(.system(size: 9, weight: .heavy, design: .rounded))
            .foregroundStyle(event.category.color)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(event.category.color.opacity(0.14), in: Capsule())
    }

    private var dayNumber: String {
        guard let d = AppState.date(fromKey: event.date) else { return "?" }
        let f = DateFormatter(); f.dateFormat = "d"; return f.string(from: d)
    }
    private var monthLabel: String {
        guard let d = AppState.date(fromKey: event.date) else { return "" }
        let f = DateFormatter(); f.dateFormat = "MMM"; return f.string(from: d)
    }
    private var countdown: String {
        guard let d = days else { return Fmt.day(event.date) }
        switch d {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case -1: return "Yesterday"
        case let n where n > 1: return "in \(n) days"
        default: return "\(-d) days ago"
        }
    }
    private var countdownColor: Color {
        guard let d = days, !event.done else { return Palette.faint }
        if d < 0 { return Palette.red }
        if d <= 1 { return Palette.flame }
        if d <= 7 { return Palette.brand }
        return Palette.muted
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
    @State private var category: EventCategory = .personal
    @State private var special = false
    @State private var note = ""
    @State private var showCal = false

    private var isNew: Bool { target.event == nil }
    private var prettyDate: String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US"); f.dateFormat = "EEE, MMM d, yyyy"
        return f.string(from: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isNew ? "Add event" : "Edit event")
                .font(.system(size: 18, weight: .heavy, design: .rounded)).foregroundStyle(Palette.text)

            KLabeledField(label: "What is it?", placeholder: "Trip home, a wedding, send the email…", text: $title)

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
                KFieldLabel(text: "Category")
                FlowLayout(spacing: 7, runSpacing: 7) {
                    ForEach(EventCategory.allCases, id: \.self) { c in catChip(c) }
                }
            }

            KLabeledField(label: "Note", placeholder: "Optional detail", text: $note)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(KGhostButtonStyle())
                Button(isNew ? "Add" : "Save") { save() }
                    .buttonStyle(KPrimaryButtonStyle())
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24).frame(width: 440)
        .background(Palette.elevated)
        .onAppear { load() }
    }

    private func catChip(_ c: EventCategory) -> some View {
        let on = category == c
        return Button { category = c } label: {
            HStack(spacing: 5) {
                Image(systemName: c.icon).font(.system(size: 10, weight: .bold))
                Text(c.label).font(.system(size: 12, weight: .heavy, design: .rounded))
            }
            .foregroundStyle(on ? .white : c.color)
            .padding(.horizontal, 11).padding(.vertical, 8)
            .background(on ? c.color : c.color.opacity(0.14), in: Capsule())
        }
        .buttonStyle(KPressStyle())
    }

    private func load() {
        if let e = target.event {
            title = e.title
            date = AppState.date(fromKey: e.date) ?? Date()
            category = e.category
            special = e.special
            note = e.note
        } else if let pd = target.presetDate {
            date = pd
        }
    }

    private func save() {
        let t = title.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        let key = AppState.dateKey(date)
        if let e = target.event {
            state.updateEvent(EventItem(id: e.id, date: key, title: t, category: category,
                                        note: note, special: special, done: e.done))
        } else {
            state.addEvent(date: key, title: t, category: category, note: note, special: special)
        }
        dismiss()
    }
}

// MARK: - Category styling

extension EventCategory {
    var color: Color {
        switch self {
        case .travel:    return Palette.blue
        case .family:    return Palette.flame
        case .work:      return Palette.amber
        case .personal:  return Palette.brand
        case .milestone: return Palette.purple
        case .reminder:  return Palette.ice
        case .other:     return Palette.muted
        }
    }
    var icon: String {
        switch self {
        case .travel:    return "airplane"
        case .family:    return "house.fill"
        case .work:      return "briefcase.fill"
        case .personal:  return "person.fill"
        case .milestone: return "flag.fill"
        case .reminder:  return "bell.fill"
        case .other:     return "calendar"
        }
    }
}
