import SwiftUI

/// Appearance picker. MyOS used to ship its own colour sets, so this card drew
/// two miniature previews of the app to choose between. Since the conversion to
/// system colours there is nothing to preview — the choice is only whether we
/// follow the OS or pin light/dark — so it is a plain segmented control, which
/// is what Settings.app uses for exactly this setting.
struct AppearanceCard: View {
    var boxed = true
    @EnvironmentObject var state: AppState
    @ObservedObject private var themeStore = ThemeStore.shared

    private var selection: Binding<String> {
        Binding(
            get: { themeStore.theme.id },
            set: { state.setTheme(AppTheme.by(id: $0)) }
        )
    }

    var body: some View {
        let inner = VStack(alignment: .leading, spacing: Gap.row) {
            if boxed { SectionTitle(text: "Appearance") }
            Picker("Appearance", selection: selection) {
                ForEach(AppTheme.all) { theme in
                    Label(theme.name, systemImage: theme.symbol).tag(theme.id)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text(hint)
                .font(.footnote)
                .foregroundStyle(Palette.muted)
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

    private var hint: String {
        #if os(macOS)
        "System follows your Mac's Appearance setting."
        #else
        "System follows your iPhone's Display setting."
        #endif
    }
}
