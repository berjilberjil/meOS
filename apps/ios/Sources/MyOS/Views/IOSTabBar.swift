import SwiftUI

/// Custom iPhone dock: Today · Fold · Fitness · Notes · Journal, with Scan
/// raised in the exact center.
struct IOSTabBar: View {
    @Binding var tab: NavTab
    let onScan: () -> Void
    var onSettings: () -> Void = {}
    var onNotesTap: () -> Void = {}
    var onFoldTap: () -> Void = {}

    private let left: [NavTab] = [.today, .fold]
    private let right: [NavTab] = [.fitness, .notes]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(left) { t in slot(t) }
            scanButton
            ForEach(right) { t in slot(t) }
        }
        .padding(.horizontal, 6)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(
            // Translucent dock — content can sit under it; material weight
            // plus a tinted wash so Light/Dark both stay readable.
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Palette.sidebar.opacity(0.78))
                .overlay(alignment: .top) { Rectangle().fill(Palette.border).frame(height: 1) }
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func slot(_ t: NavTab) -> some View {
        let on = (tab == t || (t == .fold && tab == .stuff)) && tab != .scan
        return Button {
            if t == .notes { onNotesTap() }
            else if t == .fold { onFoldTap() }
            else { tab = t }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: t.icon)
                    .font(.system(size: 18, weight: on ? .semibold : .regular))
                Text(t.title)
                    .font(.system(size: 10, weight: on ? .semibold : .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(on ? t.tint : Palette.muted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in onSettings() })
    }

    private var scanButton: some View {
        Button(action: onScan) {
            ZStack {
                Circle()
                    .fill(Palette.teal)
                    .frame(width: 46, height: 46)
                    .shadow(color: Palette.teal.opacity(0.28), radius: 6, y: 2)
                Image(systemName: "viewfinder")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
            }
            .offset(y: -10)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Scan")
        .frame(width: 52)
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in onSettings() })
    }
}
