import SwiftUI
#if os(macOS)
import ServiceManagement
#endif

#if os(macOS)
/// Whether MyOS starts with the Mac.
///
/// This belongs next to the activity toggle because it is the difference
/// between tracking that works and tracking that mostly works: the Mac's sensor
/// is `NSWorkspace` inside this process, so a MyOS that is not running is a Mac
/// that is not being watched. Everything else about the feature can be right and
/// the numbers will still be missing the first four hours of the day.
@MainActor
final class LoginItemStore: ObservableObject {
    static let shared = LoginItemStore()

    @Published private(set) var enabled: Bool
    /// Registration can be refused — this app is ad-hoc signed — and a toggle
    /// that silently springs back is worse than one that says why.
    @Published private(set) var error: String?

    private init() { enabled = SMAppService.mainApp.status == .enabled }

    func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        enabled = SMAppService.mainApp.status == .enabled
    }
}
#endif

/// Settings → Activity. What is recorded, on which devices, and how to make the
/// iPhone report anything at all.
struct ActivitySettingsCard: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var coordinator = ActivityCoordinator.shared
    @State private var showingSetup = false
    @State private var confirmingWipe = false

    private var sessionCount: Int { state.activity.events.count }
    private var trackedDays: Int { Set(state.activity.events.map(\.day)).count + state.activity.days.count }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Gap.row) {
                SectionTitle(text: "Activity")

                Toggle(isOn: Binding(get: { coordinator.enabled },
                                     set: { coordinator.setEnabled($0) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(toggleTitle).font(.myBody.weight(.medium)).foregroundStyle(Palette.text)
                        Text(toggleDetail).font(.myCaption).foregroundStyle(Palette.faint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(Palette.action)

                #if os(macOS)
                launchAtLogin
                #endif

                Divider().overlay(Palette.divider)
                devices

                Divider().overlay(Palette.divider)
                iphoneSetup

                Divider().overlay(Palette.divider)
                storage
            }
        }
        .sheet(isPresented: $showingSetup) { IPhoneActivitySetupSheet() }
    }

    private var toggleTitle: String {
        #if os(macOS)
        return "Track activity on this Mac"
        #else
        return "Track MyOS use on this iPhone"
        #endif
    }

    /// Says exactly what is and is not recorded. A tracker you cannot describe
    /// in one sentence is a tracker you should not run.
    private var toggleDetail: String {
        #if os(macOS)
        return "Records which app is in front and for how long — the app's name, never what is inside it. Stops while the screen is locked or you are away from the keyboard."
        #else
        return "iOS only lets an app time itself. This records MyOS's own foreground time; other apps need the automations below."
        #endif
    }

    #if os(macOS)
    @ObservedObject private var loginItem = LoginItemStore.shared

    private var launchAtLogin: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Toggle(isOn: Binding(get: { loginItem.enabled },
                                 set: { loginItem.set($0) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Open MyOS at login").font(.myBody.weight(.medium)).foregroundStyle(Palette.text)
                    Text("The Mac is only watched while MyOS is running. Without this, every morning before you open it is a gap in the day.")
                        .font(.myCaption).foregroundStyle(Palette.faint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(Palette.action)
            if let error = loginItem.error {
                Text(error).font(.myCaption).foregroundStyle(Palette.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    #endif

    /// Which iPhone apps have actually reported. The automations are set up one
    /// at a time on the phone and it is genuinely hard to remember which ones
    /// are done — so this is the answer, taken from what has arrived.
    private var reportingApps: [String] {
        var names = Set(state.activity.events.filter { $0.deviceType == .iphone }.map(\.appName))
        names.remove("MyOS")
        return names.sorted()
    }

    private var devices: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionLabel(text: "Devices reporting")
            if state.activity.devices.isEmpty {
                Text("None yet.").font(.myBody).foregroundStyle(Palette.faint)
            } else {
                ForEach(state.activity.devices.values.sorted { $0.lastSeen > $1.lastSeen }) { device in
                    HStack(spacing: Space.sm) {
                        Image(systemName: device.deviceType.icon)
                            .font(.myBody).foregroundStyle(Palette.muted)
                        Text(device.name).font(.myBody).foregroundStyle(Palette.text)
                        Spacer(minLength: 0)
                        Text(Fmt.day(device.lastSeen))
                            .font(.myCaption).foregroundStyle(Palette.faint)
                    }
                }
            }
        }
    }

    private var iphoneSetup: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionLabel(text: "iPhone apps", accent: .activity)
            Text("iOS gives no app permission to read another app's usage — Apple's Screen Time data is walled off behind an entitlement that needs a paid developer account, and even then it can only be drawn, not read. A Shortcuts automation is the way round it.")
                .font(.myCaption).foregroundStyle(Palette.faint)
                .fixedSize(horizontal: false, vertical: true)
            if reportingApps.isEmpty {
                Text("No iPhone app has reported yet.")
                    .font(.myCaption).foregroundStyle(Palette.faint)
            } else {
                Text("Reporting: \(reportingApps.joined(separator: ", "))")
                    .font(.myCaption).foregroundStyle(Palette.success)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("How to set it up") { showingSetup = true }
                .buttonStyle(.borderless)
                .tint(Palette.action)
        }
    }

    private var storage: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionLabel(text: "Recorded")
            Text("\(sessionCount) session\(sessionCount == 1 ? "" : "s") held in full, across \(trackedDays) day\(trackedDays == 1 ? "" : "s"). Sessions older than \(ActivityDoc.retentionDays) days are kept as daily totals only.")
                .font(.myCaption).foregroundStyle(Palette.faint)
                .fixedSize(horizontal: false, vertical: true)
            Button(confirmingWipe ? "Tap again to erase everything" : "Erase activity history") {
                if confirmingWipe {
                    state.eraseActivity()
                    confirmingWipe = false
                } else {
                    confirmingWipe = true
                }
            }
            .buttonStyle(.borderless)
            .tint(Palette.warning)
        }
    }
}

/// The setup walkthrough. Written as the steps in the iPhone's own words, so it
/// can be followed with the phone in hand.
struct IPhoneActivitySetupSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let steps: [(String, String)] = [
        ("Open Shortcuts on your iPhone",
         "Go to the Automation tab and tap +."),
        ("Choose App",
         "Pick the app you want tracked — WhatsApp, Instagram, YouTube, whatever actually eats your day."),
        ("Select “Is Opened”, then Run Immediately",
         "Turn off “Notify When Run”, or you will get a banner every time you open it."),
        ("Add the action “Track App Activity”",
         "It is under MyOS. Set App to the app's name and State to opened."),
        ("Repeat with “Is Closed”",
         "Same automation app, State set to closed. Without this MyOS caps the session at 30 minutes rather than guessing."),
        ("Open MyOS once a day",
         "The automations queue up in the background; MyOS folds them into sessions the next time you open it."),
    ]

    var body: some View {
        let content = ScrollView {
            VStack(alignment: .leading, spacing: Gap.screen) {
                VStack(alignment: .leading, spacing: Space.sm) {
                    Text("Track iPhone apps").font(.myDisplay).foregroundStyle(Palette.text)
                    Text("One automation per app, set up once. MyOS never sees what you did in the app — only that it was in front, and for how long.")
                        .font(.myBody).foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: Space.md) {
                        Text("\(index + 1)")
                            .font(.myCaption.weight(.bold))
                            .foregroundStyle(Accent.activity.ink)
                            .frame(width: 22, height: 22)
                            .background(Palette.activity, in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(step.0).font(.myBody.weight(.semibold)).foregroundStyle(Palette.text)
                            Text(step.1).font(.myCaption).foregroundStyle(Palette.faint)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                Text("Why not Screen Time: Apple's DeviceActivity framework needs the family-controls entitlement, which a free developer account cannot provision — and its report extension is sandboxed so the per-app numbers can be shown but never handed back to MyOS. This is the only route that works without paying for a developer account.")
                    .font(.myCaption).foregroundStyle(Palette.faint)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(Space.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardSkin(.elevated, radius: Radius.md)

                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.action)
                    .foregroundStyle(Accent.green.ink)
                    .frame(maxWidth: .infinity)
            }
            .padding(Space.xl)
        }
        .background(Palette.background)

        #if os(iOS)
        content.presentationDetents([.large])
        #else
        content.frame(width: 460, height: 620)
        #endif
    }
}
