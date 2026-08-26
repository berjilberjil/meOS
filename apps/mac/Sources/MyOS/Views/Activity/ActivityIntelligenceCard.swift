import SwiftUI

/// Today's activity card.
///
/// It answers, in order: what am I doing right now, where has today's time
/// actually gone, and what should I do about it. The middle one is a Screen
/// Time answer — per place — because "3 hours tracked" is a number you can't
/// act on and "1h 20m on youtube.com" is.
///
/// The same card on both devices, showing the same day. The Mac records it; the
/// phone reads it, including what the Mac is in front of at this second, which
/// arrives as a note in the synced document rather than as a session.
struct ActivityIntelligenceCard: View {
    /// The day being shown. Today unless the Today page has been swiped.
    var day: String? = nil
    /// Jump to the deeper view.
    var go: ((NavTab) -> Void)? = nil

    @EnvironmentObject var state: AppState
    @ObservedObject private var coordinator = ActivityCoordinator.shared

    var body: some View {
        // One pass over the day's sessions, not three: this card is alive on
        // three Today pages at once.
        let key = day ?? state.todayKey
        let summary = state.activitySummaryLive(key)
        let live = key == state.todayKey ? state.currentFocus : nil
        let read = ActivityInsights.dayIntelligence(summary: summary, current: live,
                                                    device: state.currentFocusDevice,
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

                if summary.isEmpty && !tracking {
                    offState
                } else {
                    Divider().overlay(Palette.divider)
                    ScreenTimeBreakdown(summary: summary,
                                        appLimit: Self.appLimit,
                                        chartHeight: Self.chartHeight,
                                        trailing: detailsButton,
                                        emptyLine: emptyLine)
                }

                if let action = read.action {
                    ActionCallout(action: action)
                }
            }
        }
    }

    /// Today is a page of sections, not a dashboard — on the phone this card
    /// has to answer the question and then get out of the way, so it shows four
    /// apps and a shorter strip. The Mac has the height for six.
    #if os(macOS)
    private static let appLimit = 6
    private static let chartHeight: CGFloat = 96
    #else
    private static let appLimit = 4
    private static let chartHeight: CGFloat = 78
    #endif

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

    /// Whether a day *can* be recorded from where this card is being read. On
    /// the phone the answer is always no, and that is not a failure to report —
    /// the Mac is the sensor and this is the screen.
    private var tracking: Bool {
        #if os(macOS)
        return coordinator.enabled
        #else
        return true
        #endif
    }

    private var idleLine: String {
        #if os(macOS)
        if !coordinator.enabled { return "Not tracking on this device." }
        if (day ?? state.todayKey) != state.todayKey { return "A past day — no live session." }
        return "Nothing in front of you right now."
        #else
        if (day ?? state.todayKey) != state.todayKey { return "A past day — no live session." }
        if state.activity.devices.isEmpty { return "Nothing recorded yet — your Mac does the recording." }
        return "Your Mac isn't in front of anything right now."
        #endif
    }

    /// An empty day on the phone is almost always a Mac that has not synced
    /// yet, and saying "nothing recorded" would be a claim about the day.
    private var emptyLine: String {
        #if os(macOS)
        return "Nothing recorded yet."
        #else
        return "Nothing from your Mac for this day yet."
        #endif
    }

    /// Honest about which of the two possible nothings this is. A zero here
    /// would be a claim that nothing happened, which is not the same as MyOS
    /// not having watched.
    private var offState: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Text("MyOS isn't recording where your time goes on this Mac. Turn it on and this card starts answering what you're focused on and whether it's worth doing.")
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
