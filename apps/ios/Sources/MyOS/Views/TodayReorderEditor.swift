import SwiftUI

/// Editor for reordering Today tab sections — opened from Settings.
///
/// One handle per row: `List` in edit mode already draws a grip on the trailing
/// edge, so the custom leading one was a second handle for the same gesture.
/// Rows are sized and tinted like the Settings listing they were opened from.
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
                    .listRowSeparatorTint(Palette.border.opacity(0.7))
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
            .environment(\.editMode, .constant(.active))
            // A List is greedy, which would make this sheet full height whatever
            // is in it. Asking for exactly the rows lets the sheet be the size of
            // the list — capped, so a longer list scrolls instead of overflowing.
            .frame(height: min(CGFloat(sections.count) * Self.rowHeight, 520))
        }
    }
}
