import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// Fluid interface — Apple's physical-motion rules, translated to SwiftUI.
//
// Source: "Designing Fluid Interfaces" (WWDC 2018) via the repo's apple-design
// doc. SwiftUI's springs are already interruptible and velocity-aware when they
// animate a `value:` binding, which is exactly what interruption (§3) needs —
// so the job here is to make the *right* spring the easiest one to reach for,
// and to pin the gesture maths (projection, rubber-banding, velocity handoff)
// as pure, testable functions instead of scattering them across views.
//
// Rules encoded, by doc section:
//   §1 response      — `FluidPressStyle`: highlight on press-down, instant,
//                      ~100ms. Never gate feedback on release.
//   §3 interruptible — every token is a spring on a `value:`, never a
//                      fixed-duration ease on a transition; input is never
//                      locked out mid-flight.
//   §4 springs       — `FluidSpring`: critically damped (1.0) by default;
//                      bounce (0.8) only when a flick preceded it.
//   §5 velocity      — `Fluid.relativeVelocity`, and the slide controls hand
//                      release velocity into their snap-back spring.
//   §6 projection    — `Fluid.project`: exponential-decay form Apple ships,
//                      NOT v²/(2·decel).
//   §9 rubber-band   — `FluidRubberband`: progressive resistance past a bound.
//   §10 gestures     — `VelocityTracker` + commit-by-velocity-sign.
//   §12 materials    — `fluidBarMaterial()`: translucent bars with content
//                      scrolling underneath, never opaque strips.
//   §13 feedback     — haptics fire on the causal event, inside the same frame
//                      as the visual commit (call sites pair `Haptics.*` with
//                      the state change, not after a delay).
//   §14 reduced      — `Fluid.reducedMotion` / `reducedTransparency`: springs
//                      become short cross-fades, materials go solid.
//   §15 type         — `FluidType`: size-specific tracking/leading.

// MARK: - Springs (§4)

/// The two designer-friendly spring parameters. Response is NOT duration — a
/// spring has no fixed duration; settle time emerges from these.
struct FluidSpring {
    /// Damping ratio. 1.0 = critically damped, no bounce. ~0.8 = slight
    /// overshoot, only when a flick preceded the motion.
    var damping: Double
    /// How quickly the value reaches target, in seconds. Lower = snappier.
    var response: Double

    /// The default for all UI: graceful, non-distracting, no overshoot.
    static let ui = FluidSpring(damping: 1.0, response: 0.32)
    /// Momentum interaction — a flick, throw or drag release preceded this.
    static let momentum = FluidSpring(damping: 0.8, response: 0.32)
    /// Small controls popping (tab switch, expand chevron).
    static let pop = FluidSpring(damping: 1.0, response: 0.26)
    /// Sheets / drawers.
    static let sheet = FluidSpring(damping: 0.8, response: 0.30)
    /// Repositioning (page turns, re-layout).
    static let move = FluidSpring(damping: 1.0, response: 0.40)

    var animation: Animation {
        .spring(response: response, dampingFraction: damping)
    }

    /// Reduced-motion equivalent: a short opacity cross-fade, no travel, no
    /// overshoot (§14). Springs never survive reduced motion.
    var reducedAnimation: Animation {
        .easeOut(duration: 0.2)
    }
}

extension Animation {
    /// A critically-damped spring for general UI (§4 default).
    static var fluidUI: Animation {
        Motion.reduceMotion ? FluidSpring.ui.reducedAnimation : FluidSpring.ui.animation
    }
    /// Under-damped spring — only for motion a flick preceded (§4).
    static var fluidMomentum: Animation {
        Motion.reduceMotion ? FluidSpring.momentum.reducedAnimation : FluidSpring.momentum.animation
    }
    /// Small control pop. No bounce, ever.
    static var fluidPop: Animation {
        Motion.reduceMotion ? .easeOut(duration: 0.12) : FluidSpring.pop.animation
    }
    /// Sheets / drawers.
    static var fluidSheet: Animation {
        Motion.reduceMotion ? FluidSpring.sheet.reducedAnimation : FluidSpring.sheet.animation
    }
    /// Repositioning.
    static var fluidMove: Animation {
        Motion.reduceMotion ? FluidSpring.move.reducedAnimation : FluidSpring.move.animation
    }
}

// MARK: - Projection + velocity handoff (§5, §6)

enum Fluid {
    /// Apple's exact momentum-projection function (exponential decay, from the
    /// *Designing Fluid Interfaces* sample code). `decelerationRate ≈ 0.998`
    /// for normal scroll feel, `0.99` for snappier.
    static func project(initialVelocity velocity: Double, decelerationRate d: Double = 0.998) -> Double {
        (velocity / 1000) * d / (1 - d)
    }

    /// Where the gesture is *going*: rest point if released now, before any
    /// snap decision. Choose the target from this, not from the release point.
    static func projectedEndpoint(current: Double, velocity: Double, decelerationRate d: Double = 0.998) -> Double {
        current + project(initialVelocity: velocity, decelerationRate: d)
    }

    /// Snap target nearest the projected endpoint.
    static func nearestSnap(projected: Double, snaps: [Double]) -> Double {
        guard let first = snaps.first else { return projected }
        return snaps.min(by: { abs($0 - projected) < abs($1 - projected) }) ?? first
    }

    /// Normalised initial velocity for spring APIs that want it relative to
    /// the remaining distance.
    static func relativeVelocity(gestureVelocity v: Double, current: Double, target: Double) -> Double {
        let remaining = target - current
        guard remaining != 0 else { return 0 }
        return v / remaining
    }

    /// Commit-or-reverse decision at release (§10, quick reference). Velocity
    /// SIGN wins over position: a fast fling toward commit commits even from
    /// just short of the threshold, and a fling back reverses even from just
    /// past it. `direction` is +1 when commit means increasing progress.
    static func shouldCommit(progress: Double, threshold: Double, velocity: Double,
                             direction: Double = 1, flingThreshold: Double = 400) -> Bool {
        let signed = velocity * direction
        if signed >= flingThreshold { return true }
        if signed <= -flingThreshold { return false }
        return progress >= threshold
    }
}

// MARK: - Rubber-banding (§9)

/// Soft boundaries: resist progressively past the edge instead of hard-stopping.
/// A hard stop reads as frozen; continuous resistance reads as responsive.
enum FluidRubberband {
    /// Damped overshoot. `overshoot` is points past the bound, `dimension` is
    /// the draggable extent (e.g. travel), `constant` tunes softness (0.55 ≈ iOS).
    static func apply(overshoot: Double, dimension: Double, constant: Double = 0.55) -> Double {
        guard overshoot != 0, dimension > 0 else { return 0 }
        let mag = (abs(overshoot) * dimension * constant) / (dimension + constant * abs(overshoot))
        return overshoot < 0 ? -mag : mag
    }

    /// Clamp a drag offset to `[0, travel]` with rubber-banding on both ends.
    static func clamp(_ offset: Double, travel: Double) -> Double {
        if offset < 0 { return apply(overshoot: offset, dimension: travel) }
        if offset > travel { return travel + apply(overshoot: offset - travel, dimension: travel) }
        return offset
    }
}

// MARK: - Velocity history (§2)

/// Short position/time history for release-velocity handoff (§5). Feed every
/// `onChanged` sample; read `velocity` in `onEnded`.
struct VelocityTracker {
    private var samples: [(pos: Double, time: Double)] = []
    private let maxSamples = 5
    /// Samples older than this are irrelevant to the release flick.
    private let window: Double = 0.12

    mutating func append(_ pos: Double, at time: Double = Date().timeIntervalSinceReferenceDate) {
        samples.append((pos, time))
        if samples.count > maxSamples { samples.removeFirst(samples.count - maxSamples) }
        samples.removeAll { time - $0.time > window && $0.time != time }
    }

    /// Points per second at release. 0 when there is nothing to inherit.
    var velocity: Double {
        guard samples.count >= 2,
              let first = samples.first, let last = samples.last,
              last.time > first.time else { return 0 }
        return (last.pos - first.pos) / (last.time - first.time)
    }

    mutating func reset() { samples.removeAll() }
}

// MARK: - Press feedback (§1)

/// Instant press-down feedback: scale 0.97 in ~100ms, applied the moment the
/// finger lands — never waiting for release. The SwiftUI equivalent of the
/// doc's `.button:active` rule.
struct FluidPressStyle: ButtonStyle {
    var scale: CGFloat = 0.97
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            // 100ms ease-out on press: instant enough to feel glued (§1).
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

extension View {
    /// Press-down physics for any button. Pair with a `Haptics.tap()` in the
    /// action for the §13 visual+haptic same-frame harmony.
    func fluidPressable(scale: CGFloat = 0.97) -> some View {
        buttonStyle(FluidPressStyle(scale: scale))
    }
}

// MARK: - Materials (§12)

extension View {
    /// Translucent bar material: content scrolls underneath a blurred layer,
    /// not behind an opaque strip. Goes solid when the user asked for reduced
    /// transparency (§14). iOS bars and the Mac sidebar both build on this.
    @ViewBuilder
    func fluidBarMaterial() -> some View {
        if Fluid.reduceTransparency {
            self.background(Palette.background)
        } else {
            self.background(.ultraThinMaterial)
        }
    }
}

extension Fluid {
    /// `prefers-reduced-transparency: reduce` — translucent surfaces go solid.
    static var reduceTransparency: Bool {
        #if os(iOS)
        UIAccessibility.isReduceTransparencyEnabled
        #else
        NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        #endif
    }

    /// `prefers-reduced-motion: reduce` — springs become cross-fades (§14).
    /// Centralised on `Motion.reduceMotion` so there is one switch, not three.
    static var reducedMotion: Bool { Motion.reduceMotion }
}

// MARK: - Typography (§15)

/// Size-specific tracking/leading. Large display text wants negative tracking
/// and tight leading; small caps labels want positive tracking; body stays
/// near zero. A fixed `letter-spacing` is wrong somewhere — these are the
/// per-role values.
enum FluidType {
    /// Large hero text: tight leading, negative tracking. 64pt wants more
    /// pull-in than a caption — a fixed -0.5 leaves the digits looking sparse.
    static let displayTracking: CGFloat = -1.2
    static let displayLeading: CGFloat = 1.05
    /// Uppercase section labels (caption, heavy, tracked): positive tracking.
    static let sectionTracking: CGFloat = 0.8
    /// Body: near-zero tracking, comfortable leading.
    static let bodyTracking: CGFloat = 0
    static let bodyLeading: CGFloat = 1.5
}

extension View {
    /// Hero metrics — the one number a card exists to show (§15 display).
    func fluidDisplay() -> some View {
        self.font(.myDisplay)
            .tracking(FluidType.displayTracking)
            .lineSpacing(0)
    }
    /// Uppercase section label with size-correct tracking.
    func fluidSectionLabel() -> some View {
        self.font(.myCaption)
            .tracking(FluidType.sectionTracking)
    }
}
