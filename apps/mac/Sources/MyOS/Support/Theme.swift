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

// MyOS design language — the system's. Chrome, type, motion and controls all come
// from AppKit/UIKit rather than from values typed in here, which is what makes the
// app track Light/Dark, Increase Contrast, Dynamic Type and vibrancy for free.
// Converted 2026-08-24 at Berjil's explicit request (see feat/native-ui): the
// Fold black + green skin and the earlier Duolingo look are both gone. The green
// survives only as the app tint. Do not reintroduce hardcoded hex chrome.
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

/// Appearance preference. MyOS no longer ships colour values, so a "theme" is
/// only the question of whether we follow the OS or pin light/dark.
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

    /// Drives `.preferredColorScheme`. nil hands the decision back to the OS.
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

/// Every colour in MyOS. Chrome forwards to the system semantic colours; macOS
/// and iOS spell those differently, so the platform split lives here and nowhere
/// else in the app.
enum Palette {
    /// The one colour MyOS still owns. Applied as the app `.tint` so it lands on
    /// controls the way an accent colour is meant to.
    static let accent = Color(hex: 0x56BB06)

    // Chrome. These were the system greys until 2026-08-25; Berjil's reading of
    // that was "no more grey shit", so MyOS owns them again — as ink-blue
    // neutrals, and as *dynamic* colours so Light/Dark still switches. Text
    // colours below stay system semantic on purpose: a bold card flips the
    // environment's colorScheme to dark, and semantic labels are what turn
    // white for free when it does.
    static let bg           = Color.dynamic(light: 0xF3F6FD, dark: 0x0B0F17)
    static let sidebar      = Color.dynamic(light: 0xEAEFFA, dark: 0x080B12)
    static let surface      = Color.dynamic(light: 0xFFFFFF, dark: 0x151B28)
    static let surface2     = Color.dynamic(light: 0xE9EFFA, dark: 0x1E2636)
    static let elevated     = Color.dynamic(light: 0xFFFFFF, dark: 0x1A2130)
    static let border       = Color.dynamic(light: 0xDBE3F3, dark: 0x2A3345)
    static let borderStrong = Color.dynamic(light: 0xC1CCE3, dark: 0x3A4459)

    #if os(macOS)
    static var text: Color         { Color(nsColor: .labelColor) }
    static var muted: Color        { Color(nsColor: .secondaryLabelColor) }
    static var faint: Color        { Color(nsColor: .tertiaryLabelColor) }
    #else
    static var text: Color         { Color(uiColor: .label) }
    static var muted: Color        { Color(uiColor: .secondaryLabel) }
    static var faint: Color        { Color(uiColor: .tertiaryLabel) }
    #endif

    static var ring: Color         { accent }
    static var brand: Color        { accent }
    static var brandDeep: Color    { accent }
    static var green: Color        { accent }

    // Feature colours are the hue cores, so a chart, a chip and a card that all
    // mean "workout" are the same blue rather than three neighbouring blues.
    static var red    : Color { Hue.red.core }
    static var blue   : Color { Hue.blue.core }
    static var amber  : Color { Hue.amber.core }
    static var purple : Color { Hue.purple.core }
    static var flame  : Color { Hue.orange.core }
    static var ice    : Color { Hue.cyan.core }
    static var rose   : Color { Hue.pink.core }
    static var teal   : Color { Hue.teal.core }
    static var gold   : Color { Hue.amber.core }
    static var coral  : Color { Hue.orange.core }
    static var indigo : Color { Hue.indigo.core }
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
    // Stiff again, 2026-08-24. These were switched to the system spring presets
    // earlier the same day; the app then read as "buggy and stuck", which is the
    // same complaint that produced the stiff rule in the first place. A page
    // that is still settling when your thumb arrives feels broken, not lively.
    static let knFast     = Animation.easeOut(duration: Motion.fast)
    static let knNormal   = Animation.easeInOut(duration: Motion.normal)
    /// Screens arrive by fading, not by moving. See `RiseIn`.
    static let knEntrance = Animation.easeOut(duration: 0.14)
    /// No bounce. A control that overshoots reads as loose.
    static let knPop      = Animation.spring(response: 0.26, dampingFraction: 1.0)
    /// Dark ↔ light. Interrupted retargets from the live colour (no snap).
    static var knTheme: Animation {
        Motion.reduceMotion
            ? .easeInOut(duration: 0.2)
            : .spring(response: Motion.theme, dampingFraction: 1.0)
    }
}


// MARK: - Elevation

extension View {
    /// Native surfaces carry no app-drawn shadow: grouped content sits flat on
    /// the grouped background, and floating chrome takes its depth from a
    /// material. Kept as a no-op so the call sites read unchanged.
    func knShadow(_ strong: Bool = false) -> some View { self }
}

// MARK: - Card

/// How a card is filled.
enum CardLook {
    /// Hero. Saturated gradient, white text, a coloured shadow under it. For the
    /// one or two cards on a screen that carry the answer.
    case bold
    /// The default. The screen's hue, washed out, with a hairline of the hue.
    case tinted
    /// Plain surface. Left for places where colour would fight the content —
    /// long-form text, photo grids, editors.
    case plain
}

/// The standard MyOS surface.
///
/// Built on SwiftUI's own `GroupBox` rather than a bare `RoundedRectangle`: a
/// group box *is* the platform's card, so the content inside is grouped for
/// VoiceOver and the container behaves like one everywhere it is nested. The
/// look is supplied by `MyOSCardStyle`, which replaces the system chrome
/// wholesale — MyOS cards are coloured, and the system's are not.
///
/// A card with no `hue` takes the ambient `\.cardHue`, so a screen colours its
/// whole stack with one modifier.
struct Card<Content: View>: View {
    var padding: CGFloat = 18
    var radius: CGFloat = Radius.lg
    /// Overrides the ambient hue for this card only.
    var hue: Hue? = nil
    /// nil = take the ambient `\.cardLook`.
    var look: CardLook? = nil
    @ViewBuilder var content: Content

    @Environment(\.cardHue) private var ambientHue
    @Environment(\.cardLook) private var ambientLook

    var body: some View {
        GroupBox { content }
            .groupBoxStyle(MyOSCardStyle(hue: hue ?? ambientHue, look: look ?? ambientLook,
                                         padding: padding, radius: radius))
    }
}

/// The MyOS card look, as a real `GroupBoxStyle`.
struct MyOSCardStyle: GroupBoxStyle {
    let hue: Hue
    let look: CardLook
    var padding: CGFloat = 18
    var radius: CGFloat = Radius.lg

    func makeBody(configuration: Configuration) -> some View {
        configuration.content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(CardSkin(hue: hue, look: look, radius: radius))
    }
}

/// Paints a card. Separated from the style so `.cardSkin()` can give the same
/// treatment to things that are card-shaped but are not `Card` — tiles, tappable
/// rows, the meal grid.
struct CardSkin: ViewModifier {
    let hue: Hue
    let look: CardLook
    var radius: CGFloat = Radius.lg

    /// A washed card *inside* a bold one cannot use its own fill — that is the
    /// hue painted on the hue. It becomes translucent white instead, the way a
    /// system material would.
    @Environment(\.onBoldCard) private var onBold

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: radius, style: .continuous) }

    func body(content: Content) -> some View {
        switch look {
        case .bold:
            // Flipping the environment to dark is what makes every `Palette.text`
            // and `Palette.muted` *inside* the card resolve white — the reason a
            // hero card needed no edits to the ~40 labels it contains.
            content
                .environment(\.colorScheme, .dark)
                .environment(\.onBoldCard, true)
                .foregroundStyle(.white)
                .background(hue.boldGradient, in: shape)
                .overlay(shape.strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                .shadow(color: hue.core.opacity(0.32), radius: 16, x: 0, y: 8)
        case .tinted:
            content
                .background(onBold ? AnyShapeStyle(Color.white.opacity(0.15)) : AnyShapeStyle(hue.fill), in: shape)
                .overlay(shape.strokeBorder(onBold ? AnyShapeStyle(Color.white.opacity(0.28))
                                                   : AnyShapeStyle(hue.line), lineWidth: 1))
        case .plain:
            content
                .background(onBold ? AnyShapeStyle(Color.white.opacity(0.15)) : AnyShapeStyle(Palette.surface), in: shape)
                .overlay(shape.strokeBorder(onBold ? AnyShapeStyle(Color.white.opacity(0.28))
                                                   : AnyShapeStyle(Palette.border), lineWidth: 1))
        }
    }
}

extension View {
    /// Card treatment for something that is not a `Card` — a tile, a tappable
    /// row, a grid cell. Same three looks, same hue inheritance rules.
    func cardSkin(_ look: CardLook = .tinted, hue: Hue, radius: CGFloat = Radius.lg) -> some View {
        modifier(CardSkin(hue: hue, look: look, radius: radius))
    }
}

// MARK: - Labels

/// The name of a screen, at the system's large-title style so it tracks Dynamic
/// Type instead of sitting at a fixed 28pt.
struct ScreenTitle: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.largeTitle.bold())
            .foregroundStyle(Palette.text)
    }
}

/// A grouped-section header, matching the system's footnote-uppercase-secondary.
struct SectionTitle: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Palette.muted)
    }
}

extension View {
    /// Fire a light tap when a button style transitions into the pressed state.
    func pressHaptic(_ pressed: Bool) -> some View {
        onChange(of: pressed) { _, now in if now { Haptics.tap() } }
    }
}

// Balanced pointing-hand cursor (uses .set(), so no push/pop imbalance on disappear).
// No-op on iOS — there's no pointer to change.
func cursor(_ inside: Bool) {
    #if os(macOS)
    if inside { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
    #endif
}

/// Full-width primary action used by forms (login, etc.).
struct PrimaryButton: View {
    let title: String
    var loading = false
    var tint: Color = Palette.accent
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if loading { ProgressView().controlSize(.small) }
                Text(title)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(tint)
        .disabled(loading)
    }
}

// MARK: - Text field styling

extension View {
    /// The MyOS input look: filled, rounded, a 2px border that glows the accent on focus.
    func knField(focused: Bool = false, radius: CGFloat = Radius.md) -> some View {
        self
            .padding(.horizontal, 13).padding(.vertical, 10)
            .background(.hueFillStrong,
                        in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(focused ? AnyShapeStyle(Palette.brand) : AnyShapeStyle(.hueLine), lineWidth: 2)
            )
            .animation(.knFast, value: focused)
    }
}

// MARK: - Entrance

/// Entrance for a screen's blocks: a short rise on a system spring, lightly
/// staggered so a page reads as arriving in order.
///
/// The stagger is why this modifier was once reduced to a bare fade — inside a
/// scroll view, a page still cascading when your thumb lands shifts content
/// under you. The fix that matters is not stillness but the `knEntrances` guard
/// below: `TodayPager` sets it false, so turning a page never replays entrances.
/// Keep that guard wherever blocks are not genuinely arriving. Reduce Motion
/// drops the movement entirely, and the stagger is capped so a long page cannot
/// cascade for a noticeable length of time.
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

    /// One-letter weekday for a `yyyy-MM-dd` key. Hand-rolled rather than
    /// localised: a strip of seven needs exactly one character each, and some
    /// locales give two.
    static func weekdayInitial(_ iso: String) -> String {
        guard let date = CalMath.date(fromKey: String(iso.prefix(10))) else { return "" }
        let i = CalMath.cal.component(.weekday, from: date)   // Sunday = 1
        return ["S", "M", "T", "W", "T", "F", "S"][max(0, min(6, i - 1))]
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
