import SwiftUI

/// iOS Settings — one grouped list, same card language as Today / Fitness.
/// Sheets are full-height so editors aren't crushed into a medium detent.
struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var themeStore = ThemeStore.shared
    @AppStorage(BiometricLock.key) private var faceIDEnabled = false
    @State private var page: Page?

    private enum Page: String, Identifiable {
        case you, appearance, launch, reminders, assistant, keys, reorder
        var id: String { rawValue }
        var title: String {
            switch self {
            case .you: return "You"
            case .appearance: return "Look"
            case .launch: return "Open on"
            case .reminders: return "Reminders"
            case .assistant: return "Catherine"
            case .keys: return "AI keys"
            case .reorder: return "Reorder Today"
            }
        }
        var icon: String {
            switch self {
            case .you: return "person.fill"
            case .appearance: return "circle.lefthalf.filled"
            case .launch: return "square.grid.2x2.fill"
            case .reminders: return "bell.fill"
            case .assistant: return "sparkles"
            case .keys: return "key.fill"
            case .reorder: return "arrow.up.arrow.down"
            }
        }
        var tint: Color {
            switch self {
            case .you: return Palette.teal
            case .appearance: return Palette.purple
            case .launch: return Palette.blue
            case .reminders: return Palette.amber
            case .assistant: return Palette.green
            case .keys: return Palette.flame
            case .reorder: return Palette.ice
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Settings").font(.system(size: 28, weight: .semibold)).foregroundStyle(Palette.text)

            youCard

            group {
                row(.reorder)
                divider
                row(.appearance)
                divider
                row(.launch)
                divider
                row(.reminders)
            }

            group {
                row(.assistant)
                divider
                row(.keys)
            }

            if BiometricLock.isAvailable { lockCard }

            signOutButton
        }
        .animation(.knTheme, value: themeStore.theme.id)
        .sheet(item: $page) { p in editorSheet(p) }
    }

    private var youCard: some View {
        Button { page = .you } label: {
            Card(padding: 18) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle().fill(Palette.teal.opacity(0.18))
                        Image(systemName: "person.fill")
                            .font(.system(size: 22, weight: .semibold)).foregroundStyle(Palette.teal)
                    }
                    .frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(state.profile.name.isEmpty
                             ? (state.username.isEmpty ? "You" : "@\(state.username)")
                             : state.profile.name)
                            .font(.system(size: 18, weight: .semibold)).foregroundStyle(Palette.text)
                        Text(state.profile.role.isEmpty ? "Name, city, what you do" : state.profile.role)
                            .font(.system(size: 14)).foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.faint)
                }
            }
        }
        .buttonStyle(KPressStyle())
    }

    private func group<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        Card(padding: 6) {
            VStack(spacing: 0) { content() }
        }
    }

    private func row(_ p: Page) -> some View {
        Button { page = p } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(p.tint.opacity(0.18))
                    Image(systemName: p.icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(p.tint)
                }
                .frame(width: 36, height: 36)
                Text(p.title).font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.text)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.faint)
            }
            .padding(.horizontal, 10).padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(KPressStyle())
    }

    private var divider: some View {
        Rectangle().fill(Palette.border).frame(height: 1).padding(.leading, 60)
    }

    private var lockCard: some View {
        Card(padding: 16) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.ice.opacity(0.2))
                    Image(systemName: "lock.fill").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.ice)
                }
                .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Lock with \(BiometricLock.biometryName)")
                        .font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.text)
                    Text("Ask every time the app opens.")
                        .font(.system(size: 13)).foregroundStyle(Palette.muted)
                }
                Spacer()
                Toggle("", isOn: $faceIDEnabled).labelsHidden().tint(Palette.teal)
            }
        }
    }

    private var signOutButton: some View {
        Button { Task { await state.logout() } } label: {
            Text("Sign out")
                .font(.system(size: 17, weight: .semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(KSecondaryButtonStyle(fullWidth: true))
        .padding(.top, 4)
    }

    @ViewBuilder
    private func editorSheet(_ p: Page) -> some View {
        NavigationStack {
            Group {
                if p == .reorder {
                    TodayReorderEditor()
                } else {
                    ScrollView {
                        Group {
                            switch p {
                            case .you: PersonDetailsEditor()
                            case .appearance: AppearanceCard(boxed: false)
                            case .launch: GeneralSettingsCard(boxed: false)
                            case .reminders: NotificationsCard(boxed: false)
                            case .assistant: AgentSettingsCard(boxed: false)
                            case .keys: AIProvidersCard(boxed: false)
                            case .reorder: EmptyView()
                            }
                        }
                        .padding(20)
                    }
                }
            }
            .background(Palette.bg.ignoresSafeArea())
            .navigationTitle(p.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { page = nil }.font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(themeStore.theme.brand)
                }
            }
        }
        .preferredColorScheme(themeStore.theme.colorScheme)
        .animation(.knTheme, value: themeStore.theme.id)
        .presentationDetents([.large])
        .presentationBackground(Palette.bg)
    }
}
