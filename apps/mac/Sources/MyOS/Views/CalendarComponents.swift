import SwiftUI

/// Month math on a POSIX/gregorian calendar (never Calendar.current for key strings).
enum CalMath {
    static var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "en_US_POSIX")
        return c
    }
    static func daysInMonth(year: Int, month: Int) -> Int {
        guard let d = cal.date(from: DateComponents(year: year, month: month, day: 1)),
              let range = cal.range(of: .day, in: .month, for: d) else { return 30 }
        return range.count
    }
    /// Weekday of the 1st — 0=Sun … 6=Sat.
    static func firstWeekday(year: Int, month: Int) -> Int {
        guard let d = cal.date(from: DateComponents(year: year, month: month, day: 1)) else { return 0 }
        return cal.component(.weekday, from: d) - 1
    }
    static func key(_ year: Int, _ month: Int, _ day: Int) -> String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }
    static func monthName(_ month: Int, short: Bool = false) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US")
        let syms = short ? f.shortMonthSymbols : f.monthSymbols
        return (syms?[max(0, min(11, month - 1))]) ?? ""
    }
    static func dateKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
    static func date(fromKey key: String) -> Date? {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: key)
    }
    static func todayKey() -> String { dateKey(Date()) }
    /// (isSaturday, isSunday) for a `yyyy-MM-dd` key.
    static func weekend(_ key: String) -> (sat: Bool, sun: Bool) {
        guard let d = date(fromKey: key) else { return (false, false) }
        let wd = cal.component(.weekday, from: d)   // 1=Sun … 7=Sat
        return (wd == 7, wd == 1)
    }
    static func addMonth(year: Int, month: Int, delta: Int) -> (Int, Int) {
        var m = month + delta, y = year
        while m > 12 { m -= 12; y += 1 }
        while m < 1 { m += 12; y -= 1 }
        return (y, m)
    }
}

/// The reveal every "tap the calendar icon" panel uses.
///
/// Deliberately NOT `.move(edge: .top)`: that draws the panel outside its own
/// slot, so on the way in it slides down over the rows above it and on the way
/// out it smears back through them. A fade with a hair of scale from the top
/// edge stays inside the layout, so nothing ever overlaps.
extension AnyTransition {
    static var knReveal: AnyTransition {
        .opacity.combined(with: .scale(scale: 0.985, anchor: .top))
    }
}

/// THE MyOS calendar grid — one style used everywhere (Events, the date picker,
/// the Productivity filter). Monday-first, compact rounded cells, green selected
/// day, a ring on today, and a small colored dot on days that have content.
struct KMonthGrid: View {
    let year: Int
    let month: Int
    var selected: String? = nil
    var compact: Bool = false
    var big: Bool = false          // full-width Events calendar — larger cells + type
    /// A dot colour for a day that has content (nil = no dot).
    var dot: (String) -> Color? = { _ in nil }
    /// A holiday name for a day (nil = none) — shown on hover, flagged with a top dot.
    var holiday: (String) -> String? = { _ in nil }
    /// A rich card to float on hover for a day (nil = none) — e.g. that day's memories.
    var hoverCard: (String) -> AnyView? = { _ in nil }
    var onTap: (String) -> Void = { _ in }

    private let weekdays = ["M", "T", "W", "T", "F", "S", "S"]   // Monday-first

    private var cellHeight: CGFloat { big ? 60 : (compact ? 20 : 38) }
    private var radius: CGFloat { big ? 12 : (compact ? 5 : 9) }
    private var colGap: CGFloat { big ? 6 : 0 }

    /// Always a full 6x7 board. A month needs 4-6 rows depending on where it
    /// starts, and letting the row count follow the month made the grid — and
    /// every card hosting it — resize as you paged through, which read as a jump.
    /// Padding to a fixed 42 cells keeps the height constant all year.
    static let rowCount = 6

    private var cells: [Int?] {
        let lead = (CalMath.firstWeekday(year: year, month: month) + 6) % 7   // Monday-first offset
        let days = (1...CalMath.daysInMonth(year: year, month: month)).map { Optional($0) }
        let board = Array(repeating: nil, count: lead) + days
        return board + Array(repeating: nil, count: max(0, Self.rowCount * 7 - board.count))
    }

    /// Header letter colour — Saturday blue, Sunday red, weekdays faint.
    private func weekdayTint(_ i: Int) -> Color {
        if i == 6 { return Palette.warning.opacity(0.85) }
        if i == 5 { return Palette.blue.opacity(0.85) }
        return Palette.faint
    }

    var body: some View {
        let rows = Self.rowCount
        VStack(spacing: big ? 10 : (compact ? 3 : 6)) {
            HStack(spacing: colGap) {
                ForEach(0..<7, id: \.self) { i in
                    Text(weekdays[i])
                        .font(.system(size: big ? 13 : (compact ? 8 : 10), weight: .heavy, design: .rounded))
                        .foregroundStyle(weekdayTint(i))
                        .frame(maxWidth: .infinity)
                }
            }
            VStack(spacing: big ? 6 : (compact ? 2 : 4)) {
                ForEach(0..<rows, id: \.self) { r in
                    HStack(spacing: colGap) {
                        ForEach(0..<7, id: \.self) { c in
                            let i = r * 7 + c
                            Group {
                                if i < cells.count, let day = cells[i] {
                                    let k = CalMath.key(year, month, day)
                                    DayCell(day: day, key: k, selected: selected,
                                            compact: compact, big: big, radius: radius, cellHeight: cellHeight,
                                            dotColor: dot(k), holidayName: holiday(k), hoverCard: hoverCard(k),
                                            onTap: { onTap(k) })
                                }
                                else { Color.clear.frame(height: cellHeight) }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
    }

}

/// One day button — hover lift + (optionally) a floating card of that day's memories.
private struct DayCell: View {
    let day: Int
    let key: String
    let selected: String?
    let compact: Bool
    let big: Bool
    let radius: CGFloat
    let cellHeight: CGFloat
    let dotColor: Color?
    let holidayName: String?
    let hoverCard: AnyView?
    let onTap: () -> Void

    @State private var hover = false
    @State private var showCard = false

    var body: some View {
        let isToday = key == CalMath.todayKey()
        let isSel = key == selected
        let wknd = CalMath.weekend(key)
        let numberColor: Color = isSel ? .white
            : (wknd.sun ? Palette.warning : (wknd.sat ? Palette.blue : (isToday ? Palette.action : Palette.text)))
        let weekendBG: Color = wknd.sun ? Palette.warning.opacity(0.10)
            : (wknd.sat ? Palette.blue.opacity(0.06) : .clear)
        let cellBG: Color = isSel ? Palette.action : (holidayName != nil ? Palette.attention.opacity(0.12) : weekendBG)

        return Button(action: onTap) {
            VStack(spacing: big ? 4 : (compact ? 1 : 3)) {
                Text("\(day)")
                    .font(.system(size: big ? 21 : (compact ? 9 : 13),
                                  weight: (isSel || isToday) ? .heavy : .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(numberColor)
                if !compact {
                    Circle().fill(isSel ? Color.white.opacity(dotColor == nil ? 0 : 0.9) : (dotColor ?? .clear))
                        .frame(width: big ? 7 : 5, height: big ? 7 : 5)
                }
            }
            .frame(maxWidth: .infinity).frame(height: cellHeight)
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(cellBG))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)   // hover lift
                .fill(Color.white.opacity(hover && !isSel ? 0.07 : 0)))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(borderColor(isToday: isToday, isSel: isSel), lineWidth: 1.5))
            .overlay(alignment: .top) {
                if holidayName != nil {
                    Circle().fill(isSel ? Color.white : Palette.attention)
                        .frame(width: big ? 5 : 3, height: big ? 5 : 3)
                        .padding(.top, big ? 5 : 2)
                }
            }
            .overlay(alignment: .bottom) {
                if compact, let dotColor { Circle().fill(dotColor).frame(width: 3, height: 3).padding(.bottom, 2) }
            }
            .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(holidayName ?? "")
        .onHover { h in
            hover = h
            if hoverCard != nil {
                if h { scheduleCard() } else { showCard = false }
            }
        }
        .animation(.knFast, value: hover)
        .zIndex(hover ? 1 : 0)
        .popover(isPresented: $showCard, arrowEdge: .bottom) { hoverCard }
    }

    private func borderColor(isToday: Bool, isSel: Bool) -> Color {
        if isToday && !isSel { return Palette.action.opacity(0.55) }
        if hover && !isSel { return Palette.border }
        return .clear
    }

    // Show the card after a short dwell so a quick sweep across the grid doesn't flash it.
    private func scheduleCard() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 260_000_000)
            if hover { showCard = true }
        }
    }
}

/// A compact month header — title + Today + prev/next. Shared so every calendar
/// screen navigates the same way.
struct KMonthHeader: View {
    let year: Int
    let month: Int
    var showToday: Bool = true
    let onPrev: () -> Void
    let onNext: () -> Void
    var onToday: () -> Void = {}

    var body: some View {
        HStack(spacing: 8) {
            Text("\(CalMath.monthName(month)) \(String(year))")
                .font(.callout.weight(.heavy)).foregroundStyle(Palette.text)
            Spacer()
            if showToday { Button("Today", action: onToday).buttonStyle(.borderless) }
            Button(action: onPrev) { Image(systemName: "chevron.left").font(.caption2.weight(.bold)) }
                .buttonStyle(.borderless)
            Button(action: onNext) { Image(systemName: "chevron.right").font(.caption2.weight(.bold)) }
                .buttonStyle(.borderless)
        }
    }
}

/// A MyOS-styled inline date picker — the shared month grid with nav. Replaces the
/// native macOS DatePicker so every date field stays on-brand.
struct KDatePicker: View {
    @Binding var date: Date
    @State private var viewYear: Int
    @State private var viewMonth: Int

    init(date: Binding<Date>) {
        _date = date
        let comps = CalMath.cal.dateComponents([.year, .month], from: date.wrappedValue)
        _viewYear = State(initialValue: comps.year ?? 2026)
        _viewMonth = State(initialValue: comps.month ?? 1)
    }

    var body: some View {
        VStack(spacing: 10) {
            KMonthHeader(year: viewYear, month: viewMonth, showToday: false,
                         onPrev: { shift(-1) }, onNext: { shift(1) })
            KMonthGrid(year: viewYear, month: viewMonth, selected: CalMath.dateKey(date), onTap: { key in
                if let d = CalMath.date(fromKey: key) { date = d }
            })
        }
        .padding(12)
        .background(Palette.background, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Palette.border, lineWidth: 2))
    }

    private func shift(_ d: Int) {
        let (y, m) = CalMath.addMonth(year: viewYear, month: viewMonth, delta: d)
        withAnimation(.knFast) { viewYear = y; viewMonth = m }
    }
}
