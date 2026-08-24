import SwiftUI

/// Drag-to-confirm. Task Mode's "done" is a slide rather than a tap because a
/// tap is one stray click away from marking work finished that isn't, and the
/// whole point of the mode is that you are moving fast inside it.
///
/// Re-key it (`.id(taskID)`) when the thing being completed changes — the knob
/// stays parked at the end after a successful slide, which is the right look
/// until it is a different task.
struct SlideToComplete: View {
    var title: String
    var tint: Color = Palette.green
    let action: () -> Void

    @State private var offset: CGFloat = 0
    @State private var completed = false

    private let knob: CGFloat = 44
    private let inset: CGFloat = 4
    /// How far along counts as meant-it.
    private let threshold = 0.72

    var body: some View {
        GeometryReader { geo in
            let travel = max(1, geo.size.width - knob - inset * 2)
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.surface2)
                Capsule().fill(tint.opacity(0.18))
                    .frame(width: knob + offset + inset * 2)

                Text(completed ? "Done" : title)
                    .font(.footnote.weight(.heavy))
                    .foregroundStyle(completed ? tint : Palette.muted)
                    .frame(maxWidth: .infinity)
                    // Fades out as the knob travels over it.
                    .opacity(completed ? 1 : 1 - Double(offset / travel))

                knobView
                    .offset(x: offset + inset)
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { v in
                                guard !completed else { return }
                                offset = min(travel, max(0, v.translation.width))
                            }
                            .onEnded { _ in
                                guard !completed else { return }
                                if offset > travel * threshold {
                                    completed = true
                                    offset = travel
                                    Haptics.success()
                                    action()
                                } else {
                                    withAnimation(.knPop) { offset = 0 }
                                }
                            }
                    )
            }
        }
        .frame(height: knob + inset * 2)
        .accessibilityElement()
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { if !completed { completed = true; action() } }
    }

    private var knobView: some View {
        ZStack {
            Circle().fill(tint)
            Image(systemName: completed ? "checkmark" : "chevron.right")
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(.white)
        }
        .frame(width: knob, height: knob)
    }
}
