import SwiftUI

/// Theme picker for Settings — swatch + name per theme, tap to switch. Shared by the
/// mac and iOS Settings screens.
struct AppearanceCard: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var themeStore = ThemeStore.shared

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(text: "Appearance")
                ForEach(AppTheme.all) { theme in row(theme) }
            }
        }
    }

    private func row(_ theme: AppTheme) -> some View {
        let on = themeStore.theme.id == theme.id
        return Button { state.setTheme(theme) } label: {
            HStack(spacing: 12) {
                HStack(spacing: -7) {
                    swatch(theme.bg)
                    swatch(theme.surface2)
                    swatch(theme.brand)
                }
                Text(theme.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.text)
                Spacer()
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(on ? Palette.brand : Palette.faint)
            }
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(KPressStyle())
        .onHover { h in cursor(h) }
    }

    private func swatch(_ c: Color) -> some View {
        Circle().fill(c).frame(width: 22, height: 22)
            .overlay(Circle().strokeBorder(Palette.border, lineWidth: 1.5))
    }
}
