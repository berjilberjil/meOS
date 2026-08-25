import SwiftUI

/// How MyOS looks, as data — the part of the design system Berjil owns.
///
/// The rest of `DesignSystem.swift` decides what colour *means*: green is go,
/// orange is bad news, blue is information. This decides what those meanings
/// look like. Keeping the two apart is what lets the whole app re-skin from one
/// screen without a single call site changing, and what stops a re-skin from
/// quietly making an error message look like a success.
///
/// It rides the synced state blob, so choosing a colour on the Mac is the same
/// choice on the iPhone a poll later. That is deliberate: an operating system
/// that looks different on each device is two apps.
struct AppearanceSettings: Codable, Hashable {

    /// How a card separates itself from the canvas.
    enum CardStyle: String, Codable, CaseIterable, Identifiable, Hashable {
        /// Near-black surface and a hairline. The original, and still the
        /// quietest.
        case flat
        /// A heavier fill, so cards read as objects on the canvas rather than
        /// regions of it.
        case filled
        /// The fill, with a soft vertical grade across it.
        case gradient

        var id: String { rawValue }
        var label: String {
            switch self {
            case .flat:     return "Flat"
            case .filled:   return "Filled"
            case .gradient: return "Gradient"
            }
        }
    }

    /// Which preset this came from, or `custom` when the colour was picked by
    /// hand. Stored so the picker can show what is selected rather than
    /// guessing from a hex match.
    var presetID: String = ThemePreset.green.id
    /// The primary colour, per appearance. Two values rather than one because a
    /// neon that sings on black is unreadable on white.
    var primaryLight: UInt32 = 0x18A400
    var primaryDark: UInt32 = 0x39FF14
    var cardStyle: CardStyle = .flat
    /// Black, white, and nothing else — anywhere.
    var mono: Bool = false

    init() {}

    /// Tolerant: a field added later must not stop an older payload decoding.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        presetID     = try c.decodeIfPresent(String.self, forKey: .presetID) ?? ThemePreset.green.id
        primaryLight = try c.decodeIfPresent(UInt32.self, forKey: .primaryLight) ?? 0x18A400
        primaryDark  = try c.decodeIfPresent(UInt32.self, forKey: .primaryDark) ?? 0x39FF14
        cardStyle    = CardStyle(rawValue: (try? c.decode(String.self, forKey: .cardStyle)) ?? "") ?? .flat
        mono         = try c.decodeIfPresent(Bool.self, forKey: .mono) ?? false
    }

    enum CodingKeys: String, CodingKey { case presetID, primaryLight, primaryDark, cardStyle, mono }

    /// Apply a preset, keeping everything else.
    func applying(_ preset: ThemePreset) -> AppearanceSettings {
        var out = self
        out.presetID = preset.id
        out.primaryLight = preset.light
        out.primaryDark = preset.dark
        out.mono = preset.isMono
        return out
    }
}

/// A named primary colour.
///
/// Presets rather than a raw colour well as the main route, because the pair of
/// values matters: every one of these has been picked as a light/dark *pair*
/// that stays legible against both the white and the black canvas. A free colour
/// picker is still there for when he wants one, but it should not be the first
/// thing offered.
struct ThemePreset: Identifiable, Hashable {
    let id: String
    let name: String
    let light: UInt32
    let dark: UInt32
    /// The mono theme is a preset like any other, so it appears in the same row
    /// rather than hiding behind a switch somewhere else.
    var isMono: Bool = false

    static let green  = ThemePreset(id: "green",  name: "Green",  light: 0x18A400, dark: 0x39FF14)
    static let blue   = ThemePreset(id: "blue",   name: "Blue",   light: 0x0B72D8, dark: 0x2196FF)
    static let purple = ThemePreset(id: "purple", name: "Purple", light: 0x6D28D9, dark: 0xA78BFA)
    static let pink   = ThemePreset(id: "pink",   name: "Pink",   light: 0xBE185D, dark: 0xFF5FA2)
    static let amber  = ThemePreset(id: "amber",  name: "Amber",  light: 0xB45309, dark: 0xFFB020)
    static let teal   = ThemePreset(id: "teal",   name: "Teal",   light: 0x0F766E, dark: 0x2DD4BF)
    static let mono   = ThemePreset(id: "mono",   name: "Mono",   light: 0x000000, dark: 0xFFFFFF,
                                    isMono: true)

    static let all: [ThemePreset] = [green, blue, purple, pink, amber, teal, mono]

    static func by(id: String) -> ThemePreset? { all.first { $0.id == id } }

    /// The swatch to draw in the picker for a given appearance.
    func swatch(_ dark: Bool) -> Color { Color(hex: dark ? self.dark : light) }
}

/// Holds the live appearance and pushes it into `Palette`.
///
/// A separate object from `ThemeStore` because they answer different questions:
/// `ThemeStore` is light-or-dark, which is a system-level preference; this is
/// what MyOS's own colours are, which is Berjil's.
@MainActor
final class AppearanceStore: ObservableObject {
    static let shared = AppearanceStore()

    @Published private(set) var settings = AppearanceSettings()
    /// Bumped on every change. `RootView` keys the whole tree on it, because a
    /// palette swap has to reach every view and SwiftUI has no way to know that
    /// a global changed underneath it.
    @Published private(set) var revision = 0

    private init() {
        // The synced copy arrives after unlock. Until then use the last one this
        // device saw, so the launch screen is not briefly the wrong colour.
        if let data = UserDefaults.standard.data(forKey: Self.cacheKey),
           let cached = try? JSONDecoder().decode(AppearanceSettings.self, from: data) {
            settings = cached
        }
        Palette.apply(settings)
    }

    private static let cacheKey = "myos.appearance.cache"

    func apply(_ next: AppearanceSettings) {
        guard next != settings else { return }
        settings = next
        if let data = try? JSONEncoder().encode(next) {
            UserDefaults.standard.set(data, forKey: Self.cacheKey)
        }
        Palette.apply(next)
        revision += 1
    }
}
