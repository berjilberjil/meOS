import SwiftUI

/// Month grid for switching which day's progress photo you're viewing — same
/// shape as the journal's `StreakCalendar`, but the "flame" is simply whether
/// that day has at least one photo (and, once cloud sync lands, whether it's
/// still uploading).
struct ProgressPhotoCalendar: View {
    /// Every day that has at least one local photo.
    let photoDates: Set<String>
    /// Days that have a photo but haven't been confirmed on the server yet.
    let pendingDates: Set<String>
    @Binding var selected: String
    /// Called (in addition to updating `selected`) when a day is tapped.
    var onSelect: ((String) -> Void)? = nil

    @State private var monthAnchor: String

    init(photoDates: Set<String>, pendingDates: Set<String> = [], selected: Binding<String>,
         onSelect: ((String) -> Void)? = nil) {
        self.photoDates = photoDates
        self.pendingDates = pendingDates
        _selected = selected
        self.onSelect = onSelect
        _monthAnchor = State(initialValue: String(selected.wrappedValue.prefix(7)) + "-01")
    }

    private static let cal = Calendar(identifier: .gregorian)
    private var todayKey: String { AppState.dateKey(Date()) }

    var body: some View {
        VStack(spacing: 10) {
            header
            weekdayRow
            grid
        }
    }

    private var header: some View {
        HStack {
            Button { shiftMonth(-1) } label: {
                Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(KIconButtonStyle(size: 24))
            Spacer()
            Text(monthTitle).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.text)
            Spacer()
            Button { shiftMonth(1) } label: {
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(KIconButtonStyle(size: 24))
            .disabled(isCurrentMonth)
            .opacity(isCurrentMonth ? 0.3 : 1)
        }
    }

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { _, d in
                Text(d).font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.faint)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// Always six rows. A month spans 4-6 depending on where it starts, and
    /// following that made the whole card resize as you paged — the jump the
    /// shared `KMonthGrid` had too.
    private static let rowCount = 6

    private var grid: some View {
        let cells = monthCells
        return VStack(spacing: 3) {
            ForEach(0..<Self.rowCount, id: \.self) { row in
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
        let isSelected = key == selected
        let isToday = key == todayKey
        let isFuture = key > todayKey
        let hasPhoto = photoDates.contains(key)
        let isPending = pendingDates.contains(key)

        return Button {
            selected = key
            onSelect?(key)
        } label: {
            VStack(spacing: 3) {
                Text("\(dayNum)")
                    .font(.system(size: 12, weight: isSelected ? .bold : .medium)).monospacedDigit()
                    .foregroundStyle(isSelected ? .white : (isFuture ? Palette.faint : Palette.text))
                Circle()
                    .fill(hasPhoto ? (isSelected ? Color.white : (isPending ? Palette.amber : Palette.teal)) : .clear)
                    .frame(width: 6, height: 6)
                    .frame(height: 8)
            }
            .frame(width: 32, height: 38)
            .background(isSelected ? Palette.brand : .clear,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                if isToday && !isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Palette.brand.opacity(0.6), lineWidth: 1)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .opacity(isFuture ? 0.35 : 1)
        }
        .buttonStyle(KPressStyle(scale: 0.92))
        .disabled(isFuture)
    }

    // MARK: Month math (POSIX/gregorian keys only — same approach as StreakCalendar)

    private var monthCells: [String?] {
        guard let first = AppState.date(fromKey: monthAnchor) else { return [] }
        let dayCount = Self.cal.range(of: .day, in: .month, for: first)?.count ?? 30
        let weekday = Self.cal.component(.weekday, from: first)
        let lead = (weekday + 5) % 7
        let prefix = String(monthAnchor.prefix(8))
        let board: [String?] = Array(repeating: nil, count: lead)
            + (1...dayCount).map { prefix + String(format: "%02d", $0) }
        return board + Array(repeating: nil, count: max(0, Self.rowCount * 7 - board.count))
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
        monthAnchor.prefix(7) == todayKey.prefix(7)
    }

    private func shiftMonth(_ n: Int) {
        guard let d = AppState.date(fromKey: monthAnchor),
              let moved = Self.cal.date(byAdding: .month, value: n, to: d) else { return }
        withAnimation(.knFast) { monthAnchor = String(AppState.dateKey(moved).prefix(7)) + "-01" }
    }
}
