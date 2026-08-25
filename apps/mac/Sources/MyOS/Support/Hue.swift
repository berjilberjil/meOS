import SwiftUI

/// MyOS colour. Every surface in the app belongs to a *hue* — Activity is green,
/// Intake orange, Workout blue — and a hue knows every form it has to take: the
/// saturated gradient a hero card is filled with, the soft wash a quiet card
/// gets, the near-flat canvas a whole screen sits on, its border, and the ink
/// that stays legible on top of its wash.
///
/// Two hex values define a hue and everything else is derived from them, which
/// is what stops the palette drifting: a new hue is one line, and it arrives
/// with a light *and* a dark form of all seven roles.
///
/// This deliberately re-introduces app-owned colour, reversing the 2026-08-24
/// "system semantic colours only" pass. That pass made the app track Light/Dark
/// for free and made it grey — and grey, per Berjil, reads as an unfinished app.
/// Light/dark tracking is kept by building every derived colour as a *dynamic*
/// colour (see `Color.dynamic`) rather than by giving up the colour.
struct Hue: Identifiable {
    let id: String
    /// The vivid face of the hue. Dark enough that white text clears contrast.
    let core: Color
    /// The far end of the bold gradient — the same colour, deeper.
    let edge: Color
    /// Card fill for the quiet cards: the hue, washed out.
    let fill: Color
    /// A step up from `fill` — chips and rows *inside* a card.
    let fillStrong: Color
    /// Whole-screen background. Barely there, but never grey.
    let canvas: Color
    /// Hairline around a washed card.
    let line: Color
    /// Text/glyph colour that stays legible on `fill`.
    let ink: Color
    /// The fill of a hero card. White text goes on this.
    let boldGradient: LinearGradient

    init(id: String, core coreHex: UInt32, edge edgeHex: UInt32) {
        let core = Color(hex: coreHex)
        let edge = Color(hex: edgeHex)
        self.id = id
        self.core = core
        self.edge = edge
        // Light mode washes toward white, dark mode toward black, so a card is
        // pale-tinted on a white page and deep-tinted on a black one.
        self.fill       = .dynamic(light: core.mixedWithWhite(0.82), dark: core.mixedWithBlack(0.72))
        self.fillStrong = .dynamic(light: core.mixedWithWhite(0.78), dark: core.mixedWithBlack(0.60))
        self.canvas     = .dynamic(light: core.mixedWithWhite(0.95), dark: core.mixedWithBlack(0.92))
        self.line       = .dynamic(light: core.opacity(0.22),        dark: core.opacity(0.34))
        self.ink        = .dynamic(light: core.mixedWithBlack(0.42), dark: core.mixedWithWhite(0.52))
        // The gradient starts a shade below `core` where it has to: white text
        // sits on the top-left corner, and amber, cyan and orange are all light
        // enough at full strength that white on them fails contrast. `core`
        // itself stays vivid — it is what chart bars and status dots use, where
        // nothing is written on top.
        self.boldGradient = LinearGradient(colors: [core.darkenedForWhiteText(), edge],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

extension Hue: Hashable {
    // LinearGradient is not Hashable, and identity is the id anyway.
    static func == (a: Hue, b: Hue) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension Hue {
    static let green  = Hue(id: "green",  core: 0x4EA80C, edge: 0x2C6B08)
    static let orange = Hue(id: "orange", core: 0xF97316, edge: 0xC2410C)
    static let blue   = Hue(id: "blue",   core: 0x3B82F6, edge: 0x1D4ED8)
    static let purple = Hue(id: "purple", core: 0x9333EA, edge: 0x6B21A8)
    static let teal   = Hue(id: "teal",   core: 0x0EA5A5, edge: 0x0F766E)
    static let cyan   = Hue(id: "cyan",   core: 0x0EA5E9, edge: 0x0369A1)
    static let amber  = Hue(id: "amber",  core: 0xE0A100, edge: 0xB45309)
    static let pink   = Hue(id: "pink",   core: 0xEC4899, edge: 0xBE185D)
    static let indigo = Hue(id: "indigo", core: 0x6366F1, edge: 0x4338CA)
    static let red    = Hue(id: "red",    core: 0xEF4444, edge: 0xB91C1C)

    static let all: [Hue] = [green, orange, blue, purple, teal, cyan, amber, pink, indigo, red]
    static func named(_ id: String) -> Hue { all.first { $0.id == id } ?? .indigo }

    /// Deterministic hue for an arbitrary string — used where the thing being
    /// coloured has no fixed identity (a tag, a note, a food category) but still
    /// must not be grey, and must keep the same colour between launches.
    static func forKey(_ key: String) -> Hue {
        guard !key.isEmpty else { return .indigo }
        var hash: UInt64 = 5381
        for byte in key.utf8 { hash = (hash &* 33) &+ UInt64(byte) }
        return all[Int(hash % UInt64(all.count))]
    }
}

// MARK: - Contrast

extension Color {
    /// WCAG relative luminance.
    var wcagLuminance: Double {
        let c = platformComponents(self, fallback: .black)
        func channel(_ v: Double) -> Double {
            v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b)
    }

    /// Contrast ratio against white.
    var contrastWithWhite: Double { 1.05 / (wcagLuminance + 0.05) }

    /// The colour, darkened just far enough that white text on it clears
    /// `minContrast` (3:1 is the WCAG floor for large text; 3.4 leaves margin).
    func darkenedForWhiteText(minContrast: Double = 3.4) -> Color {
        guard contrastWithWhite < minContrast else { return self }
        var t = 0.02
        while t < 0.6 {
            let candidate = mixedWithBlack(t)
            if candidate.contrastWithWhite >= minContrast { return candidate }
            t += 0.02
        }
        return mixedWithBlack(0.6)
    }
}

// MARK: - Dynamic colour

extension Color {
    /// A colour that resolves differently in Light and Dark. Hand-written hexes
    /// would otherwise be frozen at one appearance — this is what lets MyOS own
    /// its palette without losing the appearance switch.
    static func dynamic(light: Color, dark: Color) -> Color {
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

    /// Hex spelling of the same thing, for the chrome table in `Palette`.
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        dynamic(light: Color(hex: light), dark: Color(hex: dark))
    }
}

// MARK: - Ambient hue

private struct CardHueKey: EnvironmentKey { static let defaultValue = Hue.indigo }

extension EnvironmentValues {
    /// The hue a `Card` takes when it is not given one. Screens set this once and
    /// every card, chip and row underneath inherits it — which is how ~166 card
    /// sites got colour without ~166 edits.
    var cardHue: Hue {
        get { self[CardHueKey.self] }
        set { self[CardHueKey.self] = newValue }
    }
}

private struct CardLookKey: EnvironmentKey { static let defaultValue = CardLook.tinted }

private struct OnBoldCardKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// True inside a `.bold` card. Anything that paints itself from the hue has
    /// to switch to translucent white in there — the hue's own dark fill on top
    /// of the hue's own saturated gradient is a chip you cannot see.
    var onBoldCard: Bool {
        get { self[OnBoldCardKey.self] }
        set { self[OnBoldCardKey.self] = newValue }
    }
}

extension EnvironmentValues {
    /// The fill a `Card` takes when it is not given one, so a section can hand
    /// its cards a look without those card types knowing they are on Today.
    var cardLook: CardLook {
        get { self[CardLookKey.self] }
        set { self[CardLookKey.self] = newValue }
    }
}

extension View {
    /// Colour everything below this point, without painting a background.
    func cardHue(_ hue: Hue) -> some View { environment(\.cardHue, hue) }

    /// Fill style for everything below this point.
    func cardLook(_ look: CardLook) -> some View { environment(\.cardLook, look) }

    /// A screen's colour: sets the ambient hue *and* paints the canvas, so
    /// switching tabs reads as moving between rooms rather than between lists.
    func pageTint(_ hue: Hue) -> some View {
        environment(\.cardHue, hue)
            .background(PageCanvas(hue: hue))
    }
}

/// The screen background. A single flat colour reads as paper; two stops of the
/// same hue give the page a top-light that stops it looking printed.
struct PageCanvas: View {
    let hue: Hue
    var body: some View {
        LinearGradient(
            colors: [
                Color.dynamic(light: hue.core.mixedWithWhite(0.90), dark: hue.core.mixedWithBlack(0.84)),
                hue.canvas
            ],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

/// The ambient hue's canvas, for containers that used to paint `Palette.bg`
/// directly. Reading the hue from the environment is what lets a screen keep one
/// `.background(HueCanvas())` and still change colour with the tab it is in.
struct HueCanvas: View {
    @Environment(\.cardHue) private var hue
    var body: some View { PageCanvas(hue: hue) }
}

// MARK: - Hue-resolving shape styles

/// A fill that reads the ambient `\.cardHue` at draw time.
///
/// This exists because `Palette.surface` and friends are `static` — they cannot
/// know which screen they are on, which is exactly why the app was grey in the
/// first place: one hundred and thirty painted surfaces all reaching for the
/// same neutral. A `ShapeStyle` gets the environment handed to it, so the same
/// call site paints teal on Scan and pink on Fitness.
struct HueFill: ShapeStyle {
    enum Level { case canvas, soft, strong }
    let level: Level

    func resolve(in environment: EnvironmentValues) -> Color {
        if environment.onBoldCard {
            switch level {
            case .canvas: return .white.opacity(0.10)
            case .soft:   return .white.opacity(0.15)
            case .strong: return .white.opacity(0.22)
            }
        }
        let hue = environment.cardHue
        switch level {
        case .canvas: return hue.canvas
        case .soft:   return hue.fill
        case .strong: return hue.fillStrong
        }
    }
}

extension ShapeStyle where Self == HueFill {
    /// Page-level: the quietest form of the hue.
    static var hueCanvas: HueFill { HueFill(level: .canvas) }
    /// Card-level.
    static var hueFill: HueFill { HueFill(level: .soft) }
    /// Chips and rows inside a card — one step up from `hueFill`.
    static var hueFillStrong: HueFill { HueFill(level: .strong) }
}

/// A hairline in the ambient hue.
struct HueLine: ShapeStyle {
    func resolve(in environment: EnvironmentValues) -> Color {
        environment.onBoldCard ? .white.opacity(0.28) : environment.cardHue.line
    }
}

extension ShapeStyle where Self == HueLine {
    static var hueLine: HueLine { HueLine() }
}
