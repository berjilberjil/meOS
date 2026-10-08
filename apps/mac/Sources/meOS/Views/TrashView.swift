import SwiftUI

/// The recycle bin.
///
/// Everything deleted anywhere in meOS lands here and waits thirty days. Two
/// buttons per row, and they mean opposite things, so they do not look alike:
/// restore is the accent and quiet, delete-forever is the warning colour and
/// goes through the same hold-to-confirm gate as every other irreversible thing
/// in the app.
///
/// Grouped by kind rather than shown as one flat list of everything. A bin is
/// something you open looking for a specific thing you just lost — "the note",
/// "that photo" — and scanning one section of four beats scanning a mixed list
/// of forty.
struct TrashView: View {
    @EnvironmentObject var state: AppState
    var boxed = true

    /// ONE confirmation state for both destructive actions.
    ///
    /// `holdToDelete` is a `.sheet(isPresented:)` on iOS, and two of those on the
    /// same view is the SwiftUI trap `EventsView` already documents — only one of
    /// them ever presents. So the two gates share a modifier and differ by case.
    private enum Confirm: Equatable {
        case purge(TrashEntry)
        case empty
    }
    @State private var confirming: Confirm?
    /// A restore that could not read its own payload. Rare, and worth saying out
    /// loud rather than having the button appear to do nothing.
    @State private var problem: String?

    private var entries: [TrashEntry] { state.liveTrash }

    private var groups: [(kind: TrashKind, items: [TrashEntry])] {
        Dictionary(grouping: entries, by: \.kind)
            .map { (kind: $0.key, items: $0.value) }
            .sorted { $0.kind.rank < $1.kind.rank }
    }

    var body: some View {
        Group {
            if boxed { Card { inner } } else { inner }
        }
        .holdToDelete(
            isPresented: Binding(get: { confirming != nil },
                                 set: { if !$0 { confirming = nil } }),
            title: confirmTitle,
            message: confirmMessage,
            confirmLabel: confirmLabel
        ) {
            switch confirming {
            case .purge(let e): state.purgeFromTrash(e)
            case .empty:        state.emptyTrash()
            case nil:           break
            }
            confirming = nil
        }
    }

    private var confirmTitle: String {
        switch confirming {
        case .purge(let e): return "Delete \(e.displayTitle) forever?"
        case .empty:        return "Empty the bin?"
        case nil:           return "Delete forever?"
        }
    }

    private var confirmMessage: String {
        switch confirming {
        case .purge:
            return "This one skips the remaining days. It cannot be undone."
        case .empty:
            let n = entries.count
            return "Deletes all \(n) item\(n == 1 ? "" : "s") for good, including any photos they are holding on to."
        case nil:
            return "This can't be undone."
        }
    }

    private var confirmLabel: String {
        if case .empty = confirming { return "Hold to empty" }
        return "Hold to delete"
    }

    private var inner: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(Palette.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if entries.isEmpty {
                empty
            } else {
                ForEach(groups, id: \.kind) { group in
                    section(group.kind, group.items)
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            if boxed { SectionTitle(text: "Recycle bin") }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(entries.isEmpty
                     ? "Anything you delete waits here for \(TrashRetention.days) days."
                     : "\(entries.count) item\(entries.count == 1 ? "" : "s"), kept for \(TrashRetention.days) days from the day you deleted them.")
                    .font(.footnote).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if !entries.isEmpty {
                    Button("Empty") { confirming = .empty }
                        .font(.footnote.weight(.semibold))
                        .buttonStyle(.plain)
                        .foregroundStyle(Palette.warning)
                }
            }
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Nothing in the bin.")
                .font(.footnote.weight(.semibold)).foregroundStyle(Palette.muted)
            Text("Delete a note, an event, a photo — it turns up here rather than going.")
                .font(.caption2).foregroundStyle(Palette.faint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 14)
    }

    // MARK: - A section per kind

    private func section(_ kind: TrashKind, _ items: [TrashEntry]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(items.count == 1 ? kind.label : kind.plural)
                    .font(.caption.weight(.semibold)).foregroundStyle(Palette.muted)
                Text("\(items.count)")
                    .font(.caption2.weight(.bold)).monospacedDigit()
                    .foregroundStyle(Palette.faint)
            }
            .padding(.leading, 2)

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 {
                        Rectangle().fill(Palette.border.opacity(0.7))
                            .frame(height: 1).padding(.leading, 46)
                    }
                    row(entry)
                }
            }
            .background(Palette.background, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 1))
        }
    }

    private func row(_ e: TrashEntry) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint(e.kind).opacity(0.18))
                Image(systemName: e.kind.symbol)
                    .font(.caption.weight(.semibold)).foregroundStyle(tint(e.kind))
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(e.displayTitle)
                    .font(.footnote.weight(.semibold)).foregroundStyle(Palette.text)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    if !e.subtitle.isEmpty {
                        Text(e.subtitle).lineLimit(1)
                        Text("·")
                    }
                    Text(TrashRetention.deletedPhrase(e, todayKey: state.todayKey))
                    Text("·")
                    // The number that is actually load-bearing — it is the only
                    // thing on the row telling you how long you have to change
                    // your mind, so it is the only thing on the row with colour.
                    Text(TrashRetention.remainingPhrase(e, todayKey: state.todayKey))
                        .foregroundStyle(urgent(e) ? Palette.warning : Palette.faint)
                }
                .font(.caption2).foregroundStyle(Palette.faint)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button { restore(e) } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.caption.weight(.bold)).foregroundStyle(Palette.action)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Put it back")

            Button { confirming = .purge(e) } label: {
                Image(systemName: "trash")
                    .font(.caption.weight(.bold)).foregroundStyle(Palette.warning)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Delete it now, for good")
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
    }

    /// The last three days get the warning colour. Before that the number is
    /// information; after that it is a deadline.
    private func urgent(_ e: TrashEntry) -> Bool {
        TrashRetention.daysLeft(e, todayKey: state.todayKey) <= 3
    }

    private func restore(_ e: TrashEntry) {
        problem = nil
        guard state.restoreFromTrash(e) else {
            problem = "\(e.displayTitle) couldn't be read back, so it has been left in the bin rather than lost."
            return
        }
    }

    /// Colour carries meaning here, so it is the module's own colour rather than
    /// twelve decorative hues.
    private func tint(_ kind: TrashKind) -> Color {
        switch kind {
        case .note:          return Palette.information
        case .event:         return Palette.blue
        case .progressPhoto: return Palette.attention
        case .belonging:     return Palette.activity
        case .todo:          return Palette.success
        case .watch:         return Palette.action
        case .scan:          return Palette.information
        case .chatThread:    return Palette.green
        case .program:       return Palette.activity
        case .exercise:      return Palette.success
        case .food:          return Palette.attention
        }
    }
}
