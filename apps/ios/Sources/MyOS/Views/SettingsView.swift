import SwiftUI

/// iOS Settings — labelled groups on the shared card surface. One rhythm
/// throughout: 22pt between sections, a 9pt gap under each label, rows on a
/// 4pt-inset card so the hairlines never crowd the rounded corners.
/// Sheets are full-height so editors aren't crushed into a medium detent.
struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var themeStore = ThemeStore.shared
    @AppStorage(BiometricLock.key) private var faceIDEnabled = false
    @State private var page: Page?
    /// How tall each sub-page's content is, keyed by page. A screen with two
    /// theme previews on it has no business covering the whole display, so the
    /// sheet is only as tall as what it contains — see `detents(for:)`.
    ///
    /// Per page, not one shared value, and never cleared on dismiss. Both of
    /// those were the same bug: the detent set is derived from this, so zeroing
    /// it the instant the sheet started leaving swapped `[.height(h), .large]`
    /// for `[.large]` mid-animation and the sheet snapped to full screen on its
    /// way out. Keeping the measurement also means the second time you open a
    /// page it is already the right size instead of resizing in front of you.
    @State private var sheetHeights: [String: CGFloat] = [:]

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
            // Not the warning colour the reset row wears. This is where things
            // come back from, which is the opposite meaning.
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
        // This is a sheet, so it is outside MainView's scroll container — it has
        // to bring its own, and its own horizontal padding, or it is a fixed
        // column of content clipped at whatever the sheet's height happens to be.
        ScrollView {
            groups
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .background(Palette.background)
        .presentationBackground(Palette.background)
        .presentationDragIndicator(.visible)
        .animation(.knTheme, value: themeStore.theme.id)
        .sheet(item: $page) { p in editorSheet(p) }
        // Heights are remembered across launches, so the next open of a page
        // already knows its size.
        .onChange(of: sheetHeights) { _, now in
            for (page, h) in now { SheetHeightCache.shared.record(page, h) }
        }
        // Arrived from the Friday report notification — open straight on it.
        //
        // Also on every later change, not just `onAppear`: if Settings was
        // already up when the notification was tapped, `showSettings = true`
        // changed nothing, `onAppear` never re-fired, and the flag stayed set —
        // so nothing happened then, and the *next* time Settings was opened for
        // something else it jumped to the weekly report unasked.
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
        .fluidPressable(scale: 0.99)
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
        .fluidPressable(scale: 0.99)
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
            Toggle("", isOn: $faceIDEnabled).labelsHidden().tint(Palette.success)
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
                        .padding(.horizontal, 16).padding(.vertical, 20)
                        .measuringSheetHeight()
                    }
                    .scrollIndicators(.hidden)
                    // Age and the API key use the number pad / no return key, so
                    // dragging the page is the way back out of them.
                    .scrollDismissesKeyboard(.interactively)
                }
            }
            .background(Palette.background)
            .navigationTitle(p.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { page = nil }.font(.body.weight(.semibold))
                        .foregroundStyle(Palette.accent)
                }
            }
        }
        .preferredColorScheme(themeStore.theme.colorScheme)
        .animation(.knTheme, value: themeStore.theme.id)
        .onPreferenceChange(SheetContentHeight.self) { h in
            guard h > 0 else { return }
            sheetHeights[p.rawValue] = min(h + Self.sheetChrome, Self.sheetCap)
        }
        .presentationDetents(detents(for: p))
        .presentationDragIndicator(.visible)
        // Scrolling a short page should not drag the sheet taller.
        .presentationContentInteraction(.scrolls)
        .presentationBackground(Palette.background)
    }

    /// Nav bar + the sheet's own top inset + the home indicator. Measured
    /// content is only the content.
    private static let sheetChrome: CGFloat = 112
    private static var sheetCap: CGFloat { UIScreen.main.bounds.height * 0.92 }

    /// Content height as the resting detent, with `.large` still available so a
    /// page you want more room on can be dragged up. A page that already needs
    /// the full screen just gets `.large` — offering both would be one detent
    /// pretending to be two.
    ///
    /// Falls back to the height this page measured on a previous launch, so the
    /// only time a settings page ever resizes itself is the very first time it
    /// is opened on a device.
    private func detents(for page: Page) -> Set<PresentationDetent> {
        let h = sheetHeights[page.rawValue] ?? SheetHeightCache.shared.height(page.rawValue) ?? 0
        guard h > 0, h < Self.sheetCap - 1 else { return [.large] }
        return [.height(h), .large]
    }
}
