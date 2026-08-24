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

    #if os(macOS)
    static var bg: Color           { Color(nsColor: .windowBackgroundColor) }
    static var sidebar: Color      { Color(nsColor: .underPageBackgroundColor) }
    static var surface: Color      { Color(nsColor: .controlBackgroundColor) }
    static var surface2: Color     { Color(nsColor: .unemphasizedSelectedContentBackgroundColor) }
    static var elevated: Color     { Color(nsColor: .controlBackgroundColor) }
    static var border: Color       { Color(nsColor: .separatorColor) }
    static var borderStrong: Color { Color(nsColor: .separatorColor) }
    static var text: Color         { Color(nsColor: .labelColor) }
    static var muted: Color        { Color(nsColor: .secondaryLabelColor) }
    static var faint: Color        { Color(nsColor: .tertiaryLabelColor) }
    #else
    static var bg: Color           { Color(uiColor: .systemGroupedBackground) }
    static var sidebar: Color      { Color(uiColor: .secondarySystemGroupedBackground) }
    static var surface: Color      { Color(uiColor: .secondarySystemGroupedBackground) }
    static var surface2: Color     { Color(uiColor: .tertiarySystemFill) }
    static var elevated: Color     { Color(uiColor: .secondarySystemGroupedBackground) }
    static var border: Color       { Color(uiColor: .separator) }
    static var borderStrong: Color { Color(uiColor: .opaqueSeparator) }
    static var text: Color         { Color(uiColor: .label) }
    static var muted: Color        { Color(uiColor: .secondaryLabel) }
    static var faint: Color        { Color(uiColor: .tertiaryLabel) }
    #endif

    static var ring: Color         { accent }
    static var brand: Color        { accent }
    static var brandDeep: Color    { accent }
    static var green: Color        { accent }

    // Feature colours — system hues, so they shift correctly between light and
    // dark and respond to Increase Contrast.
    static let red    = Color.red
    static let blue   = Color.blue
    static let amber  = Color.orange
    static let purple = Color.purple
    static let flame  = Color.orange
    static let ice    = Color.cyan
    static let rose   = Color.pink
    static let teal   = Color.teal
    static let gold   = Color.yellow
    static let coral  = Color.orange
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
    /// Native surfaces carry no app-drawn shadow: grouped content sits flat on
    /// the grouped background, and floating chrome takes its depth from a
    /// material. Kept as a no-op so the call sites read unchanged.
    func knShadow(_ strong: Bool = false) -> some View { self }
}

// MARK: - Card

/// The standard MyOS surface — a grouped-content cell. The 2px border, the
/// Duolingo fill and the drop shadow are gone; on both platforms this is now the
/// same shape the system draws behind an inset-grouped row.
struct Card<Content: View>: View {
    var padding: CGFloat = 18
    var radius: CGFloat = Radius.lg
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
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
                .font(.subheadline.weight(.bold))
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
                .font(.footnote.weight(.semibold))
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
                .font(.footnote.weight(.bold))
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
                .font(.footnote.weight(.bold))
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
                    .font((fillsWidth ? Font.caption : Font.footnote).weight(.heavy))
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
