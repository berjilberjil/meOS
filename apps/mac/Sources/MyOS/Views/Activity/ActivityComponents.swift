import SwiftUI
import Charts

// The pieces Today, Productivity and the Weekly Report share, so the same
// number never gets two different treatments in two places.
//
// Colour here is entirely semantic: productive is green, distracting is orange,
// neutral is muted white. Nothing is coloured to look interesting.

extension ProductivityType {
    var accent: Accent {
        switch self {
        case .productive:  return .green
        case .neutral:     return .none
        case .distracting: return .orange
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
            SectionLabel(text: "Focusing now", accent: .orange)

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

            HStack(spacing: Space.sm) {
                Text(focus.category.label)
                    .font(.myBody)
                    .foregroundStyle(Palette.muted)
                WorthBadge(worth: focus.productivity)
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
        case .fixThisNow: return .orange
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

/// Mac and iPhone side by side. They are separate sensors that add up to one
/// model, and the split is worth showing because it is where the honesty about
/// what iOS allows lives.
struct DeviceSplit: View {
    let mac: Int
    let iphone: Int
    var showsTotal = true

    var body: some View {
        HStack(spacing: Space.sm) {
            tile(.mac, mac)
            tile(.iphone, iphone)
            if showsTotal {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("Total").font(.myCaption).foregroundStyle(Palette.faint)
                    Text(Fmt.duration(mac + iphone))
                        .font(.myBody.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(Palette.activity)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Space.md)
                .cardSkin(.elevated, radius: Radius.md)
            }
        }
    }

    private func tile(_ device: DeviceType, _ seconds: Int) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Label(device.label, systemImage: device.icon)
                .font(.myCaption)
                .foregroundStyle(Palette.faint)
            Text(seconds > 0 ? Fmt.duration(seconds) : "—")
                .font(.myBody.weight(.semibold)).monospacedDigit()
                .foregroundStyle(seconds > 0 ? Palette.text : Palette.faint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.md)
        .cardSkin(.elevated, radius: Radius.md)
    }
}

/// One app's line in a breakdown.
struct AppUsageRow: View {
    let usage: AppUsage
    /// The biggest app in the list, so the bar is relative to something real.
    let peak: Int

    var body: some View {
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
            SectionLabel(text: heading, accent: verdict.isPositive ? .green : .orange)
            Text(verdict.label.uppercased())
                .font(.title2.weight(.bold))
                .tracking(0.5)
                .foregroundStyle(verdict.isPositive ? Palette.success : Palette.attention)
            Text(line)
                .font(.myBody)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
