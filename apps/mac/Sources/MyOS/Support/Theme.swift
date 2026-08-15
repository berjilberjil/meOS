import SwiftUI
#if os(macOS)
import AppKit
typealias PlatformColor = NSColor
#else
import UIKit
typealias PlatformColor = UIColor
#endif

/// sRGB components of a Color, read via the platform color type (NSColor on
/// macOS, UIColor on iOS) so `mixedWithBlack`/`mixedWithWhite` work everywhere.
private func platformComponents(_ color: Color, fallback: PlatformColor) -> (r: Double, g: Double, b: Double, a: Double) {
    #if os(macOS)
    let c = NSColor(color).usingColorSpace(.sRGB) ?? fallback
    return (Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent), Double(c.alphaComponent))
    #else
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
    return (Double(r), Double(g), Double(b), Double(a))
    #endif
}

// MyOS design language — Duolingo-inspired. Dark teal-navy canvas, bright candy
// feature colors, chunky rounded cards with a visible 2px border, SF Rounded
// (Feather-substitute) type, and the signature 3D "press-down" button: a flat
// bright face sitting on a solid darker edge that sinks on tap. Playful, tactile,
// gamified — a second brain that feels like a game.
extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }

    /// Blend toward black by `t` (0…1) — used to derive a button's darker 3D edge
    /// from its face color, so any tint gets a matching edge for free.
    func mixedWithBlack(_ t: Double) -> Color {
        let c = platformComponents(self, fallback: .black)
        return Color(.sRGB, red: c.r * (1 - t), green: c.g * (1 - t), blue: c.b * (1 - t), opacity: c.a)
    }
    /// Blend toward white by `t` — hover highlight.
    func mixedWithWhite(_ t: Double) -> Color {
        let c = platformComponents(self, fallback: .white)
        return Color(.sRGB, red: c.r + (1 - c.r) * t, green: c.g + (1 - c.g) * t, blue: c.b + (1 - c.b) * t, opacity: c.a)
    }
}

/// A named colour scheme. The chrome (canvas / surfaces / text / accent) varies per
/// theme; the semantic feature colours (red/blue/amber/…) are shared across themes.
struct AppTheme: Identifiable, Hashable {
    let id: String
    let name: String
    let bg, sidebar, surface, surface2, elevated: Color
    let border, borderStrong, ring: Color
    let text, muted, faint: Color
    let brand, brandDeep, green: Color

    static let foldDark = AppTheme(
        id: "foldDark", name: "Fold Dark",
        bg: Color(hex: 0x000000), sidebar: Color(hex: 0x000000),
        surface: Color(hex: 0x151515), surface2: Color(hex: 0x242424), elevated: Color(hex: 0x1B1B1B),
        border: Color(hex: 0x242424), borderStrong: Color(hex: 0x333333), ring: Color(hex: 0x242424),
        text: Color(hex: 0xFFFFFF), muted: Color(hex: 0x9A9A9A), faint: Color(hex: 0x5E5E5E),
        brand: Color(hex: 0x1FD37A), brandDeep: Color(hex: 0x12A85E), green: Color(hex: 0x1FD37A))

    static let midnight = AppTheme(
        id: "midnight", name: "Midnight",
        bg: Color(hex: 0x0B0F1A), sidebar: Color(hex: 0x080B14),
        surface: Color(hex: 0x141A28), surface2: Color(hex: 0x1F2739), elevated: Color(hex: 0x18202F),
        border: Color(hex: 0x232C40), borderStrong: Color(hex: 0x33405B), ring: Color(hex: 0x232C40),
        text: Color(hex: 0xF3F5FA), muted: Color(hex: 0x93A0B8), faint: Color(hex: 0x5A6784),
        brand: Color(hex: 0x6E8BFF), brandDeep: Color(hex: 0x4C63D6), green: Color(hex: 0x35D07A))

    static let light = AppTheme(
        id: "light", name: "Light",
        bg: Color(hex: 0xF6F7F9), sidebar: Color(hex: 0xEFF1F4),
        surface: Color(hex: 0xFFFFFF), surface2: Color(hex: 0xEDEFF3), elevated: Color(hex: 0xFFFFFF),
        border: Color(hex: 0xE3E6EB), borderStrong: Color(hex: 0xCED3DB), ring: Color(hex: 0xE3E6EB),
        text: Color(hex: 0x0B0D12), muted: Color(hex: 0x5C6470), faint: Color(hex: 0x99A1AE),
        brand: Color(hex: 0x12B76A), brandDeep: Color(hex: 0x0E9257), green: Color(hex: 0x12B76A))

    static let all: [AppTheme] = [foldDark, midnight, light]
    static func by(id: String) -> AppTheme { all.first { $0.id == id } ?? foldDark }
}

/// Holds the active theme app-wide and persists the choice. Views pick up a change
/// because the root re-renders (see AppState.setTheme / RootView).
final class ThemeStore: ObservableObject {
    static let shared = ThemeStore()
    private static let key = "myos.theme"
    @Published private(set) var theme: AppTheme
    private init() { theme = AppTheme.by(id: UserDefaults.standard.string(forKey: Self.key) ?? "foldDark") }
    func set(_ t: AppTheme) {
        theme = t
        UserDefaults.standard.set(t.id, forKey: Self.key)
    }
}

enum Palette {
    private static var t: AppTheme { ThemeStore.shared.theme }
    // Chrome — varies per theme.
    static var bg: Color          { t.bg }
    static var sidebar: Color     { t.sidebar }
    static var surface: Color     { t.surface }
    static var surface2: Color    { t.surface2 }
    static var elevated: Color    { t.elevated }
    static var border: Color      { t.border }
    static var borderStrong: Color { t.borderStrong }
    static var ring: Color        { t.ring }
    static var text: Color        { t.text }
    static var muted: Color       { t.muted }
    static var faint: Color       { t.faint }
    static var brand: Color       { t.brand }
    static var brandDeep: Color   { t.brandDeep }
    static var green: Color       { t.green }
    // Semantic feature colours — shared across themes.
    static let red    = Color(hex: 0xFF5A5F)
    static let blue   = Color(hex: 0x4AA8FF)
    static let amber  = Color(hex: 0xFFC24B)
    static let purple = Color(hex: 0xB98CFF)
    static let flame  = Color(hex: 0xFF8A3D)
    static let ice    = Color(hex: 0x7FD1FF)
}

enum Radius {
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12   // chips / small controls
    static let md: CGFloat = 16   // inputs / small buttons / nav items
    static let lg: CGFloat = 20   // cards
    static let xl: CGFloat = 28   // dialogs / modals
}

// Motion tokens.
enum Motion {
    static let fast   = 0.10   // interactions (hover / press)
    static let normal = 0.18   // toggles / segmented
    static let slow   = 0.28
}

extension Animation {
    static let knFast     = Animation.easeOut(duration: Motion.fast)
    static let knNormal   = Animation.easeInOut(duration: Motion.normal)
    // A calm, barely-there settle — Fold's motion is smooth, not bouncy.
    static let knEntrance = Animation.spring(response: 0.5, dampingFraction: 0.9)
    static let knPop      = Animation.spring(response: 0.34, dampingFraction: 0.88)
}

// MARK: - Elevation

extension View {
    /// Soft, layered shadow for floating surfaces. Toned down from the original
    /// 0.5/0.3 opacity + 26/14 radius, which read as too heavy.
    func knShadow(_ strong: Bool = false) -> some View {
        shadow(color: .black.opacity(strong ? 0.4 : 0.25),
               radius: strong ? 16 : 7,
               x: 0, y: strong ? 8 : 3)
    }
}

// MARK: - Card

/// The standard MyOS surface: a filled card with a chunky 2px border and a soft
/// shadow — the Duolingo card look.
struct Card<Content: View>: View {
    var padding: CGFloat = 18
    var radius: CGFloat = Radius.lg
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: 1)
            )
            .knShadow()
    }
}

// MARK: - Labels

struct SectionTitle: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .heavy, design: .rounded))
            .tracking(0.8)
            .foregroundStyle(Palette.muted)
    }
}

// A compact KPI tile for dashboards.
struct StatTile: View {
    let label: String
    let value: String
    var sub: String? = nil
    var accent: Color = Palette.text
    var body: some View {
        Card(padding: 15) {
            VStack(alignment: .leading, spacing: 7) {
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .heavy, design: .rounded)).tracking(0.8)
                    .foregroundStyle(Palette.faint)
                Text(value)
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(accent)
                    .lineLimit(1).minimumScaleFactor(0.6)
                if let sub {
                    Text(sub).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.muted)
                        .lineLimit(1)
                }
            }
        }
    }
}

// MARK: - The 3D button (Duolingo signature)

/// A flat bright face sitting on a solid darker edge. The face reveals `depth`
/// px of the edge at the bottom; on press it sinks down to cover the edge — the
/// classic Duolingo "press-down". Layout height is constant (a top/bottom pad
/// swap), so nothing jumps.
private struct Duo3DBackground: View {
    var face: Color
    var edge: Color
    var radius: CGFloat
    var pressed: Bool
    var depth: CGFloat
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous).fill(edge)
            RoundedRectangle(cornerRadius: radius, style: .continuous).fill(face)
                .padding(.bottom, pressed ? 0 : depth)
        }
    }
}

/// Primary pill — green 3D button, uppercase heavy label. The hero control.
struct KPrimaryButtonStyle: ButtonStyle {
    var tint: Color = Palette.brand
    var fullWidth = false
    func makeBody(configuration: Configuration) -> some View {
        Inner(configuration: configuration, tint: tint, fullWidth: fullWidth)
    }
    private struct Inner: View {
        let configuration: ButtonStyleConfiguration
        let tint: Color
        let fullWidth: Bool
        @State private var hover = false
        var body: some View {
            let pressed = configuration.isPressed
            let face = hover ? tint.mixedWithWhite(0.10) : tint
            configuration.label
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .tracking(0.3)
                .textCase(.uppercase)
                .foregroundStyle(Palette.bg)
                .padding(.horizontal, 20)
                .padding(.vertical, 13)
                .frame(maxWidth: fullWidth ? .infinity : nil)
                .background(face, in: Capsule())
                .contentShape(Capsule())
                .scaleEffect(pressed ? 0.97 : 1)
                .opacity(pressed ? 0.9 : 1)
                .animation(.knFast, value: pressed)
                .animation(.knFast, value: hover)
                .onHover { h in hover = h; cursor(h) }
        }
    }
}

/// Secondary — neutral 3D button (surface face, darker edge). White text.
struct KSecondaryButtonStyle: ButtonStyle {
    var fullWidth = false
    func makeBody(configuration: Configuration) -> some View {
        Inner(configuration: configuration, fullWidth: fullWidth)
    }
    private struct Inner: View {
        let configuration: ButtonStyleConfiguration
        let fullWidth: Bool
        @State private var hover = false
        var body: some View {
            let pressed = configuration.isPressed
            let face = hover ? Palette.surface2.mixedWithWhite(0.06) : Palette.surface2
            configuration.label
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.text)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .frame(maxWidth: fullWidth ? .infinity : nil)
                .background(face, in: Capsule())
                .overlay(Capsule().strokeBorder(Palette.border, lineWidth: 1))
                .contentShape(Capsule())
                .scaleEffect(pressed ? 0.97 : 1)
                .animation(.knFast, value: pressed)
                .animation(.knFast, value: hover)
                .onHover { h in hover = h; cursor(h) }
        }
    }
}

/// Ghost button — transparent, hover reveals a soft surface. For toolbar-ish actions.
struct KGhostButtonStyle: ButtonStyle {
    var color: Color = Palette.muted
    func makeBody(configuration: Configuration) -> some View {
        Inner(configuration: configuration, color: color)
    }
    private struct Inner: View {
        let configuration: ButtonStyleConfiguration
        let color: Color
        @State private var hover = false
        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(hover ? Palette.text : color)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(hover ? Palette.surface2.opacity(0.8) : .clear,
                            in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                .scaleEffect(configuration.isPressed ? 0.96 : 1)
                .animation(.knFast, value: configuration.isPressed)
                .animation(.knFast, value: hover)
                .onHover { h in hover = h; cursor(h) }
        }
    }
}

/// Icon-only button — hover reveals a soft round backing. For xmark / trash / pin.
struct KIconButtonStyle: ButtonStyle {
    var size: CGFloat = 28
    var color: Color = Palette.muted
    func makeBody(configuration: Configuration) -> some View {
        Inner(configuration: configuration, size: size, color: color)
    }
    private struct Inner: View {
        let configuration: ButtonStyleConfiguration
        let size: CGFloat
        let color: Color
        @State private var hover = false
        var body: some View {
            configuration.label
                .foregroundStyle(hover ? Palette.text : color)
                .frame(width: size, height: size)
                .background(hover ? Palette.surface2 : .clear, in: Circle())
                .contentShape(Circle())
                .scaleEffect(configuration.isPressed ? 0.9 : 1)
                .animation(.knFast, value: configuration.isPressed)
                .animation(.knFast, value: hover)
                .onHover { h in hover = h; cursor(h) }
        }
    }
}

/// Tinted 3D chip — quick actions like "Pay ₹5k" / "+ ₹2k". A small press-down
/// button that keeps its color coding (amber pay, blue fund, …).
struct KSoftButtonStyle: ButtonStyle {
    var tint: Color
    func makeBody(configuration: Configuration) -> some View {
        Inner(configuration: configuration, tint: tint)
    }
    private struct Inner: View {
        let configuration: ButtonStyleConfiguration
        let tint: Color
        @State private var hover = false
        var body: some View {
            let pressed = configuration.isPressed
            let base = hover ? tint.opacity(0.26) : tint.opacity(0.16)
            configuration.label
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(base, in: Capsule())
                .contentShape(Capsule())
                .scaleEffect(pressed ? 0.96 : 1)
                .animation(.knFast, value: pressed)
                .animation(.knFast, value: hover)
                .onHover { h in hover = h; cursor(h) }
        }
    }
}

// Balanced pointing-hand cursor (uses .set(), so no push/pop imbalance on disappear).
// No-op on iOS — there's no pointer to change.
func cursor(_ inside: Bool) {
    #if os(macOS)
    if inside { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
    #endif
}

/// Adds only tactile press-scale — for buttons that carry their own visual state
/// (nav items, cards) but still want the press feedback.
struct KPressStyle: ButtonStyle {
    var scale: CGFloat = 0.97
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.knFast, value: configuration.isPressed)
    }
}

/// Full-width primary action used by forms (login, etc.).
struct PrimaryButton: View {
    let title: String
    var loading = false
    var tint: Color = Palette.brand
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if loading { ProgressView().controlSize(.small).tint(.white) }
                Text(title)
            }
        }
        .buttonStyle(KPrimaryButtonStyle(tint: tint, fullWidth: true))
        .disabled(loading)
    }
}

// MARK: - Meter

/// A chunky progress bar (gold-loan / emergency fund), animating to its fraction.
struct MeterBar: View {
    var fraction: Double            // 0...1
    var tint: Color = Palette.green
    var height: CGFloat = 14
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.surface2)
                Capsule()
                    .fill(tint)
                    .overlay(alignment: .top) {
                        // Duolingo's meters have a lighter top sheen.
                        Capsule().fill(.white.opacity(0.25))
                            .frame(height: height * 0.34)
                            .padding(.horizontal, height * 0.28)
                            .padding(.top, height * 0.18)
                    }
                    .frame(width: max(fraction > 0 ? height : 0, min(1, fraction) * geo.size.width))
                    .animation(.knEntrance, value: fraction)
            }
        }
        .frame(height: height)
    }
}

// MARK: - Segmented control

struct Segmented<T: Hashable>: View {
    let options: [(value: T, title: String)]
    @Binding var selection: T
    @Namespace private var ns
    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { opt in
                let on = selection == opt.value
                Text(opt.title)
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .foregroundStyle(on ? Palette.text : Palette.muted)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background {
                        if on {
                            Capsule().fill(Palette.surface2)
                                .matchedGeometryEffect(id: "seg", in: ns)
                        }
                    }
                    .contentShape(Capsule())
                    .onTapGesture {
                        withAnimation(.knNormal) { selection = opt.value }
                    }
            }
        }
        .padding(3)
        .background(Palette.bg, in: Capsule())
        .overlay(Capsule().strokeBorder(Palette.border, lineWidth: 2))
    }
}

// MARK: - Text field styling

extension View {
    /// The MyOS input look: filled, rounded, a 2px border that glows the accent on focus.
    func knField(focused: Bool = false, radius: CGFloat = Radius.md) -> some View {
        self
            .padding(.horizontal, 13).padding(.vertical, 10)
            .background(Palette.bg,
                        in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(focused ? Palette.brand : Palette.border, lineWidth: 2)
            )
            .animation(.knFast, value: focused)
    }
}

// MARK: - Entrance

/// Staggered spring rise-in on appear — a bouncy, game-like page load.
struct RiseIn: ViewModifier {
    var index: Int = 0
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 14)
            .onAppear {
                withAnimation(.knEntrance.delay(Double(index) * 0.045)) { shown = true }
            }
    }
}

extension View {
    func knRise(_ index: Int = 0) -> some View { modifier(RiseIn(index: index)) }
}

/// Subtle hover feedback for tappable cards — a barely-there lift + brighten.
struct HoverLift: ViewModifier {
    @State private var hover = false
    func body(content: Content) -> some View {
        content
            .scaleEffect(hover ? 1.008 : 1)
            .brightness(hover ? 0.04 : 0)
            .animation(.knFast, value: hover)
            .onHover { h in hover = h; cursor(h) }
    }
}

extension View {
    func knHoverLift() -> some View { modifier(HoverLift()) }
}

// MARK: - Formatting

// Number formatting.
enum Fmt {
    /// Weight with at most one decimal (e.g. 72 or 72.5).
    static func trimKg(_ v: Double) -> String {
        let r = (v * 10).rounded() / 10
        return r == r.rounded() ? String(Int(r)) : String(format: "%.1f", r)
    }

    /// Human day label from an ISO stamp ("2026-08-04" or "2026-08-04T13:22:10").
    /// → "Today" / "Yesterday" / "Aug 4" / "Aug 4, 2025".
    static func day(_ iso: String) -> String {
        let datePart = String(iso.prefix(10))
        let inFmt = DateFormatter()
        inFmt.calendar = Calendar(identifier: .gregorian)
        inFmt.locale = Locale(identifier: "en_US_POSIX")
        inFmt.dateFormat = "yyyy-MM-dd"
        guard let date = inFmt.date(from: datePart) else { return datePart }

        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }

        let out = DateFormatter()
        out.locale = Locale(identifier: "en_US")
        out.dateFormat = cal.isDate(date, equalTo: Date(), toGranularity: .year) ? "MMM d" : "MMM d, yyyy"
        return out.string(from: date)
    }
}
