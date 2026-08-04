import SwiftUI

/// Review-then-save. After a screenshot / statement is read, the user confirms the
/// rows here — fix an amount, change a category, drop a wrong one — then saves the
/// selected ones in one batch. Likely duplicates come in pre-unchecked.
struct TxnReviewSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    let summary: String
    let source: TxnSource
    @State var drafts: [DraftTxn]

    private var included: [DraftTxn] { drafts.filter { $0.include } }
    private var includedOut: Double {
        included.filter { $0.kind == .expense }.reduce(0) { $0 + $1.amountInr }
    }
    private var allOn: Bool { !drafts.isEmpty && drafts.allSatisfy { $0.include } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Review \(drafts.count) \(drafts.count == 1 ? "transaction" : "transactions")")
                        .font(.system(size: 18, weight: .heavy, design: .rounded)).foregroundStyle(Palette.text)
                    Spacer()
                    Button(allOn ? "Clear all" : "Select all") {
                        let target = !allOn
                        for i in drafts.indices { drafts[i].include = target }
                    }
                    .buttonStyle(KGhostButtonStyle())
                }
                if !summary.isEmpty {
                    Text(summary).font(.system(size: 12)).foregroundStyle(Palette.muted)
                }
            }
            .padding(20)

            Divider().overlay(Palette.border)

            if drafts.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach($drafts) { $d in
                            DraftRow(draft: $d,
                                     duplicate: state.isLikelyDuplicate(amount: d.amountInr, date: d.date, merchant: d.merchant))
                        }
                    }
                    .padding(16)
                }
                .frame(maxHeight: 420)
            }

            Divider().overlay(Palette.border)

            // Footer
            HStack(spacing: 12) {
                Text("\(included.count) selected · \(Fmt.inr(includedOut)) out")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.muted)
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(KGhostButtonStyle())
                Button("Save \(included.count)") {
                    state.addTransactions(included, source: source)
                    dismiss()
                }
                .buttonStyle(KPrimaryButtonStyle())
                .disabled(included.isEmpty)
                .opacity(included.isEmpty ? 0.5 : 1)
            }
            .padding(20)
        }
        .frame(width: 600)
        .background(Palette.elevated)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "text.magnifyingglass").font(.system(size: 26)).foregroundStyle(Palette.faint)
            Text("Couldn't read any transactions from that image.")
                .font(.system(size: 13)).foregroundStyle(Palette.muted)
            Text("Try a clearer, tighter crop of the transaction list.")
                .font(.system(size: 12)).foregroundStyle(Palette.faint)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
    }
}

/// One editable extracted row.
private struct DraftRow: View {
    @Binding var draft: DraftTxn
    let duplicate: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                // Include toggle
                Button { draft.include.toggle() } label: {
                    Image(systemName: draft.include ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18))
                        .foregroundStyle(draft.include ? Palette.green : Palette.faint)
                }
                .buttonStyle(KPressStyle())

                KindToggle(kind: $draft.kind)

                // Amount
                HStack(spacing: 2) {
                    Text("₹").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.faint)
                    TextField("0", value: $draft.amountInr, format: .number)
                        .textFieldStyle(.plain).monospacedDigit()
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(Palette.text).frame(width: 74)
                }
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(Palette.bg, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))

                CategoryPickerChip(category: $draft.category)

                Spacer(minLength: 0)

                if duplicate {
                    HStack(spacing: 3) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 9))
                        Text("Dupe?").font(.system(size: 10, weight: .heavy, design: .rounded))
                    }
                    .foregroundStyle(Palette.amber)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Palette.amber.opacity(0.14), in: Capsule())
                }
            }

            HStack(spacing: 10) {
                if draft.kind == .expense { QualityPicker(quality: $draft.quality) }
                Text([draft.merchant, draft.account].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 11)).foregroundStyle(Palette.faint).lineLimit(1)
                Spacer(minLength: 0)
                Text(Fmt.day(draft.date)).font(.system(size: 11)).foregroundStyle(Palette.faint)
            }
        }
        .padding(11)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(draft.include ? Palette.border : Palette.border.opacity(0.5), lineWidth: 1))
        .opacity(draft.include ? 1 : 0.55)
        .animation(.knFast, value: draft.include)
    }
}
