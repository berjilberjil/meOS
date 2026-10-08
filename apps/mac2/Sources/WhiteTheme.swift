import SwiftUI

/// The rebuilt Mac look, in one place: balanced white, minimal, one accent.
///
/// The palette itself stays `Palette` (DesignSystem.swift), because the shared
/// cards the iOS app draws are what this app shows too — in Light they ARE the
/// balanced-white look: white canvas, `F6F6F8` surfaces, hairlines instead of
/// shadows, dark green as the only voice. What is NEW here is the Mac chrome:
/// the shell, the tab set, and the launch defaults that pin it.
///
/// Colour still must mean something: green acts, orange warns, blue informs,
/// and nothing is decorated.
@MainActor
enum WhiteTheme {

    /// The sidebar. The iOS bar shows five tabs; the Mac adds Events as its
    /// own item because a sidebar can afford one more line and iOS reaches
    /// events one push deep. Everything else is the same map.
    static let tabs: [NavTab] = [.today, .productivity, .scan, .fitness, .notes, .events]

    private static let marker = "myos.mac2.installed"

    /// First launch of the rebuilt app pins Light. The old app's stored
    /// preference (if any) is the old look's preference; this app starts on
    /// the white canvas once, and after that whatever you pick in Settings
    /// stays picked.
    static func installDefaults() {
        let d = UserDefaults.standard
        guard !d.bool(forKey: marker) else { return }
        d.set(true, forKey: marker)
        ThemeStore.shared.set(.light)
    }
}
