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
        static let green      = Color(hex: 0x39FF14)
        static let orange     = Color(hex: 0xFF7A00)
        static let blue       = Color(hex: 0x2196FF)
    }
    enum Light {
        static let background = Color(hex: 0xFFFFFF)
        static let surface    = Color(hex: 0xF6F6F8)
        static let elevated   = Color(hex: 0xFFFFFF)
        static let text       = Color.black
        static let green      = Color(hex: 0x18A400)
        static let orange     = Color(hex: 0xE06A00)
        static let blue       = Color(hex: 0x0B72D8)
    }

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
    static let green  = Color.dynamic(lightColor: Light.green, darkColor: Dark.green)
    /// WARNING / FAILURE / WASTED TIME. Never decoration.
    static let orange = Color.dynamic(lightColor: Light.orange, darkColor: Dark.orange)
    /// INFORMATION / EVENTS / SYSTEM DATA. Used sparingly.
    static let blue   = Color.dynamic(lightColor: Light.blue, darkColor: Dark.blue)

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
/// All of these are Dynamic Type text styles, so they scale with the system.
extension Font {
    /// Hero metrics — the one number a card exists to show.
    static var myDisplay: Font { .system(.largeTitle, design: .default).weight(.bold) }
    /// Section titles.
    static var myHeading: Font { .system(.subheadline).weight(.semibold) }
    /// Descriptions, insight text, list rows.
    static var myBody: Font { .system(.footnote) }
    /// Metadata, units, timestamps.
    static var myCaption: Font { .system(.caption2).weight(.medium) }
}

/// A section header: uppercase, tracked, muted — or accented when the section
/// has earned a colour.
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
