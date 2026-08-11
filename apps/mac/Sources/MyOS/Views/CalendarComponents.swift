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
    var onTap: (String) -> Void = { _ in }

    private let weekdays = ["M", "T", "W", "T", "F", "S", "S"]   // Monday-first

    private var cellHeight: CGFloat { big ? 60 : (compact ? 20 : 38) }
    private var radius: CGFloat { big ? 12 : (compact ? 5 : 9) }
    private var colGap: CGFloat { big ? 6 : 0 }

    private var cells: [Int?] {
        let lead = (CalMath.firstWeekday(year: year, month: month) + 6) % 7   // Monday-first offset
        return Array(repeating: nil, count: lead)
            + (1...CalMath.daysInMonth(year: year, month: month)).map { Optional($0) }
    }

    /// Header letter colour — Saturday blue, Sunday red, weekdays faint.
    private func weekdayTint(_ i: Int) -> Color {
        if i == 6 { return Palette.red.opacity(0.85) }
        if i == 5 { return Palette.blue.opacity(0.85) }
        return Palette.faint
    }

    var body: some View {
        let rows = (cells.count + 6) / 7
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
                                if i < cells.count, let day = cells[i] { cell(day) }
                                else { Color.clear.frame(height: cellHeight) }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
    }

    private func cell(_ day: Int) -> some View {
        let key = CalMath.key(year, month, day)
        let isToday = key == CalMath.todayKey()
        let isSel = key == selected
        let dc = dot(key)
        let hol = holiday(key)
        let wknd = CalMath.weekend(key)
        let numberColor: Color = isSel ? .white
            : (wknd.sun ? Palette.red : (wknd.sat ? Palette.blue : (isToday ? Palette.brand : Palette.text)))
        let weekendBG: Color = wknd.sun ? Palette.red.opacity(0.10)
            : (wknd.sat ? Palette.blue.opacity(0.06) : .clear)
        let cellBG: Color = isSel ? Palette.brand : (hol != nil ? Palette.amber.opacity(0.12) : weekendBG)

        return Button { onTap(key) } label: {
            VStack(spacing: big ? 4 : (compact ? 1 : 3)) {
                Text("\(day)")
                    .font(.system(size: big ? 21 : (compact ? 9 : 13),
                                  weight: (isSel || isToday) ? .heavy : .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(numberColor)
                if !compact {
                    Circle().fill(isSel ? Color.white.opacity(dc == nil ? 0 : 0.9) : (dc ?? .clear))
                        .frame(width: big ? 7 : 5, height: big ? 7 : 5)
                }
            }
            .frame(maxWidth: .infinity).frame(height: cellHeight)
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(cellBG))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(isToday && !isSel ? Palette.brand.opacity(0.55) : .clear, lineWidth: 1.5))
            .overlay(alignment: .top) {
                if hol != nil {
                    Circle().fill(isSel ? Color.white : Palette.amber)
                        .frame(width: big ? 5 : 3, height: big ? 5 : 3)
                        .padding(.top, big ? 5 : 2)
                }
            }
            .overlay(alignment: .bottom) {
                if compact, let dc { Circle().fill(dc).frame(width: 3, height: 3).padding(.bottom, 2) }
            }
            .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
        .buttonStyle(KPressStyle(scale: 0.92))
        .help(hol ?? "")
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
                .font(.system(size: 16, weight: .heavy, design: .rounded)).foregroundStyle(Palette.text)
            Spacer()
            if showToday { Button("Today", action: onToday).buttonStyle(KGhostButtonStyle()) }
            Button(action: onPrev) { Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold)) }
                .buttonStyle(KIconButtonStyle(size: 26))
            Button(action: onNext) { Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)) }
                .buttonStyle(KIconButtonStyle(size: 26))
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
            KMonthGrid(year: viewYear, month: viewMonth, selected: CalMath.dateKey(date)) { key in
                if let d = CalMath.date(fromKey: key) { date = d }
            }
        }
        .padding(12)
        .background(Palette.bg, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Palette.border, lineWidth: 2))
    }

    private func shift(_ d: Int) {
        let (y, m) = CalMath.addMonth(year: viewYear, month: viewMonth, delta: d)
        withAnimation(.knFast) { viewYear = y; viewMonth = m }
    }
}
