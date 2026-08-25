import SwiftUI

// Navigation icons.
//
// This file used to hold ten hand-drawn "cartoon" glyphs from the Duolingo-era
// skin — a yellow sun, a gold coin, a blue book, a red-capped pen — each with
// its own palette and, in two cases, its own gradient. Ten differently-coloured
// icons in one rail is most of what made MyOS read as a set of unrelated
// widgets, so they are gone.
//
// An icon is now an SF Symbol that inherits its colour from the call site:
// muted white at rest, green when the tab is active. `NavTab` already names the
// symbol, so there is one source of truth for that too.

/// A nav tab's icon. Deliberately colourless — whoever draws it decides whether
/// this tab is the active one.
struct NavGlyph: View {
    let tab: NavTab
    var size: CGFloat = 26
    var body: some View {
        Image(systemName: tab.icon)
            .font(.system(size: size * 0.68, weight: .medium))
            .frame(width: size, height: size)
    }
}

/// The empty-state mark on Notes. One symbol, one weight, no colour of its own.
struct NoteGlyph: View {
    var s: CGFloat = 64
    var body: some View {
        Image(systemName: "note.text")
            .font(.system(size: s * 0.8, weight: .light))
            .foregroundStyle(Palette.faint)
            .frame(width: s, height: s)
    }
}
