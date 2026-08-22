import SwiftUI

/// Settings card for the daily reminders (food / workout / weight+journal).
/// Master toggle requests notification permission; each row has its own time and
/// on/off. Device-local via `ReminderStore`. Shared by mac + iOS.
///
/// On the phone the master sits in a card of its own above the list, because a
/// master switch that is merely the first row of the same card does not read as
/// governing the rows beneath it.
struct NotificationsCard: View {
    var boxed = true
    @ObservedObject private var store = ReminderStore.shared

    var body: some View {
        Group {
            if boxed { Card { boxedInner } } else { page }
        }
        .task { await store.refreshAuthorization() }
    }

    // MARK: - Phone: a page

    private var page: some View {
        SettingsPage {
            SettingsIntro(text: "Nudges on this device, at the times you choose.")

            SettingsGroup(footer: store.enabled
                          ? nil
                          : "Turn on to get nudged at 6am, 8am, 12:30pm, 4pm and 7pm.") {
                SettingsToggleRow(title: "All reminders",
                                  subtitle: "Eat, train, log weight and journal.",
                                  icon: "bell.fill", tint: Palette.amber,
                                  isOn: master)
            }

            if store.enabled {
                SettingsGroup(title: "Daily") {
                    ForEach(Array(store.reminders.enumerated()), id: \.element.id) { i, r in
                        if i > 0 { SettingsDivider(inset: SettingsMetrics.plainInset) }
                        reminderRow(r)
                    }
                }
            }
        }
    }

    private func reminderRow(_ r: Reminder) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(r.label)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(r.enabled ? Palette.text : Palette.muted)
                Text(r.body)
                    .font(.system(size: 12)).foregroundStyle(Palette.faint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            timePicker(r)
            Toggle("", isOn: Binding(get: { r.enabled },
                                     set: { store.setEnabled(id: r.id, $0) }))
                .labelsHidden().tint(Palette.brand)
        }
        .padding(.horizontal, SettingsMetrics.rowPadH)
        .padding(.vertical, 11)
    }

    private func timePicker(_ r: Reminder) -> some View {
        DatePicker("", selection: timeBinding(r), displayedComponents: .hourAndMinute)
            .labelsHidden()
            #if os(iOS)
            .datePickerStyle(.compact)
            #endif
            .disabled(!r.enabled)
            .opacity(r.enabled ? 1 : 0.35)
            .animation(.knFast, value: r.enabled)
    }

    private var master: Binding<Bool> {
        Binding(
            get: { store.enabled },
            set: { on in
                if on { Task { await store.requestAuthorization() } }
                else { store.enabled = false }
            }
        )
    }

    // MARK: - Mac: a card

    private var boxedInner: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(text: "Reminders")
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("All reminders")
                        .font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.text)
                    Text("Eat, train, log weight and journal.")
                        .font(.system(size: 13)).foregroundStyle(Palette.muted)
                }
                Spacer()
                Toggle("", isOn: master).labelsHidden().tint(Palette.brand)
            }

            if store.enabled {
                ForEach(store.reminders) { r in
                    Divider().overlay(Palette.border)
                    HStack(alignment: .center, spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(r.label).font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.text)
                            Text(r.body).font(.system(size: 13)).foregroundStyle(Palette.faint)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        DatePicker("", selection: timeBinding(r), displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .disabled(!r.enabled)
                            .opacity(r.enabled ? 1 : 0.4)
                        Toggle("", isOn: Binding(get: { r.enabled },
                                                 set: { store.setEnabled(id: r.id, $0) }))
                            .labelsHidden().tint(Palette.brand)
                    }
                }
            } else {
                Text("Turn on to get nudged at 6am, 8am, 12:30pm, 4pm and 7pm.")
                    .font(.system(size: 14)).foregroundStyle(Palette.faint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
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
