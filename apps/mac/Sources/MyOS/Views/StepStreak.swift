import SwiftUI

// The streak, and the moment a goal is crossed.
//
// The streak used to be journaling, and the mark used to be a flame. It is
// steps now, because steps is the thing being worked at — a journal entry is a
// record of the day and a step count is the day itself.

/// One day's steps, as a single mark.
///
/// Filled ring for the mandatory goal, filled ring with a halo for the stretch,
/// a hollow ring for a day that was walked but came up short, and nothing at all
/// for a day with no steps. The halo is the only thing that separates 8k from
/// 10k, deliberately: two goals should read as one road with a milestone on it,
/// not as two competing scores.
struct StepMark: View {
    let day: StepDay
    var size: CGFloat = 14

    var body: some View {
        switch day {
        case .stretch:
            ZStack {
                Circle().strokeBorder(Palette.complete.opacity(0.35), lineWidth: max(1, size * 0.1))
                    .frame(width: size, height: size)
                Circle().fill(Palette.complete).frame(width: size * 0.6, height: size * 0.6)
            }
            .frame(width: size, height: size)
        case .hit:
            Circle().fill(Palette.complete).frame(width: size * 0.6, height: size * 0.6)
                .frame(width: size, height: size)
        case .short:
            Circle().strokeBorder(Palette.warning.opacity(0.65), lineWidth: max(1, size * 0.09))
                .frame(width: size * 0.6, height: size * 0.6)
                .frame(width: size, height: size)
        case .pending:
            Circle().strokeBorder(Palette.faint.opacity(0.7), lineWidth: max(1, size * 0.09))
                .frame(width: size * 0.6, height: size * 0.6)
                .frame(width: size, height: size)
        case .none:
            Circle().fill(Palette.surfaceElevated)
                .frame(width: size * 0.4, height: size * 0.4)
                .frame(width: size, height: size)
        }
    }
}

// MARK: - Month calendar

/// A month grid that knows nothing about what it is marking.
///
/// One calendar, two callers: the steps streak marks goal days, and Journal uses
/// the same grid to jump to a date with a dot on the days that have an entry.
/// Journal's version is navigation, not a score — which is the point of pulling
/// the mark out as a closure rather than leaving it hard-wired to a flame.
struct MonthCalendar: View {
    @EnvironmentObject var state: AppState
    @Binding var viewedDate: String
    @Binding var isPresented: Bool
    var wide: Bool = false
    var onSelect: ((String) -> Void)? = nil
    var legend: AnyView? = nil
    var mark: (String) -> AnyView

    @State private var monthAnchor: String   // yyyy-MM-01

    init(viewedDate: Binding<String>, isPresented: Binding<Bool>,
         wide: Bool = false, onSelect: ((String) -> Void)? = nil,
         legend: AnyView? = nil,
         mark: @escaping (String) -> AnyView) {
        _viewedDate = viewedDate
        _isPresented = isPresented
        self.wide = wide
        self.onSelect = onSelect
        self.legend = legend
        self.mark = mark
        _monthAnchor = State(initialValue: String(viewedDate.wrappedValue.prefix(7)) + "-01")
    }

    private static let cal = Calendar(identifier: .gregorian)

    var body: some View {
        VStack(spacing: 10) {
            header
            weekdayRow
            grid
            if let legend { legend.padding(.top, 2) }
        }
        .padding(wide ? 18 : 14)
        .frame(width: wide ? nil : 268)
        .frame(maxWidth: wide ? .infinity : nil)
        .background(wide ? Palette.background : Palette.elevated)
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

        return Button {
            if let onSelect { onSelect(key) } else { viewedDate = key }
            isPresented = false
        } label: {
            VStack(spacing: 3) {
                Text("\(dayNum)")
                    .font(.caption.weight(isViewed ? .bold : .medium)).monospacedDigit()
                    .foregroundStyle(isViewed ? .white : (isFuture ? Palette.faint : Palette.text))
                mark(key)
                    .frame(height: 10)
                    .opacity(isFuture ? 0 : 1)
            }
            .frame(width: 32, height: 38)
            .background(isViewed ? Palette.action : .clear,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                if isToday && !isViewed {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Palette.action.opacity(0.6), lineWidth: 1)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .opacity(isFuture ? 0.35 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
    }

    // MARK: Month math (POSIX/gregorian keys only)

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

    private var isCurrentMonth: Bool { monthAnchor.prefix(7) == state.todayKey.prefix(7) }

    private func shiftMonth(_ n: Int) {
        guard let d = AppState.date(fromKey: monthAnchor),
              let moved = Self.cal.date(byAdding: .month, value: n, to: d) else { return }
        let c = Self.cal.dateComponents([.year, .month], from: moved)
        monthAnchor = String(format: "%04d-%02d-01", c.year ?? 2026, c.month ?? 1)
    }
}

/// The month grid, marked with step goals.
struct StepStreakCalendar: View {
    @EnvironmentObject var state: AppState
    @Binding var viewedDate: String
    @Binding var isPresented: Bool
    var wide: Bool = false
    var onSelect: ((String) -> Void)? = nil

    var body: some View {
        MonthCalendar(viewedDate: $viewedDate, isPresented: $isPresented,
                      wide: wide, onSelect: onSelect,
                      legend: AnyView(legend)) { key in
            AnyView(StepMark(day: state.stepDay(key), size: 10))
        }
    }

    private var legend: some View {
        HStack(spacing: 14) {
            HStack(spacing: 5) {
                StepMark(day: .hit, size: 10)
                Text("\(state.stepGoals.daily.formatted())")
                    .font(.caption2.weight(.medium)).foregroundStyle(Palette.muted)
            }
            HStack(spacing: 5) {
                StepMark(day: .stretch, size: 10)
                Text("\(state.stepGoals.stretch.formatted())")
                    .font(.caption2.weight(.medium)).foregroundStyle(Palette.muted)
            }
            Spacer()
            Text("\(state.stepStreak)d")
                .font(.caption2.weight(.bold)).monospacedDigit()
                .foregroundStyle(Palette.text)
        }
    }
}

/// This week's marks, Monday-first. Lives on the steps sheet, where the streak
/// belongs now.
struct StepStreakStrip: View {
    @EnvironmentObject var state: AppState

    var body: some View {
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
                        .foregroundStyle(isToday ? Palette.text : Palette.faint)
                    StepMark(day: state.stepDay(key), size: isToday ? 16 : 14)
                        .opacity(isFuture ? 0.25 : 1)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func mondayOfCurrentWeek() -> String {
        let today = state.todayKey
        guard let date = AppState.date(fromKey: today) else { return today }
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        let weekday = cal.component(.weekday, from: date)   // 1 = Sun
        let back = (weekday + 5) % 7
        return AppState.addDays(-back, to: today)
    }
}
