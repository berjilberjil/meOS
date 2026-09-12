import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MyOS design system — the one source of truth for colour, and the only file in
// the app allowed to name a colour value.
//
// History matters here, because this file has been rewritten in both directions.
// The app was a Fold-style black+green skin, then a Duolingo skin, then (2026-08-24)
// pure system semantic colours, then (2026-08-25 morning) a ten-hue palette that
// gave every card, tab, meal and note its own colour. That last one is what this
// replaces: the verdict was that it read as "a collection of unrelated widgets
// instead of one premium operating system".
//
// The rule now is that COLOUR MUST HAVE MEANING. There are three accents and no
// decorative colour at all:
//
//   GREEN  → go / good / complete / action / fitness / productive / activity /
//            time / food. This is the app's colour; a screen with nothing to
//            warn about is black, white and green.
//   ORANGE → the only three things worth interrupting for: a warning, a failure,
//            and time you wasted. Nothing decorative is ever orange.
//   BLUE   → information / events / system data
//   WHITE  → content
//   BLACK  → environment
//
// 2026-08-25 evening: orange used to carry activity, attention, time and food as
// well, which put it on the steps chart, the intake bar, every pin and star and
// half the section labels — and the verdict was that the app looked randomly
// orange. Green took all of those. What is left in orange is only ever bad news,
// which is what makes it readable as bad news.
//
// If you are about to add a colour because a card looks plain, don't. Add
// hierarchy instead: a heavier weight, more space, or an accent that is already
// earned by the content's meaning.

enum Palette {

    // The raw, per-appearance values. Everything below is built from these, and
    // anything that needs to *reason* about a colour (contrast maths, tests)
    // must use these rather than the dynamic colours: resolving a dynamic
    // NSColor's components re-enters its provider and is pathologically slow —
    // measured at ~100s for a few hundred calls.
    enum Dark {
        static let background = Color(hex: 0x000000)
        static let surface    = Color(hex: 0x0A0A0A)
        static let elevated   = Color(hex: 0x131313)
        static let text       = Color.white
        /// The primary — whatever Berjil chose in Settings. Green out of the box.
        static var green: Color { Palette.accentRaw(.primary, dark: true) }
        static var orange: Color { Palette.accentRaw(.warning, dark: true) }
        static var blue: Color { Palette.accentRaw(.info, dark: true) }
        /// The palette's own defaults, for anything that needs the shipped
        /// values rather than the chosen ones.
        static let defaultGreen  = Color(hex: 0x39FF14)
        static let defaultOrange = Color(hex: 0xFF7A00)
        static let defaultBlue   = Color(hex: 0x2196FF)
    }
    enum Light {
        static let background = Color(hex: 0xFFFFFF)
        static let surface    = Color(hex: 0xF6F6F8)
        static let elevated   = Color(hex: 0xFFFFFF)
        static let text       = Color.black
        static var green: Color { Palette.accentRaw(.primary, dark: false) }
        static var orange: Color { Palette.accentRaw(.warning, dark: false) }
        static var blue: Color { Palette.accentRaw(.info, dark: false) }
        static let defaultGreen  = Color(hex: 0x18A400)
        static let defaultOrange = Color(hex: 0xE06A00)
        static let defaultBlue   = Color(hex: 0x0B72D8)
    }

    // MARK: The chosen appearance
    //
    // `AppearanceStore` owns the setting and calls `apply` on the main thread;
    // everything here only ever reads. The three dynamic `Color`s are CACHED
    // rather than rebuilt per access: `Color.dynamic` allocates a platform
    // colour with a provider closure, and these are read thousands of times a
    // frame.

    /// Which of the three meanings a raw value is being asked for.
    enum AccentSlot { case primary, warning, info }

    nonisolated(unsafe) private(set) static var appearance = AppearanceSettings()

    /// Install a new appearance. Main thread only — `AppearanceStore` is the
    /// only caller, and it is `@MainActor`.
    static func apply(_ next: AppearanceSettings) {
        appearance = next
        greenCache  = build(.primary)
        orangeCache = build(.warning)
        blueCache   = build(.info)
    }

    /// One appearance's raw value for a slot. Contrast maths and tests use this
    /// — never introspect a dynamic colour, it re-enters its provider and is
    /// pathologically slow.
    static func accentRaw(_ slot: AccentSlot, dark: Bool) -> Color {
        // Mono is not "grey everything": the three meanings still have to be
        // told apart, so they become three steps of the ink instead of three
        // hues. Primary is full strength, information three-quarters, warning
        // just over half — which is still the one that looks *wrong* on a page
        // of solid ink, which is what a warning needs to do.
        if appearance.mono {
            let ink: Color = dark ? .white : .black
            switch slot {
            case .primary: return ink
            case .info:    return ink.opacity(0.75)
            case .warning: return ink.opacity(0.55)
            }
        }
        switch slot {
        case .primary: return Color(hex: dark ? appearance.primaryDark : appearance.primaryLight)
        case .warning: return dark ? Dark.defaultOrange : Light.defaultOrange
        case .info:    return dark ? Dark.defaultBlue : Light.defaultBlue
        }
    }

    /// A colour that came from **data** rather than from the design system — an
    /// event tag's hex, a belonging's tint, a mood stop.
    ///
    /// These are the colours the palette does not own: Berjil picked them, they
    /// are stored in the synced blob, and rewriting them when he changes theme
    /// would be destroying his data to satisfy a setting. So they are *mapped*
    /// at draw time instead. Mono is the case that matters: an Events tab full
    /// of green, blue, amber and purple chips is not a monochrome app, however
    /// black the canvas behind it is.
    ///
    /// The mapping is by perceived luminance, so a set of distinct hues stays a
    /// set of distinct greys — a light tag reads light and a dark one reads
    /// dark, which is the most a single ink can preserve.
    static func dataTint(_ hex: UInt32) -> Color {
        guard appearance.mono else { return Color(hex: hex) }
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        // Rec. 709 luma. Floored at 0.45 so the darkest tag is still legible
        // against the canvas rather than vanishing into it.
        let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
        let strength = 0.45 + 0.55 * min(1, max(0, luma))
        return .dynamic(lightColor: .black.opacity(strength), darkColor: .white.opacity(strength))
    }

    private static func build(_ slot: AccentSlot) -> Color {
        .dynamic(lightColor: accentRaw(slot, dark: false), darkColor: accentRaw(slot, dark: true))
    }

    nonisolated(unsafe) private static var greenCache  = build(.primary)
    nonisolated(unsafe) private static var orangeCache = build(.warning)
    nonisolated(unsafe) private static var blueCache   = build(.info)

    /// Whichever of black or white is actually legible on `tint`. Not a guess —
    /// neon green wants black, the light-mode blue wants white, and hard-coding
    /// either one makes half the buttons unreadable.
    static func legibleInk(on tint: Color) -> Color {
        tint.contrast(with: .black) >= tint.contrast(with: .white) ? .black : .white
    }

    // MARK: Environment

    /// True black. Not navy, not charcoal — the app is one continuous canvas.
    static let background = Color.dynamic(lightColor: Light.background, darkColor: Dark.background)
    /// A card. Separated from the canvas by a hair, not by a colour.
    static let surface = Color.dynamic(lightColor: Light.surface, darkColor: Dark.surface)
    /// A row or chip inside a card — one step up from `surface`.
    static let surfaceElevated = Color.dynamic(lightColor: Light.elevated, darkColor: Dark.elevated)

    // MARK: Content
    //
    // Secondary and tertiary text are the primary colour at reduced opacity, not
    // separate greys. That is what stops six slightly different greys appearing
    // across six screens.

    static let text  = Color.dynamic(lightColor: Light.text, darkColor: Dark.text)
    static let muted = Color.dynamic(lightColor: .black.opacity(0.60), darkColor: .white.opacity(0.65))
    static let faint = Color.dynamic(lightColor: .black.opacity(0.38), darkColor: .white.opacity(0.40))

    // MARK: Accents — three, and only three.

    /// GO / GOOD / COMPLETE / ACTION / FITNESS / PRODUCTIVE / ACTIVITY / TIME / FOOD.
    /// The app's primary, and the one Settings can change.
    static var green: Color { greenCache }
    /// WARNING / FAILURE / WASTED TIME. Never decoration, and deliberately NOT
    /// derived from the primary — a warning that matches the rest of the app is
    /// a warning you stop seeing.
    static var orange: Color { orangeCache }
    /// INFORMATION / EVENTS / SYSTEM DATA. Used sparingly.
    static var blue: Color { blueCache }

    // MARK: Semantic aliases
    //
    // Screens name the *meaning*, never the colour. Changing what "nutrition"
    // looks like is then one line here rather than a search across the app.

    static var success:     Color { green }
    static var action:      Color { green }
    static var complete:    Color { green }
    static var fitness:     Color { green }
    static var productive:  Color { green }
    static var activity:    Color { green }
    static var attention:   Color { green }
    static var nutrition:   Color { green }

    /// Something is wrong, or about to be — an error, a destructive action, a
    /// risk. The only reason to reach for orange.
    static var warning:     Color { orange }
    /// Time that did nothing for you. Orange because it has to read *against*
    /// the productive green sitting next to it in the same breakdown.
    static var distracting: Color { orange }

    static var information: Color { blue }
    static var events:      Color { blue }

    /// Neutral / uncategorised. Deliberately not a colour.
    static var neutral:     Color { muted }

    // MARK: Lines

    /// The separation between a card and the canvas. Subtle by design — a card
    /// should be found by its content, not outlined like a form field.
    static let border  = Color.dynamic(lightColor: .black.opacity(0.10), darkColor: .white.opacity(0.08))
    static let divider = Color.dynamic(lightColor: .black.opacity(0.07), darkColor: .white.opacity(0.06))

    // MARK: Chrome

    /// The Mac sidebar. Very slightly lifted off the canvas so the rail reads as
    /// chrome, using the same near-black the cards use.
    static var sidebar: Color { surface }
    static var elevated: Color { surfaceElevated }
    static var borderStrong: Color { Color.dynamic(lightColor: .black.opacity(0.18), darkColor: .white.opacity(0.16)) }

    /// The app tint — the colour of an active control, everywhere, always.
    static var accent: Color { green }
}

// MARK: - Accent

/// The accent a piece of content has *earned*. `.none` is the default and the
/// right answer for most cards: a card with no semantic colour is a black card
/// with white type, which is what the app should mostly look like.
enum Accent: String, CaseIterable, Identifiable, Hashable {
    case none, green, orange, blue

    var id: String { rawValue }

    /// The accent colour itself — for a value, a glyph, a hairline, a chart mark.
    var tint: Color {
        switch self {
        case .none:   return Palette.muted
        case .green:  return Palette.green
        case .orange: return Palette.orange
        case .blue:   return Palette.blue
        }
    }

    /// Text drawn ON `tint` when the accent is used as a fill. Computed per
    /// appearance from the raw values, because the answer genuinely differs:
    /// the neon green and the orange both want black, while the darker
    /// light-mode blue wants white.
    var ink: Color {
        switch self {
        case .none: return Palette.text
        case .green:
            return .dynamic(lightColor: Palette.legibleInk(on: Palette.Light.green),
                            darkColor:  Palette.legibleInk(on: Palette.Dark.green))
        case .orange:
            return .dynamic(lightColor: Palette.legibleInk(on: Palette.Light.orange),
                            darkColor:  Palette.legibleInk(on: Palette.Dark.orange))
        case .blue:
            return .dynamic(lightColor: Palette.legibleInk(on: Palette.Light.blue),
                            darkColor:  Palette.legibleInk(on: Palette.Dark.blue))
        }
    }

    /// The raw tint for one appearance — for contrast maths and tests, which
    /// must never introspect a dynamic colour.
    func raw(_ scheme: ColorScheme) -> Color {
        switch (self, scheme) {
        case (.green, .dark):   return Palette.Dark.green
        case (.green, _):       return Palette.Light.green
        case (.orange, .dark):  return Palette.Dark.orange
        case (.orange, _):      return Palette.Light.orange
        case (.blue, .dark):    return Palette.Dark.blue
        case (.blue, _):        return Palette.Light.blue
        case (.none, .dark):    return Palette.Dark.text
        case (.none, _):        return Palette.Light.text
        }
    }

    /// A barely-there fill of the accent, for the rare surface that genuinely
    /// belongs to one meaning. This is NOT a card background — see `CardLook`.
    var wash: Color { tint.opacity(0.12) }

    /// Semantic constructors, so call sites read as meaning rather than colour.
    /// Nothing outside this file should name `.orange` — say `.warning` and the
    /// meaning survives the next time the palette moves.
    static var productive: Accent { .green }
    static var activity: Accent { .green }
    static var nutrition: Accent { .green }
    static var complete: Accent { .green }
    static var attention: Accent { .green }
    static var information: Accent { .blue }
    static var warning: Accent { .orange }
    static var distracting: Accent { .orange }
}

// MARK: - Ambient accent

private struct CardAccentKey: EnvironmentKey { static let defaultValue = Accent.none }

extension EnvironmentValues {
    /// The accent a section's content has earned. Cards read it to colour their
    /// title glyph and values — never to fill themselves.
    var cardAccent: Accent {
        get { self[CardAccentKey.self] }
        set { self[CardAccentKey.self] = newValue }
    }
}

extension View {
    /// Give everything below this point one semantic accent.
    func cardAccent(_ accent: Accent) -> some View { environment(\.cardAccent, accent) }

    /// A screen's ground: the canvas, and no accent unless the screen's content
    /// earns one. Replaces the per-tab coloured backgrounds — every screen in
    /// MyOS is the same black.
    func pageBackground() -> some View {
        background(Palette.background.ignoresSafeArea())
    }
}

// MARK: - Dynamic colour

extension Color {
    /// A colour that resolves differently in Light and Dark. MyOS owns its
    /// palette, so this is what keeps the appearance switch working.
    static func dynamic(lightColor light: Color, darkColor dark: Color) -> Color {
        #if os(macOS)
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(dark) : NSColor(light)
        })
        #else
        return Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
        #endif
    }

    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        dynamic(lightColor: Color(hex: light), darkColor: Color(hex: dark))
    }
}

// MARK: - Spacing

/// One spacing scale. Anything not on it is a mistake unless a comment says why.
enum Space {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let section: CGFloat = 32
    static let screen: CGFloat = 40
}

// MARK: - Type

/// Four roles. A card that needs a fifth size is a card that is doing too much.
///
/// Fold scale: the hero dominates, headings carry sections, body reads,
/// captions whisper. All of these scale with the system text size —
/// `myDisplay` is an explicit size (there is no text style bigger than
/// `largeTitle`), the rest are Dynamic Type text styles.
extension Font {
    /// Hero metrics — the one number a card exists to show. Bigger than
    /// `largeTitle`, bold, with `FluidType.displayTracking` negative tracking
    /// (see `.fluidDisplay()`). Numbers add `.monospacedDigit()` at the call
    /// site so a ticking value does not jitter its width.
    static var myDisplay: Font { .system(size: 52, design: .default).weight(.bold) }
    /// Screen/section names when they are content, not chrome.
    static var myHeading: Font { .system(.title3).weight(.semibold) }
    /// Descriptions, insight text, list rows. Readable copy — never footnote.
    static var myBody: Font { .system(.body) }
    /// Metadata, units, timestamps. The only thing allowed to be small.
    static var myCaption: Font { .system(.caption).weight(.medium) }
}

/// A section header: uppercase, tracked, muted — or accented when the section
/// has earned a colour. The tracking is the size-specific value for an
/// uppercase caption (§15, `FluidType.sectionTracking`): small text wants
/// positive tracking for legibility, and this is the one place that rule lives.
struct SectionLabel: View {
    let text: String
    var accent: Accent = .none
    var body: some View {
        Text(text.uppercased())
            .font(.myCaption)
            .tracking(0.8)
            .foregroundStyle(accent == .none ? Palette.faint : accent.tint)
    }
}
