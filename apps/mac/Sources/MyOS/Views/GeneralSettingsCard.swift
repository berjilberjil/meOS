import SwiftUI

/// General app preferences card — where MyOS opens. The first option is to
/// resume, which is the default; picking a tab pins every launch to it instead.
/// Device-local via `PrefsStore`. Shared by mac + iOS; the tab list is the full
/// set on mac and just the bottom-bar tabs on iOS.
struct GeneralSettingsCard: View {
    var boxed = true
    @ObservedObject private var prefs = PrefsStore.shared

    #if os(iOS)
    private let options = NavTab.iosTabs
    #else
    private let options = NavTab.allCases
    #endif

    @ViewBuilder
    private func boxedRow(title: String, icon: String, tint: Color,
                          selected: Bool, divider: Bool, action: @escaping () -> Void) -> some View {
        if divider { Rectangle().fill(Palette.border).frame(height: 1) }
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 28)
                Text(title).font(.body.weight(.semibold)).foregroundStyle(Palette.text)
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3).foregroundStyle(Palette.green)
                }
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        let inner = VStack(alignment: .leading, spacing: 6) {
            SectionTitle(text: "General").padding(.bottom, 8)
            boxedRow(title: "Where I left off", icon: "arrow.uturn.backward",
                     tint: Palette.success, selected: prefs.launchTab == nil, divider: false) {
                prefs.launchTab = nil
            }
            ForEach(options) { t in
                boxedRow(title: t.title, icon: t.icon, tint: t.tint,
                         selected: t == prefs.launchTab, divider: true) {
                    prefs.launchTab = t
                }
            }
        }
        if boxed {
            Card { inner }
        } else {
            SettingsPage {
                SettingsIntro(text: "Where MyOS opens. Resuming also reopens what you had open — the note you were writing, not just the screen it was on.")
                SettingsGroup {
                    SettingsPickRow(title: "Where I left off", icon: "arrow.uturn.backward",
                                    tint: Palette.success, selected: prefs.launchTab == nil) {
                        Haptics.selection()
                        prefs.launchTab = nil
                    }
                    ForEach(options) { t in
                        SettingsDivider()
                        SettingsPickRow(title: t.title, icon: t.icon, tint: t.tint,
                                        selected: t == prefs.launchTab) {
                            Haptics.selection()
                            prefs.launchTab = t
                        }
                    }
                }
            }
        }
    }
}
