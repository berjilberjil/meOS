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
        id: "foldDark", name: "Dark",
        bg: Color(hex: 0x000000), sidebar: Color(hex: 0x000000),
        surface: Color(hex: 0x151515), surface2: Color(hex: 0x242424), elevated: Color(hex: 0x1B1B1B),
        border: Color(hex: 0x242424), borderStrong: Color(hex: 0x333333), ring: Color(hex: 0x242424),
        text: Color(hex: 0xFFFFFF), muted: Color(hex: 0x9A9A9A), faint: Color(hex: 0x5E5E5E),
        brand: Color(hex: 0x1FD37A), brandDeep: Color(hex: 0x12A85E), green: Color(hex: 0x1FD37A))

    static let light = AppTheme(
        id: "light", name: "Light",
        bg: Color(hex: 0xF6F7F9), sidebar: Color(hex: 0xEFF1F4),
        surface: Color(hex: 0xFFFFFF), surface2: Color(hex: 0xEDEFF3), elevated: Color(hex: 0xFFFFFF),
        border: Color(hex: 0xE3E6EB), borderStrong: Color(hex: 0xCED3DB), ring: Color(hex: 0xE3E6EB),
        text: Color(hex: 0x0B0D12), muted: Color(hex: 0x5C6470), faint: Color(hex: 0x99A1AE),
        brand: Color(hex: 0x12B76A), brandDeep: Color(hex: 0x0E9257), green: Color(hex: 0x12B76A))

    static let all: [AppTheme] = [foldDark, light]
    static func by(id: String) -> AppTheme {
        if id == light.id { return light }
        return foldDark
    }

    /// Drives system chrome (status bar, sheets, keyboards). Light is the only
    /// light scheme; everything else — including a leftover Midnight id — is dark.
    var colorScheme: ColorScheme { id == AppTheme.light.id ? .light : .dark }
}

/// Holds the active theme app-wide and persists the choice. Views pick up a change
/// because the root re-renders (see AppState.setTheme / RootView).
final class ThemeStore: ObservableObject {
    static let shared = ThemeStore()
    private static let key = "myos.theme"
    @Published private(set) var theme: AppTheme
    private init() { theme = AppTheme.by(id: UserDefaults.standard.string(forKey: Self.key) ?? "foldDark") }
    func set(_ t: AppTheme) {
        guard t.id != theme.id else { return }
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
    static let rose   = Color(hex: 0xFF6B9A)
    static let teal   = Color(hex: 0x2DD4BF)
    static let gold   = Color(hex: 0xF5C451)
    static let coral  = Color(hex: 0xFF7A59)
}

/// Vertical rhythm. Screens differed by a few points each — 14 here, 16 there,
/// 18, 20, 22 — which is small enough to never look like a bug and big enough
/// that every tab switch re-spaces the page under you. One beat, everywhere.
enum Gap {
    /// Between a screen's top-level blocks.
    static let screen: CGFloat = 18
    /// Between rows inside a card.
    static let row: CGFloat = 12
    static let tight: CGFloat = 8
}

enum Radius {
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12   // chips / small controls
    static let md: CGFloat = 16   // inputs / small buttons / nav items
    static let lg: CGFloat = 20   // cards
    static let xl: CGFloat = 28   // dialogs / modals
}

// Motion tokens. Springs use Apple's designer pair (WWDC 2018): response +
// damping ratio. Default UI is critically damped (no bounce). Bounce is only
// for momentum-driven moves (tab pop, flick).
enum Motion {
    static let fast   = 0.10   // interactions (hover / press)
    static let normal = 0.18   // toggles / segmented
    static let slow   = 0.28
    /// Theme / chrome color settle — Apple "move" spring.
    static let theme  = 0.40

    static var reduceMotion: Bool {
        #if os(iOS)
        UIAccessibility.isReduceMotionEnabled
        #else
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        #endif
    }
}

extension Animation {
    static let knFast     = Animation.easeOut(duration: Motion.fast)
    static let knNormal   = Animation.easeInOut(duration: Motion.normal)
    // Screens arrive by fading, not by moving. See `RiseIn`.
    static let knEntrance = Animation.easeOut(duration: 0.14)
    // No bounce, anywhere. A control that overshoots reads as loose, and the
    // whole point of this design language is that nothing wobbles after it lands.
    static let knPop      = Animation.spring(response: 0.26, dampingFraction: 1.0)
    /// Dark ↔ light. Interrupted retargets from the live color (no snap).
    static var knTheme: Animation {
        Motion.reduceMotion
            ? .easeInOut(duration: 0.2)
            : .spring(response: Motion.theme, dampingFraction: 1.0)
    }
}

// MARK: - Elevation

extension View {
    /// Soft, layered shadow for floating surfaces. Toned down from the original
    /// 0.5/0.3 opacity + 26/14 radius, which read as too heavy.
    func knShadow(_ strong: Bool = false) -> some View {
        let light = ThemeStore.shared.theme.id == "light"
        return shadow(color: light ? .clear : .black.opacity(strong ? 0.4 : 0.25),
                      radius: light ? 0 : (strong ? 16 : 7),
                      x: 0, y: light ? 0 : (strong ? 8 : 3))
    }
}

// MARK: - Card

/// The standard MyOS surface: a filled card with a chunky 2px border and a soft
/// shadow — the Duolingo card look.
struct Card<Content: View>: View {
    var padding: CGFloat = 18
    var radius: CGFloat = Radius.lg
    @ObservedObject private var themeStore = ThemeStore.shared
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
            .animation(.knTheme, value: themeStore.theme.id)
    }
}

// MARK: - Labels

/// The name of a screen. Titles ran at both 24 and 28 depending on which screen
/// you were on — sometimes both inside one file — so this is the only size.
struct ScreenTitle: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 28, weight: .semibold))
            .foregroundStyle(Palette.text)
    }
}

struct SectionTitle: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .heavy, design: .rounded))
            .tracking(0.8)
            .foregroundStyle(Palette.muted)
    }
}

extension View {
    /// Fire a light tap when a button style transitions into the pressed state.
    func pressHaptic(_ pressed: Bool) -> some View {
        onChange(of: pressed) { _, now in if now { Haptics.tap() } }
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
                .pressHaptic(configuration.isPressed)
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
                .pressHaptic(configuration.isPressed)
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
                .pressHaptic(configuration.isPressed)
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
                .pressHaptic(configuration.isPressed)
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
                .pressHaptic(configuration.isPressed)
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
            .pressHaptic(configuration.isPressed)
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
    /// Share the row evenly (7 weekdays on iPhone). Default keeps hugging labels.
    var fillsWidth: Bool = false
    @Namespace private var ns
    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { opt in
                let on = selection == opt.value
                Text(opt.title)
                    .font(.system(size: fillsWidth ? 12 : 13, weight: .heavy, design: .rounded))
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .foregroundStyle(on ? Palette.text : Palette.muted)
                    .padding(.horizontal, fillsWidth ? 4 : 14).padding(.vertical, 7)
                    .frame(maxWidth: fillsWidth ? .infinity : nil)
                    .background {
                        if on {
                            Capsule().fill(Palette.surface2)
                                .matchedGeometryEffect(id: "seg", in: ns)
                        }
                    }
                    .contentShape(Capsule())
                    .onTapGesture {
                        Haptics.selection()
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
/// Entrance for a screen's blocks: one short fade, nothing else.
///
/// It used to slide each block up 14pt on a spring, staggered 45ms apart. Inside
/// a scroll view that is a layout that is still moving when your thumb arrives —
/// you scroll, the page is mid-cascade, and the content shifts under you. A card
/// that is already where it will end up cannot do that. `index` is kept so the
/// 60-odd call sites still read as an order, but nothing is staggered any more:
/// a staggered fade is the same wobble measured in opacity.
struct RiseIn: ViewModifier {
    var index: Int = 0
    @Environment(\.knEntrances) private var entrances
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .opacity(entrances ? (shown ? 1 : 0) : 1)
            .onAppear { if entrances { withAnimation(.knEntrance) { shown = true } } }
    }
}

private struct KnEntrancesKey: EnvironmentKey { static let defaultValue = true }

extension EnvironmentValues {
    /// False where blocks are not *arriving*. A paged day is the case that
    /// matters: turning the page is not an entrance, so fading nine cards up
    /// from zero every time you swipe reads as the page failing to draw.
    var knEntrances: Bool {
        get { self[KnEntrancesKey.self] }
        set { self[KnEntrancesKey.self] = newValue }
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
