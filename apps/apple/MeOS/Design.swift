import SwiftUI

// Monochrome system. Everything is black/white; hierarchy comes from size, weight and opacity.
enum DS {
    static let radius: CGFloat = 28
    static let pad: CGFloat = 20
    static let gap: CGFloat = 14
    /// Apple default: critically damped, no overshoot.
    static let spring = Animation.spring(response: 0.35, dampingFraction: 1)
    /// Only for momentum-driven moments (flicks, completions).
    static let bouncy = Animation.spring(response: 0.4, dampingFraction: 0.8)
}

extension Color {
    static let ink = Color.primary
    #if os(iOS)
    static let paper = Color(uiColor: .systemBackground)
    #else
    /// Pure black / pure white, like the phone, not the Mac's grey window colour.
    static let paper = Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .black : .white })
    #endif
    static let card = Color.primary.opacity(0.06)
    static let hairline = Color.primary.opacity(0.1)
    static let dim = Color.primary.opacity(0.5)
}

// Feedback on touch-down, instant; release springs back.
struct PressStyle: ButtonStyle {
    var scale: CGFloat = 0.96
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(configuration.isPressed ? .easeOut(duration: 0.1) : DS.spring, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressStyle {
    static var press: PressStyle { PressStyle() }
}

struct MCard<Content: View>: View {
    var inverted = false
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(DS.pad)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(inverted ? Color.paper : .ink)
            .background(inverted ? Color.ink : Color.card, in: .rect(cornerRadius: DS.radius))
    }
}

struct BigIcon: View {
    let name: String
    var size: CGFloat = 26
    var inverted = false
    var body: some View {
        Image(systemName: name)
            .font(.system(size: size, weight: .semibold))
            .frame(width: size * 2.1, height: size * 2.1)
            .foregroundStyle(inverted ? Color.paper : .ink)
            .background(inverted ? Color.ink : Color.card, in: .rect(cornerRadius: size * 0.7))
    }
}

struct Title: View {
    let text: String
    var sub: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let sub { Text(sub.uppercased()).font(.caption.weight(.semibold)).tracking(1.2).foregroundStyle(Color.dim) }
            Text(text).font(.system(size: 40, weight: .bold)).tracking(-0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct Stat: View {
    let value: String
    let label: String
    var big = false
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: big ? 52 : 30, weight: .bold, design: .rounded)).tracking(-1)
                .contentTransition(.numericText())
            Text(label).font(.subheadline.weight(.medium)).opacity(0.55)
        }
    }
}

struct Ring: View {
    let progress: Double
    var width: CGFloat = 10
    var color: Color = .ink
    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.15), lineWidth: width)
            Circle().trim(from: 0, to: min(progress, 1))
                .stroke(color, style: .init(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(DS.spring, value: progress)
    }
}

struct Bar: View {
    let progress: Double
    var body: some View {
        GeometryReader { g in
            Capsule().fill(Color.hairline)
                .overlay(alignment: .leading) {
                    Capsule().fill(Color.ink).frame(width: max(8, g.size.width * min(progress, 1)))
                }
        }
        .frame(height: 10)
        .animation(DS.spring, value: progress)
    }
}

struct MButton: View {
    let title: String
    var icon: String?
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label { Text(title) } icon: { if let icon { Image(systemName: icon) } }
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity).frame(height: 62)
                .foregroundStyle(Color.paper)
                .background(Color.ink, in: .rect(cornerRadius: 22))
        }
        .buttonStyle(.press)
    }
}

struct Chip: View {
    let text: String
    var on = false
    var body: some View {
        Text(text).font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16).frame(height: 40)
            .foregroundStyle(on ? Color.paper : .ink)
            .background(on ? Color.ink : Color.card, in: .capsule)
            .animation(DS.spring, value: on)
    }
}

/// Screen scaffold: big title, generous spacing, content scrolls.
struct Screen<Content: View>: View {
    let title: String
    var sub: String?
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.gap) {
                #if os(macOS)
                MacBack()
                #endif
                Title(text: title, sub: sub).padding(.bottom, 8)
                content
            }
            .padding(.horizontal, DS.pad).padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .toolbarTitleDisplayMode(.inline)
    }
}

/// Staggered, springy entrance used once per card.
struct Appear: ViewModifier {
    let index: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduce
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduce ? 0 : 24)
            .onAppear {
                withAnimation(DS.spring.delay(Double(index) * 0.05)) { shown = true }
            }
    }
}

extension View {
    func appear(_ i: Int) -> some View { modifier(Appear(index: i)) }
}

struct MField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    var secure = false
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.title3.weight(.semibold)).frame(width: 28)
            Group { if secure { SecureField(placeholder, text: $text) } else { TextField(placeholder, text: $text) } }
                .font(.title3).textInputAutocapitalization(.never).autocorrectionDisabled()
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 20).frame(height: 64)
        .background(Color.card, in: .rect(cornerRadius: 22))
    }
}

/// A tappable card row: big icon, title, optional detail, chevron.
struct Row: View {
    let icon: String
    let title: String
    var detail: String?
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon).font(.title2.weight(.semibold)).frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title3.weight(.semibold)).lineLimit(1)
                if let detail { Text(detail).font(.subheadline).foregroundStyle(Color.dim).lineLimit(2) }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.headline).foregroundStyle(Color.dim)
        }
        .padding(DS.pad).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card, in: .rect(cornerRadius: DS.radius))
        .contentShape(.rect)
    }
}

struct MLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased()).font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(Color.dim).padding(.top, 10)
    }
}

/// Big −/value/+ control.
struct BigStepper: View {
    let label: String
    let value: String
    let minus: () -> Void
    let plus: () -> Void
    var body: some View {
        HStack {
            Text(label).font(.headline)
            Spacer()
            Button(action: minus) { Image(systemName: "minus").font(.headline).frame(width: 44, height: 44).background(Color.hairline, in: .circle) }
            Text(value).font(.title3.bold()).monospacedDigit().frame(minWidth: 64).contentTransition(.numericText())
            Button(action: plus) { Image(systemName: "plus").font(.headline).frame(width: 44, height: 44).background(Color.hairline, in: .circle) }
        }
        .buttonStyle(.press)
    }
}

/// Empty state: one big icon and a line.
struct Empty: View {
    let icon: String
    let text: String
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 44, weight: .light))
            Text(text).font(.headline).foregroundStyle(Color.dim).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 50)
    }
}

extension View {
    /// Zoom out of the tapped card on iPhone. A Mac window pushes in place instead.
    @ViewBuilder
    func zoomFrom(_ id: some Hashable, in ns: Namespace.ID) -> some View {
        #if os(iOS)
        navigationTransition(.zoom(sourceID: id, in: ns))
        #else
        self
        #endif
    }
}

// MARK: - Screen actions

extension View {
    /// A screen's own buttons. iPhone: the navigation bar, as before. Mac: the
    /// top-right corner of the screen itself — the Mac window has no toolbar,
    /// so nothing grey appears above the content and tabs never jump.
    func meActions<A: View>(@ViewBuilder _ actions: () -> A) -> some View {
        #if os(iOS)
        toolbar { ToolbarItemGroup(placement: .primaryAction) { actions() } }
        #else
        overlay(alignment: .topTrailing) {
            HStack(spacing: 8) { actions() }
                .buttonStyle(MacActionStyle())
                .padding(.top, 22).padding(.trailing, DS.pad)
        }
        #endif
    }

    /// iPhone: the system search bar. Mac: put a `MeSearchField` in `meActions`.
    func meSearchable(text: Binding<String>) -> some View {
        #if os(iOS)
        searchable(text: text)
        #else
        self
        #endif
    }
}

#if os(macOS)
/// Round card-tinted icon button, the Mac twin of the phone's bar buttons.
struct MacActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .frame(minWidth: 38, minHeight: 38)
            .background(Color.card, in: .circle)
            .contentShape(.circle)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(configuration.isPressed ? .easeOut(duration: 0.1) : DS.spring, value: configuration.isPressed)
    }
}

struct MeSearchField: View {
    @Binding var text: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.dim)
            TextField("Search", text: $text).textFieldStyle(.plain).font(.system(size: 14))
        }
        .padding(.horizontal, 14).frame(width: 220, height: 38)
        .background(Color.card, in: .capsule)
    }
}

/// Back for a pushed screen. The window has no toolbar, so the screen carries it.
struct MacBack: View {
    @Environment(\.isPresented) private var isPresented
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        if isPresented {
            Button { dismiss() } label: { Image(systemName: "chevron.left") }
                .buttonStyle(MacActionStyle())
                .keyboardShortcut("[", modifiers: .command)
                .help("Back  ⌘[")
        }
    }
}
#endif
