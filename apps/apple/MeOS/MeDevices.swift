import SwiftUI

/// Settings → Devices.
///
/// The list comes from the server's account registry, not the encrypted state
/// blob: a device that has not unlocked its vault yet still has to show up, and
/// "last active" advances without every device rewriting the same document.
/// Everything here is metadata — a name, a machine name, an OS version and two
/// timestamps. No synced content is exposed.
struct MeDevices: View {
    @EnvironmentObject var state: AppState

    @State private var devices: [AccountDevice] = []
    @State private var loading = true
    @State private var error: String?
    @State private var renaming: AccountDevice?
    @State private var showRename = false
    @State private var draft = ""

    private var currentID: String { ActivityDeviceIdentity.deviceId }

    var body: some View {
        Screen(title: "Devices", sub: subtitle) {
            MCard {
                Label("One account, every device", systemImage: "laptopcomputer.and.iphone")
                    .font(.title3.weight(.semibold))
                Text("These devices have signed in as \(state.username). While signed in they share the same synced data, so a note, event or weigh-in saved on one appears on the others.")
                    .font(.subheadline).foregroundStyle(Color.dim)
            }

            if loading && devices.isEmpty {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Looking for your devices…").foregroundStyle(Color.dim)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
            } else if let error, devices.isEmpty {
                MCard {
                    Label("Couldn't load devices", systemImage: "exclamationmark.triangle")
                        .font(.headline)
                    Text(error).font(.subheadline).foregroundStyle(Color.dim)
                    Button("Try again") { Task { await load() } }.font(.headline)
                }
            } else {
                ForEach(devices) { device in
                    row(device)
                }

                if let error {
                    Text(error).font(.subheadline).foregroundStyle(Color.dim)
                }

                Text(devices.count == 1
                     ? "Open MeOS on your other Mac or iPhone while signed in and it will appear here."
                     : "The data is the same on all of them. Only this device's window layout and local caches stay local.")
                    .font(.caption).foregroundStyle(Color.dim)
                    .padding(.horizontal, 4)

                Button { Task { await load() } } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.card, in: .rect(cornerRadius: 18))
                }
                .buttonStyle(.press)
                .disabled(loading)
            }
        }
        .task {
            // Make sure this install is in the list even if the launch
            // heartbeat raced a network change, then read the account's rows.
            await state.registerCurrentDevice(force: true)
            await load()
        }
        .alert("Rename device", isPresented: $showRename) {
            TextField("Name", text: $draft)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Save") { Task { await saveName() } }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("This name is only used in this list. The device keeps its own system name too.")
        }
    }

    private var subtitle: String {
        if devices.isEmpty { return "Signed in as \(state.username)" }
        return "\(devices.count) device\(devices.count == 1 ? "" : "s") · \(state.username)"
    }

    // MARK: - Rows

    private func row(_ device: AccountDevice) -> some View {
        let isCurrent = device.id == currentID
        return MCard {
            HStack(alignment: .top, spacing: 14) {
                BigIcon(name: device.type.icon, size: 18, inverted: isCurrent)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(device.name)
                            .font(.title3.weight(.semibold))
                            .lineLimit(1)
                        if isCurrent { thisDeviceBadge }
                    }
                    Text("\(device.type.label) · \(device.platform)")
                        .font(.subheadline)
                        .foregroundStyle(Color.dim)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        Image(systemName: "clock")
                        Text(lastSeen(device))
                    }
                    .font(.caption)
                    .foregroundStyle(Color.dim)
                }

                Spacer(minLength: 8)

                Button {
                    draft = device.name
                    renaming = device
                    showRename = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.headline)
                        .frame(width: 40, height: 40)
                        .background(Color.hairline, in: .circle)
                }
                .buttonStyle(.press)
                .accessibilityLabel("Rename \(device.name)")
            }

            if device.systemName != device.name {
                Text("System name: \(device.systemName)")
                    .font(.caption)
                    .foregroundStyle(Color.dim)
            }
        }
    }

    private var thisDeviceBadge: some View {
        Text("THIS DEVICE")
            .font(.system(size: 9, weight: .bold))
            .tracking(0.8)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .foregroundStyle(Color.paper)
            .background(Color.ink, in: .capsule)
            .fixedSize()
    }

    private func lastSeen(_ device: AccountDevice) -> String {
        if device.id == currentID { return "Active now" }
        guard let date = DeviceDate.parse(device.lastSeen) else { return "Last active recently" }
        if Date().timeIntervalSince(date) < 120 { return "Active now" }
        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .full
        return "Active \(relative.localizedString(for: date, relativeTo: .now))"
    }

    // MARK: - Actions

    private func load() async {
        loading = true
        error = nil
        do {
            devices = try await state.api.devices()
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
        loading = false
    }

    private func saveName() async {
        guard let device = renaming else { return }
        let name = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        do {
            let updated = try await state.api.renameDevice(id: device.id, to: name)
            if let i = devices.firstIndex(where: { $0.id == updated.id }) {
                devices[i] = updated
            }
            showRename = false
            renaming = nil
            Haptics.success()
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }
}

/// The server writes `Date.toISOString()`, which includes milliseconds.
/// `.withInternetDateTime` alone does not parse those, so try the fractional
/// form first and the plain one as a fallback.
private enum DeviceDate {
    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parse(_ value: String) -> Date? {
        fractional.date(from: value) ?? plain.date(from: value)
    }
}
