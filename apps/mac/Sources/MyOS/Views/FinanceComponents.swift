import SwiftUI

// Small reusable finance controls, shared by FinanceView, the review sheet, and
// the portfolio tracker. Colourful and tactile, matching the design language.

/// A category's icon in its colour, in a soft rounded tile.
struct CategoryBadge: View {
    let category: String
    var size: CGFloat = 32
    var body: some View {
        Image(systemName: CatStyle.icon(category))
            .font(.system(size: size * 0.42, weight: .bold))
            .foregroundStyle(CatStyle.color(category))
            .frame(width: size, height: size)
            .background(CatStyle.color(category).opacity(0.15),
                        in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
    }
}

/// A compact category dropdown chip.
struct CategoryPickerChip: View {
    @Binding var category: String
    var body: some View {
        Menu {
            ForEach(Categories.all, id: \.self) { c in
                Button { category = c } label: { Label(CatStyle.label(c), systemImage: CatStyle.icon(c)) }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: CatStyle.icon(category))
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(CatStyle.color(category))
                Text(CatStyle.label(category))
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.text)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold)).foregroundStyle(Palette.faint)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(Palette.surface2.opacity(0.6),
                        in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 1))
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
    }
}

/// Three tap-to-pick chips for the useless / useful / investment read. Tapping
/// the active one clears it (nil).
struct QualityPicker: View {
    @Binding var quality: TxnQuality?
    var body: some View {
        HStack(spacing: 5) {
            ForEach(TxnQuality.allCases, id: \.self) { q in
                let on = quality == q
                Button { quality = on ? nil : q } label: {
                    HStack(spacing: 4) {
                        Image(systemName: q.icon).font(.system(size: 9, weight: .bold))
                        Text(q.short).font(.system(size: 11, weight: .heavy, design: .rounded))
                    }
                    .foregroundStyle(on ? .white : q.color)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(on ? q.color : q.color.opacity(0.14), in: Capsule())
                }
                .buttonStyle(KPressStyle())
            }
        }
    }
}

/// A read-only quality tag for transaction rows.
struct QualityTag: View {
    let quality: TxnQuality
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: quality.icon).font(.system(size: 8, weight: .bold))
            Text(quality.short).font(.system(size: 10, weight: .heavy, design: .rounded))
        }
        .foregroundStyle(quality.color)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(quality.color.opacity(0.15), in: Capsule())
    }
}

/// A tiny OUT/IN pill that toggles the transaction direction.
struct KindToggle: View {
    @Binding var kind: TxnKind
    var body: some View {
        Button { kind = kind == .expense ? .income : .expense } label: {
            Text(kind == .expense ? "OUT" : "IN")
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .foregroundStyle(kind == .expense ? Palette.red : Palette.green)
                .frame(width: 34)
                .padding(.vertical, 6)
                .background((kind == .expense ? Palette.red : Palette.green).opacity(0.15), in: Capsule())
        }
        .buttonStyle(KPressStyle())
    }
}
