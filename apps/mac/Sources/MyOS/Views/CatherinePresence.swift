import SwiftUI

/// Catherine, as a form rather than a logo: a small dense core inside two soft
/// blooms of her own green. The core holds still; only the light around it
/// breathes — which is what reads as presence instead of a pulsing indicator.
///
/// The blooms are deliberately off-centre from each other by a few points. A
/// perfectly concentric version reads as a target or a loading ring; the slight
/// offset makes it feel lit rather than drawn.
struct CatherinePresence: View {
    /// 0 = a single point, 1 = fully formed. Driven by the splash's boot sequence.
    var reveal: Double = 1
    /// Started once she has finished arriving, so the breath never fights the
    /// reveal animation for the same layer.
    var breathing: Bool = false
    var size: CGFloat = 132

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breath: CGFloat = 1

    var body: some View {
        ZStack {
            // The light: ambient, offset, breathing.
            ZStack {
                bloom(alpha: 0.13, scale: 1.90, blur: 30, offset: CGSize(width: -5, height: -7))
                bloom(alpha: 0.26, scale: 1.15, blur: 14, offset: CGSize(width: 3, height: 4))
            }
            .scaleEffect(breath)
            .opacity(reveal)

            core
        }
        .frame(width: size, height: size)
        .onAppear { if breathing { start() } }
        .onChange(of: breathing) { _, on in if on { start() } else { breath = 1 } }
    }

    /// The point everything grows out of. It never scales past 1, so the
    /// silhouette stays still while the light moves around it.
    private var core: some View {
        // Spelled out rather than inlined: the mixed CGFloat/Double arithmetic
        // in one chain is enough to time out the type-checker.
        let side: CGFloat = size * 0.21
        let scale: CGFloat = CGFloat(0.10 + 0.90 * reveal)
        let glow: CGFloat = CGFloat(12 * reveal)
        // Fades in over the first sliver of the reveal: at rest it is a dot of
        // light, not a shrunken circle.
        let alpha: Double = min(1, reveal * 8)

        return Circle()
            // Lit from up and to the left rather than filled flat — a flat disc
            // with a vector-perfect edge reads as a status LED, which is the one
            // thing this must not be. The half-point of blur takes the edge off
            // so it sits in its own light.
            .fill(RadialGradient(colors: [Palette.brand, Palette.brandDeep],
                                 center: UnitPoint(x: 0.36, y: 0.30),
                                 startRadius: 0, endRadius: side * 0.95))
            .frame(width: side, height: side)
            .blur(radius: 0.6)
            .scaleEffect(scale)
            // Its own short bleed, so the edge is never a sticker on black.
            .shadow(color: Palette.brand.opacity(0.5), radius: glow)
            .opacity(alpha)
    }

    private func bloom(alpha: Double, scale: CGFloat, blur: CGFloat, offset: CGSize) -> some View {
        Circle()
            .fill(RadialGradient(colors: [Palette.brand.opacity(alpha), Palette.brand.opacity(0)],
                                 center: .center, startRadius: 0, endRadius: size * scale * 0.5))
            .frame(width: size * scale, height: size * scale)
            .blur(radius: blur)
            .offset(x: offset.width, y: offset.height)
    }

    /// Slow enough to read as breathing rather than pulsing — 2.6s out and back,
    /// six percent of travel. Reduce Motion holds it still.
    private func start() {
        guard !reduceMotion else { breath = 1; return }
        withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) {
            breath = 1.06
        }
    }
}

/// When each beat of the launch lands. Kept out of the view so the one promise
/// that matters — the splash is never what makes the app feel slow — is a thing
/// tests can hold us to.
enum SplashTimeline {
    /// A single point of green appears.
    static let point = 0.20
    /// It opens into her.
    static let form = 0.32
    static let formDuration = 0.40
    /// The light starts breathing.
    static let breathe = 0.72
    /// The name arrives.
    static let word = 0.80
    /// The status line, if there is real work to report.
    static let status = 0.95
    static let fade = 0.40

    /// Everything has landed by here.
    static var settled: Double { status + fade }
}
