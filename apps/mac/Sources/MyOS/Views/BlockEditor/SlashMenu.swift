import AppKit
import SwiftUI

struct SlashCommand: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let keywords: [String]
    let type: BlockType
    let level: Int?

    static let all: [SlashCommand] = [
        .init(id: "text", title: "Text", subtitle: "Plain paragraph", icon: "text.alignleft",
              keywords: ["text", "paragraph", "plain", "body"], type: .paragraph, level: nil),
        .init(id: "h1", title: "Heading 1", subtitle: "Big section heading", icon: "textformat.size.larger",
              keywords: ["h1", "heading", "title", "big"], type: .heading, level: 1),
        .init(id: "h2", title: "Heading 2", subtitle: "Medium heading", icon: "textformat.size",
              keywords: ["h2", "heading", "subtitle"], type: .heading, level: 2),
        .init(id: "h3", title: "Heading 3", subtitle: "Small heading", icon: "textformat.size.smaller",
              keywords: ["h3", "heading"], type: .heading, level: 3),
        .init(id: "todo", title: "To-do", subtitle: "Checkbox list", icon: "checklist",
              keywords: ["todo", "task", "check", "checkbox"], type: .todo, level: nil),
        .init(id: "bullet", title: "Bulleted list", subtitle: "Simple bullets", icon: "list.bullet",
              keywords: ["bullet", "list", "unordered"], type: .bullet, level: nil),
        .init(id: "numbered", title: "Numbered list", subtitle: "Ordered 1. 2. 3.", icon: "list.number",
              keywords: ["number", "ordered", "list"], type: .numbered, level: nil),
        .init(id: "quote", title: "Quote", subtitle: "Callout / quote", icon: "text.quote",
              keywords: ["quote", "callout", "blockquote"], type: .quote, level: nil),
        .init(id: "code", title: "Code", subtitle: "Monospace block", icon: "chevron.left.forwardslash.chevron.right",
              keywords: ["code", "mono", "snippet"], type: .code, level: nil),
        .init(id: "divider", title: "Divider", subtitle: "Horizontal rule", icon: "minus",
              keywords: ["divider", "rule", "separator", "line"], type: .divider, level: nil),
    ]
}

/// Owns the floating slash-command popover and its filtered state.
final class SlashMenuController: ObservableObject {
    @Published var filtered: [SlashCommand] = SlashCommand.all
    @Published var selectedIndex = 0
    private(set) var isActive = false
    var triggerLocation: Int?
    var query = ""
    private var onPick: ((SlashCommand) -> Void)?
    private var panel: NSPanel?

    func begin(anchor: NSRect, host: NSView, onPick: @escaping (SlashCommand) -> Void) {
        self.onPick = onPick
        self.triggerLocation = (host as? BlockTextView)?.selectedRange().location
        self.query = ""
        self.filtered = SlashCommand.all
        self.selectedIndex = 0
        self.isActive = true
        showPanel(anchor: anchor)
    }

    func updateQuery(_ q: String, anchor: NSRect) {
        query = q
        let ql = q.lowercased()
        filtered = ql.isEmpty
            ? SlashCommand.all
            : SlashCommand.all.filter { c in
                c.title.lowercased().contains(ql) || c.keywords.contains { $0.contains(ql) }
            }
        if filtered.isEmpty { dismiss(); return }
        selectedIndex = min(selectedIndex, filtered.count - 1)
        sizePanel(anchor: anchor)
    }

    func move(_ delta: Int) {
        guard !filtered.isEmpty else { return }
        selectedIndex = (selectedIndex + delta + filtered.count) % filtered.count
    }

    func commitSelection() {
        guard isActive, filtered.indices.contains(selectedIndex) else { dismiss(); return }
        let cmd = filtered[selectedIndex]
        onPick?(cmd)
    }

    func pick(_ cmd: SlashCommand) { onPick?(cmd) }

    func dismiss() {
        isActive = false
        triggerLocation = nil
        onPick = nil
        panel?.orderOut(nil)
        panel = nil
    }

    // MARK: Panel

    private func showPanel(anchor: NSRect) {
        let host = NSHostingView(rootView: SlashMenuView(controller: self))
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 280, height: 240),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .popUpMenu
        p.hasShadow = true
        p.backgroundColor = .clear
        p.isOpaque = false
        p.contentView = host
        panel = p
        sizePanel(anchor: anchor)
        p.orderFront(nil)
    }

    private func sizePanel(anchor: NSRect) {
        guard let p = panel else { return }
        let rows = min(filtered.count, 6)
        let height = CGFloat(rows) * 46 + 12
        p.setContentSize(NSSize(width: 280, height: height))
        p.setFrameTopLeftPoint(NSPoint(x: anchor.minX, y: anchor.minY - 6))
    }
}

private struct SlashMenuView: View {
    @ObservedObject var controller: SlashMenuController

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(controller.filtered.enumerated()), id: \.element.id) { i, cmd in
                        row(cmd, selected: i == controller.selectedIndex)
                            .contentShape(Rectangle())
                            .onTapGesture { controller.selectedIndex = i; controller.pick(cmd) }
                    }
                }
                .padding(6)
            }
        }
        .frame(width: 280)
        .background(Palette.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Palette.border, lineWidth: 1))
    }

    private func row(_ cmd: SlashCommand, selected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: cmd.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(selected ? .white : Palette.muted)
                .frame(width: 26, height: 26)
                .background(selected ? Palette.brand : Palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(cmd.title).font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.text)
                Text(cmd.subtitle).font(.system(size: 11)).foregroundStyle(Palette.faint)
            }
            Spacer()
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(selected ? Palette.brand.opacity(0.16) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}
