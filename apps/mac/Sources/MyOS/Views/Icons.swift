import SwiftUI

// Cartoon nav icons — flat, chunky vector art in the Duolingo spirit, drawn with
// plain SwiftUI shapes so they stay crisp at any size and need no image assets.
// Each is a self-contained glyph sized to a square `size` box.

/// Routes a nav tab to its cartoon glyph.
struct NavGlyph: View {
    let tab: NavTab
    var size: CGFloat = 26
    var body: some View {
        Group {
            switch tab {
            case .today:   SunGlyph(s: size)
            case .events:  CalendarGlyph(s: size)
            case .finance: CoinGlyph(s: size)
            case .fitness: DumbbellGlyph(s: size)
            case .productivity: PlayGlyph(s: size)
            case .journal: BookGlyph(s: size)
            case .notes:   NoteGlyph(s: size)
            case .profile: AvatarGlyph(s: size)
            case .settings: GearGlyph(s: size)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Today · sun

struct SunGlyph: View {
    let s: CGFloat
    var body: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { i in
                Capsule()
                    .fill(Palette.flame)
                    .frame(width: s * 0.075, height: s * 0.19)
                    .offset(y: -s * 0.40)
                    .rotationEffect(.degrees(Double(i) * 45))
            }
            Circle()
                .fill(LinearGradient(colors: [Palette.amber, Palette.flame],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: s * 0.54, height: s * 0.54)
            Circle()
                .fill(.white.opacity(0.5))
                .frame(width: s * 0.14, height: s * 0.14)
                .offset(x: -s * 0.09, y: -s * 0.09)
        }
    }
}

// MARK: - Finance · coin

struct CoinGlyph: View {
    let s: CGFloat
    var body: some View {
        ZStack {
            Circle().fill(Palette.amber.mixedWithBlack(0.18))
                .frame(width: s * 0.84, height: s * 0.84)
            Circle().fill(Palette.amber)
                .frame(width: s * 0.68, height: s * 0.68)
            Text("₹")
                .font(.system(size: s * 0.4, weight: .heavy, design: .rounded))
                .foregroundStyle(Palette.amber.mixedWithBlack(0.32))
            Ellipse().fill(.white.opacity(0.55))
                .frame(width: s * 0.16, height: s * 0.1)
                .offset(x: -s * 0.14, y: -s * 0.18)
        }
    }
}

// MARK: - Fitness · dumbbell

struct DumbbellGlyph: View {
    let s: CGFloat
    var body: some View {
        ZStack {
            Capsule()
                .fill(Palette.muted)
                .frame(width: s * 0.5, height: s * 0.12)
            plate.offset(x: -s * 0.25)
            plate.offset(x: s * 0.25)
        }
    }
    private var plate: some View {
        RoundedRectangle(cornerRadius: s * 0.06, style: .continuous)
            .fill(Palette.blue)
            .frame(width: s * 0.17, height: s * 0.48)
            .overlay(alignment: .leading) {
                Capsule().fill(.white.opacity(0.3))
                    .frame(width: s * 0.04, height: s * 0.3)
                    .padding(.leading, s * 0.03)
            }
    }
}

// MARK: - Journal · book with bookmark

struct BookGlyph: View {
    let s: CGFloat
    var body: some View {
        ZStack {
            // pages peeking on the right
            RoundedRectangle(cornerRadius: s * 0.03, style: .continuous)
                .fill(.white.opacity(0.92))
                .frame(width: s * 0.1, height: s * 0.58)
                .offset(x: s * 0.2)
            // cover
            RoundedRectangle(cornerRadius: s * 0.1, style: .continuous)
                .fill(Palette.green)
                .frame(width: s * 0.56, height: s * 0.72)
                .offset(x: -s * 0.02)
            // spine shade
            RoundedRectangle(cornerRadius: s * 0.05, style: .continuous)
                .fill(Palette.green.mixedWithBlack(0.18))
                .frame(width: s * 0.09, height: s * 0.72)
                .offset(x: -s * 0.255)
            // bookmark ribbon
            Rectangle()
                .fill(Palette.flame)
                .frame(width: s * 0.08, height: s * 0.24)
                .offset(x: s * 0.12, y: -s * 0.30)
        }
    }
}

// MARK: - Notes · sticky note

struct NoteGlyph: View {
    let s: CGFloat
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: s * 0.12, style: .continuous)
                .fill(Palette.amber)
                .frame(width: s * 0.62, height: s * 0.62)
            VStack(alignment: .leading, spacing: s * 0.09) {
                line(0.34); line(0.34); line(0.22)
            }
        }
    }
    private func line(_ w: CGFloat) -> some View {
        Capsule().fill(Palette.amber.mixedWithBlack(0.3))
            .frame(width: s * w, height: s * 0.055)
    }
}

// MARK: - Settings · gear

struct GearGlyph: View {
    let s: CGFloat
    var body: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { i in
                RoundedRectangle(cornerRadius: s * 0.03, style: .continuous)
                    .fill(Palette.muted)
                    .frame(width: s * 0.14, height: s * 0.24)
                    .offset(y: -s * 0.3)
                    .rotationEffect(.degrees(Double(i) * 45))
            }
            Circle().fill(Palette.muted)
                .frame(width: s * 0.56, height: s * 0.56)
            Circle().fill(Palette.sidebar)
                .frame(width: s * 0.24, height: s * 0.24)
        }
    }
}

// MARK: - Events · calendar

struct CalendarGlyph: View {
    let s: CGFloat
    var body: some View {
        ZStack {
            // red frame — the header strip shows above/around the white body
            RoundedRectangle(cornerRadius: s * 0.15, style: .continuous)
                .fill(Palette.red)
                .frame(width: s * 0.74, height: s * 0.7)
                .offset(y: s * 0.04)
            // white page
            RoundedRectangle(cornerRadius: s * 0.09, style: .continuous)
                .fill(.white)
                .frame(width: s * 0.6, height: s * 0.44)
                .offset(y: s * 0.12)
            // binding rings poking above the top
            Capsule().fill(Palette.red.mixedWithBlack(0.25))
                .frame(width: s * 0.07, height: s * 0.18).offset(x: -s * 0.17, y: -s * 0.32)
            Capsule().fill(Palette.red.mixedWithBlack(0.25))
                .frame(width: s * 0.07, height: s * 0.18).offset(x: s * 0.17, y: -s * 0.32)
            // the highlighted day
            RoundedRectangle(cornerRadius: s * 0.03, style: .continuous)
                .fill(Palette.red)
                .frame(width: s * 0.15, height: s * 0.15).offset(y: s * 0.12)
        }
    }
}

// MARK: - Productivity · play screen

struct PlayGlyph: View {
    let s: CGFloat
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: s * 0.2, style: .continuous)
                .fill(LinearGradient(colors: [Palette.purple, Palette.purple.mixedWithBlack(0.18)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: s * 0.82, height: s * 0.6)
            PlayTriangle()
                .fill(.white)
                .frame(width: s * 0.22, height: s * 0.26)
                .offset(x: s * 0.03)
        }
    }
}

/// A right-pointing play triangle.
private struct PlayTriangle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Profile · avatar

struct AvatarGlyph: View {
    let s: CGFloat
    var body: some View {
        ZStack {
            Circle().fill(Palette.blue)
                .frame(width: s * 0.86, height: s * 0.86)
            ZStack {
                Circle().fill(.white)
                    .frame(width: s * 0.24, height: s * 0.24)
                    .offset(y: -s * 0.07)
                Ellipse().fill(.white)
                    .frame(width: s * 0.52, height: s * 0.4)
                    .offset(y: s * 0.32)
            }
            .frame(width: s * 0.86, height: s * 0.86)
            .clipShape(Circle())
        }
    }
}
