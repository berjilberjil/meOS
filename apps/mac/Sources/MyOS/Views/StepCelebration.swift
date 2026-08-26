import SwiftUI

// Crossing a step goal: the ring that shows both goals, and the card that says
// something about it when one of them is passed.

/// The day's steps against both goals, as one ring.
///
/// Scaled to the *stretch*, with the mandatory goal marked by a tick — one road
/// with a milestone on it, rather than two competing scores. The arc up to the
/// tick is solid: once it is full, the day's job is done and everything past it
/// is a lighter shade, which is exactly the weight those two things should have.
struct StepGoalRing: View {
    let steps: Int
    let goals: StepGoals
    var size: CGFloat = 190
    var lineWidth: CGFloat = 14

    /// Where the mandatory goal sits on a ring scaled to the stretch.
    private var milestone: Double { Double(goals.daily) / Double(goals.stretch) }
    private var progress: Double { min(1, Double(steps) / Double(max(1, goals.stretch))) }
    private var hitDaily: Bool { steps >= goals.daily }

    var body: some View {
        ZStack {
            Circle().stroke(Palette.border, lineWidth: lineWidth)

            // The mandatory stretch of the ring.
            Circle()
                .trim(from: 0, to: max(0.002, min(progress, milestone)))
                .stroke(hitDaily ? Palette.complete : Palette.activity,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))

            // Everything past it, lighter — earned, not owed.
            if progress > milestone {
                Circle()
                    .trim(from: milestone, to: progress)
                    .stroke(Palette.complete.opacity(0.45),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }

            // The tick, so 8,000 is a place on the ring and not a guess.
            Rectangle()
                .fill(Palette.background)
                .frame(width: 2, height: lineWidth + 2)
                .offset(y: -size / 2 + lineWidth / 2)
                .rotationEffect(.degrees(360 * milestone))

            VStack(spacing: 1) {
                Text(steps.formatted())
                    .font(.largeTitle.weight(.heavy)).monospacedDigit()
                    .foregroundStyle(Palette.text)
                Text("of \(goals.stretch.formatted()) steps")
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(Palette.faint)
                Text(caption)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(hitDaily ? Palette.complete : Palette.muted)
                    .padding(.top, 2)
            }
        }
        .frame(width: size, height: size)
        .frame(maxWidth: .infinity)
    }

    /// Always names the goal that matters *next* — the one you have not reached.
    private var caption: String {
        if steps >= goals.stretch { return "Both goals" }
        if hitDaily { return "\((goals.stretch - steps).formatted()) to \(goals.stretch.formatted())" }
        return "\((goals.daily - steps).formatted()) to \(goals.daily.formatted())"
    }
}

/// Two goals as one bar, for the cards that have no room for a ring.
struct StepGoalBar: View {
    let steps: Int
    let goals: StepGoals
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let milestone = Double(goals.daily) / Double(max(1, goals.stretch))
            let progress = min(1, Double(steps) / Double(max(1, goals.stretch)))
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.border)
                Capsule()
                    .fill(steps >= goals.daily ? Palette.complete.opacity(0.45) : Palette.activity)
                    .frame(width: max(2, w * progress))
                if steps >= goals.daily {
                    Capsule().fill(Palette.complete).frame(width: max(2, w * milestone))
                }
                Rectangle()
                    .fill(Palette.background)
                    .frame(width: 2, height: height)
                    .offset(x: w * milestone - 1)
            }
        }
        .frame(height: height)
    }
}

/// A goal, just crossed.
///
/// It takes over the steps card rather than arriving as a banner, because a
/// banner is something you dismiss without reading and this is the one moment in
/// the day the app has something worth saying. It shows once — `hailed` in the
/// synced day makes sure of that — and the streak line underneath is the reason
/// tomorrow matters.
struct StepCelebrationCard: View {
    let celebration: StepCelebration
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: celebration.level >= 2 ? "star.circle.fill" : "checkmark.circle.fill")
                    .font(.callout.weight(.bold))
                    .foregroundStyle(Palette.complete)
                Text(celebration.level >= 2 ? "STRETCH GOAL" : "GOAL HIT")
                    .font(.caption.weight(.heavy))
                    .kerning(0.8)
                    .foregroundStyle(Palette.complete)
                Spacer(minLength: 0)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(celebration.steps.formatted())
                    .font(.largeTitle.weight(.heavy)).monospacedDigit()
                    .foregroundStyle(Palette.text)
                Text("steps")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.muted)
            }

            if celebration.streak > 0 {
                Text(celebration.streak == 1
                     ? "Day 1 of a new streak."
                     : "Day \(celebration.streak) of the streak.")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.muted)
            }

            Text(celebration.quote)
                .font(.callout.weight(.medium))
                .foregroundStyle(Palette.text)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                if let remaining = celebration.remaining, let next = celebration.next, remaining > 0 {
                    Text("\(remaining.formatted()) to \(next.formatted())")
                        .font(.caption.weight(.bold)).monospacedDigit()
                        .foregroundStyle(Palette.complete)
                }
                Spacer(minLength: 0)
                Button("Nice", action: onDismiss)
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.action)
                    .foregroundStyle(Accent.green.ink)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.complete.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(Palette.complete.opacity(0.45), lineWidth: 1.5))
        .transition(.scale(scale: 0.96).combined(with: .opacity))
    }
}
