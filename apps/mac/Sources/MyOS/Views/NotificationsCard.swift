import SwiftUI

/// Settings card for the daily reminders (food / workout / weight+journal).
/// Master toggle requests notification permission; each row has its own time and
/// on/off. Device-local via `ReminderStore`. Shared by mac + iOS.
struct NotificationsCard: View {
    @ObservedObject private var store = ReminderStore.shared

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionTitle(text: "Reminders")
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { store.enabled },
                        set: { on in
                            if on { Task { await store.requestAuthorization() } }
                            else { store.enabled = false }
                        }
                    )).labelsHidden().tint(Palette.brand)
                }
                Text("Daily nudges to eat, train, and log your weight + journal.")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)

                if store.enabled {
                    ForEach(store.reminders) { r in
                        Divider().overlay(Palette.border)
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.label).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.text)
                                Text(r.body).font(.system(size: 11)).foregroundStyle(Palette.faint).lineLimit(1)
                            }
                            Spacer()
                            DatePicker("", selection: timeBinding(r), displayedComponents: .hourAndMinute)
                                .labelsHidden()
                                .disabled(!r.enabled)
                                .opacity(r.enabled ? 1 : 0.4)
                            Toggle("", isOn: Binding(
                                get: { r.enabled },
                                set: { store.setEnabled(id: r.id, $0) }
                            )).labelsHidden().tint(Palette.brand)
                        }
                    }
                } else {
                    Text("Turn on to get reminded at 6am (log), 8am, 12:30pm, 4pm (workout) and 7pm.")
                        .font(.system(size: 11)).foregroundStyle(Palette.faint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .task { await store.refreshAuthorization() }
    }

    private func timeBinding(_ r: Reminder) -> Binding<Date> {
        Binding(
            get: {
                var c = DateComponents(); c.hour = r.hour; c.minute = r.minute
                return Calendar.current.date(from: c) ?? Date()
            },
            set: { newDate in
                let c = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                store.setTime(id: r.id, hour: c.hour ?? r.hour, minute: c.minute ?? r.minute)
            }
        )
    }
}
