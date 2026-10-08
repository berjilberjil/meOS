import SwiftUI
import AppKit

/// What the editor currently has selected, as far as a format bar cares.
struct EditorSelection: Equatable {
    /// The selection's bounding box, in the editor's own coordinate space —
    /// the clip view, which is flipped and so shares an origin with the SwiftUI
    /// frame wrapped around the editor.
    var rect: CGRect
    /// Marks carried by the *whole* selection. A part-bold selection is not
    /// bold, so the button reads unset and one press bolds all of it.
    var marks: Set<Mark>
}

/// The bridge between the AppKit editor and SwiftUI chrome around it.
///
/// The editor already understood bold, italic, strikethrough and code — ⌘B, ⌘I
/// and ⌘E have worked all along. What it had no way to do was *say so*: there
/// was nothing on screen when you selected text, so unless you knew the
/// shortcuts the formatting may as well not have existed. This publishes the
/// selection up and takes commands back down.
@MainActor
final class EditorCommands: ObservableObject {
    @Published var selection: EditorSelection?

    weak var coordinator: BlockEditor.Coordinator?

    func toggle(_ mark: Mark) { coordinator?.toggleMark(mark) }

    /// True while there is something to format.
    var hasSelection: Bool { selection != nil }
}

/// The floating format bar — bold, italic, strikethrough, code.
///
/// Deliberately four buttons. This is the bar that appears over a selection, not
/// a ribbon: block structure already has the slash menu, and a bar with ten
/// controls in it is a bar you read instead of use.
struct FormatBar: View {
    @ObservedObject var commands: EditorCommands

    /// Width is fixed so the bar can be centred over the selection without
    /// waiting for a layout pass to find out how wide it turned out.
    static let width: CGFloat = 152
    static let height: CGFloat = 34

    private struct Item: Identifiable {
        let mark: Mark
        let icon: String
        let help: String
        let key: String
        var id: String { icon }
    }

    private let items: [Item] = [
        Item(mark: .bold,   icon: "bold",          help: "Bold",          key: "⌘B"),
        Item(mark: .italic, icon: "italic",        help: "Italic",        key: "⌘I"),
        Item(mark: .strike, icon: "strikethrough", help: "Strikethrough", key: ""),
        Item(mark: .code,   icon: "chevron.left.forwardslash.chevron.right", help: "Code", key: "⌘E"),
    ]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items) { item in
                let on = commands.selection?.marks.contains(item.mark) ?? false
                Button { commands.toggle(item.mark) } label: {
                    Image(systemName: item.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 30, height: 26)
                        .foregroundStyle(on ? Accent.green.ink : Palette.text)
                        .background(on ? Palette.accent : .clear,
                                    in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(item.key.isEmpty ? item.help : "\(item.help) (\(item.key))")
                .accessibilityLabel(item.help)
            }
        }
        .padding(.horizontal, 4)
        .frame(width: Self.width, height: Self.height)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .strokeBorder(Palette.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.28), radius: 10, y: 3)
    }
}

/// Puts the bar above the selection, inside the editor's bounds.
struct FormatBarOverlay: ViewModifier {
    @ObservedObject var commands: EditorCommands

    func body(content: Content) -> some View {
        content.overlay(alignment: .topLeading) {
            GeometryReader { geo in
                if let selection = commands.selection {
                    let x = min(max(0, selection.rect.midX - FormatBar.width / 2),
                                max(0, geo.size.width - FormatBar.width))
                    // Above the selection where there is room, below it where
                    // there isn't — a bar hanging off the top of the note is a
                    // bar you cannot press.
                    let above = selection.rect.minY - FormatBar.height - 8
                    let y = above >= 0 ? above : selection.rect.maxY + 8
                    FormatBar(commands: commands)
                        .offset(x: x, y: min(y, max(0, geo.size.height - FormatBar.height)))
                        .transition(.opacity)
                }
            }
            .allowsHitTesting(commands.selection != nil)
        }
        .animation(.knFast, value: commands.selection?.rect.origin.y)
    }
}

extension View {
    /// Show the format bar over whatever this editor has selected.
    func formatBar(_ commands: EditorCommands) -> some View {
        modifier(FormatBarOverlay(commands: commands))
    }
}
