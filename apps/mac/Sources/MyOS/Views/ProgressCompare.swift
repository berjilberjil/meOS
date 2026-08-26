import SwiftUI
#if os(macOS)
import AppKit

// Two dates, side by side.
//
// Mac only, and not by omission: a body-progress comparison is two full photos
// at once, and two full photos on a phone are two thumbnails — which is worse
// than the single photo you already had. Deciding a cut is working is a question
// you ask at a desk.

/// The arithmetic of a comparison, without any of the pixels. Pure so the
/// interesting parts — an empty library, one photo, several on the same day —
/// are pinned by tests rather than found by clicking.
@MainActor
enum PhotoCompare {

    /// Oldest first. The panes index into this, photo by photo rather than day
    /// by day, so several shots on one date can be stepped through instead of
    /// one of them being unreachable.
    static func ordered(_ photos: [ProgressPhoto]) -> [ProgressPhoto] {
        photos.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
    }

    /// Where the two panes start: the oldest against the newest, which is the
    /// comparison anyone opens this for.
    static func endpoints(_ photos: [ProgressPhoto]) -> (left: Int, right: Int)? {
        let all = ordered(photos)
        guard all.count >= 2 else { return nil }
        return (0, all.count - 1)
    }

    /// Whole days between two `yyyy-MM-dd` keys, always positive.
    static func daysApart(_ a: String, _ b: String) -> Int {
        guard let da = AppState.date(fromKey: a), let db = AppState.date(fromKey: b) else { return 0 }
        return abs(Calendar(identifier: .gregorian)
            .dateComponents([.day], from: min(da, db), to: max(da, db)).day ?? 0)
    }

    /// The line under the two photos. nil where there is nothing true to say —
    /// the same day twice, or no weight logged on either end.
    static func caption(left: ProgressPhoto, right: ProgressPhoto,
                        weight: (String) -> Double?) -> String? {
        var parts: [String] = []
        let days = daysApart(left.date, right.date)
        if days > 0 { parts.append("\(days) day\(days == 1 ? "" : "s") apart") }
        if let a = weight(left.date), let b = weight(right.date) {
            let delta = b - a
            let sign = delta > 0 ? "+" : (delta < 0 ? "−" : "")
            parts.append("\(sign)\(Fmt.trimKg(abs(delta))) kg")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Two panes, each with its own day stepper.
struct ProgressCompareView: View {
    @EnvironmentObject var state: AppState
    let onClose: () -> Void

    @State private var all: [ProgressPhoto]
    @State private var left: Int
    @State private var right: Int

    init(photos: [ProgressPhoto], onClose: @escaping () -> Void) {
        self.onClose = onClose
        let ordered = PhotoCompare.ordered(photos)
        _all = State(initialValue: ordered)
        let ends = PhotoCompare.endpoints(ordered)
        _left = State(initialValue: ends?.left ?? 0)
        _right = State(initialValue: ends?.right ?? 0)
    }

    private var leftPhoto: ProgressPhoto? { all.indices.contains(left) ? all[left] : nil }
    private var rightPhoto: ProgressPhoto? { all.indices.contains(right) ? all[right] : nil }

    private var windowSize: CGSize {
        let visible = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1440, height: 900)
        return CGSize(width: min(1280, visible.width * 0.92), height: min(880, visible.height * 0.92))
    }

    var body: some View {
        VStack(spacing: 14) {
            header
            if all.count < 2 {
                Spacer()
                Text("Two photos are needed to compare. Add another day first.")
                    .font(.myBody).foregroundStyle(Palette.faint)
                Spacer()
            } else {
                panes
                caption
            }
            keys
        }
        .padding(20)
        .frame(width: windowSize.width, height: windowSize.height)
        .background(Palette.elevated)
    }

    private var header: some View {
        HStack {
            Text("Compare").font(.callout.weight(.heavy)).foregroundStyle(Palette.text)
            Spacer()
            if all.count >= 2 {
                Button {
                    let l = left; left = right; right = l
                } label: { Label("Swap", systemImage: "arrow.left.arrow.right") }
                    .buttonStyle(.borderless).tint(Palette.faint)
                    .help("Swap the two sides")
            }
            Button(action: onClose) { Image(systemName: "xmark").font(.footnote.weight(.bold)) }
                .buttonStyle(.borderless)
        }
    }

    private var panes: some View {
        HStack(spacing: 16) {
            pane(index: $left, photo: leftPhoto)
            Divider().overlay(Palette.divider)
            pane(index: $right, photo: rightPhoto)
        }
    }

    private func pane(index: Binding<Int>, photo: ProgressPhoto?) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button { step(index, -1) } label: {
                    Image(systemName: "chevron.left").font(.caption.weight(.bold))
                }
                .buttonStyle(.borderless)
                .disabled(index.wrappedValue <= 0)

                VStack(spacing: 1) {
                    Text(Fmt.day(photo?.date ?? ""))
                        .font(.callout.weight(.heavy)).foregroundStyle(Palette.text)
                    if let photo, let kg = state.fitness[photo.date]?.weightKg {
                        Text("\(Fmt.trimKg(kg)) kg")
                            .font(.caption2.weight(.semibold)).monospacedDigit()
                            .foregroundStyle(Palette.muted)
                    }
                }
                .frame(maxWidth: .infinity)

                Button { step(index, 1) } label: {
                    Image(systemName: "chevron.right").font(.caption.weight(.bold))
                }
                .buttonStyle(.borderless)
                .disabled(index.wrappedValue >= all.count - 1)
            }

            if let photo {
                DiskImage(url: photo.url, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            } else {
                Palette.surfaceElevated.opacity(0.4)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
        }
    }

    @ViewBuilder private var caption: some View {
        if let l = leftPhoto, let r = rightPhoto,
           let line = PhotoCompare.caption(left: l, right: r, weight: { state.fitness[$0]?.weightKg }) {
            Text(line)
                .font(.footnote.weight(.semibold)).monospacedDigit()
                .foregroundStyle(Palette.muted)
        }
    }

    /// Arrow keys drive the right-hand side, which is the one that moves — the
    /// left is usually pinned to where you started. `[` and `]` move it when it
    /// needs to.
    private var keys: some View {
        HStack(spacing: 12) {
            Text("← → moves the right side · [ ] moves the left")
                .font(.caption2).foregroundStyle(Palette.faint)
            Spacer()
        }
        .background {
            ZStack {
                Button("") { step($right, -1) }.keyboardShortcut(.leftArrow, modifiers: [])
                Button("") { step($right, 1) }.keyboardShortcut(.rightArrow, modifiers: [])
                Button("") { step($left, -1) }.keyboardShortcut("[", modifiers: [])
                Button("") { step($left, 1) }.keyboardShortcut("]", modifiers: [])
                Button("") { onClose() }.keyboardShortcut(.cancelAction)
            }
            .opacity(0)
        }
    }

    private func step(_ index: Binding<Int>, _ delta: Int) {
        let next = index.wrappedValue + delta
        guard all.indices.contains(next) else { return }
        index.wrappedValue = next
    }
}

#endif
