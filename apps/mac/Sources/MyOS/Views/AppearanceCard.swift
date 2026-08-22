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
            HStack(spacing: 12) {
                ForEach(AppTheme.all) { preview($0) }
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
                SettingsIntro(text: "Dark or light. Changes everywhere, instantly.")
                inner
            }
        }
    }

    private func preview(_ theme: AppTheme) -> some View {
        let on = themeStore.theme.id == theme.id
        return Button { state.setTheme(theme) } label: {
            VStack(spacing: 11) {
                ZStack(alignment: .bottomTrailing) {
                    // A miniature of the app rather than three grey bars: a
                    // title, a hero card, two rows. You are choosing a look, so
                    // the preview should look like the thing.
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(theme.bg)
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 5) {
                            Capsule().fill(theme.brand).frame(width: 26, height: 5)
                            Capsule().fill(theme.border).frame(width: 12, height: 5)
                        }
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(theme.surface)
                            .frame(maxHeight: .infinity)
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 5, style: .continuous).fill(theme.surface2)
                            RoundedRectangle(cornerRadius: 5, style: .continuous).fill(theme.surface2)
                        }
                        .frame(height: 16)
                    }
                    .padding(11)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                    if on {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(theme.brand)
                            .background(Circle().fill(theme.bg).padding(2))
                            .padding(9)
                            .transition(.opacity)
                    }
                }
                .frame(height: boxed ? 96 : nil)
                .aspectRatio(boxed ? nil : 0.82, contentMode: .fit)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(on ? theme.brand : theme.border, lineWidth: on ? 2.5 : 1)
                )
                Text(theme.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(on ? Palette.text : Palette.muted)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .animation(.knFast, value: on)
        }
        .buttonStyle(KPressStyle())
        .accessibilityAddTraits(on ? .isSelected : [])
        .onHover { h in cursor(h) }
    }
}
