import SwiftUI

/// Editor for reordering Today tab sections — opened from Settings.
struct TodayReorderEditor: View {
    @State private var sections: [TodaySection] = TodaySection.ordered()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Drag to reorder the Today tab sections.")
                .font(.system(size: 14)).foregroundStyle(Palette.muted)
                .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 12)

            List {
                ForEach(sections) { s in
                    HStack(spacing: 14) {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Palette.faint)
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(s.tint.opacity(0.18))
                            Image(systemName: s.icon)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(s.tint)
                        }
                        .frame(width: 36, height: 36)
                        Text(s.label)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Palette.text)
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(Palette.surface)
                    .listRowSeparator(.hidden)
                }
                .onMove { from, to in
                    withAnimation(.snappy) {
                        sections.move(fromOffsets: from, toOffset: to)
                        TodaySection.save(sections)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.editMode, .constant(.active))
        }
    }
}
