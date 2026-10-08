import SwiftUI

/// Mio is MeOS's platform-neutral companion model. It deliberately uses only
/// SwiftUI primitives so the same character and event vocabulary can ship on
/// iPhone, iPad, and macOS without a separate animation runtime.
enum MioExpression: String, CaseIterable, Identifiable {
    case peaceful, curious, focused, thinking, encouraging, proud, celebrating
    case grateful, playful, sleepy, concerned, reassuring, determined, surprised, zen

    var id: String { rawValue }
    var accessibilityLabel: String { rawValue.capitalized }
}

enum MioForm: String, CaseIterable, Identifiable {
    case companion, focusOrb, checkmark, reminderBell, calendar, progressRing, insight
    var id: String { rawValue }
}

enum MioEvent {
    case welcome(name: String)
    case taskCompleted
    case taskCreated
    case focusStarted(title: String)
    case focusCompleted
    case planning
    case reminder
    case insight(message: String)
    case reset
}

@MainActor
final class MioController: ObservableObject {
    @Published private(set) var expression: MioExpression = .peaceful
    @Published private(set) var form: MioForm = .companion
    @Published private(set) var message = "I’m here for the next small win."
    @Published var isVisible: Bool { didSet { UserDefaults.standard.set(isVisible, forKey: Self.visibleKey) } }

    private static let visibleKey = "mio.isVisible"
    private var resetTask: Task<Void, Never>?

    init() {
        isVisible = UserDefaults.standard.object(forKey: Self.visibleKey) as? Bool ?? true
    }

    func handle(_ event: MioEvent) {
        switch event {
        case let .welcome(name): set(.encouraging, .companion, "Good to see you, \(name). What would make today feel lighter?", linger: 7)
        case .taskCompleted: set(.celebrating, .checkmark, "That counts. One clear win at a time.", linger: 2.8)
        case .taskCreated: set(.encouraging, .companion, "Nice. A clear next step changes the day.", linger: 3.5)
        case let .focusStarted(title): set(.focused, .focusOrb, "I’ll keep the space clear while you focus on \(title).", linger: 8)
        case .focusCompleted: set(.proud, .checkmark, "Focus session complete. Take the win.", linger: 3.5)
        case .planning: set(.thinking, .calendar, "Let’s give your time a little more room.", linger: 4)
        case .reminder: set(.curious, .reminderBell, "A gentle nudge: your future self left this for you.", linger: 4)
        case let .insight(message): set(.curious, .insight, message, linger: 7)
        case .reset: reset()
        }
    }

    func reset() {
        resetTask?.cancel()
        expression = .peaceful
        form = .companion
        message = "I’m here for the next small win."
    }

    private func set(_ expression: MioExpression, _ form: MioForm, _ message: String, linger: Double) {
        resetTask?.cancel()
        self.expression = expression
        self.form = form
        self.message = message
        resetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(linger))
            guard !Task.isCancelled else { return }
            self?.reset()
        }
    }
}

/// Full-body, shape-shifting character. `form` changes its silhouette while
/// `expression` changes eye, mouth and motion language independently.
struct MioCharacter: View {
    let expression: MioExpression
    let form: MioForm
    var size: CGFloat = 112
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var floating = false

    private var isCelebrating: Bool { expression == .celebrating || expression == .proud }
    private var verticalOffset: CGFloat { reduceMotion ? 0 : (floating ? -5 : 5) }

    var body: some View {
        ZStack {
            glow
            if form == .progressRing {
                Circle().trim(from: 0.07, to: 0.76).stroke(Color.primary, style: .init(lineWidth: size * 0.11, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            bodyShape
                .overlay { face.padding(size * 0.21) }
                .overlay(alignment: .bottom) { arms.offset(y: size * 0.05) }
            if isCelebrating { sparks }
        }
        .frame(width: size * 1.35, height: size * 1.35)
        .offset(y: verticalOffset)
        .scaleEffect(isCelebrating && !reduceMotion ? 1.06 : 1)
        .animation(reduceMotion ? .easeOut(duration: 0.18) : .spring(response: 0.42, dampingFraction: 0.72), value: form)
        .animation(reduceMotion ? .easeOut(duration: 0.18) : .spring(response: 0.38, dampingFraction: 0.72), value: expression)
        .animation(reduceMotion ? .easeOut(duration: 0.18) : .easeInOut(duration: 2.2).repeatForever(autoreverses: true), value: floating)
        .onAppear { floating = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Mio, \(expression.accessibilityLabel)")
    }

    private var glow: some View {
        Circle().fill(Color.primary.opacity(0.10)).frame(width: size * 1.08, height: size * 1.08)
            .blur(radius: size * 0.08)
    }

    @ViewBuilder private var bodyShape: some View {
        switch form {
        case .checkmark:
            Image(systemName: "checkmark").font(.system(size: size * 0.58, weight: .black))
                .foregroundStyle(Color.white).frame(width: size, height: size).background(Color.black, in: .circle)
        case .reminderBell:
            Image(systemName: "bell.fill").font(.system(size: size * 0.56, weight: .bold))
                .frame(width: size, height: size).background(Color.primary.opacity(0.08), in: .circle)
                .rotationEffect(reduceMotion ? .zero : .degrees(expression == .curious ? -8 : 0))
        case .calendar:
            Image(systemName: "calendar").font(.system(size: size * 0.53, weight: .bold))
                .frame(width: size, height: size).background(Color.primary.opacity(0.08), in: .rect(cornerRadius: size * 0.25))
        case .focusOrb:
            Circle().fill(Color.black).overlay { Circle().stroke(Color.white.opacity(0.6), lineWidth: size * 0.035).padding(size * 0.12) }
        case .progressRing:
            Circle().fill(Color.primary.opacity(0.08))
        case .insight:
            Image(systemName: "sparkles").font(.system(size: size * 0.48, weight: .bold))
                .frame(width: size, height: size).background(Color.primary.opacity(0.08), in: .circle)
        case .companion:
            RoundedRectangle(cornerRadius: size * 0.40, style: .continuous)
                .fill(Color.black)
                .scaleEffect(x: expression == .focused ? 0.88 : 1, y: expression == .sleepy ? 0.82 : 1)
                .rotationEffect(.degrees(expression == .curious ? -5 : 0))
        }
    }

    private var face: some View {
        Group {
            if form == .companion || form == .focusOrb || form == .progressRing {
                VStack(spacing: size * 0.13) {
                    HStack(spacing: size * 0.19) {
                        eye.scaleEffect(y: expression == .sleepy || expression == .zen ? 0.18 : 1)
                        eye.scaleEffect(y: expression == .sleepy || expression == .zen ? 0.18 : 1)
                    }
                    mouth
                }
                .foregroundStyle(form == .companion || form == .focusOrb ? Color.white : Color.black)
            }
        }
    }

    private var eye: some View { Capsule().frame(width: size * 0.105, height: size * 0.15) }

    private var mouth: some View {
        Capsule().frame(width: expression == .surprised ? size * 0.13 : size * 0.25, height: expression == .surprised ? size * 0.18 : size * 0.055)
            .scaleEffect(y: expression == .concerned ? 0.8 : 1)
            .offset(y: expression == .proud || expression == .celebrating ? size * 0.02 : 0)
    }

    private var arms: some View {
        HStack(spacing: size * 0.68) {
            Capsule().frame(width: size * 0.09, height: size * 0.26).rotationEffect(.degrees(isCelebrating ? -35 : 24))
            Capsule().frame(width: size * 0.09, height: size * 0.26).rotationEffect(.degrees(isCelebrating ? 35 : -24))
        }
        .foregroundStyle(Color.black)
        .opacity(form == .companion ? 1 : 0)
    }

    private var sparks: some View {
        ForEach(0..<5, id: \.self) { index in
            Circle().fill(Color.primary).frame(width: size * 0.06, height: size * 0.06)
                .offset(x: [-0.48, -0.27, 0, 0.27, 0.48][index] * size, y: index.isMultiple(of: 2) ? -size * 0.49 : size * 0.36)
        }
    }
}

/// Reusable card for Today, macOS dashboard and future surfaces. Tapping opens
/// a small, non-judgmental check-in instead of a full-screen interruption.
struct MioCompanionCard: View {
    @EnvironmentObject private var mio: MioController
    @State private var showingCheckIn = false
    var compact = false

    var body: some View {
        if mio.isVisible {
            Button { showingCheckIn = true } label: {
                HStack(spacing: compact ? 10 : 16) {
                    MioCharacter(expression: mio.expression, form: mio.form, size: compact ? 54 : 76)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Mio").font(compact ? .subheadline.weight(.bold) : .headline)
                        Text(mio.message).font(compact ? .caption : .subheadline).foregroundStyle(Color.primary.opacity(0.55)).multilineTextAlignment(.leading).lineLimit(compact ? 2 : 3)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Color.primary.opacity(0.55))
                }
                .padding(compact ? 10 : 20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.06), in: .rect(cornerRadius: compact ? 20 : 28))
            }
            .buttonStyle(MioPressStyle())
            .sheet(isPresented: $showingCheckIn) { MioCheckIn() }
        }
    }
}

struct MioCheckIn: View {
    @EnvironmentObject private var mio: MioController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 22) {
            MioCharacter(expression: mio.expression, form: mio.form, size: 128)
            VStack(spacing: 8) {
                Text("A quick check-in").font(.title2.bold())
                Text(mio.message).multilineTextAlignment(.center).foregroundStyle(Color.primary.opacity(0.55))
            }
            VStack(spacing: 10) {
                MioChoice(title: "Help me start", symbol: "play.fill") { mio.handle(.focusStarted(title: "the next small step")); dismiss() }
                MioChoice(title: "Help me make a plan", symbol: "calendar") { mio.handle(.planning); dismiss() }
                MioChoice(title: "I need a reset", symbol: "leaf") { mio.handle(.reset); dismiss() }
            }
            Button("Hide Mio") { mio.isVisible = false; dismiss() }.font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary.opacity(0.55))
        }
        .padding(28)
        .presentationDetents([.medium])
    }
}

private struct MioChoice: View {
    let title: String
    let symbol: String
    let action: () -> Void
    var body: some View {
        Button(action: action) { Label(title, systemImage: symbol).font(.headline).frame(maxWidth: .infinity).frame(height: 52) }
            .buttonStyle(.bordered)
    }
}

private struct MioPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 1), value: configuration.isPressed)
    }
}
