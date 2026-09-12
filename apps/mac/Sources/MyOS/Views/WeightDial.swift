import SwiftUI

// The weight dial — the one control in MyOS you work by feel.
//
// Berjil's ask was a physical knob: turn it and the number moves 50 g a tick,
// each tick a tap of haptics; tap the caps either side for half a kilo. The
// reference he sent was a hi-fi knob ringed with a red-amber-green LED arc.
// That arc is the one thing here that is deliberately NOT copied: MyOS has
// three colours and each has a job, and orange means something has gone wrong.
// A weight you logged is not a warning. So the ring is faint ticks that light
// green as they pass, and the dial's weight on the page comes from being the
// only round thing on a page of rectangles.
//
// Arithmetic lives in `WeightDial` / `DialRotation` (Support/WeightDialMath),
// in front of tests. Nothing below decides what a turn is worth.

// MARK: - The control

/// A knob. Turn it for 50 g a detent; tap its centre to log the number as it
/// stands. Callers own the value and get told when a gesture finishes, so the
/// network sees one write per turn rather than one per tick.
struct WeightDialControl: View {
    @Binding var kg: Double
    /// A turn or a tap ended — persist now.
    var onCommit: () -> Void
    var size: CGFloat = 176
    /// Dimmed until the day actually has a weight against it.
    var logged: Bool = true

    /// Detents in a full revolution — 24, so one turn is 1.2 kg.
    private var ticks: Int { Int(360 / WeightDial.degreesPerDetent) }

    @State private var rotation = DialRotation()
    @State private var turning = false

    var body: some View {
        ZStack {
            tickRing
            face
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(turn)
        .onTapGesture { commitAsIs() }
        .scaleEffect(turning ? 0.97 : 1)
        .animation(.knFast, value: turning)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Weight")
        .accessibilityValue("\(WeightDial.format(kg)) kilograms")
        .accessibilityAdjustableAction { direction in
            step(direction == .increment ? 1 : -1)
            onCommit()
        }
    }

    // MARK: Ring

    /// One mark per detent. The mark the dial is currently parked on is lit, so
    /// a single tick of the thumb is visible as well as felt — the number moves
    /// by 0.05, which is easy to miss, but the light jumping a mark is not.
    private var tickRing: some View {
        let active = activeTick
        let count = ticks
        return ZStack {
            ForEach(0..<count, id: \.self) { i in
                tick(lit: i == active, at: Double(i) / Double(count) * 360)
            }
        }
        .animation(.knFast, value: active)
    }

    private func tick(lit: Bool, at degrees: Double) -> some View {
        let fill: Color = lit ? Palette.action : Palette.faint.opacity(0.35)
        let w: CGFloat = lit ? 4 : 2.5
        let h: CGFloat = lit ? 13 : 9
        return Capsule()
            .fill(fill)
            .frame(width: w, height: h)
            .offset(y: -(size / 2) + 7)
            .rotationEffect(.degrees(degrees))
    }

    /// Which mark the current weight sits on. Wraps every revolution, which is
    /// what makes it read as a wheel rather than a gauge.
    private var activeTick: Int {
        let steps = Int((WeightDial.clamp(kg) / WeightDial.fineStep).rounded())
        return ((steps % ticks) + ticks) % ticks
    }

    // MARK: Face

    private var face: some View {
        ZStack {
            Circle()
                .fill(Palette.surfaceElevated)
                .overlay(Circle().strokeBorder(Palette.borderStrong, lineWidth: 1))
                .overlay(
                    // A hair of light off the top edge, so the disc reads as a
                    // machined object rather than a flat hole in the card.
                    Circle().strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.10), .clear],
                                       startPoint: .top, endPoint: .center),
                        lineWidth: 1.5)
                )
                .padding(20)

            VStack(spacing: 0) {
                Text(WeightDial.format(kg))
                    .font(.system(size: 38, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(logged ? Palette.text : Palette.faint)
                    .contentTransition(.numericText())
                Text("kg")
                    .font(.myCaption.weight(.bold))
                    .foregroundStyle(Palette.faint)
                    .textCase(.uppercase)
                    .tracking(1)
            }
            .animation(.knFast, value: kg)
        }
    }

    // MARK: Turning

    /// `minimumDistance` is small but not zero: at zero the dial claims the
    /// touch the instant a finger lands, and Today is a page you scroll and
    /// swipe between days. Two points is under the threshold of a tap and over
    /// the threshold of resting a thumb.
    private var turn: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                turning = true
                let centre = CGPoint(x: size / 2, y: size / 2)
                let dx = value.location.x - centre.x
                let dy = value.location.y - centre.y
                // Dead zone. Within a few points of the centre the angle swings
                // wildly for a movement of nothing, which would spin the weight
                // on a thumb that is barely moving.
                guard dx * dx + dy * dy > pow(size * 0.16, 2) else { return }
                step(rotation.update(radians: atan2(dy, dx)))
            }
            .onEnded { _ in
                turning = false
                rotation.reset()
                onCommit()
            }
    }

    private func step(_ detents: Int) {
        guard detents != 0 else { return }
        let next = WeightDial.stepped(kg, detents: detents)
        // Silence at the limits is the point: no tick means the dial has
        // nothing left to give, which a hand understands without a label.
        guard next != kg else { return }
        kg = next
        Haptics.selection()
    }

    /// Tapped the face. The weight is already right — say so — which is the
    /// common case on a day you have not drifted.
    private func commitAsIs() {
        Haptics.success()
        onCommit()
    }
}

// MARK: - The card

/// The dial as it appears on Today and on Fitness: caps either side, the day's
/// number in the middle, and what it means underneath.
struct WeightCard: View {
    @EnvironmentObject var state: AppState
    /// The day this logs against — Today is paged, so it is not always `today`.
    var day: String
    var size: CGFloat = 176

    @State private var kg: Double = WeightDial.fallbackKg
    /// Seeded per day, so swiping to another day re-reads that day's number
    /// instead of carrying this one across.
    @State private var seededFor: String?

    private var loggedToday: Double? {
        let w = state.fitnessDay(day).weightKg
        return (w ?? 0) > 0 ? w : nil
    }
    private var previous: (kg: Double, date: String)? { state.lastWeight(before: day) }
    private var isLogged: Bool { loggedToday != nil }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                header
                HStack(spacing: 14) {
                    cap("minus", by: -WeightDial.coarseStep)
                    Spacer(minLength: 0)
                    WeightDialControl(kg: $kg, onCommit: commit, size: size, logged: isLogged)
                    Spacer(minLength: 0)
                    cap("plus", by: WeightDial.coarseStep)
                }
                .frame(maxWidth: .infinity)
                footer
            }
        }
        .onAppear { seed() }
        .onChange(of: day) { _, _ in seededFor = nil; seed() }
        // The number can also move from elsewhere — the typed field in Fitness
        // settings, or a pull from the other device.
        .onChange(of: loggedToday) { _, new in
            guard let new, abs(new - kg) > 1e-9 else { return }
            kg = WeightDial.clamp(WeightDial.snap(new))
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            SectionTitle(text: "Weight")
            Spacer()
            if let t = state.fitnessProfile.targetWeightKg, t > 0 {
                Text("goal \(Fmt.trimKg(t))")
                    .font(.myCaption.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(Palette.faint)
            }
        }
    }

    /// What the number on the dial means. Three states, and each is a different
    /// sentence rather than the same sentence greyed out.
    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 6) {
            if let delta = WeightDial.deltaLabel(kg, from: previous?.kg), let p = previous {
                Image(systemName: delta.hasPrefix("+") ? "arrow.up.right" : "arrow.down.right")
                    .font(.myCaption.weight(.bold))
                Text("\(delta) kg since \(Fmt.day(p.date))")
                    .font(.myCaption.weight(.semibold)).monospacedDigit()
            } else if isLogged {
                Image(systemName: "checkmark.circle.fill").font(.myCaption)
                Text("Logged for \(Fmt.day(day))").font(.myCaption.weight(.semibold))
            } else {
                Image(systemName: "hand.draw").font(.myCaption)
                Text("Turn to log · tap to keep \(WeightDial.format(kg))")
                    .font(.myCaption.weight(.semibold))
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(isLogged ? Palette.action : Palette.muted)
        .lineLimit(1)
        .minimumScaleFactor(0.85)
    }

    /// Half a kilo, for when the dial is simply in the wrong place.
    private func cap(_ symbol: String, by delta: Double) -> some View {
        Button {
            let next = WeightDial.nudged(kg, by: delta)
            guard next != kg else { return }
            kg = next
            Haptics.tap()
            commit()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Palette.action)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Palette.surfaceElevated))
                .overlay(Circle().strokeBorder(Palette.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(delta > 0 ? "Add half a kilo" : "Take off half a kilo")
    }

    private func seed() {
        guard seededFor != day else { return }
        seededFor = day
        kg = WeightDial.seed(logged: loggedToday,
                             latest: previous?.kg,
                             target: state.fitnessProfile.targetWeightKg)
    }

    private func commit() { state.setWeight(kg, on: day) }
}
