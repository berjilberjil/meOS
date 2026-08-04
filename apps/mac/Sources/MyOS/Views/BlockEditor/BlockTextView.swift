import AppKit

/// The single editing surface. Overrides key input for block behaviors and draws
/// per-block decorations (bullets, numbers, checkboxes, quote bars, code bg, rules)
/// in the gutter that paragraph indents leave free.
final class BlockTextView: NSTextView {
    weak var coordinator: BlockEditor.Coordinator?
    var placeholderText: String = ""
    private var checkboxRects: [(NSRect, String)] = []

    // MARK: Key input

    override func insertText(_ string: Any, replacementRange: NSRange) {
        super.insertText(string, replacementRange: replacementRange)
        if let s = string as? String, s == "/" {
            coordinator?.slashTyped()
        }
    }

    override func insertNewline(_ sender: Any?) {
        if coordinator?.handleReturn() == true { return }
        super.insertNewline(sender)
    }

    override func deleteBackward(_ sender: Any?) {
        if coordinator?.handleBackspace() == true { return }
        super.deleteBackward(sender)
    }

    override func keyDown(with event: NSEvent) {
        if coordinator?.slash.isActive == true {
            switch event.keyCode {
            case 126: coordinator?.moveSlash(-1); return   // up
            case 125: coordinator?.moveSlash(1); return    // down
            case 36, 76: coordinator?.commitSlash(); return // return / enter
            case 48: coordinator?.commitSlash(); return     // tab
            case 53: coordinator?.dismissSlash(); return    // esc
            default: break
            }
        }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), !event.modifierFlags.contains(.option),
           let ch = event.charactersIgnoringModifiers?.lowercased() {
            switch ch {
            case "b": coordinator?.toggleMark(.bold); return true
            case "i": coordinator?.toggleMark(.italic); return true
            case "e": coordinator?.toggleMark(.code); return true
            default: break
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        for (rect, id) in checkboxRects where rect.insetBy(dx: -5, dy: -5).contains(p) {
            coordinator?.toggleChecked(blockID: id)
            return
        }
        super.mouseDown(with: event)
    }

    // MARK: Caret geometry (for the slash popover)

    func caretRectOnScreen() -> NSRect {
        guard let lm = layoutManager, let tc = textContainer else { return .zero }
        let len = textStorage?.length ?? 0
        let loc = min(selectedRange().location, len)
        let glyph = lm.glyphIndexForCharacter(at: loc)
        var rect = lm.lineFragmentRect(forGlyphAt: min(glyph, max(0, lm.numberOfGlyphs - 1)), effectiveRange: nil)
        if len == 0 { rect = NSRect(x: 0, y: 0, width: 1, height: 22) }
        rect.origin.x += textContainerOrigin.x
        rect.origin.y += textContainerOrigin.y
        let inWindow = convert(rect, to: nil)
        return window?.convertToScreen(inWindow) ?? inWindow
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        drawBlockBackgrounds()
        super.draw(dirtyRect)
        drawBlockDecorations()
        drawPlaceholder()
    }

    private func drawPlaceholder() {
        guard (textStorage?.length ?? 0) == 0, !placeholderText.isEmpty else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15),
            .foregroundColor: EditorTheme.faint,
        ]
        placeholderText.draw(at: NSPoint(x: textContainerOrigin.x + 5, y: textContainerOrigin.y + 1),
                             withAttributes: attrs)
    }

    private func drawBlockBackgrounds() {
        enumerateParagraphs { type, _, _, rect, _ in
            let o = self.textContainerOrigin
            let r = rect.offsetBy(dx: o.x, dy: o.y)
            switch type {
            case .code:
                let box = NSRect(x: 4, y: r.minY - 3, width: self.bounds.width - 8, height: r.height + 6)
                let path = NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6)
                EditorTheme.surface2.setFill(); path.fill()
            case .quote:
                let bar = NSRect(x: o.x + 3, y: r.minY, width: 3, height: max(r.height, 18))
                let path = NSBezierPath(roundedRect: bar, xRadius: 1.5, yRadius: 1.5)
                EditorTheme.brand.withAlphaComponent(0.8).setFill(); path.fill()
            default: break
            }
        }
    }

    private func drawBlockDecorations() {
        checkboxRects.removeAll()
        enumerateParagraphs { type, attrs, firstLine, _, number in
            let o = self.textContainerOrigin
            let line = firstLine.offsetBy(dx: o.x, dy: o.y)
            switch type {
            case .bullet:
                let dot = NSRect(x: o.x + 8, y: line.midY - 2.5, width: 5, height: 5)
                EditorTheme.text.setFill()
                NSBezierPath(ovalIn: dot).fill()
            case .numbered:
                let s = "\(number)."
                let a: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 15, weight: .regular),
                    .foregroundColor: EditorTheme.muted,
                ]
                let size = s.size(withAttributes: a)
                s.draw(at: NSPoint(x: o.x + EditorMetrics.listGutter - size.width - 6, y: line.minY),
                       withAttributes: a)
            case .todo:
                let checked = (attrs[.todoChecked] as? Bool) ?? false
                let box = NSRect(x: o.x + 5, y: line.midY - EditorMetrics.checkboxSize / 2,
                                 width: EditorMetrics.checkboxSize, height: EditorMetrics.checkboxSize)
                let path = NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4)
                if checked {
                    EditorTheme.brand.setFill(); path.fill()
                    let check = NSBezierPath()
                    check.move(to: NSPoint(x: box.minX + 4, y: box.midY + 0.5))
                    check.line(to: NSPoint(x: box.midX - 1, y: box.minY + 4.5))
                    check.line(to: NSPoint(x: box.maxX - 3.5, y: box.maxY - 4))
                    check.lineWidth = 1.8
                    check.lineCapStyle = .round; check.lineJoinStyle = .round
                    NSColor.white.setStroke(); check.stroke()
                } else {
                    EditorTheme.faint.setStroke(); path.lineWidth = 1.5; path.stroke()
                }
                let id = attrs[.blockID] as? String ?? ""
                self.checkboxRects.append((box, id))
            case .divider:
                let y = line.midY
                let rule = NSBezierPath()
                rule.move(to: NSPoint(x: 6, y: y))
                rule.line(to: NSPoint(x: self.bounds.width - 6, y: y))
                rule.lineWidth = 1
                EditorTheme.border.setStroke(); rule.stroke()
            default: break
            }
        }
    }

    /// Walk every paragraph, handing back its block type, attributes, first-line rect,
    /// full rect, and (for numbered lists) its 1-based index in the run.
    private func enumerateParagraphs(_ body: (BlockType, [NSAttributedString.Key: Any], NSRect, NSRect, Int) -> Void) {
        guard let storage = textStorage, let lm = layoutManager, let tc = textContainer, storage.length > 0 else { return }
        let ns = storage.string as NSString
        var paras: [(NSRange, NSRange)] = []
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byParagraphs) { _, subRange, enclosing, _ in
            paras.append((subRange, enclosing))
        }
        var numberCounter = 0
        for (subRange, enclosing) in paras {
            let readAt = subRange.length > 0 ? subRange.location : max(0, min(enclosing.location, storage.length - 1))
            let attrs = storage.attributes(at: readAt, effectiveRange: nil)
            let type = BlockType(rawValue: attrs[.blockType] as? String ?? "paragraph") ?? .paragraph
            if type == .numbered { numberCounter += 1 } else { numberCounter = 0 }
            let glyphRange = lm.glyphRange(forCharacterRange: enclosing, actualCharacterRange: nil)
            let full = lm.boundingRect(forGlyphRange: glyphRange, in: tc)
            let firstLine = lm.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
            body(type, attrs, firstLine, full, numberCounter)
        }
    }
}
