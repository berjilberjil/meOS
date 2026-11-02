import SwiftUI

// MARK: - Dashboard widget
//
// Compact enough to sit among the other Today cards: title + tagline, the day
// counter as the focal point, an orange progress bar, weight, and today's
// status. The whole card is one button, so tapping anywhere opens the tracker
// and no inner control has to fight the tap.

struct SixPackChallengeCard: View {
    @EnvironmentObject var state: AppState
    @State private var showDetail = false

    private var today: String { state.todayKey }
    private var challenge: SixPackState { state.sixPack }
    private var day: Int { challenge.dayNumber(on: today) }
    private var progress: Double { challenge.progress(on: today) }
    private var remaining: Int { challenge.daysRemaining(on: today) }
    private var record: SixPackDayRecord { challenge.record(on: today) }

    var body: some View {
        Button { showDetail = true } label: {
            MCard {
                // Title + day counter
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("SIX-PACK CHALLENGE")
                            .font(.caption.weight(.bold))
                            .tracking(1.3)
                            .foregroundStyle(Palette.orange)
                        Text("60 Days. One Mission. Earn Your Abs.")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Palette.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text("DAY")
                            .font(.caption2.weight(.bold))
                            .tracking(1)
                            .foregroundStyle(Palette.faint)
                        Text("\(day)")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .tracking(-1)
                            .foregroundStyle(Palette.text)
                            .contentTransition(.numericText())
                            .monospacedDigit()
                        Text("/ \(challenge.config.durationDays)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Palette.muted)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Day \(day) of \(challenge.config.durationDays)")
                }

                // Progress
                VStack(spacing: 6) {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Palette.surfaceElevated)
                            Capsule()
                                .fill(Palette.orange)
                                .frame(width: max(6, g.size.width * progress))
                        }
                    }
                    .frame(height: 8)
                    .animation(DS.spring, value: progress)

                    HStack {
                        Text(remaining == 0 ? "Final day" : "\(remaining) days remaining")
                            .font(.myCaption)
                            .foregroundStyle(Palette.faint)
                        Spacer()
                        Text("\(Int((progress * 100).rounded()))%")
                            .font(.myCaption.weight(.semibold))
                            .foregroundStyle(Palette.orange)
                            .monospacedDigit()
                    }
                }

                // Weight + today's status
                HStack(spacing: 8) {
                    Image(systemName: "scalemass")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.muted)
                    Text("\(Fmt.trimKg(challenge.currentWeightKg)) kg")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.text)
                        .monospacedDigit()
                    if abs(challenge.weightDeltaKg) >= 0.05 {
                        Text(deltaLabel)
                            .font(.myCaption)
                            .foregroundStyle(challenge.weightDeltaKg < 0 ? Palette.green : Palette.muted)
                    }

                    Spacer()

                    statusPill
                }
            }
        }
        .buttonStyle(.press)
        .accessibilityHint("Opens the six-pack challenge tracker")
        .sheet(isPresented: $showDetail) {
            SixPackChallengeDetail()
                .environmentObject(state)
        }
    }

    private var deltaLabel: String {
        let d = challenge.weightDeltaKg
        return "\(d < 0 ? "−" : "+")\(Fmt.trimKg(abs(d)))"
    }

    private var statusPill: some View {
        let done = record.isComplete
        let count = record.completedCount
        return HStack(spacing: 5) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle.dashed")
                .font(.caption.weight(.semibold))
            Text(done ? "Complete" : "\(count) of 5")
                .font(.myCaption.weight(.semibold))
                .monospacedDigit()
        }
        .foregroundStyle(done ? Palette.green : Palette.muted)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background((done ? Palette.green : Palette.muted).opacity(0.12), in: .capsule)
    }
}

// MARK: - Full tracker

struct SixPackChallengeDetail: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var weightDraft = ""
    @State private var showSaved = false
    @State private var showWidgetHelp = false

    private var today: String { state.todayKey }
    private var challenge: SixPackState { state.sixPack }
    private var day: Int { challenge.dayNumber(on: today) }
    private var progress: Double { challenge.progress(on: today) }
    private var record: SixPackDayRecord { challenge.record(on: today) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                header
                hero
                checklist
                weightCard
                historyCard
                footer
            }
            .padding(.horizontal, DS.pad)
            .padding(.top, Space.sm)
            .padding(.bottom, Space.screen)
        }
        .scrollIndicators(.hidden)
        .background(Palette.background.ignoresSafeArea())
        .onAppear {
            weightDraft = Fmt.trimKg(challenge.currentWeightKg)
        }
        .sensoryFeedback(.success, trigger: showSaved) { _, now in now }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("SIX-PACK CHALLENGE")
                    .font(.caption.weight(.bold))
                    .tracking(1.6)
                    .foregroundStyle(Palette.orange)
                Text("60 Days. One Mission. Earn Your Abs.")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Palette.text)
            }
            Spacer()
            Button { dismiss() } label: { BigIcon(name: "xmark", size: 15) }
                .buttonStyle(.press)
        }
        .padding(.top, Space.sm)
    }

    // MARK: Hero

    private var hero: some View {
        MCard {
            HStack(alignment: .center, spacing: Space.lg) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("DAY")
                        .font(.caption.weight(.bold))
                        .tracking(1.4)
                        .foregroundStyle(Palette.faint)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(day)")
                            .font(.system(size: 72, weight: .bold, design: .rounded))
                            .tracking(-2)
                            .foregroundStyle(Palette.text)
                            .contentTransition(.numericText())
                            .monospacedDigit()
                        Text("/ \(challenge.config.durationDays)")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Palette.muted)
                    }
                    Text(remainingText)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Palette.muted)
                }

                Spacer(minLength: 0)

                Ring(progress: progress, width: 10, color: Palette.orange)
                    .frame(width: 86, height: 86)
                    .overlay {
                        Text("\(Int((progress * 100).rounded()))%")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(Palette.text)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                    .animation(DS.spring, value: progress)
            }

            VStack(spacing: 6) {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Palette.surfaceElevated)
                        Capsule()
                            .fill(Palette.orange)
                            .frame(width: max(6, g.size.width * progress))
                    }
                }
                .frame(height: 10)

                HStack {
                    Text(challenge.config.startDateKey.prettyDay)
                    Spacer()
                    Text(challenge.endDateKey().prettyDay)
                }
                .font(.myCaption)
                .foregroundStyle(Palette.faint)
            }
            .animation(DS.spring, value: progress)
        }
    }

    private var remainingText: String {
        let n = challenge.daysRemaining(on: today)
        return n == 0 ? "Final day — finish it" : "\(n) days remaining"
    }

    // MARK: Checklist

    private var checklist: some View {
        MCard {
            HStack(alignment: .firstTextBaseline) {
                Text("Today's Checklist")
                    .font(.myHeading)
                    .foregroundStyle(Palette.text)
                Spacer()
                Text("\(record.completedCount) / 5")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(record.isComplete ? Palette.green : Palette.muted)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }

            ForEach(SixPackItem.allCases) { item in
                Button {
                    withAnimation(DS.spring) { state.toggleSixPackItem(item) }
                } label: {
                    HStack(spacing: Space.md) {
                        Image(systemName: record.isOn(item) ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 26, weight: .regular))
                            .foregroundStyle(record.isOn(item) ? Palette.green : Palette.faint)
                            .contentTransition(.symbolEffect(.replace))

                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.title)
                                .font(.body.weight(.medium))
                                .foregroundStyle(record.isOn(item) ? Palette.muted : Palette.text)
                                .strikethrough(record.isOn(item), color: Palette.faint)
                            Text(item.detail)
                                .font(.myCaption)
                                .foregroundStyle(Palette.faint)
                        }

                        Spacer(minLength: 8)

                        if item == .sleep, let hours = record.sleepHours {
                            Text("\(Fmt.trimKg(hours))h")
                                .font(.myCaption.weight(.semibold))
                                .foregroundStyle(record.sleepIsWithinTarget ? Palette.green : Palette.orange)
                                .monospacedDigit()
                        }
                    }
                    .padding(.vertical, 4)
                    .contentShape(.rect)
                }
                .buttonStyle(.press)
                .sensoryFeedback(.selection, trigger: record.isOn(item))
            }

            Text(record.isComplete
                 ? "Today is complete. That is the whole job."
                 : "Tap a row to tick it. A missed day never resets the challenge.")
                .font(.myCaption)
                .foregroundStyle(record.isComplete ? Palette.green : Palette.faint)
                .padding(.top, 2)
        }
    }

    // MARK: Weight

    private var weightCard: some View {
        MCard {
            HStack(alignment: .firstTextBaseline) {
                Text("Weight")
                    .font(.myHeading)
                    .foregroundStyle(Palette.text)
                Spacer()
                Text(deltaText)
                    .font(.myCaption.weight(.semibold))
                    .foregroundStyle(challenge.weightDeltaKg <= 0 ? Palette.green : Palette.orange)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Fmt.trimKg(challenge.currentWeightKg))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .tracking(-1)
                    .foregroundStyle(Palette.text)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("kg")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Palette.muted)
                Spacer()
                Text("Start \(Fmt.trimKg(challenge.config.startWeightKg)) kg")
                    .font(.myCaption)
                    .foregroundStyle(Palette.faint)
            }

            HStack(spacing: Space.sm) {
                TextField("Today's weigh-in", text: $weightDraft)
                    .font(.body)
                    .textFieldStyle(.plain)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                    .onSubmit { saveWeight() }

                Button { saveWeight() } label: {
                    Text("Save")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.background)
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .background(Palette.orange, in: .capsule)
                }
                .buttonStyle(.press)
                .disabled(Fmt.parseWeightKg(weightDraft) == nil)
                .opacity(Fmt.parseWeightKg(weightDraft) == nil ? 0.4 : 1)
            }
            .padding(.horizontal, Space.md)
            .frame(height: 46)
            .background(Palette.surfaceElevated, in: .rect(cornerRadius: Radius.md))

            if !challenge.sortedWeighIns.isEmpty {
                HStack(spacing: Space.sm) {
                    ForEach(challenge.sortedWeighIns.suffix(5).reversed()) { w in
                        VStack(spacing: 1) {
                            Text(Fmt.trimKg(w.kg))
                                .font(.myCaption.weight(.semibold))
                                .foregroundStyle(Palette.text)
                                .monospacedDigit()
                            Text(w.dateKey.shortDay)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(Palette.faint)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    private var deltaText: String {
        let d = challenge.weightDeltaKg
        if abs(d) < 0.05 { return "No change yet" }
        return "\(d < 0 ? "−" : "+")\(Fmt.trimKg(abs(d))) kg since start"
    }

    private func saveWeight() {
        guard let kg = Fmt.parseWeightKg(weightDraft) else { return }
        withAnimation(DS.spring) { state.logSixPackWeight(kg) }
        weightDraft = Fmt.trimKg(kg)
        showSaved.toggle()
    }

    // MARK: History

    private var historyCard: some View {
        MCard {
            HStack(alignment: .firstTextBaseline) {
                Text("Last 60 Days")
                    .font(.myHeading)
                    .foregroundStyle(Palette.text)
                Spacer()
                Text("\(challenge.completedDays) complete")
                    .font(.myCaption.weight(.semibold))
                    .foregroundStyle(Palette.green)
                    .monospacedDigit()
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 10), spacing: 6) {
                ForEach(historyKeys, id: \.self) { key in
                    let mark = challenge.mark(for: key, today: today)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(color(for: mark))
                        .frame(height: 16)
                        .overlay {
                            if key == today {
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .strokeBorder(Palette.orange, lineWidth: 1.5)
                            }
                        }
                        .accessibilityLabel("\(key.prettyDay): \(label(for: mark))")
                }
            }

            HStack(spacing: Space.md) {
                legend(Palette.green, "Complete")
                legend(Palette.orange, "Today")
                legend(Palette.surfaceElevated, "Missed")
                Spacer()
                Text("\(challenge.streak(on: today)) day streak")
                    .font(.myCaption.weight(.semibold))
                    .foregroundStyle(Palette.muted)
                    .monospacedDigit()
            }
        }
    }

    private var historyKeys: [String] {
        (0..<challenge.config.durationDays).map {
            SixPackDayMath.addDays($0, to: challenge.config.startDateKey)
        }
    }

    private func color(for mark: SixPackState.DayMark) -> Color {
        switch mark {
        case .complete: return Palette.green
        case .today:    return Palette.orange.opacity(0.22)
        case .partial:  return Palette.orange.opacity(0.35)
        case .missed:   return Palette.surfaceElevated
        case .future:   return Palette.surfaceElevated.opacity(0.45)
        case .before:   return .clear
        }
    }

    private func label(for mark: SixPackState.DayMark) -> String {
        switch mark {
        case .complete: return "complete"
        case .today:    return "today, still open"
        case .partial:  return "partly done"
        case .missed:   return "missed"
        case .future:   return "upcoming"
        case .before:   return "before the challenge"
        }
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
            Text(text).font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.faint)
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 4) {
            Text("Started \(challenge.config.startDateKey.prettyDay) · Ends \(challenge.endDateKey().prettyDay)")
                .font(.myCaption)
                .foregroundStyle(Palette.faint)
            Text("\(challenge.config.calorieMin)–\(challenge.config.calorieMax) kcal · \(challenge.config.proteinMin)–\(challenge.config.proteinMax) g protein · \(challenge.config.fastingWindowLabel)")
                .font(.myCaption)
                .foregroundStyle(Palette.faint)
                .multilineTextAlignment(.center)

            #if os(iOS)
            Button { showWidgetHelp = true } label: {
                Label("Add to Home Screen", systemImage: "plus.rectangle.on.rectangle")
                    .font(.myCaption.weight(.semibold))
                    .foregroundStyle(Palette.orange)
            }
            .buttonStyle(.press)
            .padding(.top, Space.sm)
            .alert("Add the Six-Pack widget", isPresented: $showWidgetHelp) {
                Button("Got it", role: .cancel) {}
            } message: {
                Text("Touch and hold the Home Screen, tap Edit → Add Widget, then choose MeOS and Six-Pack Challenge.")
            }
            #endif
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Space.xs)
    }
}

// MARK: - Formatting helpers

private extension String {
    /// `2026-11-01` → `1 Nov`.
    var prettyDay: String {
        guard let date = SixPackDayMath.date(from: self) else { return self }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }

    /// `2026-11-01` → `1 Nov`.
    var shortDay: String {
        guard let date = SixPackDayMath.date(from: self) else { return self }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }
}
