import SwiftUI

/// Mac Settings — the iOS settings screen, ported.
///
/// Same labelled groups on the shared card surface, same rhythm: a 9pt gap
/// under each label, rows on a 4pt-inset card so the hairlines never crowd
/// the rounded corners. The sub-pages open as plain sheets on the Mac; the
/// phone's detent-height machinery is iOS-only and has no place here.
struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var themeStore = ThemeStore.shared
    @AppStorage(BiometricLock.key) private var biometricEnabled = false
    @State private var page: Page?

    /// Icon tile, and the divider inset that lines up with the text beside it.
    private let tile: CGFloat = 34
    private var textInset: CGFloat { tile + 14 + 12 }

    private enum Page: String, Identifiable {
        case you, appearance, launch, reminders, assistant, memory, keys, reorder, data, calendar, weekly, activity, trash
        var id: String { rawValue }
        var title: String {
            switch self {
            case .calendar: return "Day calendar"
            case .you: return "You"
            case .appearance: return "Look"
            case .launch: return "Open on"
            case .reminders: return "Reminders"
            case .assistant: return "Catherine"
            case .memory: return "Memory"
            case .keys: return "AI keys"
            case .reorder: return "Reorder Today"
            case .data: return "Data & resets"
            case .weekly: return "Weekly report"
            case .activity: return "Activity tracking"
            case .trash: return "Recycle bin"
            }
        }
        var icon: String {
            switch self {
            case .calendar: return "calendar"
            case .you: return "person.fill"
            case .appearance: return "circle.lefthalf.filled"
            case .launch: return "square.grid.2x2.fill"
            case .reminders: return "bell.fill"
            case .assistant: return "sparkles"
            case .memory: return "brain.head.profile"
            case .keys: return "key.fill"
            case .reorder: return "arrow.up.arrow.down"
            case .data: return "trash.fill"
            case .weekly: return "chart.line.uptrend.xyaxis"
            case .activity: return "timer"
            case .trash: return "arrow.uturn.backward.circle.fill"
            }
        }
        var tint: Color {
            switch self {
            case .calendar: return Palette.blue
            case .you: return Palette.success
            case .appearance: return Palette.information
            case .launch: return Palette.blue
            case .reminders: return Palette.attention
            case .assistant: return Palette.green
            case .memory: return Palette.success
            case .keys: return Palette.activity
            case .reorder: return Palette.information
            case .data: return Palette.warning
            case .weekly: return Palette.attention
            case .activity: return Palette.activity
            // Not the warning colour the reset row wears. This is where
            // things come back from, which is the opposite meaning.
            case .trash: return Palette.action
            }
        }
    }

    @ObservedObject private var signals = UISignals.shared

    private func consumeWeeklySignal() {
        guard signals.openWeeklyReport else { return }
        signals.openWeeklyReport = false
        page = .weekly
    }

    var body: some View {
        ScrollView {
            groups
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
        .background(Palette.background)
        .animation(.knTheme, value: themeStore.theme.id)
        .sheet(item: $page) { p in editorSheet(p) }
        // Arrived from the Friday report notification — open straight on it.
        // Also on every later change, not just `onAppear`: if Settings was
        // already up when the notification was tapped, `onAppear` never
        // re-fired and the flag stayed set.
        .onAppear { consumeWeeklySignal() }
        .onChange(of: signals.openWeeklyReport) { _, _ in consumeWeeklySignal() }
    }

    private var groups: some View {
        VStack(alignment: .leading, spacing: Gap.screen) {
            ScreenTitle(text: "Settings").padding(.leading, 2)

            youCard

            section("App") {
                row(.calendar); divider
                row(.reorder); divider
                row(.appearance); divider
                row(.launch); divider
                row(.weekly); divider
                row(.activity); divider
                row(.reminders)
            }

            section("Advanced") { MacroEntryCard(boxed: false).padding(10) }

            section("Assistant") {
                row(.assistant); divider
                row(.memory); divider
                row(.keys)
            }

            if BiometricLock.isAvailable {
                section("Security") { lockRow }
            }

            section("Data") {
                row(.trash); divider
                row(.data)
            }

            signOutButton
        }
    }

    // MARK: - Pieces

    private var youCard: some View {
        Button { page = .you } label: {
            Card(padding: 16) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle().fill(Palette.success.opacity(0.18))
                        Image(systemName: "person.fill")
                            .font(.title3.weight(.semibold)).foregroundStyle(Palette.success)
                    }
                    .frame(width: 50, height: 50)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(state.profile.name.isEmpty
                             ? (state.username.isEmpty ? "You" : "@\(state.username)")
                             : state.profile.name)
                            .font(.body.weight(.semibold)).foregroundStyle(Palette.text)
                        Text(state.profile.role.isEmpty ? "Name, city, what you do" : state.profile.role)
                            .font(.footnote).foregroundStyle(Palette.muted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold)).foregroundStyle(Palette.faint)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionTitle(text: title).padding(.leading, 4)
            Card(padding: 4) {
                VStack(spacing: 0) { content() }
            }
        }
    }

    private func row(_ p: Page) -> some View {
        Button { page = p } label: {
            HStack(spacing: 14) {
                iconTile(p.icon, p.tint)
                Text(p.title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(p == .data ? Palette.warning : Palette.text)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold)).foregroundStyle(Palette.faint)
            }
            .padding(.horizontal, 12).padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var lockRow: some View {
        HStack(spacing: 14) {
            iconTile("lock.fill", Palette.information)
            VStack(alignment: .leading, spacing: 2) {
                Text("Lock with \(BiometricLock.biometryName)")
                    .font(.callout.weight(.semibold)).foregroundStyle(Palette.text)
                Text("Ask every time the app opens.")
                    .font(.caption).foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: $biometricEnabled).labelsHidden().tint(Palette.success)
        }
        .padding(.horizontal, 12).padding(.vertical, 11)
    }

    private func iconTile(_ symbol: String, _ tint: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous).fill(tint.opacity(0.18))
            Image(systemName: symbol).font(.footnote.weight(.semibold)).foregroundStyle(tint)
        }
        .frame(width: tile, height: tile)
    }

    /// Starts where the row's text does, stops short of the card's rounded edge.
    private var divider: some View {
        Rectangle().fill(Palette.border.opacity(0.7))
            .frame(height: 1)
            .padding(.leading, textInset)
            .padding(.trailing, 6)
    }

    private var signOutButton: some View {
        Button { Task { await state.logout() } } label: {
            Text("Sign out")
                .font(.callout.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered).controlSize(.large).frame(maxWidth: .infinity)
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
                            case .calendar: DayDetailView()
                            case .you: PersonDetailsEditor()
                            case .appearance: AppearanceCard(boxed: false)
                            case .launch: GeneralSettingsCard(boxed: false)
                            case .reminders: NotificationsCard(boxed: false)
                            case .assistant: AgentSettingsCard(boxed: false)
                            case .memory: MemoryCard(boxed: false)
                            case .keys: AIProvidersCard(boxed: false)
                            case .weekly: WeeklyReportCard(boxed: false)
                            case .activity: ActivitySettingsCard()
                            case .trash: TrashView(boxed: false)
                            case .data: DataManagementCard(boxed: false)
                            case .reorder: EmptyView()
                            }
                        }
                        .padding(.horizontal, 20).padding(.vertical, 24)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .background(Palette.background)
            .navigationTitle(p.title)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { page = nil }.font(.body.weight(.semibold))
                        .foregroundStyle(Palette.accent)
                }
            }
        }
        .preferredColorScheme(themeStore.theme.colorScheme)
        .animation(.knTheme, value: themeStore.theme.id)
        .frame(minWidth: 560, minHeight: 420)
    }
}
