import SwiftUI
#if os(macOS)
import AppKit
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

/// Settings → Activity. What is recorded, how much detail, and how to erase it.
///
/// The Mac is the only sensor. iOS gives an app no way to read another app's
/// usage — Screen Time is walled behind an entitlement a free account cannot
/// have, and even with it the numbers render in a sandbox that cannot hand them
/// back — so the phone shows this document rather than writing to it, and there
/// is no phone section to configure.
struct ActivitySettingsCard: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var coordinator = ActivityCoordinator.shared
    @State private var confirmingWipe = false
    #if os(macOS)
    @State private var trusted = AXAccess.isTrusted
    #endif

    private var sessionCount: Int { state.activity.events.count }
    private var trackedDays: Int { Set(state.activity.events.map(\.day)).count + state.activity.days.count }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Gap.row) {
                SectionTitle(text: "Activity")

                #if os(macOS)
                Toggle(isOn: Binding(get: { coordinator.enabled },
                                     set: { coordinator.setEnabled($0) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Track activity on this Mac")
                            .font(.myBody.weight(.medium)).foregroundStyle(Palette.text)
                        Text("Records which app is in front and for how long. Stops while the screen is locked or you are away from the keyboard.")
                            .font(.myCaption).foregroundStyle(Palette.faint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(Palette.action)

                launchAtLogin

                Divider().overlay(Palette.divider)
                detail
                #else
                phoneNote
                #endif

                Divider().overlay(Palette.divider)
                devices

                Divider().overlay(Palette.divider)
                storage
            }
        }
    }

    #if !os(macOS)
    /// The honest sentence, in place of a switch that would control nothing.
    private var phoneNote: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionLabel(text: "Recorded by your Mac", accent: .activity)
            Text("iOS gives an app no way to read another app's usage — Screen Time is walled off behind an entitlement a free developer account cannot get, and even with it the numbers can only be drawn, never handed back. So MyOS does not pretend to track this iPhone. Everything you see here was recorded on your Mac and synced.")
                .font(.myCaption).foregroundStyle(Palette.faint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    #endif

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

    #if os(macOS)
    /// The Accessibility permission and what it buys, said plainly.
    ///
    /// Without it a browser is one undifferentiated block called "Chrome",
    /// which is the single biggest hole in the numbers — it is where the work
    /// happens *and* where the day leaks, and the app name cannot tell those
    /// apart. Granting it is what turns that block into github.com and
    /// youtube.com.
    private var detail: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionLabel(text: "Detail", accent: .activity)
            Text(trusted
                 ? "Accessibility is on. MyOS reads the frontmost window's title, and a browser's domain, so the breakdown names places rather than apps."
                 : "MyOS can see which app is in front, but not what is in it — so every browser hour reads as \"Chrome\". Accessibility fixes that. It reads the title bar and the domain; never the page, never the path, never a keystroke.")
                .font(.myCaption).foregroundStyle(trusted ? Palette.success : Palette.faint)
                .fixedSize(horizontal: false, vertical: true)

            if !trusted {
                HStack(spacing: Space.sm) {
                    Button("Allow Accessibility") { AXAccess.request(); recheck() }
                        .buttonStyle(.bordered)
                    Button("Open System Settings") { AXAccess.openSettings() }
                        .buttonStyle(.borderless)
                        .tint(Palette.action)
                }
            }

            Toggle(isOn: Binding(get: { coordinator.recordsTitles },
                                 set: { coordinator.setRecordsTitles($0) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Record window titles").font(.myBody.weight(.medium)).foregroundStyle(Palette.text)
                    Text("The second line under each row — which file, which video, which document. Turn it off and MyOS keeps domains only.")
                        .font(.myCaption).foregroundStyle(Palette.faint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(Palette.action)
            .disabled(!trusted)

            Text("This app is ad-hoc signed, so macOS may drop the permission after MyOS is reinstalled. If the rows go back to app names, come back here.")
                .font(.myCaption).foregroundStyle(Palette.faint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear(perform: recheck)
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in recheck() }
    }

    private func recheck() { trusted = AXAccess.isTrusted }
    #endif

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
