import SwiftUI
import Charts
#if os(macOS)
import AppKit
#endif

/// Real application icons, resolved once per bundle identifier.
///
/// A list of app names is a list of strings; a list of app icons is recognisable
/// at a glance, which is the whole reason to look at it. Only the Mac has the
/// bundles on disk, so on the phone — which reads the Mac's day rather than
/// recording one — every row falls back to a monogram rather than a wrong icon.
@MainActor
enum AppIconCache {
    #if os(macOS)
    private static var cache: [String: NSImage?] = [:]

    static func icon(for appId: String) -> NSImage? {
        if let hit = cache[appId] { return hit }
        let resolved: NSImage? = {
            guard appId.contains("."), !appId.hasPrefix("app."),
                  let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appId)
            else { return nil }
            return NSWorkspace.shared.icon(forFile: url.path)
        }()
        cache[appId] = resolved
        return resolved
    }
    #endif
}

/// An app's mark: its real icon where meOS can find one, else its initial on a
/// tile tinted by what the app is worth.
struct AppIconTile: View {
    let appId: String
    let appName: String
    let worth: ProductivityType
    var size: CGFloat = 30

    var body: some View {
        #if os(macOS)
        if let image = AppIconCache.icon(for: appId) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        } else {
            monogram
        }
        #else
        monogram
        #endif
    }

    private var monogram: some View {
        Text(String(appName.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased())
            .font(.system(size: size * 0.44, weight: .bold))
            .foregroundStyle(worth.tint)
            .frame(width: size, height: size)
            .background(worth.tint.opacity(0.14),
                        in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }
}

/// One app in the grid: mark, name, time.
struct AppTimeRow: View {
    let usage: AppUsage
    var iconSize: CGFloat = 30
    /// How many window titles to show under the row. Zero on Today, where the
    /// card has to answer and get out of the way.
    var detailLimit: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.sm) {
                AppIconTile(appId: usage.iconId.isEmpty ? usage.appId : usage.iconId,
                            appName: usage.appName,
                            worth: usage.productivity, size: iconSize)
                VStack(alignment: .leading, spacing: 1) {
                    Text(usage.appName)
                        .font(.myBody.weight(.medium))
                        .foregroundStyle(Palette.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(Fmt.duration(usage.seconds))
                        .font(.myCaption).monospacedDigit()
                        .foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 0)
            }
            if detailLimit > 0, !usage.details.isEmpty {
                details
            }
        }
    }

    /// What the window said, under what the app was. This is the level
    /// Accessibility buys: not "Xcode 2h" but which files those two hours went
    /// into.
    private var details: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(usage.details.prefix(detailLimit)) { detail in
                HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                    Text(detail.title)
                        .font(.myCaption)
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: Space.sm)
                    Text(Fmt.duration(detail.seconds))
                        .font(.myCaption).monospacedDigit()
                        .foregroundStyle(Palette.faint)
                }
            }
        }
        .padding(.leading, iconSize + Space.sm)
    }
}

/// The category legend under the timeline — the top few kinds of time, named
/// and totalled, coloured by what that time was worth.
struct CategoryLegend: View {
    let categories: [CategoryUsage]
    var limit: Int = 3

    var body: some View {
        HStack(alignment: .top, spacing: Space.md) {
            ForEach(Array(categories.prefix(limit))) { usage in
                VStack(alignment: .leading, spacing: 1) {
                    Text(usage.category.label)
                        .font(.myCaption.weight(.semibold))
                        .foregroundStyle(usage.productivity.tint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(Fmt.duration(usage.seconds))
                        .font(.myBody.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(Palette.text)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// Where the time actually went: which places, which hours.
///
/// This is the same question Apple's Screen Time answers, asked in meOS's terms
/// — the hours are stacked by *worth* rather than by Apple's categories, and a
/// row is a place rather than an app, so a browser breaks into the domains that
/// were actually open in it.
///
/// There is no device switch. The Mac is the only thing that can see a day, and
/// the phone shows the same day rather than a second, emptier one.
struct ScreenTimeBreakdown: View {
    let summary: ActivitySummary
    /// How many rows to show before stopping.
    var appLimit: Int = 6
    /// Window titles under each row — the deep view has the height for them.
    var detailLimit: Int = 0
    var chartHeight: CGFloat = 96
    /// The deep view has room to also name the *kinds* of time; Today does not,
    /// and there the worth split under the chart is already the legend.
    var showsCategories: Bool = false
    /// Shown next to the total — "Details ›" on Today, nothing on the deep view.
    var trailing: AnyView? = nil
    /// Tapping an app reclassifies it, where the surface supports that.
    var onApp: ((AppUsage) -> Void)? = nil

    private var columns: [GridItem] {
        [GridItem(.flexible(), spacing: Space.md), GridItem(.flexible(), spacing: Space.md)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                Text(Fmt.duration(summary.totalSeconds))
                    .font(.myDisplay).monospacedDigit()
                    .foregroundStyle(Palette.text)
                Spacer(minLength: 0)
                if let trailing { trailing }
            }

            if summary.isEmpty {
                Text(emptyLine)
                    .font(.myBody)
                    .foregroundStyle(Palette.faint)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ActivityTimelineChart(timeline: summary.timeline, height: chartHeight)
                // The worth split is the chart's key as well as its own answer:
                // the bars are stacked in exactly these three colours.
                WorthBreakdown(productive: summary.seconds(.productive),
                               neutral: summary.seconds(.neutral),
                               distracting: summary.seconds(.distracting))
                if showsCategories && !summary.categories.isEmpty {
                    Divider().overlay(Palette.divider)
                    CategoryLegend(categories: summary.categories)
                }
                Divider().overlay(Palette.divider)
                apps
            }
        }
    }

    /// Two columns where the rows are one line each — the shape the phone's own
    /// Screen Time card uses, and the one that fits the most in the least
    /// height. One column once titles are shown, because a row is then three
    /// lines tall and two of those side by side is a wall.
    private var apps: some View {
        let shown = Array(summary.apps.prefix(appLimit))
        return VStack(alignment: .leading, spacing: Space.md) {
            if detailLimit > 0 {
                VStack(alignment: .leading, spacing: Space.md) {
                    ForEach(shown) { row($0) }
                }
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: Space.md) {
                    ForEach(shown) { row($0) }
                }
            }
            if summary.apps.count > shown.count {
                Text("+ \(summary.apps.count - shown.count) more")
                    .font(.myCaption)
                    .foregroundStyle(Palette.faint)
            }
        }
    }

    @ViewBuilder
    private func row(_ usage: AppUsage) -> some View {
        let content = AppTimeRow(usage: usage, detailLimit: detailLimit)
        if let onApp {
            Button { onApp(usage) } label: { content.contentShape(Rectangle()) }
                .buttonStyle(.plain)
        } else {
            content
        }
    }

    /// The empty line, which must not read as "nothing happened" when the truth
    /// is "nothing was watching".
    var emptyLine: String = "Nothing recorded yet."
}
