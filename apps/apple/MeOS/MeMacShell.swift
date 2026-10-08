#if os(macOS)
import SwiftUI

/// The Mac's version of MeTabs. The iPhone's five tabs and its More grid become
/// one sidebar; every destination is the same Me* screen the phone shows.
struct MeMacShell: View {
    @EnvironmentObject var state: AppState
    @AppStorage("mac.space") private var selection: Space = .today
    @AppStorage("mac.sidebarCollapsed") private var collapsed = false
    @Namespace private var pill
    @Environment(\.accessibilityReduceMotion) private var reduce

    enum Space: String, CaseIterable, Identifiable {
        case today, journal, fitness, notes
        case catherine, events, watch, scan, productivity, stuff, money, macro, gallery, bin, settings
        var id: String { rawValue }

        static let main: [Space] = [.today, .journal, .fitness, .notes]
        static let more: [Space] = [.catherine, .events, .watch, .scan, .productivity, .stuff, .money, .macro, .gallery, .bin, .settings]

        var title: String {
            switch self {
            case .today: "Today"
            case .journal: "Journal"
            case .fitness: "Fitness"
            case .notes: "Notes"
            case .catherine: AgentConfig.shared.name
            case .events: "Events"
            case .watch: "Watch log"
            case .scan: "Scan"
            case .productivity: "Productivity"
            case .stuff: "Stuff"
            case .money: "Money"
            case .macro: "Macro"
            case .gallery: "Gallery"
            case .bin: "Recycle bin"
            case .settings: "Settings"
            }
        }

        var icon: String {
            switch self {
            case .today: "sun.max"
            case .journal: "book.closed"
            case .fitness: "figure.run"
            case .notes: "note.text"
            case .catherine: "sparkles"
            case .events: "calendar"
            case .watch: "play.rectangle"
            case .scan: "camera.viewfinder"
            case .productivity: "chart.bar"
            case .stuff: "shippingbox"
            case .money: "indianrupeesign"
            case .macro: "chart.line.uptrend.xyaxis"
            case .gallery: "photo.on.rectangle"
            case .bin: "trash"
            case .settings: "gearshape"
            }
        }

        @MainActor @ViewBuilder var screen: some View {
            switch self {
            case .today: MeToday()
            case .journal: MeJournal()
            case .fitness: MeFitness()
            case .notes: MeNotes()
            case .catherine: MeAssistant()
            case .events: MeEvents()
            case .watch: MeWatch()
            case .scan: MeScan()
            case .productivity: MeProductivity()
            case .stuff: MeStuff()
            case .money: MeMoney()
            case .macro: MeMacro()
            case .gallery: MeGallery()
            case .bin: MeBin()
            case .settings: MeSettings()
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: collapsed ? 76 : 240)
            Rectangle().fill(Color.hairline).frame(width: 1).ignoresSafeArea()
            NavigationStack {
                selection.screen
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
            }
            .id(selection)
            .transition(.opacity)
        }
        .background(Color.paper)
        // No window toolbar at all: screens carry their own buttons (meActions)
        // and back (MacBack), so there is no grey strip, windowed or full
        // screen, and switching tabs never changes the content's top edge.
        .toolbar(.hidden, for: .windowToolbar)
        .animation(reduce ? .easeOut(duration: 0.15) : DS.spring, value: selection)
        .animation(reduce ? nil : DS.spring, value: collapsed)
        .task { await MeTabs.refreshFeeds(into: state) }
    }

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: collapsed ? .center : .leading, spacing: 2) {
                HStack(spacing: 10) {
                    if !collapsed {
                        BigIcon(name: "circle.hexagongrid.fill", size: 13, inverted: true)
                        Text("MeOS").font(.system(size: 22, weight: .bold)).tracking(-0.5)
                            .transition(.opacity)
                        Spacer(minLength: 0)
                    }
                    Button { collapsed.toggle() } label: {
                        Image(systemName: "sidebar.left").font(.system(size: 15, weight: .semibold))
                            .frame(width: 38, height: 38).contentShape(.rect)
                    }
                    .buttonStyle(SidebarPress())
                    .keyboardShortcut("s", modifiers: [.command, .control])
                    .help(collapsed ? "Show sidebar  ⌃⌘S" : "Collapse sidebar  ⌃⌘S")
                }
                .padding(.horizontal, collapsed ? 0 : 8).padding(.bottom, 14)

                ForEach(Array(Space.main.enumerated()), id: \.element) { i, s in
                    row(s).keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
                }
                if collapsed {
                    Rectangle().fill(Color.hairline).frame(width: 28, height: 1).padding(.vertical, 12)
                } else {
                    MLabel("More").padding(.horizontal, 10).padding(.top, 14).padding(.bottom, 4)
                }
                ForEach(Space.more) { row($0) }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
        .background(Color.paper)
    }

    private func row(_ s: Space) -> some View {
        let on = selection == s
        return Button { selection = s } label: {
            HStack(spacing: 12) {
                Image(systemName: s.icon).font(.system(size: 15, weight: .semibold)).frame(width: 22)
                if !collapsed {
                    Text(s.title).font(.system(size: 15, weight: on ? .semibold : .medium)).lineLimit(1)
                        .transition(.opacity)
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, collapsed ? 0 : 12)
            .frame(width: collapsed ? 44 : nil, height: 38)
            .frame(maxWidth: collapsed ? nil : .infinity, alignment: .leading)
            .foregroundStyle(on ? Color.paper : .ink)
            .background {
                if on {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.ink)
                        .matchedGeometryEffect(id: "pill", in: pill)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(SidebarPress())
        .help(collapsed ? s.title : "")
    }
}

/// Instant feedback on mouse-down, a hover wash so the pointer always knows
/// what it is over; no colour, just the card tint the cards use.
private struct SidebarPress: ButtonStyle {
    @State private var hover = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.card.opacity(hover ? 1 : 0), in: .rect(cornerRadius: 12, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(configuration.isPressed ? .easeOut(duration: 0.1) : DS.spring, value: configuration.isPressed)
            .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
    }
}
#endif
