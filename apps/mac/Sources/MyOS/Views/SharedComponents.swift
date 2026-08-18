import SwiftUI

// Shared building blocks used across Settings, Journal, Fitness and Finance:
// a wrapping chip flow, tappable preset chips, the hold-to-confirm delete control
// (the "two confirmations" for sensitive data), and reusable labelled fields.

// MARK: - Flow layout (wrapping chips)

/// A simple wrapping flow — children fill a row, then wrap to the next.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var runSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for sv in subviews {
            let sz = sv.sizeThatFits(.unspecified)
            if x > 0 && x + sz.width > maxWidth {
                x = 0; y += rowHeight + runSpacing; rowHeight = 0
            }
            x += sz.width + spacing
            rowHeight = max(rowHeight, sz.height)
            widest = max(widest, x - spacing)
        }
        let width = maxWidth.isFinite ? maxWidth : widest
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let maxWidth = bounds.width
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for sv in subviews {
            let sz = sv.sizeThatFits(.unspecified)
            if x > 0 && x + sz.width > maxWidth {
                x = 0; y += rowHeight + runSpacing; rowHeight = 0
            }
            sv.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y),
                     anchor: .topLeading, proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            rowHeight = max(rowHeight, sz.height)
        }
    }
}

// MARK: - Preset chip

/// A tappable quick-add chip — soft pill with a plus affordance on hover.
struct PresetChip: View {
    let text: String
    var tint: Color = Palette.muted
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "plus").font(.system(size: 8, weight: .heavy))
                    .opacity(hover ? 1 : 0.55)
                Text(text).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            }
            .foregroundStyle(hover ? Palette.text : tint)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(hover ? Palette.surface2 : Palette.surface2.opacity(0.55), in: Capsule())
            .overlay(Capsule().strokeBorder(Palette.border, lineWidth: 1))
        }
        .buttonStyle(KPressStyle())
        .onHover { h in hover = h; cursor(h) }
    }
}

/// An editable chip (for managing preset sets in Settings) — shows the text with
/// a small remove button.
struct RemovableChip: View {
    let text: String
    var tint: Color = Palette.muted
    let remove: () -> Void
    var body: some View {
        HStack(spacing: 6) {
            Text(text).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.text).lineLimit(1)
            Button(action: remove) {
                Image(systemName: "xmark").font(.system(size: 8, weight: .heavy))
            }
            .buttonStyle(KIconButtonStyle(size: 16, color: Palette.faint))
        }
        .padding(.leading, 11).padding(.trailing, 5).padding(.vertical, 5)
        .background(tint.opacity(0.14), in: Capsule())
        .overlay(Capsule().strokeBorder(Palette.border, lineWidth: 1))
    }
}

// MARK: - Hold-to-confirm delete (two-step: open → hold)

/// A press-and-hold destructive button: a capsule that fills over `duration`;
/// if the user holds to the end it fires. Releasing early cancels. Used for
/// every sensitive delete / reset — opening the confirm is step one, holding
/// is step two.
struct HoldToConfirmButton: View {
    var label: String = "Hold to delete"
    var tint: Color = Palette.red
    var duration: Double = 1.4
    let action: () -> Void

    @State private var progress: CGFloat = 0
    @State private var holding = false
    @State private var fireTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { geo in
            let fill = holding ? max(36, geo.size.width * progress) : geo.size.width * progress
            ZStack(alignment: .leading) {
                Capsule().fill(tint.opacity(0.16))
                Capsule()
                    .fill(tint)
                    .frame(width: fill)
                HStack(spacing: 8) {
                    Image(systemName: "trash.fill").font(.system(size: 15, weight: .bold))
                    Text(holding ? "Keep holding…" : label)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                }
                .foregroundStyle(progress > 0.38 ? Color.white : tint)
                .frame(maxWidth: .infinity)
            }
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in if !holding { start() } }
                    .onEnded { _ in cancel() }
            )
            .onHover { h in cursor(h) }
        }
        .frame(height: 56)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(label)
    }

    private func start() {
        holding = true
        Haptics.tap()
        withAnimation(.linear(duration: duration)) { progress = 1 }
        fireTask?.cancel()
        fireTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            if Task.isCancelled { return }
            holding = false
            Haptics.warning()
            action()
        }
    }

    private func cancel() {
        fireTask?.cancel(); fireTask = nil
        holding = false
        withAnimation(.easeOut(duration: 0.16)) { progress = 0 }
    }
}

/// Compact confirm sheet / popover — icon, title, one line, fat hold capsule.
struct HoldDeleteCard: View {
    let title: String
    var message: String = "This can't be undone."
    var confirmLabel: String = "Hold to delete"
    var onCancel: (() -> Void)? = nil
    let onConfirm: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle().fill(Palette.red.opacity(0.14))
                Image(systemName: "trash.fill")
                    .font(.system(size: 24, weight: .semibold)).foregroundStyle(Palette.red)
            }
            .frame(width: 64, height: 64)
            .padding(.bottom, 16)
            Text(title)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Palette.text)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.system(size: 15))
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
                .padding(.bottom, 22)
            HoldToConfirmButton(label: confirmLabel, action: onConfirm)
            if let onCancel {
                Button("Cancel", action: onCancel)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Palette.muted)
                    .padding(.top, 16)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 12)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity)
        .background(Palette.bg)
    }
}

extension View {
    /// Attach a hold-to-confirm delete — compact sheet on iPhone, popover on Mac.
    /// Nothing is deleted until the capsule is held to the end.
    func holdToDelete(isPresented: Binding<Bool>, title: String,
                      message: String = "This can't be undone.",
                      confirmLabel: String = "Hold to delete",
                      action: @escaping () -> Void) -> some View {
        #if os(iOS)
        sheet(isPresented: isPresented) {
            HoldDeleteCard(title: title, message: message, confirmLabel: confirmLabel,
                           onCancel: { isPresented.wrappedValue = false }) {
                action()
                isPresented.wrappedValue = false
            }
            .presentationDetents([.height(392)])
            .presentationDragIndicator(.visible)
            .presentationBackground(Palette.bg)
        }
        #else
        popover(isPresented: isPresented, arrowEdge: .top) {
            HoldDeleteCard(title: title, message: message, confirmLabel: confirmLabel,
                           onCancel: { isPresented.wrappedValue = false }) {
                action()
                isPresented.wrappedValue = false
            }
            .frame(width: 328)
            .background(Palette.elevated)
        }
        #endif
    }
}

// MARK: - Slide to confirm (commit actions)

/// Pure drag→threshold logic for a slide-to-confirm control, split from the
/// view so it is unit-testable without SwiftUI.
struct SlideConfirmState {
    var threshold: CGFloat = 0.85
    private(set) var progress: CGFloat = 0
    private(set) var confirmed = false
    static let tickStops: [CGFloat] = [0.18, 0.36, 0.54, 0.72, 0.88]

    /// Update progress from the current drag translation and available travel.
    /// Returns how many detent ticks were newly crossed (for haptics).
    @discardableResult
    mutating func drag(translationX: CGFloat, width: CGFloat) -> Int {
        guard !confirmed else { return 0 }
        let old = progress
        progress = min(1, max(0, translationX / max(width, 1)))
        guard progress > old else { return 0 }
        return Self.tickStops.filter { old < $0 && progress >= $0 }.count
    }

    /// End the drag. Returns `true` exactly once — when released at/after the
    /// threshold. Below threshold it snaps progress back to 0.
    mutating func end() -> Bool {
        guard !confirmed else { progress = 1; return false }
        if progress >= threshold { confirmed = true; progress = 1; return true }
        progress = 0
        return false
    }

    mutating func reset() { progress = 0; confirmed = false }
}

/// A drag-to-commit control: drag the thumb to the end to fire `action`; snaps
/// back if released early; fires a success haptic on commit. The commit-side
/// counterpart to `HoldToConfirmButton` (which is destructive hold-to-delete).
struct SlideToConfirm: View {
    var label: String = "Slide to confirm"
    var tint: Color = Palette.brand
    let action: () -> Void

    @State private var state = SlideConfirmState()
    /// One size everywhere — big enough for a thumb on iPhone.
    static let height: CGFloat = 56
    private var thumb: CGFloat { Self.height }

    var body: some View {
        GeometryReader { geo in
            let travel = max(1, geo.size.width - thumb)
            ZStack(alignment: .leading) {
                Capsule().fill(tint.opacity(0.16))
                Text(state.confirmed ? "Logged" : label)
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(tint)
                    .padding(.horizontal, thumb + 8)
                    .frame(maxWidth: .infinity)
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
                Capsule().fill(tint)
                    .frame(width: thumb + state.progress * travel)
                Image(systemName: state.confirmed ? "checkmark" : "chevron.right.2")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(Palette.bg)
                    .frame(width: thumb, height: thumb)
                    .offset(x: state.progress * travel)
            }
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        let ticks: Int = {
                            var next = state
                            let n = next.drag(translationX: v.translation.width, width: travel)
                            withAnimation(.knFast) { state = next }
                            return n
                        }()
                        if ticks > 0 { Haptics.slideTicks(ticks) }
                    }
                    .onEnded { _ in
                        let fired = state.end()
                        if fired { Haptics.slideCommit(); action() }
                        else { Haptics.slideCancel(); withAnimation(.knFast) { } }
                    }
            )
            .onAppear { Haptics.prepare() }
            .onHover { h in cursor(h) }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
    }
}

// MARK: - Copy a plan day to other days

/// A "copy this day →" menu for the weekly planner: quick per-day items, "all
/// other days", and a multi-select picker. Unifies the meal + workout copy-day.
struct CopyDayMenu: View {
    let weekday: String
    let dayNames: [String]
    var disabled: Bool = false
    let copy: ([String]) -> Void
    @State private var picking = false

    var body: some View {
        Menu {
            ForEach(0..<7, id: \.self) { d in
                if String(d) != weekday { Button("Copy to \(dayNames[d])") { copy([String(d)]) } }
            }
            Divider()
            Button("Pick days…") { picking = true }
            Button("Copy to all other days") { copy(WeekdayKeys.others(except: weekday)) }
        } label: {
            Label("Copy day", systemImage: "doc.on.doc").font(.system(size: 13, weight: .semibold))
        }
        .menuStyle(.borderlessButton)
        .disabled(disabled)
        .popover(isPresented: $picking, arrowEdge: .top) {
            CopyDayPickerSheet(weekday: weekday, dayNames: dayNames, copy: copy)
        }
    }
}

/// Multi-select "copy to specific days" — a commit that overwrites the target
/// days, so it's a slide-to-confirm rather than a plain tap.
struct CopyDayPickerSheet: View {
    let weekday: String
    let dayNames: [String]
    let copy: ([String]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var picked: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Copy \(dayNames[Int(weekday) ?? 0]) to…")
                .font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundStyle(Palette.text)
            ForEach(WeekdayKeys.others(except: weekday), id: \.self) { d in
                Toggle(dayNames[Int(d) ?? 0], isOn: Binding(
                    get: { picked.contains(d) },
                    set: { if $0 { picked.insert(d) } else { picked.remove(d) } }))
                    .toggleStyle(.switch).tint(Palette.brand)
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.text)
            }
            SlideToConfirm(label: "Slide to copy", tint: Palette.brand) { copy(Array(picked)); dismiss() }
                .opacity(picked.isEmpty ? 0.4 : 1)
                .allowsHitTesting(!picked.isEmpty)
        }
        .padding(18)
        .frame(width: 300)
        .background(Palette.elevated)
    }
}

// MARK: - Reusable labelled fields (shared by Settings + editors)

/// Small uppercase field caption.
struct KFieldLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .semibold)).tracking(0.7)
            .foregroundStyle(Palette.faint)
    }
}

/// Labelled plain-text input that saves on every keystroke (binding-driven).
struct KLabeledField: View {
    let label: String
    var placeholder: String = ""
    @Binding var text: String
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            KFieldLabel(text: label)
            TextField("", text: $text,
                      prompt: Text(placeholder).foregroundColor(Palette.faint))
                .textFieldStyle(.plain).font(.system(size: 13)).foregroundStyle(Palette.text)
                .focused($focused)
                .knField(focused: focused)
        }
    }
}

/// Labelled numeric input over an optional Double — empty string clears to nil.
struct KLabeledNumberField: View {
    let label: String
    var placeholder: String = ""
    var decimals: Int = 0
    @Binding var value: Double?
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            KFieldLabel(text: label)
            TextField("", text: Binding(
                get: { Self.format(value, decimals: decimals) },
                set: { value = Self.parse($0) }),
                prompt: Text(placeholder).foregroundColor(Palette.faint))
                .textFieldStyle(.plain).font(.system(size: 13)).foregroundStyle(Palette.text)
                .monospacedDigit()
                .focused($focused)
                .knField(focused: focused)
        }
    }
    static func format(_ v: Double?, decimals: Int) -> String {
        guard let v else { return "" }
        if decimals <= 0 { return String(Int(v.rounded())) }
        let r = (v * pow(10, Double(decimals))).rounded() / pow(10, Double(decimals))
        return r == r.rounded() ? String(Int(r)) : String(format: "%.\(decimals)f", r)
    }
    static func parse(_ s: String) -> Double? {
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return nil }
        return Double(t.filter { $0.isNumber || $0 == "." })
    }
}

/// Labelled dropdown for a fixed set of choices (blood group, relationship, …) —
/// no free text, so users can only pick a valid value. A "Clear" item unsets it.
struct KLabeledMenuField: View {
    let label: String
    var placeholder: String = "Not set"
    var options: [String] = []
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            KFieldLabel(text: label)
            Menu {
                Button { text = "" } label: {
                    Label("Clear", systemImage: "xmark.circle")
                }
                Divider()
                ForEach(options, id: \.self) { option in
                    Button { text = option } label: {
                        if option == text { Label(option, systemImage: "checkmark") }
                        else { Text(option) }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(text.isEmpty ? placeholder : text)
                        .font(.system(size: 13, weight: text.isEmpty ? .regular : .semibold))
                        .foregroundStyle(text.isEmpty ? Palette.faint : Palette.text)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold)).foregroundStyle(Palette.faint)
                }
                .padding(.horizontal, 13).padding(.vertical, 10)
                .background(Palette.bg, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: 2))
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden)
        }
    }
}

/// Labelled phone input — digits only, capped at 10, so no stray letters or symbols.
struct KLabeledPhoneField: View {
    let label: String
    var placeholder: String = "10-digit mobile number"
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            KFieldLabel(text: label)
            TextField("", text: Binding(
                get: { text },
                set: { text = String($0.filter { $0.isNumber }.prefix(10)) }),
                prompt: Text(placeholder).foregroundColor(Palette.faint))
                .textFieldStyle(.plain).font(.system(size: 13)).foregroundStyle(Palette.text)
                .monospacedDigit()
                .focused($focused)
                .knField(focused: focused)
        }
    }
}

/// A validated date-of-birth field. A real date picker — no free text — so a DOB
/// can never be garbage like "qr23r23". Stores/reads a `yyyy-MM-dd` string; shows a
/// "set" affordance while empty so an unset DOB doesn't masquerade as a real date.
struct KLabeledDateField: View {
    let label: String
    @Binding var text: String

    private static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    private static let lowerBound: Date = fmt.date(from: "1900-01-01") ?? Date.distantPast
    private var parsed: Date? { Self.fmt.date(from: text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            KFieldLabel(text: label)
            if let d = parsed {
                HStack(spacing: 6) {
                    DatePicker("", selection: Binding(
                        get: { d },
                        set: { text = Self.fmt.string(from: $0) }),
                        in: Self.lowerBound...Date(), displayedComponents: .date)
                        .datePickerStyle(.compact).labelsHidden()
                    Spacer(minLength: 0)
                    Button { text = "" } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 12))
                    }
                    .buttonStyle(KIconButtonStyle(size: 20)).help("Clear date of birth")
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Palette.surface2.opacity(0.35),
                            in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: 1))
            } else {
                Button {
                    let seed = Calendar(identifier: .gregorian).date(byAdding: .year, value: -21, to: Date()) ?? Date()
                    text = Self.fmt.string(from: seed)
                } label: {
                    HStack {
                        Text("Set date of birth").foregroundStyle(Palette.faint)
                        Spacer()
                        Image(systemName: "calendar").foregroundStyle(Palette.faint)
                    }
                    .font(.system(size: 13))
                    .contentShape(Rectangle())
                }
                .buttonStyle(KPressStyle())
                .knField()
            }
        }
    }
}
