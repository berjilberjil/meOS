import SwiftUI

/// Editor for reordering Today sections — opened from Settings.
///
/// The iOS editor, ported. On the Mac a `List` drags to reorder on its own
/// (`onMove`), so there is no edit-mode environment to force; the rows keep
/// the same sizing and tinting as the Settings listing they were opened from.
struct TodayReorderEditor: View {
    @State private var sections: [TodaySection] = TodaySection.ordered()

    /// Row height plus its separator — the list frame is derived from this.
    private static let rowHeight: CGFloat = 53

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Drag to reorder the Today page.")
                .font(.footnote).foregroundStyle(Palette.muted)
                .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 14)

            List {
                ForEach(sections) { s in
                    HStack(spacing: 14) {
                        SettingsIcon(symbol: s.icon, tint: s.tint)
                        Text(s.label)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(Palette.text)
                        Spacer(minLength: 0)
                    }
                    .frame(height: Self.rowHeight - 1)
                    .listRowBackground(Palette.surface)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                }
                .onMove { from, to in
                    Haptics.selection()
                    withAnimation(.knPop) {
                        sections.move(fromOffsets: from, toOffset: to)
                        TodaySection.save(sections)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .frame(height: min(CGFloat(sections.count) * Self.rowHeight, 520))
        }
    }
}
