import SwiftUI
import WidgetKit

// MARK: - Timeline

struct SixPackEntry: TimelineEntry {
    let date: Date
    let todayKey: String
    let state: SixPackState?
}

struct SixPackProvider: TimelineProvider {
    func placeholder(in context: Context) -> SixPackEntry {
        SixPackEntry(date: .now, todayKey: SixPackDayMath.key(.now), state: .widgetPreview)
    }

    func getSnapshot(in context: Context, completion: @escaping (SixPackEntry) -> Void) {
        completion(entry(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SixPackEntry>) -> Void) {
        let now = Date()
        let calendar = Calendar(identifier: .gregorian)
        let midnight = calendar.startOfDay(for: now)
        let state = SixPackWidgetStore.load()?.sixPack

        // One entry per day for the next week. The day counter and "days left"
        // then roll over even if the app is never opened; the challenge state
        // itself only changes when the app writes a new snapshot.
        var entries = [SixPackEntry(date: now, todayKey: SixPackDayMath.key(now), state: state)]
        for offset in 1...7 {
            guard let date = calendar.date(byAdding: .day, value: offset, to: midnight) else { continue }
            entries.append(SixPackEntry(date: date, todayKey: SixPackDayMath.key(date), state: state))
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func entry(at date: Date) -> SixPackEntry {
        SixPackEntry(date: date, todayKey: SixPackDayMath.key(date), state: SixPackWidgetStore.load()?.sixPack)
    }
}

// MARK: - Widget

@main
struct MeOSWidgets: Widget {
    private let kind = "SixPackChallengeWidget"

    /// Lock Screen families only exist on iPhone; the Mac gets the three
    /// desktop sizes.
    private static var families: [WidgetFamily] {
        #if os(macOS)
        [.systemSmall, .systemMedium, .systemLarge]
        #else
        [.systemSmall, .systemMedium, .systemLarge,
         .accessoryCircular, .accessoryRectangular, .accessoryInline]
        #endif
    }

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SixPackProvider()) { entry in
            SixPackWidgetView(entry: entry)
        }
        .configurationDisplayName("Six-Pack Challenge")
        .description("Your day, today's checklist and weight for the 60-day challenge.")
        .supportedFamilies(Self.families)
    }
}

// MARK: - View

struct SixPackWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme

    let entry: SixPackEntry

    private var palette: WidgetPalette { WidgetPalette(scheme: scheme) }

    private var stats: ChallengeStats? {
        guard let state = entry.state else { return nil }
        return ChallengeStats(state: state, today: entry.todayKey)
    }

    var body: some View {
        Group {
            if let stats {
                switch family {
                case .accessoryCircular:    circular(stats)
                case .accessoryRectangular: rectangular(stats)
                case .accessoryInline:      inline(stats)
                case .systemLarge:          large(stats)
                case .systemMedium:         medium(stats)
                default:                    small(stats)
                }
            } else {
                empty
            }
        }
        #if os(iOS)
        // The Mac shell has no URL handler; a plain tap there just opens the app.
        .widgetURL(URL(string: "meos://sixpack"))
        #endif
        .containerBackground(for: .widget) { palette.background }
    }

    // MARK: Small

    private func small(_ s: ChallengeStats) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            header(s)

            Spacer(minLength: 0)

            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(s.day)")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .tracking(-2)
                        .foregroundStyle(palette.text)
                        .monospacedDigit()
                        .minimumScaleFactor(0.65)
                        .lineLimit(1)
                    Text(s.remaining == 0 ? "FINAL DAY" : "\(s.remaining) DAYS LEFT")
                        .font(.system(size: 8, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(palette.faint)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                WidgetRing(progress: s.progress, color: palette.orange, track: palette.elevated)
                    .frame(width: 48, height: 48)
                    .overlay {
                        Text("\(Int((s.progress * 100).rounded()))%")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(palette.text)
                            .monospacedDigit()
                    }
            }

            Spacer(minLength: 0)

            WidgetBar(progress: s.progress, color: palette.orange, track: palette.elevated)

            HStack(spacing: 4) {
                Image(systemName: s.record.isComplete ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.system(size: 9, weight: .bold))
                Text(s.record.isComplete ? "Complete today" : "\(s.record.completedCount) of 5 today")
                    .font(.system(size: 9, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Text(kgText(s.weight))
                    .font(.system(size: 9, weight: .semibold))
                    .monospacedDigit()
                    .privacySensitive()
            }
            .foregroundStyle(s.record.isComplete ? palette.green : palette.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // MARK: Medium

    private func medium(_ s: ChallengeStats) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                header(s)

                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(s.day)")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .tracking(-1.5)
                        .foregroundStyle(palette.text)
                        .monospacedDigit()
                    Text("/ \(s.state.config.durationDays)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(palette.muted)
                }

                Text(s.remaining == 0 ? "Final day — finish it" : "\(s.remaining) days remaining")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(palette.faint)
                    .lineLimit(1)

                Spacer(minLength: 0)

                WidgetBar(progress: s.progress, color: palette.orange, track: palette.elevated)

                HStack(spacing: 4) {
                    Image(systemName: s.record.isComplete ? "checkmark.circle.fill" : "circle.dashed")
                        .font(.system(size: 9, weight: .bold))
                    Text(s.record.isComplete ? "Complete" : "\(s.record.completedCount) of 5")
                        .font(.system(size: 9, weight: .semibold))
                    Spacer(minLength: 0)
                    Text(kgText(s.weight))
                        .font(.system(size: 9, weight: .semibold))
                        .monospacedDigit()
                        .privacySensitive()
                }
                .foregroundStyle(s.record.isComplete ? palette.green : palette.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle()
                .fill(palette.elevated)
                .frame(width: 1)

            VStack(alignment: .leading, spacing: 5) {
                Text("TODAY")
                    .font(.system(size: 8, weight: .bold))
                    .tracking(1.1)
                    .foregroundStyle(palette.faint)

                ForEach(SixPackItem.allCases) { item in
                    HStack(spacing: 6) {
                        Image(systemName: s.record.isOn(item) ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(s.record.isOn(item) ? palette.green : palette.faint)
                        Text(shortName(item))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(s.record.isOn(item) ? palette.muted : palette.text)
                            .strikethrough(s.record.isOn(item), color: palette.faint)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }
            }
            .frame(width: 104, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // MARK: Large

    private func large(_ s: ChallengeStats) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text("SIX-PACK CHALLENGE")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(palette.orange)
                Spacer(minLength: 4)
                Text("DAY \(s.day) / \(s.state.config.durationDays)")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.7)
                    .foregroundStyle(palette.faint)
                    .monospacedDigit()
            }

            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(s.day)")
                        .font(.system(size: 54, weight: .bold, design: .rounded))
                        .tracking(-2)
                        .foregroundStyle(palette.text)
                        .monospacedDigit()
                        .lineLimit(1)
                    Text(s.remaining == 0 ? "Final day — finish it" : "\(s.remaining) days remaining")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.muted)
                    HStack(spacing: 5) {
                        Text(kgText(s.weight))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(palette.text)
                            .monospacedDigit()
                        Text(deltaText(s.delta))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(s.delta <= 0 ? palette.green : palette.orange)
                    }
                    .padding(.top, 2)
                    .privacySensitive()
                }

                Spacer(minLength: 0)

                WidgetRing(progress: s.progress, color: palette.orange, track: palette.elevated)
                    .frame(width: 72, height: 72)
                    .overlay {
                        VStack(spacing: -1) {
                            Text("\(Int((s.progress * 100).rounded()))%")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(palette.text)
                                .monospacedDigit()
                            Text("DONE")
                                .font(.system(size: 7, weight: .bold))
                                .tracking(0.8)
                                .foregroundStyle(palette.faint)
                        }
                    }
            }

            WidgetBar(progress: s.progress, color: palette.orange, track: palette.elevated)

            VStack(spacing: 4) {
                ForEach(SixPackItem.allCases) { item in
                    checkRow(item, s)
                }
            }

            Spacer(minLength: 0)

            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("LAST \(s.state.config.durationDays) DAYS")
                        .font(.system(size: 8, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(palette.faint)
                    historyGrid(s)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(s.streak)")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(palette.green)
                        .monospacedDigit()
                    Text("DAY STREAK")
                        .font(.system(size: 7, weight: .bold))
                        .tracking(0.7)
                        .foregroundStyle(palette.faint)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // MARK: Lock Screen

    private func circular(_ s: ChallengeStats) -> some View {
        ZStack {
            AccessoryWidgetBackground()
            Circle()
                .stroke(Color.primary.opacity(0.18), lineWidth: 4)
            Circle()
                .trim(from: 0, to: max(0.02, s.progress))
                .stroke(palette.orange, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .widgetAccentable()
            VStack(spacing: -1) {
                Text("DAY")
                    .font(.system(size: 6, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                Text("\(s.day)")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
            }
        }
        .padding(3)
    }

    private func rectangular(_ s: ChallengeStats) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.18), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: max(0.02, s.progress))
                    .stroke(palette.orange, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .widgetAccentable()
                Text("\(s.day)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 1) {
                Text("SIX-PACK CHALLENGE")
                    .font(.system(size: 8, weight: .bold))
                    .tracking(1.1)
                    .foregroundStyle(palette.orange)
                    .widgetAccentable()
                Text("Day \(s.day) of \(s.state.config.durationDays)")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(s.record.isComplete ? "Complete" : "\(s.record.completedCount) of 5 today")
                    Text("·")
                    Text(s.remaining == 0 ? "Final day" : "\(s.remaining) days left")
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func inline(_ s: ChallengeStats) -> some View {
        Text("Six-pack day \(s.day)/\(s.state.config.durationDays) · \(s.record.isComplete ? "complete" : "\(s.record.completedCount)/5")")
    }

    // MARK: Empty

    @ViewBuilder
    private var empty: some View {
        switch family {
        case .accessoryInline:
            Text("Six-pack: open MeOS")
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 20, weight: .semibold))
            }
        case .accessoryRectangular:
            HStack(spacing: 8) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 15, weight: .semibold))
                Text("Open MeOS to start your challenge")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
        default:
            VStack(spacing: 6) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(palette.orange)
                Text("Six-Pack Challenge")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.text)
                Text("Open MeOS to set up")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(palette.faint)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Pieces

    private func header(_ s: ChallengeStats) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("SIX-PACK")
                .font(.system(size: 9, weight: .bold))
                .tracking(1.3)
                .foregroundStyle(palette.orange)
            Spacer(minLength: 2)
            Text("\(s.state.config.durationDays) DAYS")
                .font(.system(size: 8, weight: .bold))
                .tracking(0.7)
                .foregroundStyle(palette.faint)
                .monospacedDigit()
        }
    }

    private func checkRow(_ item: SixPackItem, _ s: ChallengeStats) -> some View {
        let on = s.record.isOn(item)
        return HStack(spacing: 7) {
            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(on ? palette.green : palette.faint)
            Text(item.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(on ? palette.muted : palette.text)
                .strikethrough(on, color: palette.faint)
                .lineLimit(1)
            Spacer(minLength: 4)
            if item == .sleep, let hours = s.record.sleepHours {
                Text("\(trim(hours)) h")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(s.record.sleepIsWithinTarget ? palette.green : palette.orange)
                    .monospacedDigit()
            }
        }
    }

    private func historyGrid(_ s: ChallengeStats) -> some View {
        let keys = (0..<s.state.config.durationDays).map {
            SixPackDayMath.addDays($0, to: s.state.config.startDateKey)
        }
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 15), spacing: 3) {
            ForEach(keys, id: \.self) { key in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(markColor(s.state.mark(for: key, today: s.today)))
                    .frame(height: 10)
                    .overlay {
                        if key == s.today {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .strokeBorder(palette.orange, lineWidth: 1.2)
                        }
                    }
            }
        }
    }

    private func markColor(_ mark: SixPackState.DayMark) -> Color {
        switch mark {
        case .complete: return palette.green
        case .today:    return palette.orange.opacity(0.24)
        case .partial:  return palette.orange.opacity(0.42)
        case .missed:   return palette.elevated
        case .future:   return palette.elevated.opacity(0.55)
        case .before:   return .clear
        }
    }

    private func shortName(_ item: SixPackItem) -> String {
        switch item {
        case .protein:  return "Protein"
        case .calories: return "Calories"
        case .workout:  return "Workout"
        case .fasting:  return "Fasting"
        case .sleep:    return "Sleep"
        }
    }

    private func kgText(_ kg: Double) -> String {
        let rounded = (kg * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return "\(Int(rounded)) kg"
        }
        return String(format: "%.1f kg", rounded)
    }

    private func trim(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded() ? "\(Int(rounded))" : String(format: "%.1f", rounded)
    }

    private func deltaText(_ delta: Double) -> String {
        guard abs(delta) >= 0.05 else { return "no change yet" }
        return "\(delta < 0 ? "−" : "+")\(trim(abs(delta))) kg since start"
    }
}

// MARK: - Model helpers

private struct ChallengeStats {
    let state: SixPackState
    let today: String

    var day: Int { state.dayNumber(on: today) }
    var progress: Double { state.progress(on: today) }
    var remaining: Int { state.daysRemaining(on: today) }
    var record: SixPackDayRecord { state.record(on: today) }
    var weight: Double { state.currentWeightKg }
    var delta: Double { state.weightDeltaKg }
    var streak: Int { state.streak(on: today) }
}

private struct WidgetPalette {
    let scheme: ColorScheme

    private var dark: Bool { scheme == .dark }

    var background: Color {
        dark ? .black : Color(.sRGB, red: 0.97, green: 0.97, blue: 0.98, opacity: 1)
    }
    var text: Color { dark ? .white : .black }
    var muted: Color { text.opacity(dark ? 0.64 : 0.60) }
    var faint: Color { text.opacity(dark ? 0.40 : 0.38) }
    var elevated: Color {
        dark ? Color(.sRGB, red: 0.09, green: 0.09, blue: 0.09, opacity: 1)
             : Color(.sRGB, red: 0.90, green: 0.90, blue: 0.92, opacity: 1)
    }
    var orange: Color {
        dark ? Color(.sRGB, red: 1.0, green: 0.478, blue: 0.0, opacity: 1)
             : Color(.sRGB, red: 0.878, green: 0.416, blue: 0.0, opacity: 1)
    }
    var green: Color {
        dark ? Color(.sRGB, red: 0.224, green: 1.0, blue: 0.078, opacity: 1)
             : Color(.sRGB, red: 0.094, green: 0.643, blue: 0.0, opacity: 1)
    }
}

private struct WidgetRing: View {
    let progress: Double
    let color: Color
    let track: Color

    var body: some View {
        ZStack {
            Circle().stroke(track, lineWidth: 6)
            Circle()
                .trim(from: 0, to: max(0.02, min(1, progress)))
                .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

private struct WidgetBar: View {
    let progress: Double
    let color: Color
    let track: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule()
                    .fill(color)
                    .frame(width: max(6, geo.size.width * min(1, max(0, progress))))
            }
        }
        .frame(height: 5)
    }
}

// MARK: - Preview data

private extension SixPackState {
    static var widgetPreview: SixPackState {
        let today = SixPackDayMath.key(.now)
        var state = SixPackState(config: SixPackConfig(
            startDateKey: SixPackDayMath.addDays(-17, to: today),
            durationDays: 60,
            startWeightKg: 88,
            calorieMin: 2_200,
            calorieMax: 2_400,
            proteinMin: 130,
            proteinMax: 160,
            fastingStartHour: 12,
            fastingEndHour: 20
        ))
        state.setWeight(83.2, on: today)
        state.updateRecord(on: today) { record in
            record.proteinHit = true
            record.caloriesWithinTarget = true
            record.workoutCompleted = true
            record.sleepHours = 8
        }
        for offset in 1...8 {
            state.updateRecord(on: SixPackDayMath.addDays(-offset, to: today)) { record in
                record.proteinHit = true
                record.caloriesWithinTarget = true
                record.workoutCompleted = offset % 3 != 0
                record.fastingFollowed = true
                record.sleepHours = 8
            }
        }
        return state
    }
}
