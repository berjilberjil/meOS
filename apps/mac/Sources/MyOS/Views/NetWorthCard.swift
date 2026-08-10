import SwiftUI

/// The hybrid net-worth card in Finance. Three rows are pulled live from what's
/// already tracked (portfolio value, emergency fund, gold loan) so they never drift
/// or double-count; everything else — bank cash, mom's gold, other loans — is a
/// manual line the user adds here.
struct NetWorthCard: View {
    @EnvironmentObject var state: AppState
    @State private var editTarget: NWEditTarget?

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                header
                assetsSection
                Divider().overlay(Palette.border)
                liabilitiesSection
            }
        }
        .sheet(item: $editTarget) { t in NetWorthLineEditor(target: t) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionTitle(text: "Net worth")
                Spacer()
                Text("assets − liabilities").font(.system(size: 10)).foregroundStyle(Palette.faint)
            }
            Text(Fmt.inr(state.netWorth))
                .font(.system(size: 34, weight: .heavy, design: .rounded)).monospacedDigit()
                .foregroundStyle(state.netWorth >= 0 ? Palette.text : Palette.red)
                .lineLimit(1).minimumScaleFactor(0.6)
            HStack(spacing: 14) {
                totalPill(label: "Assets", value: state.totalAssets, tint: Palette.green)
                totalPill(label: "Liabilities", value: state.totalLiabilities, tint: Palette.red)
            }
        }
    }

    private func totalPill(label: String, value: Double, tint: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(tint).frame(width: 7, height: 7)
            Text(label.uppercased()).font(.system(size: 9, weight: .heavy, design: .rounded)).tracking(0.6)
                .foregroundStyle(Palette.faint)
            Text(Fmt.inrShort(value)).font(.system(size: 12, weight: .heavy, design: .rounded)).monospacedDigit()
                .foregroundStyle(tint)
        }
    }

    // MARK: - Assets

    private var assetsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("What you own", add: { editTarget = NWEditTarget(asset: true, line: nil) })
            ForEach(state.autoAssets, id: \.0) { name, amt in
                autoRow(name: name, amount: amt, tint: Palette.green)
            }
            ForEach(state.networth.assets) { line in
                manualRow(line: line, asset: true, tint: Palette.green)
            }
            if state.autoAssets.isEmpty && state.networth.assets.isEmpty {
                emptyHint("Add bank balance, cash, gold you hold…")
            }
        }
    }

    private var liabilitiesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("What you owe", add: { editTarget = NWEditTarget(asset: false, line: nil) })
            ForEach(state.autoLiabilities, id: \.0) { name, amt in
                autoRow(name: name, amount: amt, tint: Palette.red)
            }
            ForEach(state.networth.liabilities) { line in
                manualRow(line: line, asset: false, tint: Palette.red)
            }
            if state.autoLiabilities.isEmpty && state.networth.liabilities.isEmpty {
                emptyHint("Add any other loans you're carrying…")
            }
        }
    }

    private func sectionLabel(_ text: String, add: @escaping () -> Void) -> some View {
        HStack {
            Text(text.uppercased()).font(.system(size: 10, weight: .heavy, design: .rounded)).tracking(0.7)
                .foregroundStyle(Palette.muted)
            Spacer()
            Button(action: add) { Label("Add", systemImage: "plus") }
                .buttonStyle(KGhostButtonStyle(color: Palette.brand))
        }
    }

    /// A tracked row — read-only, tagged "auto", pulled from its source tab.
    private func autoRow(name: String, amount: Double, tint: Color) -> some View {
        HStack(spacing: 10) {
            Circle().fill(tint.opacity(0.5)).frame(width: 8, height: 8)
            Text(name).font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.text)
            Text("AUTO").font(.system(size: 8, weight: .heavy, design: .rounded)).tracking(0.5)
                .foregroundStyle(Palette.faint)
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(Palette.surface2.opacity(0.6), in: Capsule())
            Spacer()
            Text(Fmt.inr(amount)).font(.system(size: 13, weight: .semibold)).monospacedDigit()
                .foregroundStyle(Palette.muted)
        }
        .padding(.vertical, 3)
    }

    /// A manual line — tap to edit, trash asks for a hold-to-confirm.
    private func manualRow(line: NetWorthLine, asset: Bool, tint: Color) -> some View {
        NetWorthLineRow(line: line, tint: tint,
                        edit: { editTarget = NWEditTarget(asset: asset, line: line) },
                        delete: { state.deleteNetWorthLine(asset: asset, line.id) })
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text).font(.system(size: 12)).foregroundStyle(Palette.faint).padding(.vertical, 3)
    }
}

/// One editable manual asset/liability row.
private struct NetWorthLineRow: View {
    let line: NetWorthLine
    let tint: Color
    let edit: () -> Void
    let delete: () -> Void
    @State private var hover = false
    @State private var showConfirm = false

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(tint).frame(width: 8, height: 8)
            Text(line.label).font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.text).lineLimit(1)
            Spacer()
            Text(Fmt.inr(line.amountInr)).font(.system(size: 13, weight: .semibold)).monospacedDigit()
                .foregroundStyle(Palette.text)
            Button { edit() } label: { Image(systemName: "pencil").font(.system(size: 11, weight: .bold)) }
                .buttonStyle(KIconButtonStyle(size: 22)).opacity(hover ? 1 : 0).help("Edit")
            Button { showConfirm = true } label: { Image(systemName: "trash").font(.system(size: 10, weight: .bold)) }
                .buttonStyle(KIconButtonStyle(size: 22, color: Palette.red)).opacity(hover ? 1 : 0).help("Delete")
                .holdToDelete(isPresented: $showConfirm, title: "Delete this line?",
                              message: "\(line.label) · \(Fmt.inr(line.amountInr)) — this can't be undone.") { delete() }
        }
        .padding(.horizontal, 6).padding(.vertical, 5)
        .background(hover ? Palette.surface2.opacity(0.5) : .clear,
                    in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { edit() }
        .onHover { h in hover = h }
        .animation(.knFast, value: hover)
    }
}

/// Identifies which line the editor sheet is working on. `line == nil` means a new one.
struct NWEditTarget: Identifiable {
    let id = UUID()
    let asset: Bool
    var line: NetWorthLine?
}

/// Add / edit a manual asset or liability line.
private struct NetWorthLineEditor: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let target: NWEditTarget

    @State private var label = ""
    @State private var amount: Double? = nil

    private var isNew: Bool { target.line == nil }
    private var noun: String { target.asset ? "asset" : "liability" }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("\(isNew ? "Add" : "Edit") \(noun)")
                .font(.system(size: 18, weight: .heavy, design: .rounded)).foregroundStyle(Palette.text)
            KLabeledField(label: "Label", placeholder: target.asset ? "Bank balance, cash, gold…" : "Personal loan, credit card…", text: $label)
            KLabeledNumberField(label: "Amount (₹)", placeholder: "0", value: $amount)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(KGhostButtonStyle())
                Button(isNew ? "Add" : "Save") { save() }
                    .buttonStyle(KPrimaryButtonStyle())
                    .disabled(label.trimmingCharacters(in: .whitespaces).isEmpty || (amount ?? 0) <= 0)
            }
        }
        .padding(24).frame(width: 400)
        .background(Palette.elevated)
        .onAppear {
            if let l = target.line { label = l.label; amount = l.amountInr }
        }
    }

    private func save() {
        let amt = amount ?? 0
        guard !label.trimmingCharacters(in: .whitespaces).isEmpty, amt > 0 else { return }
        if let l = target.line {
            state.updateNetWorthLine(asset: target.asset,
                                     NetWorthLine(id: l.id, label: label, amountInr: amt))
        } else {
            state.addNetWorthLine(asset: target.asset, label: label, amountInr: amt)
        }
        dismiss()
    }
}
