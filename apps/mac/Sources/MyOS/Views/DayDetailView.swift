import SwiftUI

/// One calendar, one day, everything that happened on it.
///
/// Today pages by swipe for nearby days; this is for jumping somewhere far away
/// and seeing the whole day at once. It replaces the per-card month grids that
/// used to sit on Activity, Focus, Daily Progress and Coming Up — four separate
/// calendars answering the same question.
struct DayDetailView: View {
    @EnvironmentObject var state: AppState

    @State private var year: Int = 0
    @State private var month: Int = 0
    @State private var selected: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Gap.screen) {
            // No "Pick a day" caption: the month header already says which month
            // you are in, and the grid is unmistakably a date picker. The line
            // cost a row of height on a screen whose whole job is to leave room
            // for the day underneath it.
            Card(padding: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    KMonthHeader(year: year, month: month, showToday: true,
                                 onPrev: { shift(-1) }, onNext: { shift(1) },
                                 onToday: { jumpToToday() })
                    KMonthGrid(year: year, month: month, selected: selected,
                               onTap: { key in
                                   Haptics.selection()
                                   withAnimation(.knFast) { selected = key }
                               })
                }
            }

            if !selected.isEmpty { daySummary }
        }
        .onAppear(perform: jumpToTodayIfNeeded)
    }

    // MARK: The day

    private var daySummary: some View {
        VStack(alignment: .leading, spacing: Gap.row) {
            // The date is the heading for everything under it, so it is typed
            // like one — the relative label rides along as a pill rather than
            // competing as a second piece of text.
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text(prettyDate(selected))
                    .font(.title3.weight(.semibold)).foregroundStyle(Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(DayPaging.label(selected, today: state.todayKey).uppercased())
                    .font(.caption2.weight(.heavy)).tracking(0.6)
                    .foregroundStyle(Palette.action)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Palette.action.opacity(0.14), in: Capsule())
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 2)

            ActivityStepsCard(day: selected, showsCalendar: false)
            DayMacroHero(day: selected)
            mealsRow
            WorkoutChecklistCard(day: selected)
            WatchLogCard(day: selected)
            FocusCard(day: selected, showsCalendar: false)
            eventsCard
        }
    }

    private var mealsRow: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(text: "Meals")
                ForEach(MealKey.allCases, id: \.self) { meal in
                    let names = state.mealDisplayItems(date: selected, meal: meal)
                        .compactMap { state.food($0.foodId)?.name }
                    HStack(alignment: .top, spacing: 8) {
                        Text(meal.label)
                            .font(.caption.weight(.semibold)).foregroundStyle(Palette.muted)
                            .frame(width: 74, alignment: .leading)
                        Text(names.isEmpty ? "—" : names.joined(separator: ", "))
                            .font(.caption).foregroundStyle(names.isEmpty ? Palette.faint : Palette.text)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private var eventsCard: some View {
        let onDay = state.events.filter { $0.date == selected }
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(text: "Events")
                if onDay.isEmpty {
                    Text("Nothing logged.").font(.caption).foregroundStyle(Palette.faint)
                } else {
                    ForEach(onDay) { e in
                        HStack(spacing: 8) {
                            if let t = state.primaryTag(for: e) {
                                Image(systemName: t.symbol).font(.caption2.weight(.bold))
                                    .foregroundStyle(t.color)
                            }
                            Text(e.title).font(.footnote.weight(.semibold))
                                .foregroundStyle(Palette.text)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            if !e.media.isEmpty {
                                Label("\(e.media.count)", systemImage: "photo")
                                    .font(.caption2).foregroundStyle(Palette.faint)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Month navigation

    private func jumpToTodayIfNeeded() {
        guard selected.isEmpty else { return }
        jumpToToday()
    }

    private func jumpToToday() {
        selected = state.todayKey
        let parts = state.todayKey.split(separator: "-")
        year = Int(parts.first ?? "") ?? year
        month = parts.count > 1 ? (Int(parts[1]) ?? month) : month
    }

    private func shift(_ delta: Int) {
        var m = month + delta, y = year
        if m < 1 { m = 12; y -= 1 }
        if m > 12 { m = 1; y += 1 }
        withAnimation(.knNormal) { month = m; year = y }
    }

    private func prettyDate(_ key: String) -> String {
        guard let d = AppState.date(fromKey: key) else { return key }
        let f = DateFormatter(); f.dateFormat = "EEEE, d MMMM yyyy"
        return f.string(from: d)
    }
}
