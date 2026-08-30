import SwiftUI

// The Settings listing page is the benchmark every screen opened from it has to
// match. These are its parts, factored out — so a subpage is assembled from the
// same metrics instead of each one re-deriving them slightly differently, which
// is how nine screens end up looking like nine products.
//
// The listing page itself is deliberately NOT rewritten in terms of these: it
// already looks right, and re-expressing working layout is how it stops.

enum SettingsMetrics {
    static let tile: CGFloat = 34
    static let rowPadH: CGFloat = 12
    static let rowPadV: CGFloat = 13
    /// Between a section's label and its card.
    static let labelGap: CGFloat = 9
    /// Where a row's text starts — and therefore where its divider does.
    static var textInset: CGFloat { tile + 14 + rowPadH }
    /// Divider inset for rows with no icon.
    static let plainInset: CGFloat = 14
}

/// A settings page: labelled groups on one vertical beat.
struct SettingsPage<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: Gap.screen) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One line of orientation under a page title. Not a heading — the quietest
/// thing on the page.
struct SettingsIntro: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.footnote).foregroundStyle(Palette.muted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }
}

/// SECTION LABEL + one grouped card, with an optional footnote beneath.
struct SettingsGroup<Content: View>: View {
    var title: String? = nil
    var footer: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.labelGap) {
            if let title { SectionTitle(text: title).padding(.leading, 4) }
            Card(padding: 4) { VStack(spacing: 0) { content } }
            if let footer {
                Text(footer)
                    .font(.caption).foregroundStyle(Palette.faint)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 6)
            }
        }
    }
}

/// The hairline between rows. Starts where the row's text does, stops short of
/// the card's rounded edge.
struct SettingsDivider: View {
    var inset: CGFloat = SettingsMetrics.textInset
    var body: some View {
        Rectangle().fill(Palette.border.opacity(0.7))
            .frame(height: 1)
            .padding(.leading, inset)
            .padding(.trailing, 6)
    }
}

/// The rounded tinted square that carries a row's glyph.
struct SettingsIcon: View {
    let symbol: String
    var tint: Color = Palette.action
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous).fill(tint.opacity(0.18))
            Image(systemName: symbol)
                .font(.footnote.weight(.semibold)).foregroundStyle(tint)
        }
        .frame(width: SettingsMetrics.tile, height: SettingsMetrics.tile)
    }
}

/// Title (and optional subtitle) on the left, anything you like on the right.
/// Pass `action` to make the whole row tappable.
struct SettingsRow<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var icon: String? = nil
    var tint: Color = Palette.action
    var titleColor: Color = Palette.text
    var action: (() -> Void)? = nil
    @ViewBuilder var trailing: Trailing

    @ViewBuilder
    var body: some View {
        if let action {
            Button(action: action) { line }.buttonStyle(.plain)
        } else {
            line
        }
    }

    private var line: some View {
        HStack(spacing: 14) {
            if let icon { SettingsIcon(symbol: icon, tint: tint) }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold)).foregroundStyle(titleColor)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption).foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 10)
            trailing
        }
        .padding(.horizontal, SettingsMetrics.rowPadH)
        .padding(.vertical, SettingsMetrics.rowPadV)
        .contentShape(Rectangle())
    }
}

extension SettingsRow where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, icon: String? = nil,
         tint: Color = Palette.action, titleColor: Color = Palette.text,
         action: (() -> Void)? = nil) {
        self.init(title: title, subtitle: subtitle, icon: icon, tint: tint,
                  titleColor: titleColor, action: action, trailing: { EmptyView() })
    }
}

/// One option in a pick-exactly-one group.
struct SettingsPickRow: View {
    let title: String
    var subtitle: String? = nil
    var icon: String? = nil
    var tint: Color = Palette.action
    let selected: Bool
    let action: () -> Void

    var body: some View {
        SettingsRow(title: title, subtitle: subtitle, icon: icon,
                    tint: tint, action: action) {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.title3.weight(.semibold))
                .foregroundStyle(selected ? Palette.green : Palette.border)
                .animation(.knFast, value: selected)
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A switch row.
struct SettingsToggleRow: View {
    let title: String
    var subtitle: String? = nil
    var icon: String? = nil
    var tint: Color = Palette.action
    @Binding var isOn: Bool

    var body: some View {
        SettingsRow(title: title, subtitle: subtitle, icon: icon, tint: tint) {
            Toggle("", isOn: $isOn).labelsHidden().tint(Palette.action)
        }
    }
}

/// Label left, value right, tap anywhere on the row to edit — the iOS Settings
/// idiom. The alternative is a stack of full-width boxes, which turns a profile
/// into a registration form.
struct SettingsFieldRow: View {
    let label: String
    var placeholder: String = ""
    var numeric = false
    var monospaced = false
    var secure = false
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.callout.weight(.semibold)).foregroundStyle(Palette.text)
                .layoutPriority(1)
            Spacer(minLength: 12)
            field
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 16, design: monospaced ? .monospaced : .default))
                .foregroundStyle(focused ? Palette.action : Palette.muted)
                .focused($focused)
                #if os(iOS)
                .keyboardType(numeric ? .numberPad : .default)
                .autocorrectionDisabled(monospaced)
                .textInputAutocapitalization(monospaced ? .never : .sentences)
                .submitLabel(.done)
                #endif
        }
        .padding(.horizontal, SettingsMetrics.rowPadH)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
    }

    @ViewBuilder
    private var field: some View {
        if secure {
            SecureField("", text: $text, prompt: Text(placeholder).foregroundColor(Palette.faint))
        } else {
            TextField("", text: $text, prompt: Text(placeholder).foregroundColor(Palette.faint))
        }
    }
}

/// A short multi-line field that stays a card row rather than becoming a wall.
/// SwiftUI's `TextEditor` has no prompt, so the empty state is drawn on top —
/// otherwise an empty one is just a large blank rectangle.
struct SettingsTextArea: View {
    var placeholder: String = ""
    var minHeight: CGFloat = 96
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .font(.subheadline).foregroundStyle(Palette.text)
                .scrollContentBackground(.hidden)
                .frame(minHeight: minHeight)
                .focused($focused)
            if text.isEmpty {
                Text(placeholder)
                    .font(.subheadline).foregroundStyle(Palette.faint)
                    .padding(.top, 8).padding(.leading, 5)
                    .allowsHitTesting(false)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
    }
}

/// Compact, actionable, and not the loudest thing on the page. Used for the
/// real error strings the stores hand back, which are often a sentence of
/// framework prose — hence the line cap.
struct SettingsNotice: View {
    let text: String
    var tint: Color = Palette.attention
    var icon: String = "exclamationmark.triangle.fill"
    var actionLabel: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.footnote.weight(.bold)).foregroundStyle(tint)
                .padding(.top, 1)
            Text(text)
                .font(.footnote).foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let actionLabel, let action {
                Button(actionLabel, action: action).buttonStyle(.borderless)
            }
        }
        .padding(12)
        .background(tint.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(tint.opacity(0.28), lineWidth: 1))
    }
}

/// Reports how tall a sheet's content actually is, so the sheet can be that
/// tall instead of always taking the whole screen.
struct SheetContentHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

extension View {
    /// Measures this view and publishes its height as `SheetContentHeight`.
    func measuringSheetHeight() -> some View {
        background(
            GeometryReader { geo in
                Color.clear.preference(key: SheetContentHeight.self, value: geo.size.height)
            }
        )
    }
}

/// Remembers how tall each settings sub-page measured, so opening one does not
/// have to guess.
///
/// The sheet's resting detent is its content's height, which is only knowable
/// after the content has been laid out — so the first paint of a page had to
/// happen at some other size and then resize. Worse, the height was reset to
/// zero the moment the sheet started dismissing, which swapped the detent set
/// out from under an in-flight animation and snapped the sheet to full screen
/// on its way off screen. That was the jerk.
///
/// Caching per page fixes both ends: a page you have opened before opens at the
/// right size immediately, and nothing about a page's height changes while it is
/// leaving. Persisted because a measurement is worth keeping across launches —
/// it is only geometry, and a stale one self-corrects on the next layout.
@MainActor
final class SheetHeightCache {
    static let shared = SheetHeightCache()

    private let key = "myos.sheetHeights"
    private var heights: [String: CGFloat]

    private init() {
        let raw = UserDefaults.standard.dictionary(forKey: key) as? [String: Double] ?? [:]
        heights = raw.mapValues { CGFloat($0) }
    }

    func height(_ page: String) -> CGFloat? {
        guard let h = heights[page], h > 0 else { return nil }
        return h
    }

    /// Ignores zero — a view that has not been laid out yet reports 0, and
    /// storing that would teach the cache the one value it must never return.
    func record(_ page: String, _ height: CGFloat) {
        guard height > 0, heights[page] != height else { return }
        heights[page] = height
        UserDefaults.standard.set(heights.mapValues { Double($0) }, forKey: key)
    }
}
