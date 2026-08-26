import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

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
                                  icon: "bell.fill", tint: Palette.attention,
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
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(r.enabled ? Palette.text : Palette.muted)
                Text(r.body)
                    .font(.caption).foregroundStyle(Palette.faint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            soundPicker(r)
            timePicker(r)
            Toggle("", isOn: Binding(get: { r.enabled },
                                     set: { store.setEnabled(id: r.id, $0) }))
                .labelsHidden().tint(Palette.action)
        }
        .padding(.horizontal, SettingsMetrics.rowPadH)
        .padding(.vertical, 11)
    }

    /// Each reminder gets its own voice. Five that all go "ding" are five you
    /// learn to ignore without looking; a different sound for lunch and for the
    /// workout means the phone in your pocket has already told you which.
    ///
    /// Picking one plays it, because a list of sound names is not a way to
    /// choose a sound.
    private func soundPicker(_ r: Reminder) -> some View {
        Menu {
            ForEach(ReminderSound.available) { choice in
                Button {
                    store.setSound(id: r.id, choice)
                    ReminderSoundPreview.play(choice)
                } label: {
                    if choice == r.sound {
                        Label(choice.label, systemImage: "checkmark")
                    } else {
                        Text(choice.label)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: r.sound == .silent ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.caption2)
                Text(r.sound.label).font(.caption.weight(.semibold))
            }
            .foregroundStyle(r.enabled ? Palette.muted : Palette.faint)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(!r.enabled)
        .opacity(r.enabled ? 1 : 0.35)
        .help("Notification sound")
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

    /// Straight to this app's notification settings on both platforms.
    private func openNotificationSettings() {
        #if os(macOS)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
        #else
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #endif
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
                        .font(.body.weight(.semibold)).foregroundStyle(Palette.text)
                    Text("Eat, train, log weight and journal.")
                        .font(.footnote).foregroundStyle(Palette.muted)
                }
                Spacer()
                Toggle("", isOn: master).labelsHidden().tint(Palette.action)
            }

            // The card used to read only `enabled`, which lives in UserDefaults
            // and survives permission being revoked in System Settings — so it
            // went on showing the master switch on and five rows with their
            // times while nothing was ever delivered. The mirror case: if
            // permission was denied once, tapping the toggle gets no prompt at
            // all and the switch silently springs back.
            if store.isSilentlyOff {
                SettingsNotice(text: "Notifications are turned off for MyOS, so these reminders "
                               + "will not arrive. Turn them on in System Settings.",
                               actionLabel: "Open Settings") { openNotificationSettings() }
            }

            if store.enabled {
                ForEach(store.reminders) { r in
                    Divider().overlay(Palette.border)
                    HStack(alignment: .center, spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(r.label).font(.callout.weight(.semibold)).foregroundStyle(Palette.text)
                            Text(r.body).font(.footnote).foregroundStyle(Palette.faint)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        DatePicker("", selection: timeBinding(r), displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .disabled(!r.enabled)
                            .opacity(r.enabled ? 1 : 0.4)
                        Toggle("", isOn: Binding(get: { r.enabled },
                                                 set: { store.setEnabled(id: r.id, $0) }))
                            .labelsHidden().tint(Palette.action)
                    }
                }
            } else {
                Text("Turn on to get nudged at 6am, 8am, 12:30pm, 4pm and 7pm.")
                    .font(.footnote).foregroundStyle(Palette.faint)
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
