import SwiftUI

/// Settings → Weekly report. The latest Friday read-back in full, older ones
/// collapsed underneath.
struct WeeklyReportCard: View {
    var boxed = true
    @EnvironmentObject var state: AppState
    @State private var openID: String?

    private var latest: WeeklyReport? { state.weekly.first }

    var body: some View {
        let inner = VStack(alignment: .leading, spacing: Gap.row) {
            header
            if let r = latest {
                ReportBody(report: r)
                if state.weekly.count > 1 { older }
            } else {
                empty
            }
            if let err = state.weeklyError {
                Text(err).font(.caption).foregroundStyle(Palette.attention)
                    .fixedSize(horizontal: false, vertical: true)
            }
            generateButton
        }
        // Opening the report is what marks it read — the Settings row badge and
        // this are the same fact.
        .onAppear { if let r = latest, !r.seen { state.markWeeklyReportSeen(r.id) } }
        .sheet(item: Binding(get: { state.weekly.first { $0.id == openID } },
                             set: { if $0 == nil { openID = nil } })) { r in
            PastReportSheet(report: r)
        }

        if boxed { Card { inner } } else { inner }
    }

    private var header: some View {
        HStack(spacing: 8) {
            SectionTitle(text: "Weekly report")
            Spacer(minLength: 0)
            if let r = latest {
                Text(Fmt.day(r.weekEnd))
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(Palette.faint)
            }
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No report yet.")
                .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.text)
            Text("Every Friday from 6pm, MyOS reads this week's progress photos against last week's — with your goal and what you actually logged — and tells you straight whether you moved.")
                .font(.footnote).foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var older: some View {
        VStack(alignment: .leading, spacing: Gap.tight) {
            Text("EARLIER WEEKS")
                .font(.caption2.weight(.heavy)).tracking(0.6)
                .foregroundStyle(Palette.faint)
                .padding(.top, 4)
            ForEach(state.weekly.dropFirst()) { r in
                Button { openID = r.id } label: {
                    HStack(spacing: 8) {
                        VerdictDot(verdict: r.kind)
                        Text(Fmt.day(r.weekEnd))
                            .font(.caption.weight(.semibold)).foregroundStyle(Palette.text)
                        Text(r.headline)
                            .font(.caption).foregroundStyle(Palette.muted).lineLimit(1)
                        Spacer(minLength: 0)
                        if !r.percentLabel.isEmpty {
                            Text(r.percentLabel)
                                .font(.caption2.weight(.heavy)).monospacedDigit()
                                .foregroundStyle(Palette.faint)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var generateButton: some View {
        Button { Task { await state.generateWeeklyReport(notify: false) } } label: {
            HStack(spacing: 6) {
                if state.weeklyBusy {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise").font(.caption2.weight(.bold))
                }
                Text(state.weeklyBusy ? "Reading your week…"
                                      : (latest == nil ? "Read my week now" : "Read it again"))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered).controlSize(.large).frame(maxWidth: .infinity)
        .disabled(state.weeklyBusy)
    }
}

/// One report, rendered. Shared by the card and the past-report sheet.
private struct ReportBody: View {
    let report: WeeklyReport
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                VerdictDot(verdict: report.kind)
                Text(report.kind.label.uppercased())
                    .font(.caption2.weight(.heavy)).tracking(0.8)
                    .foregroundStyle(tint)
                Spacer(minLength: 0)
                if !report.percentLabel.isEmpty {
                    Text(report.percentLabel)
                        .font(.title3.weight(.heavy)).monospacedDigit()
                        .foregroundStyle(tint)
                }
            }

            Text(report.headline)
                .font(.title3.weight(.semibold)).foregroundStyle(Palette.text)
                .fixedSize(horizontal: false, vertical: true)

            if !report.read.isEmpty {
                Text(report.read)
                    .font(.footnote).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !report.workouts.isEmpty { list("TRAIN", report.workouts, tint: Palette.attention) }
            if !report.diet.isEmpty { list("EAT", report.diet, tint: Palette.green) }

            if !report.cheer.isEmpty {
                Text(report.cheer)
                    .font(.footnote.weight(.semibold)).foregroundStyle(Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }

            Text("\(report.photosThisWeek) photo\(report.photosThisWeek == 1 ? "" : "s") this week · \(report.photosLastWeek) last week")
                .font(.myCaption)
                .foregroundStyle(Palette.faint)

            // The activity half of the same week. Computed live rather than
            // frozen into the stored report — a Friday report opened on Sunday
            // must not be quietly wrong about Saturday.
            Divider().overlay(Palette.divider)
            ActivityWeeklySection(weekStart: report.weekStart, weekEnd: report.weekEnd)
        }
    }

    private var tint: Color { VerdictDot.color(report.kind) }

    private func list(_ label: String, _ items: [String], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption2.weight(.heavy)).tracking(0.6)
                .foregroundStyle(Palette.faint)
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Circle().fill(tint).frame(width: 5, height: 5).padding(.top, 6)
                    Text(item).font(.footnote).foregroundStyle(Palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

struct VerdictDot: View {
    let verdict: WeeklyReport.Verdict

    var body: some View {
        Image(systemName: Self.icon(verdict))
            .font(.footnote.weight(.bold))
            .foregroundStyle(Self.color(verdict))
    }

    static func color(_ v: WeeklyReport.Verdict) -> Color {
        switch v {
        case .gaining: return Palette.green
        case .holding: return Palette.attention
        case .slipping: return Palette.warning
        case .unknown: return Palette.muted
        }
    }

    static func icon(_ v: WeeklyReport.Verdict) -> String {
        switch v {
        case .gaining: return "arrow.up.right.circle.fill"
        case .holding: return "equal.circle.fill"
        case .slipping: return "arrow.down.right.circle.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }
}

private struct PastReportSheet: View {
    let report: WeeklyReport
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let content = ScrollView {
            VStack(alignment: .leading, spacing: Gap.screen) {
                HStack {
                    Text(Fmt.day(report.weekStart) + " – " + Fmt.day(report.weekEnd))
                        .font(.caption2.weight(.heavy))
                        .foregroundStyle(Palette.faint)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.caption.weight(.bold))
                    }
                    .buttonStyle(.borderless)
                }
                ReportBody(report: report)
            }
            .padding(20)
        }
        .background(Palette.background)

        #if os(iOS)
        content.presentationDetents([.large]).presentationBackground(Palette.background)
        #else
        content.frame(width: 460, height: 600)
        #endif
    }
}
