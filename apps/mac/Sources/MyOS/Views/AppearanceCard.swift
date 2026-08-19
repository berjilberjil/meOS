import SwiftUI

/// Theme picker — two live previews, tap to switch. Shared by mac and iOS.
/// Selection is a critically damped color settle (see `Animation.knTheme`), not
/// a view remount, so Dark ↔ Light interpolates from the on-screen colors.
struct AppearanceCard: View {
    var boxed = true
    @EnvironmentObject var state: AppState
    @ObservedObject private var themeStore = ThemeStore.shared

    var body: some View {
        let inner = VStack(alignment: .leading, spacing: 16) {
            if boxed { SectionTitle(text: "Appearance") }
            else {
                Text("Dark or light. Changes everywhere, instantly.")
                    .font(.system(size: 15)).foregroundStyle(Palette.muted)
            }
            HStack(spacing: 12) {
                ForEach(AppTheme.all) { preview($0) }
            }
        }
        // `boxed` off means this is already a full settings PAGE on iOS, which
        // supplies its own padding and background. Wrapping in a Card there adds
        // a second surface and shoves the content 18pt further in than the pages
        // that get this right — which is what made Settings look misaligned.
        if boxed { Card { inner } } else { inner }
    }

    private func preview(_ theme: AppTheme) -> some View {
        let on = themeStore.theme.id == theme.id
        return Button { state.setTheme(theme) } label: {
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(theme.bg)
                    VStack(alignment: .leading, spacing: 6) {
                        Capsule().fill(theme.brand).frame(width: 28, height: 5)
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(theme.surface)
                            .frame(height: 22)
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(theme.surface2)
                            .frame(height: 14)
                    }
                    .padding(10)
                }
                .frame(height: boxed ? 96 : 140)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(on ? theme.brand : theme.border, lineWidth: on ? 2.5 : 1)
                )
                HStack(spacing: 5) {
                    Image(systemName: on ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(on ? theme.brand : Palette.faint)
                    Text(theme.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.text)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(KPressStyle())
        .accessibilityAddTraits(on ? .isSelected : [])
        .onHover { h in cursor(h) }
    }
}
