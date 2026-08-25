import SwiftUI

/// Today's activity card.
///
/// It answers three questions in order and nothing else: what am I doing right
/// now, is it any good, and what should I do next. Anything that answers "where
/// did my time actually go" belongs on the Productivity tab — putting it here
/// would turn the top of Today into a dashboard.
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
        let live = key == state.todayKey ? state.liveActivity : nil
        let read = ActivityInsights.dayIntelligence(summary: summary, current: live,
                                                    todos: state.todayPriorities, now: Date())

        Card(accent: .orange, look: .accent) {
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

                if summary.isEmpty {
                    emptyState
                } else {
                    Divider().overlay(Palette.divider)
                    totals(summary)
                    WorthBreakdown(productive: summary.seconds(.productive),
                                   neutral: summary.seconds(.neutral),
                                   distracting: summary.seconds(.distracting))
                    ActivityTimelineChart(timeline: summary.timeline)
                }

                if let action = read.action {
                    ActionCallout(action: action)
                }
            }
        }
    }

    /// Nothing in front of us — either tracking is off, or this is a past day,
    /// or the machine is idle. Each of those is a different sentence.
    private var idleHeader: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            SectionLabel(text: "Activity", accent: .orange)
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

    private func totals(_ summary: ActivitySummary) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                Text("Today").font(.myCaption).foregroundStyle(Palette.faint)
                Text(Fmt.duration(summary.totalSeconds))
                    .font(.title2.weight(.bold)).monospacedDigit()
                    .foregroundStyle(Palette.text)
                Spacer(minLength: 0)
                if let go {
                    Button { go(.productivity) } label: {
                        HStack(spacing: Space.xs) {
                            Text("Details").font(.myCaption)
                            Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.faint)
                }
            }
            DeviceSplit(mac: summary.seconds(.mac), iphone: summary.seconds(.iphone), showsTotal: false)
        }
    }

    /// Honest about which of the two possible nothings this is. A zero here
    /// would be a claim that nothing happened, which is not the same as MyOS
    /// not having watched.
    @ViewBuilder
    private var emptyState: some View {
        if !coordinator.enabled {
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
        } else {
            Text("Nothing recorded yet today.")
                .font(.myBody)
                .foregroundStyle(Palette.faint)
        }
    }
}
