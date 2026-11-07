import AppKit

// MARK: - Text view

final class TackTextView: NSTextView {
    func replace(_ range: NSRange, with str: String, select: NSRange? = nil) {
        guard shouldChangeText(in: range, replacementString: str) else { return }
        textStorage?.replaceCharacters(in: range, with: str)
        didChangeText()
        if let select { setSelectedRange(select) }
    }

    // A click in the inactive panel acts right away (ticks a box on the first click)
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // Click on [ ] / [x] → check / uncheck
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let box = checkbox(at: p) {
            let inner = NSRange(location: box.location + 1, length: 1)
            let cur = (string as NSString).substring(with: inner)
            replace(inner, with: cur == " " ? "x" : " ")
            return
        }
        super.mouseDown(with: event)
    }

    private func checkbox(at p: NSPoint) -> NSRange? {
        guard let lm = layoutManager, let tc = textContainer, !string.isEmpty else { return nil }
        let ns = string as NSString
        let idx = min(characterIndexForInsertion(at: p), ns.length)
        let lineRange = ns.lineRange(for: NSRange(location: idx, length: 0))
        guard let m = MarkdownStyle.checkbox.firstMatch(in: string, range: lineRange) else { return nil }
        let box = m.range(at: 3)
        let hit = NSRange(location: m.range(at: 2).location, length: NSMaxRange(box) - m.range(at: 2).location)
        var rect = lm.boundingRect(forGlyphRange: lm.glyphRange(forCharacterRange: hit, actualCharacterRange: nil), in: tc)
        rect.origin.x += textContainerOrigin.x
        rect.origin.y += textContainerOrigin.y
        return rect.insetBy(dx: -4, dy: -3).contains(p) ? box : nil
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let c = event.charactersIgnoringModifiers?.lowercased()
        if flags == [.command, .shift], c == "l" { toggleLineStyle(.checklist); return true }
        if flags == .command, c == "b" { wrap("**"); return true }
        if flags == .command, c == "i" { wrap("*"); return true }
        return super.performKeyEquivalent(with: event)
    }

    private func wrap(_ marker: String) {
        let sel = selectedRange()
        let inner = (string as NSString).substring(with: sel)
        let m = (marker as NSString).length
        replace(sel, with: marker + inner + marker, select: NSRange(location: sel.location + m, length: sel.length))
    }

    private var commandObserver: NSObjectProtocol?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard commandObserver == nil else { return }
        commandObserver = NotificationCenter.default.addObserver(forName: .tackEditorCommand, object: nil, queue: .main) { [weak self] n in
            guard let raw = n.object as? String, let style = LineStyle(rawValue: raw) else { return }
            MainActor.assumeIsolated {
                guard let self, self.window != nil else { return }
                self.window?.makeFirstResponder(self)
                self.toggleLineStyle(style)
            }
        }
    }
}
