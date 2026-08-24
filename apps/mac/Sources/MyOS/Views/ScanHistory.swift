import SwiftUI

/// Everything the camera has read, and the verdict card both a fresh scan and a
/// history row render through.

// MARK: - Thumbnails

/// Decoded scan photos, keyed by R2 id. A 720px JPEG is cheap to decode once and
/// expensive to decode on every body pass — which is exactly what a list does.
@MainActor
enum ScanThumbCache {
    private static var cache: [String: Image] = [:]

    static func image(for key: String, data: Data) -> Image? {
        if let hit = cache[key] { return hit }
        guard let img = MediaJPEG.image(from: data) else { return nil }
        if cache.count > 80 { cache.removeAll() }   // bounded, crude, plenty
        cache[key] = img
        return img
    }
}

/// A scan's photo, or a glyph while it loads (or if the upload never landed).
struct ScanThumb: View {
    let record: ScanRecord
    var size: CGFloat = 46
    var radius: CGFloat = Radius.sm

    @ObservedObject private var media = EventMediaStore.shared

    var body: some View {
        ZStack {
            if let key = record.photoKey, let bytes = media.data(key: key),
               let img = ScanThumbCache.image(for: key, data: bytes) {
                img.resizable().aspectRatio(contentMode: .fill)
            } else {
                Palette.surface2
                Image(systemName: record.isFood ? "fork.knife" : "shippingbox.fill")
                    .font(.system(size: size * 0.32, weight: .semibold))
                    .foregroundStyle(Palette.faint)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

// MARK: - The verdict

/// The result body — food macros, or the wanted / not-wanted call. Shared so a
/// scan you just took and one from three weeks ago look identical.
struct ScanVerdictView: View {
    let insight: ScanInsight

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if insight.kind == .food {
                foodBody
            } else if let o = insight.object {
                objectBody(o)
            }
        }
    }

    @ViewBuilder private var foodBody: some View {
        Text("FOOD").font(.caption.weight(.heavy)).tracking(0.8)
            .foregroundStyle(Palette.green)
        Text(insight.summary).font(.body.weight(.semibold)).foregroundStyle(Palette.text)
        ForEach(insight.foods, id: \.name) { f in
            VStack(alignment: .leading, spacing: 8) {
                Text(f.name).font(.body.weight(.semibold))
                Text(f.serving).font(.footnote).foregroundStyle(Palette.muted)
                HStack {
                    macro("\(Int(f.calories))", "kcal")
                    macro("\(Int(f.protein))g", "protein")
                    macro("\(Int(f.carbs))g", "carbs")
                    macro("\(Int(f.fats))g", "fat")
                }
            }
        }
    }

    @ViewBuilder private func objectBody(_ o: ScanInsight.Object) -> some View {
        Text(ScanVerdict.label(o.needed).uppercased())
            .font(.caption.weight(.heavy)).tracking(0.7)
            .foregroundStyle(ScanVerdict.color(o.needed))
        Text(o.name)
            .font(.title2.weight(.semibold)).foregroundStyle(Palette.text)
        if !insight.summary.isEmpty, insight.summary != o.name {
            Text(insight.summary).font(.subheadline).foregroundStyle(Palette.muted)
        }

        field("WANTED FOR YOU") {
            Text(ScanVerdict.blurb(o.needed))
                .font(.callout.weight(.semibold))
                .foregroundStyle(ScanVerdict.color(o.needed))
        }
        if !o.why.isEmpty {
            field("WHY") { body(o.why) }
        }
        if !o.useful.isEmpty {
            field(o.needed == .no ? "DO THIS INSTEAD" : "HOW IT HELPS") { body(o.useful) }
        }
    }

    private func body(_ s: String) -> some View {
        Text(s).font(.callout).foregroundStyle(Palette.text)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func field<C: View>(_ label: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption2.weight(.heavy)).tracking(0.6)
                .foregroundStyle(Palette.faint)
            content()
        }
    }

    private func macro(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.subheadline.weight(.semibold)).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(Palette.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Palette.surface2, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }
}

/// The wanted / not-wanted vocabulary, in one place.
enum ScanVerdict {
    static func label(_ n: ScanInsight.Needed) -> String {
        switch n {
        case .yes: return "Wanted"
        case .no: return "Not wanted"
        case .maybe: return "Maybe useful"
        }
    }
    static func blurb(_ n: ScanInsight.Needed) -> String {
        switch n {
        case .yes: return "Yes — this fits your life."
        case .no: return "No — skip it."
        case .maybe: return "Only if you actually use it."
        }
    }
    static func color(_ n: ScanInsight.Needed) -> Color {
        switch n {
        case .yes: return Palette.green
        case .no: return Palette.red
        case .maybe: return Palette.amber
        }
    }
}

// MARK: - The list

struct ScanHistoryList: View {
    @EnvironmentObject var state: AppState
    @State private var expanded = false
    @State private var detail: ScanRecord?
    @State private var pendingDelete: String?

    private static let collapsedCount = 8

    private var shown: [ScanRecord] {
        expanded ? state.scans : Array(state.scans.prefix(Self.collapsedCount))
    }

    var body: some View {
        if !state.scans.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: Gap.row) {
                    header
                    VStack(spacing: Gap.row) {
                        ForEach(shown) { r in
                            ScanHistoryRow(record: r,
                                           today: state.todayKey,
                                           onOpen: { detail = r },
                                           onDelete: { pendingDelete = r.id })
                        }
                    }
                    if state.scans.count > Self.collapsedCount {
                        Button { withAnimation(.knNormal) { expanded.toggle() } } label: {
                            Text(expanded ? "Show less"
                                          : "Show all \(state.scans.count)")
                                .font(.caption.weight(.heavy))
                        }
                        .buttonStyle(KGhostButtonStyle(color: Palette.teal))
                    }
                }
            }
            .sheet(item: $detail) { r in
                ScanDetailSheet(record: r) { state.deleteScan(r.id); detail = nil }
            }
            .holdToDelete(
                isPresented: Binding(get: { pendingDelete != nil },
                                     set: { if !$0 { pendingDelete = nil } }),
                title: "Delete this scan?",
                message: "The photo goes too. This can't be undone."
            ) {
                if let id = pendingDelete { state.deleteScan(id) }
                pendingDelete = nil
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            SectionTitle(text: "Recent scans")
            Text("\(state.scans.count)")
                .font(.caption2.weight(.semibold)).monospacedDigit()
                .foregroundStyle(Palette.faint)
            Spacer(minLength: 0)
        }
    }
}

private struct ScanHistoryRow: View {
    let record: ScanRecord
    let today: String
    let onOpen: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onOpen) {
                HStack(spacing: 10) {
                    ScanThumb(record: record)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.title)
                            .font(.footnote.weight(.semibold)).foregroundStyle(Palette.text)
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            Text(ScanRecord.dayLabel(record.date, today: today))
                                .font(.caption2.weight(.heavy))
                                .foregroundStyle(Palette.faint)
                            if record.isFood, record.logged {
                                Text("LOGGED")
                                    .font(.caption2.weight(.heavy))
                                    .foregroundStyle(Palette.green)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                    Text(record.badge)
                        .font(.caption2.weight(.heavy))
                        .foregroundStyle(badgeColor)
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .background(badgeColor.opacity(0.14), in: Capsule())
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(KPressStyle())

            Button(action: onDelete) {
                Image(systemName: "xmark").font(.caption2.weight(.bold))
            }
            .buttonStyle(KIconButtonStyle(size: 22))
        }
    }

    private var badgeColor: Color {
        if record.isFood { return Palette.green }
        switch record.object?.needed {
        case "yes": return Palette.green
        case "no": return Palette.red
        default: return Palette.amber
        }
    }
}

// MARK: - Detail

struct ScanDetailSheet: View {
    let record: ScanRecord
    let onDelete: () -> Void

    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    var body: some View {
        let content = ScrollView {
            VStack(alignment: .leading, spacing: Gap.screen) {
                HStack {
                    Text(ScanRecord.dayLabel(record.date, today: state.todayKey))
                        .font(.caption2.weight(.heavy))
                        .foregroundStyle(Palette.faint)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.caption.weight(.bold))
                    }
                    .buttonStyle(KIconButtonStyle(size: 28))
                }

                if record.photoKey != nil {
                    ScanThumb(record: record, size: 220, radius: Radius.md)
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                ScanVerdictView(insight: record.insight)

                Button { confirmDelete = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "trash").font(.caption.weight(.bold))
                        Text("Delete scan")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(KSecondaryButtonStyle(fullWidth: true))
            }
            .padding(20)
        }
        .background(Palette.bg)
        .holdToDelete(isPresented: $confirmDelete,
                      title: "Delete this scan?",
                      message: "The photo goes too. This can't be undone.") {
            onDelete()
            dismiss()
        }

        #if os(iOS)
        content.presentationDetents([.large]).presentationBackground(Palette.bg)
        #else
        content.frame(width: 460, height: 620)
        #endif
    }
}
