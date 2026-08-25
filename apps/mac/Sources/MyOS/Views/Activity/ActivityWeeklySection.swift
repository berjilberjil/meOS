import SwiftUI

/// The activity half of the existing Weekly Report.
///
/// Deliberately a section inside the report MyOS already generates, not a second
/// report: the Friday read-back is one thing, and splitting "how your body went"
/// from "how your time went" into two places would make neither of them the
/// weekly review.
///
/// The numbers are computed live from the sessions rather than frozen into the
/// stored report. A report generated on Friday evening and opened on Sunday
/// should not be quietly wrong about Saturday.
struct ActivityWeeklySection: View {
    let weekStart: String
    let weekEnd: String

    @EnvironmentObject var state: AppState

    private var days: [String] { Self.days(from: weekStart, to: weekEnd) }

    private var previousDays: [String] {
        guard let first = days.first else { return [] }
        let priorEnd = AppState.addDays(-1, to: first)
        return Self.days(from: AppState.addDays(-(days.count - 1), to: priorEnd), to: priorEnd)
    }

    /// Inclusive day keys, capped so a malformed window cannot loop forever.
    static func days(from start: String, to end: String, limit: Int = 31) -> [String] {
        guard start <= end else { return [] }
        var out: [String] = []
        var cursor = start
        while cursor <= end && out.count < limit {
            out.append(cursor)
            cursor = AppState.addDays(1, to: cursor)
        }
        return out
    }

    var body: some View {
        let week = ActivityEngine.weekSummary(doc: state.activity, days: days)
        let previous = ActivityEngine.weekSummary(doc: state.activity, days: previousDays)
        let read = ActivityInsights.weekIntelligence(this: week, previous: previous.isEmpty ? nil : previous)

        if week.isEmpty {
            VStack(alignment: .leading, spacing: Space.xs) {
                SectionLabel(text: "Time & productivity", accent: .activity)
                Text("No activity was recorded this week.")
                    .font(.myBody).foregroundStyle(Palette.faint)
            }
        } else {
            VStack(alignment: .leading, spacing: Gap.row) {
                SectionLabel(text: "Time & productivity", accent: .activity)

                totals(week)
                WorthBreakdown(productive: week.seconds(.productive),
                               neutral: week.seconds(.neutral),
                               distracting: week.seconds(.distracting))

                if !read.narrative.isEmpty {
                    Divider().overlay(Palette.divider)
                    VStack(alignment: .leading, spacing: Space.xs) {
                        SectionLabel(text: "What your week actually looked like")
                        Text(read.narrative)
                            .font(.myBody).foregroundStyle(Palette.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                ForEach([read.biggestLeak, read.bestWindow, read.biggestImprovement].compactMap { $0 }) {
                    TimeInsightRow(insight: $0)
                }

                if let verdict = read.verdict {
                    Divider().overlay(Palette.divider)
                    VerdictBlock(heading: "Week", verdict: verdict, line: read.verdictLine)
                }
                if !read.nextWeek.isEmpty {
                    ActionCallout(action: ActivityAction(kind: .nextMove, text: read.nextWeek))
                }
            }
        }
    }

    private func totals(_ week: ActivityWeekSummary) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                Text("Total active time").font(.myCaption).foregroundStyle(Palette.faint)
                Spacer(minLength: 0)
                Text(Fmt.duration(week.totalSeconds))
                    .font(.title3.weight(.bold)).monospacedDigit()
                    .foregroundStyle(Palette.text)
            }
            DeviceSplit(mac: week.seconds(.mac), iphone: week.seconds(.iphone), showsTotal: false)
        }
    }
}
