import SwiftUI
import Charts
#if os(macOS)
import AppKit
#endif

// The pieces Today, Productivity and the Weekly Report share, so the same
// number never gets two different treatments in two places.
//
// Colour here is entirely semantic: productive is green, distracting is orange,
// neutral is muted white. Nothing is coloured to look interesting. Distracting
// is the one place in the app that still earns orange — it has to read against
// the green sitting directly above it in the same breakdown.

extension ProductivityType {
    var accent: Accent {
        switch self {
        case .productive:  return .green
        case .neutral:     return .none
        case .distracting: return .distracting
        }
    }
    var tint: Color {
        switch self {
        case .productive:  return Palette.productive
        case .neutral:     return Palette.muted
        case .distracting: return Palette.distracting
        }
    }
}

/// "FOCUSING NOW" — the app in front of you, how long, and whether it counts.
struct FocusNowHeader: View {
    let focus: FocusNow

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionLabel(text: "Focusing now", accent: .activity)

            HStack(alignment: .firstTextBaseline, spacing: Space.md) {
                Text(focus.appName)
                    .font(.myDisplay)
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(Fmt.duration(focus.seconds))
                    .font(.title3.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(Palette.muted)
                Spacer(minLength: 0)
            }

            if let detail = focus.detail {
                Text(detail)
                    .font(.myBody)
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            HStack(spacing: Space.sm) {
                Text(focus.category.label)
                    .font(.myBody)
                    .foregroundStyle(Palette.muted)
                WorthBadge(worth: focus.productivity)
                // Only ever set on the phone, where "now" is happening on the
                // other machine and saying so is the difference between a live
                // reading and a wrong one.
                if let device = focus.device {
                    Label(device, systemImage: "laptopcomputer")
                        .font(.myCaption)
                        .foregroundStyle(Palette.faint)
                        .lineLimit(1)
                }
            }
        }
    }
}

/// `✓ Productive` / `• Neutral` / `! Distracting`.
struct WorthBadge: View {
    let worth: ProductivityType
    var body: some View {
        HStack(spacing: Space.xs) {
            Image(systemName: worth.mark)
                .font(.system(size: 8, weight: .black))
            Text(worth.label)
                .font(.myCaption)
        }
        .foregroundStyle(worth.tint)
        .padding(.horizontal, Space.sm)
        .padding(.vertical, Space.xs)
        .background(worth.tint.opacity(0.12), in: Capsule())
    }
}

/// Productive / Neutral / Distracting, with duration and share.
struct WorthBreakdown: View {
    let productive: Int
    let neutral: Int
    let distracting: Int
    var total: Int { productive + neutral + distracting }

    var body: some View {
        VStack(spacing: Space.sm) {
            row(.productive, productive)
            row(.neutral, neutral)
            row(.distracting, distracting)
        }
    }

    private func row(_ worth: ProductivityType, _ seconds: Int) -> some View {
        HStack(spacing: Space.md) {
            Circle().fill(worth.tint).frame(width: 7, height: 7)
            Text(worth.label)
                .font(.myBody)
                .foregroundStyle(Palette.muted)
            Spacer(minLength: Space.sm)
            Text(Fmt.duration(seconds))
                .font(.myBody.weight(.semibold)).monospacedDigit()
                .foregroundStyle(Palette.text)
            Text(percent(seconds))
                .font(.myCaption).monospacedDigit()
                .foregroundStyle(Palette.faint)
                .frame(width: 38, alignment: .trailing)
        }
    }

    private func percent(_ seconds: Int) -> String {
        guard total > 0 else { return "—" }
        return "\(Int((Double(seconds) / Double(total) * 100).rounded()))%"
    }
}

/// The day as a strip: one stacked bar per hour, split by worth.
///
/// Deliberately not a copy of Screen Time's chart — same question, MyOS's
/// answer. Hours with nothing in them are still drawn, because the gaps are
/// half of what the shape of a day tells you.
struct ActivityTimelineChart: View {
    let timeline: [TimelineHour]
    var height: CGFloat = 92

    /// Long-form rows for Swift Charts, one per hour per worth.
    private struct Slice: Identifiable {
        let id: String
        let hour: Int
        let worth: ProductivityType
        let seconds: Int
    }

    private var slices: [Slice] {
        timeline.flatMap { hour in
            ProductivityType.allCases.compactMap { worth in
                let seconds = hour.seconds(worth)
                guard seconds > 0 else { return nil }
                return Slice(id: "\(hour.hour).\(worth.rawValue)", hour: hour.hour,
                             worth: worth, seconds: seconds)
            }
        }
    }

    var body: some View {
        Chart(slices) { slice in
            BarMark(
                x: .value("Hour", slice.hour),
                y: .value("Minutes", slice.seconds / 60),
                width: .ratio(0.72)
            )
            .foregroundStyle(slice.worth.tint)
            .cornerRadius(2)
        }
        .chartXScale(domain: 0...23)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: [0, 6, 12, 18, 23]) { value in
                AxisValueLabel {
                    if let hour = value.as(Int.self) {
                        Text(ActivityTime.hourLabel(hour))
                            .font(.myCaption)
                            .foregroundStyle(Palette.faint)
                    }
                }
            }
        }
        .frame(height: height)
    }
}

/// The single recommendation, and the only place in MyOS that shouts.
struct ActionCallout: View {
    let action: ActivityAction

    private var accent: Accent {
        switch action.kind {
        case .goodMove:   return .green
        case .nextMove:   return .none
        case .fixThisNow: return .warning
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            SectionLabel(text: action.kind.heading, accent: accent)
            Text(action.text)
                .font(.myBody)
                .foregroundStyle(Palette.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.md)
        .cardSkin(.accent, accent: accent, radius: Radius.md)
    }
}

/// One app's line in a breakdown.
struct AppUsageRow: View {
    let usage: AppUsage
    /// The biggest app in the list, so the bar is relative to something real.
    let peak: Int

    var body: some View {
        HStack(alignment: .top, spacing: Space.md) {
            AppIconTile(appId: usage.appId, appName: usage.appName,
                        worth: usage.productivity, size: 28)
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(spacing: Space.sm) {
                    Text(usage.appName)
                        .font(.myBody.weight(.medium))
                        .foregroundStyle(Palette.text)
                        .lineLimit(1)
                    Spacer(minLength: Space.sm)
                    Text(Fmt.duration(usage.seconds))
                        .font(.myBody.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(Palette.text)
                }
                HStack(spacing: Space.sm) {
                    Text(usage.category.label)
                        .font(.myCaption)
                        .foregroundStyle(Palette.faint)
                        .lineLimit(1)
                    Spacer(minLength: Space.sm)
                    Text(usage.productivity.label)
                        .font(.myCaption)
                        .foregroundStyle(usage.productivity.tint)
                }
                ProgressView(value: peak > 0 ? min(1, Double(usage.seconds) / Double(peak)) : 0)
                    .progressViewStyle(.linear)
                    .tint(usage.productivity.tint)
            }
        }
    }
}

/// A named observation.
struct TimeInsightRow: View {
    let insight: TimeInsight
    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            SectionLabel(text: insight.title, accent: insight.productivity.accent)
            Text(insight.detail)
                .font(.myBody)
                .foregroundStyle(Palette.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The verdict. The word is the headline; the explanation is the point, so it
/// gets the larger type of the two.
struct VerdictBlock: View {
    let heading: String
    let verdict: ActivityVerdict
    let line: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionLabel(text: heading, accent: verdict.isPositive ? .green : .warning)
            Text(verdict.label.uppercased())
                .font(.title2.weight(.bold))
                .tracking(0.5)
                .foregroundStyle(verdict.isPositive ? Palette.success : Palette.warning)
            Text(line)
                .font(.myBody)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The Accessibility ask, placed under the breakdown it would fix.
///
/// A permission prompt in Settings is a chore; the same prompt sitting under a
/// row that says "Chrome 2h" is an offer, because the thing it buys is on
/// screen and obviously missing. It disappears the moment it is granted, and it
/// never blocks anything — tracking works without it.
struct DetailHint: View {
    #if os(macOS)
    @State private var trusted = AXAccess.isTrusted

    var body: some View {
        Group {
            if !trusted {
                VStack(alignment: .leading, spacing: Space.sm) {
                    Text("Chrome is a room, not an activity. Give MyOS Accessibility and these rows become the sites and files you were actually in — github.com, not \"Chrome\".")
                        .font(.myCaption)
                        .foregroundStyle(Palette.faint)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: Space.sm) {
                        Button("Allow Accessibility") { AXAccess.request(); recheck() }
                            .buttonStyle(.bordered)
                        Button("Open Settings") { AXAccess.openSettings() }
                            .buttonStyle(.borderless)
                            .foregroundStyle(Palette.faint)
                    }
                    .font(.myCaption)
                }
                .padding(Space.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardSkin(.elevated, radius: Radius.md)
            }
        }
        .onAppear(perform: recheck)
        // macOS grants this in System Settings, in another window — so the
        // answer arrives when MyOS comes back to the front, not when the button
        // was pressed.
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in recheck() }
    }

    private func recheck() { trusted = AXAccess.isTrusted }
    #else
    var body: some View { EmptyView() }
    #endif
}
