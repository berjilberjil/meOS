import SwiftUI

// Programs → days → muscle groups → exercises.
//
// One route enum drives the whole section instead of a NavigationStack: the
// iOS shell deliberately has no stack (a hidden nav bar re-negotiates the
// scroll view's safe area mid-scroll), and the Mac is a sidebar app that never
// pushes. Back is a button, and every level is the same view tree.

enum ProgramRoute: Hashable {
    case list
    case program(String)
    case day(programId: String, dayId: String)
}

struct ProgramsView: View {
    @EnvironmentObject var state: AppState
    @State private var route: ProgramRoute = .list

    var body: some View {
        Group {
            switch route {
            case .list:
                ProgramListView(open: { route = .program($0) })
            case .program(let id):
                if state.program(id) != nil {
                    ProgramDetailView(programId: id,
                                      back: { route = .list },
                                      openDay: { route = .day(programId: id, dayId: $0) })
                } else {
                    missing
                }
            case .day(let pid, let did):
                if let p = state.program(pid), p.days.contains(where: { $0.id == did }) {
                    ProgramDayEditorView(programId: pid, dayId: did, back: { route = .program(pid) })
                } else {
                    missing
                }
            }
        }
        .id(route)
    }

    private var missing: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("That program is gone.").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
                Button("Back to programs") { route = .list }.buttonStyle(KSecondaryButtonStyle())
            }
        }
    }
}

// MARK: - The list

struct ProgramListView: View {
    @EnvironmentObject var state: AppState
    let open: (String) -> Void
    @State private var creating = false
    @State private var editing: WorkoutProgram?

    var body: some View {
        VStack(alignment: .leading, spacing: Gap.screen) {
            if state.programs.isEmpty {
                emptyState.knRise(0)
            } else {
                VStack(alignment: .leading, spacing: Gap.row) {
                    KFieldLabel(text: "Your programs")
                    ForEach(state.programs) { p in
                        ProgramCard(program: p,
                                    isActive: p.id == state.training.activeProgramId,
                                    open: { open(p.id) },
                                    edit: { editing = p })
                    }
                }
                .knRise(0)

                Button { creating = true } label: {
                    Label("Create program", systemImage: "plus")
                        .font(.system(size: 15, weight: .semibold))
                }
                .buttonStyle(KSecondaryButtonStyle(fullWidth: true))
                .knRise(1)
            }
        }
        .sheet(isPresented: $creating) { ProgramEditorSheet(program: nil, onCreate: open) }
        .sheet(item: $editing) { p in ProgramEditorSheet(program: p, onCreate: { _ in }) }
    }

    private var emptyState: some View {
        Card(padding: 22) {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: "list.bullet.rectangle.portrait")
                    .font(.system(size: 26, weight: .semibold)).foregroundStyle(Palette.brand)
                Text("No programs yet")
                    .font(.system(size: 20, weight: .semibold)).foregroundStyle(Palette.text)
                Text("A program holds your whole training week — the days, what each day trains, and which exercises you use for it. Build it once and Today knows what's on.")
                    .font(.system(size: 14)).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Button { creating = true } label: {
                    Label("Create my first program", systemImage: "plus")
                        .font(.system(size: 15, weight: .semibold))
                }
                .buttonStyle(KPrimaryButtonStyle(fullWidth: true))
            }
        }
    }
}

private struct ProgramCard: View {
    @EnvironmentObject var state: AppState
    let program: WorkoutProgram
    let isActive: Bool
    let open: () -> Void
    let edit: () -> Void
    @State private var showDelete = false

    private var dayCount: Int { program.trainingDayCount }

    var body: some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(program.name)
                                .font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.text)
                                .fixedSize(horizontal: false, vertical: true)
                            if isActive { ActivePill() }
                        }
                        Text(subtitle)
                            .font(.system(size: 12)).foregroundStyle(Palette.faint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    menu
                }

                if let notes = program.notes, !notes.isEmpty {
                    Text(notes).font(.system(size: 13)).foregroundStyle(Palette.muted)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }

                if !groupChips.isEmpty {
                    FlowLayout(spacing: 6, runSpacing: 6) {
                        ForEach(groupChips, id: \.self) { g in MuscleChip(group: g, compact: true) }
                    }
                }

                HStack(spacing: 8) {
                    // Two styles, two buttons — the type-erased ButtonStyle that
                    // would collapse these lives in a Mac-only file.
                    if isActive {
                        Button(action: open) {
                            Label("Continue", systemImage: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .buttonStyle(KPrimaryButtonStyle())
                    } else {
                        Button(action: open) {
                            Label("View", systemImage: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .buttonStyle(KSecondaryButtonStyle())
                    }
                    if !isActive {
                        Button { state.setActiveProgram(program.id) } label: {
                            Label("Set active", systemImage: "bolt.fill").font(.system(size: 14, weight: .semibold))
                        }
                        .buttonStyle(KGhostButtonStyle(color: Palette.brand))
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
    }

    private var subtitle: String {
        var bits = ["\(dayCount) workout day\(dayCount == 1 ? "" : "s")"]
        if let g = program.goal, !g.isEmpty { bits.append(g) }
        bits.append(program.isWeekdayBound ? "by weekday" : "rotating")
        return bits.joined(separator: " · ")
    }

    /// The muscles this program covers across the week — a glance at what it is
    /// without opening it.
    private var groupChips: [MuscleGroup] {
        var seen: [MuscleGroup] = []
        for d in program.days { for g in d.groups where !seen.contains(g) { seen.append(g) } }
        return seen.sorted { $0.sortRank < $1.sortRank }
    }

    private var menu: some View {
        Menu {
            Button("Open") { open() }
            if !isActive { Button("Set as active") { state.setActiveProgram(program.id) } }
            Divider()
            Button("Rename / edit") { edit() }
            Button("Duplicate") { state.duplicateProgram(program.id) }
            Divider()
            Button("Delete", role: .destructive) { showDelete = true }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 14, weight: .bold)).foregroundStyle(Palette.faint)
                .frame(width: 30, height: 30).contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 30)
        .holdToDelete(isPresented: $showDelete, title: "Delete \(program.name)?",
                      message: "Removes the program and its days. Workouts you already logged stay in your history.") {
            state.deleteProgram(program.id)
        }
    }
}

struct ActivePill: View {
    var body: some View {
        Text("ACTIVE")
            .font(.system(size: 9, weight: .heavy, design: .rounded)).tracking(0.6)
            .foregroundStyle(Palette.brand)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Palette.brand.opacity(0.16), in: Capsule())
    }
}

// MARK: - Program detail (the schedule)

struct ProgramDetailView: View {
    @EnvironmentObject var state: AppState
    let programId: String
    let back: () -> Void
    let openDay: (String) -> Void
    @State private var editing = false
    @State private var addingDay = false

    private var program: WorkoutProgram? { state.program(programId) }

    var body: some View {
        VStack(alignment: .leading, spacing: Gap.screen) {
            if let p = program {
                BackBar(title: "Programs", action: back).knRise(0)
                header(p).knRise(1)
                schedule(p).knRise(2)
            }
        }
        .sheet(isPresented: $editing) {
            if let p = program { ProgramEditorSheet(program: p, onCreate: { _ in }) }
        }
        .sheet(isPresented: $addingDay) {
            if let p = program { DaySettingsSheet(programId: p.id, day: nil) }
        }
    }

    private func header(_ p: WorkoutProgram) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(p.name)
                    .font(.system(size: 26, weight: .semibold)).foregroundStyle(Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                if p.id == state.training.activeProgramId { ActivePill() }
                Spacer(minLength: 0)
            }
            Text(subtitle(p)).font(.system(size: 13)).foregroundStyle(Palette.faint)
            if let n = p.notes, !n.isEmpty {
                Text(n).font(.system(size: 13)).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                if p.id != state.training.activeProgramId {
                    Button { state.setActiveProgram(p.id) } label: {
                        Label("Set as active", systemImage: "bolt.fill").font(.system(size: 14, weight: .semibold))
                    }
                    .buttonStyle(KPrimaryButtonStyle())
                }
                Button { editing = true } label: { Label("Edit", systemImage: "pencil") }
                    .buttonStyle(KGhostButtonStyle())
                Button { state.duplicateProgram(p.id) } label: { Label("Duplicate", systemImage: "doc.on.doc") }
                    .buttonStyle(KGhostButtonStyle())
                Spacer(minLength: 0)
            }
        }
    }

    private func subtitle(_ p: WorkoutProgram) -> String {
        let n = p.trainingDayCount
        var bits = ["\(n) workout day\(n == 1 ? "" : "s")"]
        if let g = p.goal, !g.isEmpty { bits.append(g) }
        bits.append(p.isWeekdayBound ? "runs by weekday" : "rotates day by day")
        return bits.joined(separator: " · ")
    }

    private func schedule(_ p: WorkoutProgram) -> some View {
        VStack(alignment: .leading, spacing: Gap.row) {
            KFieldLabel(text: p.isWeekdayBound ? "Weekly schedule" : "Rotation")
            if p.days.isEmpty {
                Card {
                    Text("No days yet. Add one to start building the week.")
                        .font(.system(size: 13)).foregroundStyle(Palette.faint)
                }
            }
            ForEach(Array(p.days.enumerated()), id: \.element.id) { i, day in
                ProgramDayRow(programId: p.id, day: day, index: i, count: p.days.count,
                              isToday: isToday(p, day),
                              open: { openDay(day.id) })
            }
            Button { addingDay = true } label: { Label("Add day", systemImage: "plus") }
                .buttonStyle(KSecondaryButtonStyle(fullWidth: true))
        }
    }

    private func isToday(_ p: WorkoutProgram, _ day: ProgramDay) -> Bool {
        guard p.id == state.training.activeProgramId else { return false }
        return state.programDay(for: state.todayKey)?.day.id == day.id
    }
}

/// One day in the schedule — the weekday tag, the day's name, what it trains,
/// and the reorder/duplicate/delete menu.
private struct ProgramDayRow: View {
    @EnvironmentObject var state: AppState
    let programId: String
    let day: ProgramDay
    let index: Int
    let count: Int
    let isToday: Bool
    let open: () -> Void
    @State private var showDelete = false
    @State private var settings = false

    private static let short = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]

    var body: some View {
        Card(padding: 14) {
            HStack(alignment: .top, spacing: 12) {
                tag
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text(day.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(day.isRestDay ? Palette.muted : Palette.text)
                            .fixedSize(horizontal: false, vertical: true)
                        if isToday {
                            Text("TODAY")
                                .font(.system(size: 8, weight: .heavy, design: .rounded)).tracking(0.6)
                                .foregroundStyle(Palette.brand)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Palette.brand.opacity(0.16), in: Capsule())
                        }
                    }
                    if day.isRestDay {
                        Label("Rest day", systemImage: "moon.zzz.fill")
                            .font(.system(size: 12)).foregroundStyle(Palette.blue)
                    } else if day.exerciseCount == 0 {
                        Text("Nothing planned yet").font(.system(size: 12)).foregroundStyle(Palette.faint)
                    } else {
                        Text(day.groupSummary)
                            .font(.system(size: 12)).foregroundStyle(Palette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(day.exerciseCount) exercise\(day.exerciseCount == 1 ? "" : "s")")
                            .font(.system(size: 11)).foregroundStyle(Palette.faint)
                    }
                }
                Spacer(minLength: 4)
                menu
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.faint)
                    .padding(.top, 8)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .sheet(isPresented: $settings) { DaySettingsSheet(programId: programId, day: day) }
    }

    private var tag: some View {
        let label = day.weekday.map { Self.short[$0] } ?? "D\(index + 1)"
        let tint = day.isRestDay ? Palette.blue : Palette.brand
        return Text(label)
            .font(.system(size: 10, weight: .heavy, design: .rounded)).tracking(0.4)
            .foregroundStyle(tint)
            .frame(width: 42, height: 30)
            .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    private var menu: some View {
        Menu {
            Button("Open") { open() }
            Button("Rename / schedule") { settings = true }
            Button(day.isRestDay ? "Make it a training day" : "Make it a rest day") {
                state.setDayRest(programId, day.id, !day.isRestDay)
            }
            Divider()
            Button("Move up") { move(-1) }.disabled(index == 0)
            Button("Move down") { move(1) }.disabled(index >= count - 1)
            Button("Duplicate") { state.duplicateDay(programId, day.id) }
            Divider()
            Button("Delete", role: .destructive) { showDelete = true }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.faint)
                .frame(width: 28, height: 28).contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 28)
        .holdToDelete(isPresented: $showDelete, title: "Delete \(day.name)?",
                      message: "Removes the day and its exercises from this program.") {
            state.deleteDay(programId, day.id)
        }
    }

    private func move(_ delta: Int) {
        guard let to = AppState.moveOffset(from: index, delta: delta, count: count) else { return }
        state.moveProgramDays(programId, from: IndexSet(integer: index), to: to)
    }
}

struct BackBar: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "chevron.left").font(.system(size: 12, weight: .bold))
                Text(title).font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(Palette.muted)
            .padding(.vertical, 4).contentShape(Rectangle())
        }
        .buttonStyle(KPressStyle())
        .onHover { h in cursor(h) }
    }
}
