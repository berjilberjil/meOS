import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Appearance: light or dark, what colour meOS is, and how its cards are drawn.
///
/// Light/dark is a system-level preference and stays on this device. Everything
/// below it — the primary colour, the card style, the mono theme — is synced,
/// because a personal operating system that looks different on each device is
/// two apps rather than one.
struct AppearanceCard: View {
    var boxed = true
    @EnvironmentObject var state: AppState
    @ObservedObject private var themeStore = ThemeStore.shared
    @ObservedObject private var appearance = AppearanceStore.shared
    @Environment(\.colorScheme) private var scheme

    private var selection: Binding<String> {
        Binding(get: { themeStore.theme.id },
                set: { state.setTheme(AppTheme.by(id: $0)) })
    }

    private var textSize: Binding<AppearanceSettings.TextSize> {
        Binding(get: { appearance.settings.textSize },
                set: { next in
                    var s = appearance.settings
                    s.textSize = next
                    state.setAppearance(s)
                })
    }

    private var cardStyle: Binding<AppearanceSettings.CardStyle> {
        Binding(get: { appearance.settings.cardStyle },
                set: { next in
                    var s = appearance.settings
                    s.cardStyle = next
                    state.setAppearance(s)
                })
    }

    /// The colour well. Reads the value for the appearance you are actually
    /// looking at, and writes both — a neon that sings on black is unreadable
    /// on white, so the two are stored separately and the light one is derived
    /// by darkening what was picked.
    private var custom: Binding<Color> {
        Binding(
            get: {
                let s = appearance.settings
                return Color(hex: scheme == .dark ? s.primaryDark : s.primaryLight)
            },
            set: { picked in
                guard let hex = picked.hexValue else { return }
                var s = appearance.settings
                s.presetID = "custom"
                s.mono = false
                if scheme == .dark {
                    s.primaryDark = hex
                    s.primaryLight = Color.darkened(hex, by: 0.42)
                } else {
                    s.primaryLight = hex
                    s.primaryDark = Color.lightened(hex, by: 0.42)
                }
                state.setAppearance(s)
            })
    }

    var body: some View {
        let inner = VStack(alignment: .leading, spacing: Gap.screen) {
            VStack(alignment: .leading, spacing: Gap.row) {
                if boxed { SectionTitle(text: "Appearance") }
                Picker("Appearance", selection: selection) {
                    ForEach(AppTheme.all) { theme in
                        Label(theme.name, systemImage: theme.symbol).tag(theme.id)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text(hint).font(.myBody).foregroundStyle(Palette.muted)
            }

            VStack(alignment: .leading, spacing: Gap.row) {
                SectionTitle(text: "Colour")
                swatches
                HStack(spacing: Space.md) {
                    ColorPicker("Custom", selection: custom, supportsOpacity: false)
                        .labelsHidden()
                    Text(appearance.settings.presetID == "custom" ? "Custom colour" : "Or pick your own")
                        .font(.myCaption).foregroundStyle(Palette.faint)
                    Spacer(minLength: 0)
                }
                Text("Your colour takes over everything the app calls green — actions, activity, food, fitness, the active tab. Warnings stay orange and information stays blue on purpose: a warning that matches the rest of the app is a warning you stop seeing.")
                    .font(.myCaption).foregroundStyle(Palette.faint)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: Gap.row) {
                SectionTitle(text: "Size")
                Picker("Size", selection: textSize) {
                    ForEach(AppearanceSettings.TextSize.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text("Moves the text and the icons together. The Mac's default is a step larger than the phone's, because a 27-inch display is not held at arm's length.")
                    .font(.myCaption).foregroundStyle(Palette.faint)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: Gap.row) {
                SectionTitle(text: "Cards")
                Picker("Cards", selection: cardStyle) {
                    ForEach(AppearanceSettings.CardStyle.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                preview
            }
        }

        // `boxed` off means this is already a full settings PAGE on iOS, which
        // supplies its own padding and background. Wrapping in a Card there adds
        // a second surface and shoves the content 18pt further in than the pages
        // that get this right — which is what made Settings look misaligned.
        if boxed {
            Card { inner }
        } else {
            SettingsPage {
                SettingsIntro(text: "Dark or light stays on this device. The colour and the card style follow you to your other one.")
                inner
            }
        }
    }

    /// Named pairs rather than a single hue, because each one has been picked as
    /// a light/dark pair that stays legible on both canvases. Mono sits in the
    /// same row: it is a theme, not a switch hidden somewhere else.
    private var swatches: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 74), spacing: Space.sm)],
                  alignment: .leading, spacing: Space.sm) {
            ForEach(ThemePreset.all) { preset in
                let on = appearance.settings.presetID == preset.id
                Button {
                    state.setAppearance(appearance.settings.applying(preset))
                } label: {
                    VStack(spacing: 5) {
                        ZStack {
                            Circle()
                                .fill(preset.swatch(scheme == .dark))
                                .frame(width: 26, height: 26)
                            if on {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .black))
                                    .foregroundStyle(Palette.legibleInk(on: preset.swatch(scheme == .dark)))
                            }
                        }
                        .overlay(Circle().strokeBorder(Palette.borderStrong, lineWidth: on ? 0 : 1)
                            .frame(width: 26, height: 26))
                        Text(preset.name)
                            .font(.myCaption)
                            .foregroundStyle(on ? Palette.text : Palette.faint)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Space.sm)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(preset.name)
            }
        }
    }

    /// Three real cards, so the card style is chosen by looking at it rather
    /// than by reading three adjectives.
    private var preview: some View {
        HStack(spacing: Space.sm) {
            Card(padding: Space.md, radius: Radius.md) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("CARD").font(.myCaption).foregroundStyle(Palette.faint)
                    Text("128").font(.title3.weight(.bold)).monospacedDigit()
                        .foregroundStyle(Palette.text)
                }
            }
            Card(padding: Space.md, radius: Radius.md, accent: .green, look: .accent) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ACCENT").font(.myCaption).foregroundStyle(Palette.accent)
                    Text("Done").font(.title3.weight(.bold)).foregroundStyle(Palette.text)
                }
            }
            Card(padding: Space.md, radius: Radius.md, accent: .green, look: .filled) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("FILLED").font(.myCaption).opacity(0.7)
                    Text("1,195").font(.title3.weight(.bold)).monospacedDigit()
                }
            }
        }
    }

    private var hint: String {
        #if os(macOS)
        "System follows your Mac's Appearance setting."
        #else
        "System follows your iPhone's Display setting."
        #endif
    }
}

// MARK: - Colour maths for the picker

extension Color {
    /// The sRGB value behind a *solid* colour. Safe here and nowhere near a
    /// dynamic colour — resolving one of those re-enters its provider and is
    /// pathologically slow.
    var hexValue: UInt32? {
        #if os(macOS)
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        let r = UInt32((c.redComponent * 255).rounded())
        let g = UInt32((c.greenComponent * 255).rounded())
        let b = UInt32((c.blueComponent * 255).rounded())
        #else
        var rf: CGFloat = 0, gf: CGFloat = 0, bf: CGFloat = 0, af: CGFloat = 0
        guard UIColor(self).getRed(&rf, green: &gf, blue: &bf, alpha: &af) else { return nil }
        let r = UInt32((rf * 255).rounded()), g = UInt32((gf * 255).rounded()), b = UInt32((bf * 255).rounded())
        #endif
        return (r << 16) | (g << 8) | b
    }

    /// Pull a colour toward black — the light-mode partner of a bright pick.
    static func darkened(_ hex: UInt32, by amount: Double) -> UInt32 {
        scale(hex) { Double($0) * (1 - amount) }
    }

    /// Push a colour toward white — the dark-mode partner of a deep pick.
    static func lightened(_ hex: UInt32, by amount: Double) -> UInt32 {
        scale(hex) { Double($0) + (255 - Double($0)) * amount }
    }

    private static func scale(_ hex: UInt32, _ f: (UInt32) -> Double) -> UInt32 {
        let r = UInt32(max(0, min(255, f((hex >> 16) & 0xFF))).rounded())
        let g = UInt32(max(0, min(255, f((hex >> 8) & 0xFF))).rounded())
        let b = UInt32(max(0, min(255, f(hex & 0xFF))).rounded())
        return (r << 16) | (g << 8) | b
    }
}
