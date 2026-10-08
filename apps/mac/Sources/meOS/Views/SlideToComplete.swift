import SwiftUI

/// Drag-to-confirm. Task Mode's "done" is a slide rather than a tap because a
/// tap is one stray click away from marking work finished that isn't, and the
/// whole point of the mode is that you are moving fast inside it.
///
/// Fluid behaviour (§2, §5, §6, §9, §10):
/// - 1:1 tracking while the thumb is down; the knob never snaps to the finger.
/// - Release velocity is handed into the settle spring, so a fling toward the
///   end commits even from just short of the threshold and a fling back
///   reverses even from just past it (velocity sign wins over position).
/// - Past either end the knob rubber-bands instead of hard-stopping.
/// - The settle animation is an interruptible spring on the live offset — grab
///   it mid-flight and it follows the finger, never finishes first.
/// - Haptics fire on the causal frame: ticks while travelling, success on
///   commit, a soft bump on reverse (§13).
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
    @State private var dragging = false
    @State private var tracker = VelocityTracker()
    @State private var lastTickBand = 0

    private let knob: CGFloat = 44
    private let inset: CGFloat = 4
    /// How far along counts as meant-it.
    private let threshold = 0.72
    /// Points/sec that counts as a fling in either direction.
    private let flingThreshold = 400.0

    var body: some View {
        GeometryReader { geo in
            let travel = max(1, geo.size.width - knob - inset * 2)
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.surfaceElevated)
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
                                if !dragging { dragging = true; Haptics.prepare() }
                                tracker.append(Double(v.translation.width))
                                // 1:1 tracking with soft boundaries (§2, §9).
                                let next = FluidRubberband.clamp(Double(v.translation.width), travel: Double(travel))
                                offset = CGFloat(next)
                                // Detent ticks as the thumb travels (§13 utility).
                                let band = Int((offset / travel) * 4)
                                if band > lastTickBand { Haptics.slideTicks(band - lastTickBand) }
                                lastTickBand = band
                            }
                            .onEnded { _ in
                                guard !completed else { return }
                                dragging = false
                                let v = tracker.velocity
                                tracker.reset()
                                lastTickBand = 0
                                let progress = Double(offset / travel)
                                if Fluid.shouldCommit(progress: progress, threshold: threshold,
                                                      velocity: v, flingThreshold: flingThreshold) {
                                    completed = true
                                    // Velocity carries through the re-target —
                                    // no brick wall at the reversal (§3, §5).
                                    withAnimation(.fluidMomentum) { offset = travel }
                                    Haptics.success()
                                    action()
                                } else {
                                    Haptics.slideCancel()
                                    withAnimation(.fluidMomentum) { offset = 0 }
                                }
                            }
                    )
            }
        }
        .frame(height: knob + inset * 2)
        .accessibilityElement()
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { if !completed { completed = true; Haptics.success(); action() } }
    }

    /// The knob grows slightly the moment the finger lands (§1: feedback on
    /// press-down, continuous during the drag, never only at the end).
    private var knobView: some View {
        ZStack {
            Circle().fill(tint)
            Image(systemName: completed ? "checkmark" : "chevron.right")
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(.white)
        }
        .frame(width: knob, height: knob)
        .scaleEffect(dragging && !completed ? 1.08 : 1)
        .animation(.easeOut(duration: 0.1), value: dragging)
    }
}
