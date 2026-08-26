import SwiftUI
#if os(macOS)
import AppKit
typealias PlatformColor = NSColor
#else
import UIKit
typealias PlatformColor = UIColor
#endif

// Structure, motion and the card. Colour lives in `DesignSystem.swift` and
// nowhere else — if you are about to write a hex value in this file, it belongs
// there instead.

/// sRGB components of a Color, read via the platform colour type, so the mixing
/// helpers below work on both platforms. Used by the hand-drawn icon glyphs.
func platformComponents(_ color: Color, fallback: PlatformColor) -> (r: Double, g: Double, b: Double, a: Double) {
    #if os(macOS)
    let c = NSColor(color).usingColorSpace(.sRGB) ?? fallback
    return (Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent), Double(c.alphaComponent))
    #else
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
    return (Double(r), Double(g), Double(b), Double(a))
    #endif
}

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

    /// Blend toward black by `t` (0…1).
    func mixedWithBlack(_ t: Double) -> Color {
        let c = platformComponents(self, fallback: .black)
        return Color(.sRGB, red: c.r * (1 - t), green: c.g * (1 - t), blue: c.b * (1 - t), opacity: c.a)
    }
    /// Blend toward white by `t`.
    func mixedWithWhite(_ t: Double) -> Color {
        let c = platformComponents(self, fallback: .white)
        return Color(.sRGB, red: c.r + (1 - c.r) * t, green: c.g + (1 - c.g) * t, blue: c.b + (1 - c.b) * t, opacity: c.a)
    }

    /// WCAG relative luminance — used to check that text on an accent fill is
    /// actually legible. Neon green and orange both fail with white on top.
    var wcagLuminance: Double {
        let c = platformComponents(self, fallback: .black)
        func channel(_ v: Double) -> Double {
            v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b)
    }

    func contrast(with other: Color) -> Double {
        let a = wcagLuminance, b = other.wcagLuminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}

/// Appearance preference. MyOS ships one palette, so a "theme" is only the
/// question of whether we follow the OS or pin light/dark.
struct AppTheme: Identifiable, Hashable {
    let id: String
    let name: String
    let symbol: String
    /// nil = follow the system Appearance.
    let scheme: ColorScheme?

    static let system = AppTheme(id: "system", name: "System", symbol: "circle.lefthalf.filled", scheme: nil)
    static let light  = AppTheme(id: "light",  name: "Light",  symbol: "sun.max", scheme: .light)
    static let dark   = AppTheme(id: "dark",   name: "Dark",   symbol: "moon",    scheme: .dark)

    static let all: [AppTheme] = [system, light, dark]
    /// Unknown ids (the retired "foldDark" / "midnight") migrate to System.
    static func by(id: String) -> AppTheme { all.first { $0.id == id } ?? system }

    var colorScheme: ColorScheme? { scheme }
}

/// Holds the appearance preference app-wide and persists it.
final class ThemeStore: ObservableObject {
    static let shared = ThemeStore()
    private static let key = "myos.theme"
    @Published private(set) var theme: AppTheme
    private init() { theme = AppTheme.by(id: UserDefaults.standard.string(forKey: Self.key) ?? "system") }
    func set(_ t: AppTheme) {
        guard t.id != theme.id else { return }
        theme = t
        UserDefaults.standard.set(t.id, forKey: Self.key)
    }
}

/// Vertical rhythm. Aliases onto the `Space` scale — one beat, everywhere.
enum Gap {
    /// Between a screen's top-level blocks.
    static let screen: CGFloat = Space.xl      // 20
    /// Between rows inside a card.
    static let row: CGFloat = Space.md         // 12
    static let tight: CGFloat = Space.sm       // 8
}

/// Three radii. Small for chips and controls, medium for inputs and rows, large
/// for cards and sheets.
enum Radius {
    static let xs: CGFloat = 12
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 24
}

// Motion tokens.
enum Motion {
    static let fast   = 0.10
    static let normal = 0.18
    static let slow   = 0.28
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
    // Stiff on purpose. These were the system spring presets for half a day and
    // the app read as "buggy and stuck" — a page still settling when your thumb
    // arrives feels broken, not lively.
    static let knFast     = Animation.easeOut(duration: Motion.fast)
    static let knNormal   = Animation.easeInOut(duration: Motion.normal)
    /// Screens arrive by fading, not by moving. See `RiseIn`.
    static let knEntrance = Animation.easeOut(duration: 0.14)
    /// No bounce. A control that overshoots reads as loose.
    static let knPop      = Animation.spring(response: 0.26, dampingFraction: 1.0)
    /// Dark ↔ light.
    static var knTheme: Animation {
        Motion.reduceMotion
            ? .easeInOut(duration: 0.2)
            : .spring(response: Motion.theme, dampingFraction: 1.0)
    }
}

// MARK: - Elevation

extension View {
    /// MyOS draws no shadows. Depth comes from the hairline between a near-black
    /// card and a black canvas — a glow on every card is a gaming dashboard, not
    /// an operating system. Kept as a no-op so call sites read unchanged.
    func knShadow(_ strong: Bool = false) -> some View { self }
}

// MARK: - Card

/// How a card separates itself from the canvas.
enum CardLook {
    /// The default, and the right answer for nearly everything: near-black
    /// surface, hairline border, white type.
    case plain
    /// A card *inside* a card, or a row that needs to lift off one.
    case elevated
    /// Carries a semantic accent as a rule down its leading edge. Rare — only
    /// where the content genuinely belongs to one meaning (activity, nutrition,
    /// events), never for decoration.
    case accent
    /// The whole card IS the accent — a solid block of colour with ink chosen
    /// to be legible on it. The loudest thing the design system can do, so at
    /// most one card on a screen may use it, and only when that card is the
    /// reason you opened the screen.
    case filled
}

/// The standard MyOS surface.
///
/// Built on SwiftUI's `GroupBox` so the content inside is grouped for VoiceOver
/// and the container behaves like the platform's own card. `MyOSCardStyle`
/// replaces the system chrome, because MyOS cards are black and the system's
/// are grey.
struct Card<Content: View>: View {
    var padding: CGFloat = Space.xl
    var radius: CGFloat = Radius.lg
    /// Overrides the ambient accent for this card only.
    var accent: Accent? = nil
    var look: CardLook = .plain
    @ViewBuilder var content: Content

    @Environment(\.cardAccent) private var ambient

    var body: some View {
        GroupBox { content }
            .groupBoxStyle(MyOSCardStyle(accent: accent ?? ambient, look: look,
                                         padding: padding, radius: radius))
    }
}

/// The MyOS card look, as a real `GroupBoxStyle`.
struct MyOSCardStyle: GroupBoxStyle {
    let accent: Accent
    let look: CardLook
    var padding: CGFloat = Space.xl
    var radius: CGFloat = Radius.lg

    func makeBody(configuration: Configuration) -> some View {
        configuration.content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(CardSkin(accent: accent, look: look, radius: radius))
    }
}

/// Paints a card. Separate from the style so `.cardSkin()` can give the same
/// treatment to things that are card-shaped but are not `Card` — tiles, tappable
/// rows, grid cells.
struct CardSkin: ViewModifier {
    var accent: Accent = .none
    var look: CardLook = .plain
    var radius: CGFloat = Radius.lg

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: radius, style: .continuous) }

    /// How a card is painted, per the chosen card style. `flat` is the original
    /// near-black surface; `filled` lifts it so a card reads as an object on the
    /// canvas rather than a region of it; `gradient` grades that fill. All three
    /// are the same two greys — this is a change of weight, not of colour, which
    /// is why it cannot collide with anything semantic.
    private func fill(_ base: Color, lifted: Color) -> AnyShapeStyle {
        switch Palette.appearance.cardStyle {
        case .flat:
            return AnyShapeStyle(base)
        case .filled:
            return AnyShapeStyle(lifted)
        case .gradient:
            return AnyShapeStyle(LinearGradient(colors: [lifted, base],
                                                startPoint: .top, endPoint: .bottom))
        }
    }

    func body(content: Content) -> some View {
        switch look {
        case .plain:
            content
                .background(fill(Palette.surface, lifted: Palette.surfaceElevated), in: shape)
                .overlay(shape.strokeBorder(Palette.border, lineWidth: 1))
        case .elevated:
            content
                .background(fill(Palette.surfaceElevated, lifted: Palette.surfaceElevated), in: shape)
                .overlay(shape.strokeBorder(Palette.border, lineWidth: 1))
        case .accent:
            content
                .background(fill(Palette.surface, lifted: Palette.surfaceElevated), in: shape)
                .overlay(shape.strokeBorder(Palette.border, lineWidth: 1))
                // A rule, not a fill. The colour marks what the card is about
                // without turning the card into the colour.
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(accent.tint)
                        .frame(width: 3)
                        .clipShape(shape)
                        .allowsHitTesting(false)
                }
        case .filled:
            content
                // No border: a solid block of colour does not also need an
                // outline to separate it from the canvas.
                .background(accent.tint, in: shape)
                // Everything inside inherits legible ink, so a filled card
                // never needs its children to know they are on colour.
                .foregroundStyle(accent.ink)
                .tint(accent.ink)
        }
    }
}

extension View {
    /// Card treatment for something that is not a `Card`.
    func cardSkin(_ look: CardLook = .plain, accent: Accent = .none, radius: CGFloat = Radius.lg) -> some View {
        modifier(CardSkin(accent: accent, look: look, radius: radius))
    }
}

// MARK: - Labels

/// The name of a screen.
struct ScreenTitle: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.largeTitle.bold())
            .foregroundStyle(Palette.text)
    }
}

/// A grouped-section header.
struct SectionTitle: View {
    let text: String
    var accent: Accent = .none
    var body: some View { SectionLabel(text: text, accent: accent) }
}

extension View {
    /// Fire a light tap when a button style transitions into the pressed state.
    func pressHaptic(_ pressed: Bool) -> some View {
        onChange(of: pressed) { _, now in if now { Haptics.tap() } }
    }
}

// Balanced pointing-hand cursor. No-op on iOS.
func cursor(_ inside: Bool) {
    #if os(macOS)
    if inside { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
    #endif
}

/// Full-width primary action. Green means action, and green is far too light to
/// carry white text — the label is black on purpose.
struct PrimaryButton: View {
    let title: String
    var loading = false
    var accent: Accent = .green
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.sm) {
                if loading { ProgressView().controlSize(.small).tint(accent.ink) }
                Text(title).fontWeight(.semibold)
            }
            .foregroundStyle(accent.ink)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(accent.tint)
        .disabled(loading)
    }
}

// MARK: - Text field styling

extension View {
    /// The MyOS input: a lifted surface, a hairline, and the accent only while
    /// focused. An input does not need a colour to exist.
    func knField(focused: Bool = false, radius: CGFloat = Radius.md) -> some View {
        self
            .padding(.horizontal, Space.md).padding(.vertical, 10)
            .background(Palette.surfaceElevated,
                        in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(focused ? Palette.action : Palette.border, lineWidth: focused ? 2 : 1)
            )
            .animation(.knFast, value: focused)
    }
}

// MARK: - Entrance

/// Entrance for a screen's blocks: a short fade, lightly staggered.
///
/// The `knEntrances` guard is the load-bearing part: `TodayPager` sets it false,
/// so turning a page never replays entrances. Keep that guard wherever blocks
/// are not genuinely arriving.
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
    /// matters: turning the page is not an entrance.
    var knEntrances: Bool {
        get { self[KnEntrancesKey.self] }
        set { self[KnEntrancesKey.self] = newValue }
    }
}

extension View {
    func knRise(_ index: Int = 0) -> some View { modifier(RiseIn(index: index)) }
}

/// Subtle hover feedback for tappable cards.
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

enum Fmt {
    /// Weight with at most one decimal (e.g. 72 or 72.5).
    ///
    /// Clamped because `Int(_: Double)` **traps** outside Int64 rather than
    /// saturating, and this runs on whatever is in the field right now — a
    /// weight field that commits on every keystroke, a height parsed with bare
    /// `Double(_:)` (which accepts "inf"), a number from sync, a number a model
    /// guessed. Nineteen digits was a hard crash on the very next render.
    static func trimKg(_ v: Double) -> String {
        guard v.isFinite else { return "0" }
        let r = (min(max(v, -1_000_000), 1_000_000) * 10).rounded() / 10
        return r == r.rounded() ? String(Int(r)) : String(format: "%.1f", r)
    }

    /// One-letter weekday for a `yyyy-MM-dd` key. Hand-rolled rather than
    /// localised: a strip of seven needs exactly one character each.
    static func weekdayInitial(_ iso: String) -> String {
        guard let date = CalMath.date(fromKey: String(iso.prefix(10))) else { return "" }
        let i = CalMath.cal.component(.weekday, from: date)   // Sunday = 1
        return ["S", "M", "T", "W", "T", "F", "S"][max(0, min(6, i - 1))]
    }

    /// Human day label from an ISO stamp → "Today" / "Yesterday" / "Aug 4".
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

    /// "7h 44m" / "44m" / "38s" — the app's one duration format.
    static func duration(_ seconds: Int) -> String {
        let s = max(0, seconds)
        let h = s / 3600, m = (s % 3600) / 60
        if h > 0 { return m > 0 ? "\(h)h \(m)m" : "\(h)h" }
        if m > 0 { return "\(m)m" }
        return "\(s)s"
    }

    /// Compact duration for tight rows: "7h 44m" → "7h44".
    static func shortDuration(_ seconds: Int) -> String {
        let s = max(0, seconds)
        let h = s / 3600, m = (s % 3600) / 60
        return h > 0 ? String(format: "%dh%02d", h, m) : "\(m)m"
    }
}
