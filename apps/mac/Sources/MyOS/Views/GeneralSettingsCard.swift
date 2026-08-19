import SwiftUI

/// General app preferences card — currently the launch tab (which screen MyOS
/// opens to). Device-local via `PrefsStore`. Shared by mac + iOS; the tab list
/// is the full set on mac and just the bottom-bar tabs on iOS.
struct GeneralSettingsCard: View {
    var boxed = true
    @ObservedObject private var prefs = PrefsStore.shared

    #if os(iOS)
    private let options = NavTab.iosTabs
    #else
    private let options = NavTab.allCases
    #endif

    var body: some View {
        let inner = VStack(alignment: .leading, spacing: 6) {
            if boxed {
                SectionTitle(text: "General")
                    .padding(.bottom, 8)
            } else {
                Text("Which screen opens when you launch MyOS.")
                    .font(.system(size: 15)).foregroundStyle(Palette.muted)
                    .padding(.bottom, 8)
            }
            ForEach(Array(options.enumerated()), id: \.element.id) { i, t in
                if i > 0 { Rectangle().fill(Palette.border).frame(height: 1) }
                Button { prefs.launchTab = t } label: {
                    HStack(spacing: 12) {
                        Image(systemName: t.icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(t.tint)
                            .frame(width: 28)
                        Text(t.title).font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.text)
                        Spacer()
                        if t == prefs.launchTab {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 20)).foregroundStyle(Palette.green)
                        }
                    }
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(KPressStyle())
            }
        }
        // `boxed` off means this is already a full settings PAGE on iOS, which
        // supplies its own padding and background. Wrapping in a Card there adds
        // a second surface and shoves the content 18pt further in than the pages
        // that get this right — which is what made Settings look misaligned.
        if boxed { Card { inner } } else { inner }
    }
}
