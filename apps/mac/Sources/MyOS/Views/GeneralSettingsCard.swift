import SwiftUI

/// General app preferences card — currently the launch tab (which screen MyOS
/// opens to). Device-local via `PrefsStore`. Shared by mac + iOS; the tab list
/// is the full set on mac and just the bottom-bar tabs on iOS.
struct GeneralSettingsCard: View {
    @ObservedObject private var prefs = PrefsStore.shared

    #if os(iOS)
    private let options = NavTab.iosTabs
    #else
    private let options = NavTab.allCases
    #endif

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(text: "General")
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Launch tab").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.text)
                        Text("Which screen MyOS opens to.").font(.system(size: 11)).foregroundStyle(Palette.faint)
                    }
                    Spacer()
                    Menu {
                        ForEach(options) { t in
                            Button { prefs.launchTab = t } label: {
                                if t == prefs.launchTab { Label(t.title, systemImage: "checkmark") }
                                else { Text(t.title) }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: prefs.launchTab.icon).font(.system(size: 12))
                            Text(prefs.launchTab.title).font(.system(size: 13, weight: .semibold))
                            Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(Palette.faint)
                        }
                        .foregroundStyle(Palette.text)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Palette.bg, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(Palette.border, lineWidth: 1))
                    }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden)
                }
            }
        }
    }
}
