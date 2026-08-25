import SwiftUI

/// Today's activity card.
///
/// It answers, in order: what am I doing right now, where has today's time
/// actually gone, and what should I do about it. The middle one is a Screen
/// Time answer — per app, per device — because "3 hours tracked" is a number
/// you can't act on and "1h 20m in CapCut" is.
///
/// The device switch is a control rather than two tiles: the Mac and the iPhone
/// are separate sensors feeding one model, and which of them you are reading
/// changes every number under it.
struct ActivityIntelligenceCard: View {
    /// The day being shown. Today unless the Today page has been swiped.
    var day: String? = nil
    /// Jump to the deeper view.
    var go: ((NavTab) -> Void)? = nil

    @EnvironmentObject var state: AppState
    @ObservedObject private var coordinator = ActivityCoordinator.shared

    /// Which device's time is on screen. Per device and not synced — reading the
    /// phone's day on the Mac is a thing you do for a moment, not a preference
    /// worth pushing to the other machine.
    @AppStorage("myos.activity.deviceFilter") private var deviceRaw = ActivityDeviceFilter.all.rawValue

    private var device: Binding<ActivityDeviceFilter> {
        Binding(get: { ActivityDeviceFilter(rawValue: deviceRaw) ?? .all },
                set: { deviceRaw = $0.rawValue })
    }

    var body: some View {
        // One pass over the day's sessions, not three: this card is alive on
        // three Today pages at once.
        let key = day ?? state.todayKey
        let summary = state.activitySummaryLive(key, device: device.wrappedValue)
        let live = key == state.todayKey ? state.liveActivity : nil
        // The verdict is always about the whole day, whichever device is being
        // read — a good afternoon on the Mac is not undone by looking at the
        // phone's tab.
        let whole = device.wrappedValue == .all ? summary : state.activitySummaryLive(key)
        let read = ActivityInsights.dayIntelligence(summary: whole, current: live,
                                                    todos: state.todayPriorities, now: Date())

        Card(accent: .activity, look: .accent) {
            VStack(alignment: .leading, spacing: Gap.row) {
                if let focus = read.focusNow {
                    FocusNowHeader(focus: focus)
                    Text(focus.insight)
                        .font(.myBody)
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    idleHeader
                }

                if whole.isEmpty && !coordinator.enabled {
                    offState
                } else {
                    Divider().overlay(Palette.divider)
                    ScreenTimeBreakdown(summary: summary,
                                        device: device,
                                        appLimit: 6,
                                        trailing: detailsButton)
                }

                if let action = read.action {
                    ActionCallout(action: action)
                }
            }
        }
    }

    private var detailsButton: AnyView? {
        guard let go else { return nil }
        return AnyView(
            Button { go(.productivity) } label: {
                HStack(spacing: Space.xs) {
                    Text("Details").font(.myCaption)
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.faint)
        )
    }

    /// Nothing in front of us — either tracking is off, or this is a past day,
    /// or the machine is idle. Each of those is a different sentence.
    private var idleHeader: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            SectionLabel(text: "Activity", accent: .activity)
            Text(idleLine)
                .font(.myBody)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var idleLine: String {
        if !coordinator.enabled { return "Not tracking on this device." }
        if (day ?? state.todayKey) != state.todayKey { return "A past day — no live session." }
        return "Nothing in front of you right now."
    }

    /// Honest about which of the two possible nothings this is. A zero here
    /// would be a claim that nothing happened, which is not the same as MyOS
    /// not having watched.
    private var offState: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Text("MyOS isn't recording where your time goes yet. Turn it on and this card starts answering what you're focused on and whether it's worth doing.")
                .font(.myBody)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            Button("Start tracking") { coordinator.setEnabled(true) }
                .buttonStyle(.borderedProminent)
                .tint(Palette.action)
                .foregroundStyle(Accent.green.ink)
        }
    }
}
