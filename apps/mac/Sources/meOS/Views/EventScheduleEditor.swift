import SwiftUI

/// The "when, how often, and warn me when" half of the event editor.
///
/// One view for both platforms — the controls are all plain SwiftUI, and an
/// event that repeats yearly on the Mac has to mean the same thing on the phone,
/// so there is one place that decides what the rule is.
///
/// Progressive, deliberately. A memory logged after the fact needs a date and
/// nothing else, and that is what you get: three closed rows. Time, repeat and
/// reminders each open only when you say the event has one.
struct EventScheduleEditor: View {
    @Binding var time: String?
    @Binding var recurrence: Recurrence
    @Binding var reminders: [ReminderLead]

    /// Held as a `Date` because that is what `DatePicker` speaks; the binding
    /// above stays `HH:mm` because that is what syncs.
    @State private var timeOfDay = Date()
    @State private var untilDate = Date()
    @State private var seeded = false

    private var hasTime: Bool { time != nil }
    private var repeats: Bool { recurrence.repeats }
    private var hasEnd: Bool { recurrence.until != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            timeSection
            divider
            repeatSection
            divider
            reminderSection
        }
        .onAppear(perform: seed)
        .onChange(of: timeOfDay) { _, now in
            guard hasTime else { return }
            time = Self.hhmm(from: now)
        }
        .onChange(of: untilDate) { _, now in
            guard hasEnd else { return }
            recurrence.until = AppState.dateKey(now)
        }
    }

    private var divider: some View {
        Rectangle().fill(Palette.border.opacity(0.6)).frame(height: 1)
    }

    // MARK: - Time

    private var timeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(
                get: { hasTime },
                set: { on in time = on ? Self.hhmm(from: timeOfDay) : nil }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Give it a time").font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.text)
                    Text(hasTime
                         ? "Reminders count back from this."
                         : "All day. Reminders arrive at \(EventNotifier.clock(EventNotifier.defaultHour * 60)).")
                        .font(.caption2).foregroundStyle(Palette.faint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(Palette.action)

            if hasTime {
                DatePicker("", selection: $timeOfDay, displayedComponents: .hourAndMinute)
                    .labelsHidden().tint(Palette.action)
            }
        }
    }

    // MARK: - Repeat

    private var repeatSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            KFieldLabel(text: "Repeat")

            // Chips rather than a menu: five options is fewer taps shown than
            // hidden, and "Yearly" being visible is what makes anyone realise a
            // birthday can be logged once instead of every year.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(Recurrence.Unit.allCases) { unit in
                        chip(unit.label, on: recurrence.unit == unit) {
                            recurrence.unit = unit
                            if unit == .none { recurrence.until = nil; recurrence.interval = 1 }
                        }
                    }
                }
                .padding(.horizontal, 1)
            }

            if repeats {
                HStack(spacing: 10) {
                    Text("Every").font(.caption).foregroundStyle(Palette.muted)
                    Stepper(value: Binding(get: { recurrence.interval },
                                           set: { recurrence.interval = max(1, $0) }),
                            in: 1...30) {
                        Text(recurrence.interval == 1
                             ? String(recurrence.unit.plural.dropLast())      // "year"
                             : "\(recurrence.interval) \(recurrence.unit.plural)")
                            .font(.caption.weight(.semibold)).monospacedDigit()
                            .foregroundStyle(Palette.text)
                    }
                }

                Toggle(isOn: Binding(
                    get: { hasEnd },
                    set: { on in recurrence.until = on ? AppState.dateKey(untilDate) : nil }
                )) {
                    Text("Stop after a date").font(.caption).foregroundStyle(Palette.muted)
                }
                .tint(Palette.action)

                if hasEnd {
                    DatePicker("", selection: $untilDate, displayedComponents: .date)
                        .labelsHidden().tint(Palette.action)
                }

                Text(EventRecurrence.describe(recurrence))
                    .font(.caption2).foregroundStyle(Palette.faint)
            }
        }
    }

    // MARK: - Reminders

    private var reminderSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                KFieldLabel(text: "Remind me")
                Spacer()
                if !reminders.isEmpty {
                    Button("None") { reminders = [] }
                        .font(.caption2.weight(.semibold))
                        .buttonStyle(.plain).foregroundStyle(Palette.faint)
                }
            }

            // Every lead visible at once. A menu would hide the fact that you can
            // have more than one, and more than one is the point — a month out to
            // plan it, the day before to actually do something.
            FlowChips(leads: ReminderLead.ordered, selected: reminders) { lead in
                if let i = reminders.firstIndex(of: lead) { reminders.remove(at: i) }
                else { reminders.append(lead) }
                reminders.sort { $0.days < $1.days }
            }

            Text(summary)
                .font(.caption2).foregroundStyle(Palette.faint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// What the choices add up to, in one line.
    private var summary: String {
        guard !reminders.isEmpty else { return "No reminder." }
        let names = reminders.sorted { $0.days > $1.days }.map(\.shortLabel).joined(separator: ", ")
        let when = hasTime ? " at \(EventNotifier.clock(EventNotifier.minutes(fromTime: time) ?? 0))"
                           : " at \(EventNotifier.clock(EventNotifier.defaultHour * 60))"
        return "Notifies \(names)\(when)."
    }

    // MARK: - Chips

    private func chip(_ text: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(on ? Palette.background : Palette.muted)
                .padding(.horizontal, 11).padding(.vertical, 6)
                .background(on ? AnyShapeStyle(Palette.action)
                               : AnyShapeStyle(Palette.action.opacity(0.12)), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Seeding

    private func seed() {
        guard !seeded else { return }
        seeded = true
        if let mins = EventNotifier.minutes(fromTime: time) {
            timeOfDay = Self.date(hour: mins / 60, minute: mins % 60)
        } else {
            timeOfDay = Self.date(hour: EventNotifier.defaultHour, minute: EventNotifier.defaultMinute)
        }
        if let until = recurrence.until, let d = AppState.date(fromKey: until) { untilDate = d }
    }

    static func hhmm(from date: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let c = cal.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    private static func date(hour: Int, minute: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        return cal.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }
}

/// The reminder leads, wrapped over as many rows as they need.
///
/// Seven chips do not fit on one phone row and a horizontal scroller would hide
/// half of them behind a gesture — which for a control whose whole job is to
/// show you that several are possible would be the wrong trade.
private struct FlowChips: View {
    let leads: [ReminderLead]
    let selected: [ReminderLead]
    let toggle: (ReminderLead) -> Void

    private var rows: [[ReminderLead]] {
        stride(from: 0, to: leads.count, by: 3).map {
            Array(leads[$0..<min($0 + 3, leads.count)])
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 7) {
                    ForEach(row) { lead in
                        let on = selected.contains(lead)
                        Button { toggle(lead) } label: {
                            HStack(spacing: 4) {
                                if on {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9, weight: .bold))
                                }
                                Text(lead.label).font(.caption.weight(.semibold))
                            }
                            .foregroundStyle(on ? Palette.background : Palette.muted)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .frame(maxWidth: .infinity)
                            .background(on ? AnyShapeStyle(Palette.blue)
                                           : AnyShapeStyle(Palette.blue.opacity(0.12)),
                                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    // Keeps the last row's chips the same width as the rest.
                    if row.count < 3 {
                        ForEach(0..<(3 - row.count), id: \.self) { _ in
                            Color.clear.frame(maxWidth: .infinity).frame(height: 1)
                        }
                    }
                }
            }
        }
    }
}
