import SwiftUI

/// Launch / lock canvas — a falling drop, a ripple, Catherine. No lock glyph,
/// no “MyOS is locked”. Face ID still runs underneath.
struct SplashView: View {
    var failed = false
    var retryTitle: String = "Try again"
    var onRetry: (() -> Void)? = nil

    @State private var dropY: CGFloat = -56
    @State private var dropOpacity = 0.0
    @State private var ripple: CGFloat = 0.4
    @State private var rippleOpacity = 0.55
    @State private var word = 0.0

    var body: some View {
        ZStack {
            Palette.bg.ignoresSafeArea()
            VStack(spacing: 32) {
                ZStack {
                    Circle()
                        .stroke(Palette.brand.opacity(rippleOpacity), lineWidth: 1.5)
                        .frame(width: 70 * ripple, height: 70 * ripple)
                    DropShape()
                        .fill(Palette.brand)
                        .frame(width: 28, height: 40)
                        .offset(y: dropY)
                        .opacity(dropOpacity)
                }
                .frame(width: 160, height: 140)

                VStack(spacing: 6) {
                    Text("Catherine")
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .foregroundStyle(Palette.text)
                    Text(failed ? "Face not recognised" : " ")
                        .font(.system(size: 13)).foregroundStyle(Palette.faint)
                        .opacity(failed ? 1 : 0)
                }
                .opacity(word)

                if failed {
                    Button(retryTitle, action: { onRetry?() })
                        .buttonStyle(KPrimaryButtonStyle())
                }
            }
        }
        .onAppear { play() }
    }

    private func play() {
        #if os(macOS)
        SoundPlayer.drop()   // on iOS the open/close sounds come from the scene phase
        #endif
        withAnimation(.spring(response: 0.52, dampingFraction: 0.78)) {
            dropY = 8
            dropOpacity = 1
        }
        withAnimation(.easeOut(duration: 0.9).delay(0.22)) {
            ripple = 2.6
            rippleOpacity = 0
        }
        withAnimation(.easeOut(duration: 0.45).delay(0.28)) { word = 1 }
    }
}

/// A simple teardrop — the mark on splash.
private struct DropShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        p.move(to: CGPoint(x: w / 2, y: 0))
        p.addQuadCurve(to: CGPoint(x: w, y: h * 0.62),
                       control: CGPoint(x: w * 0.92, y: h * 0.28))
        p.addQuadCurve(to: CGPoint(x: 0, y: h * 0.62),
                       control: CGPoint(x: w / 2, y: h * 1.12))
        p.addQuadCurve(to: CGPoint(x: w / 2, y: 0),
                       control: CGPoint(x: w * 0.08, y: h * 0.28))
        p.closeSubpath()
        return p
    }
}
