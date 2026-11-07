import AppKit
import SwiftUI

// MARK: - Markdown styling

enum MarkdownStyle {
    static var fontSize: CGFloat { CGFloat(Prefs.fontSize) }
    static var baseFont: NSFont { font(size: fontSize) }

    /// Font for the chosen family (system, serif, rounded, mono)
    static func font(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        let design: NSFontDescriptor.SystemDesign
        switch Prefs.fontFamily {
        case "serif": design = .serif
        case "rounded": design = .rounded
        case "mono": design = .monospaced
        default: return base
        }
        guard let desc = base.fontDescriptor.withDesign(design) else { return base }
        return NSFont(descriptor: desc, size: size) ?? base
    }

    static let paragraph: NSParagraphStyle = {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = 3
        p.paragraphSpacing = 3
        return p
    }()

    static var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: baseFont, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph]
    }

    private static func re(_ p: String) -> NSRegularExpression {
        RegexFactory.make(p, options: [.anchorsMatchLines])
    }

    static let heading = re(#"^(#{1,3})[ \t]+.*$"#)
    static let bullet = re(#"^[ \t]*([-*+]|\d+\.)[ \t]"#)
    static let checkbox = re(#"^([ \t]*)([-*+] )(\[[ xX]\])(.*)$"#)
    static let quote = re(#"^>.*$"#)
    static let bold = re(#"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#)
    static let italic = re(#"(?<![\*\w])([*_])(?=[^\s*_])([^*_\n]+?)(?<=\S)\1(?![\*\w])"#)
    static let code = re(#"`[^`\n]+`"#)
    static let tag = re(#"(?<![\p{L}\p{N}_#/&])#([\p{L}\p{N}_-]*\p{L}[\p{L}\p{N}_-]*)"#)
    static let listPrefix = RegexFactory.make(#"^([ \t]*)(?:([-*+]) \[[ xX]\] |([-*+]) |(\d+)\. )"#)
    static let detector = RegexFactory.linkDetector

    private static func addTrait(_ trait: NSFontTraitMask, _ ts: NSTextStorage, _ range: NSRange) {
        ts.enumerateAttribute(.font, in: range) { val, r, _ in
            let f = (val as? NSFont) ?? baseFont
            ts.addAttribute(.font, value: NSFontManager.shared.convert(f, toHaveTrait: trait), range: r)
        }
    }

    /// Everything one styling pass needs.
    private struct Pass {
        let ts: NSTextStorage
        let string: String
        let full: NSRange
        let simple: Bool
        let dim = NSColor.secondaryLabelColor.withAlphaComponent(0.55)
        let accent = NSColor.controlAccentColor
        let hidden: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 0.1), .foregroundColor: NSColor.clear]

        func matches(_ re: NSRegularExpression) -> [NSTextCheckingResult] { re.matches(in: string, range: full) }
        /// Markers such as `**` or `#`: dimmed in Markdown mode, invisible in Simple mode.
        var markers: [NSAttributedString.Key: Any] { simple ? hidden : [.foregroundColor: dim] }
    }

    static func highlight(_ ts: NSTextStorage) {
        let s = ts.string
        let pass = Pass(ts: ts, string: s, full: NSRange(location: 0, length: (s as NSString).length),
                        simple: Prefs.editorMode == "simple")
        ts.beginEditing()
        ts.setAttributes(baseAttributes, range: pass.full)
        styleHeadings(pass)
        styleLists(pass)
        styleInline(pass)
        styleTagsRemindersLinks(pass)
        ts.endEditing()
    }

    private static func styleHeadings(_ p: Pass) {
        for m in p.matches(heading) {
            let level = m.range(at: 1).length
            p.ts.addAttribute(.font, value: font(size: fontSize + [0, 7, 3, 1][level], weight: .bold), range: m.range)
            let marker = NSRange(location: m.range(at: 1).location, length: level + (p.simple ? 1 : 0))
            p.ts.addAttributes(p.markers, range: marker)
        }
    }

    private static func styleLists(_ p: Pass) {
        for m in p.matches(bullet) {
            let marker = m.range(at: 1)
            if p.simple, marker.length == 1 {
                p.ts.addAttributes([.foregroundColor: NSColor.clear, .tackBullet: true, .kern: fontSize * 0.5], range: marker)
            } else {
                p.ts.addAttribute(.foregroundColor, value: p.accent, range: marker)
            }
        }
        for m in p.matches(checkbox) {
            let box = m.range(at: 3)
            let checked = (p.string as NSString).substring(with: box).lowercased() == "[x]"
            if p.simple {
                // "- [ ]" becomes invisible and a circle is drawn instead (TackLayoutManager)
                let prefix = NSRange(location: m.range(at: 2).location, length: NSMaxRange(box) - m.range(at: 2).location)
                p.ts.removeAttribute(.tackBullet, range: prefix)
                p.ts.removeAttribute(.kern, range: prefix)
                p.ts.addAttributes([.foregroundColor: NSColor.clear, .tackCheckbox: checked], range: prefix)
            } else {
                p.ts.addAttribute(.foregroundColor, value: p.dim, range: m.range(at: 2))
                p.ts.addAttributes([
                    .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .bold),
                    .foregroundColor: checked ? NSColor.secondaryLabelColor : p.accent
                ], range: box)
            }
            if checked {
                p.ts.addAttributes([
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                    .foregroundColor: NSColor.secondaryLabelColor
                ], range: m.range(at: 4))
            }
        }
        for m in p.matches(quote) {
            p.ts.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: m.range)
            addTrait(.italicFontMask, p.ts, m.range)
        }
    }

    private static func styleInline(_ p: Pass) {
        for (regex, trait) in [(bold, NSFontTraitMask.boldFontMask), (italic, .italicFontMask)] {
            for m in p.matches(regex) {
                addTrait(trait, p.ts, m.range(at: 2))
                let len = m.range(at: 1).length
                p.ts.addAttributes(p.markers, range: m.range(at: 1))
                p.ts.addAttributes(p.markers, range: NSRange(location: NSMaxRange(m.range) - len, length: len))
            }
        }
        for m in p.matches(code) {
            p.ts.addAttributes([
                .font: NSFont.monospacedSystemFont(ofSize: fontSize - 1.5, weight: .regular),
                .backgroundColor: NSColor.quaternaryLabelColor
            ], range: m.range)
        }
    }

    private static func styleTagsRemindersLinks(_ p: Pass) {
        for m in p.matches(tag) {
            p.ts.addAttributes([.foregroundColor: p.accent, .backgroundColor: p.accent.withAlphaComponent(0.12)], range: m.range)
        }
        let now = Date()
        for m in p.matches(ReminderParser.regex) {
            guard let date = ReminderParser.date(from: m, in: p.string as NSString, now: now) else { continue }
            let line = (p.string as NSString).lineRange(for: m.range)
            let done = ReminderParser.checkedLine.firstMatch(in: p.string, range: line) != nil
            let future = date > now && !done
            p.ts.addAttributes([
                .foregroundColor: future ? NSColor.systemOrange : NSColor.tertiaryLabelColor,
                .backgroundColor: future ? NSColor.systemOrange.withAlphaComponent(0.14) : NSColor.clear,
                .toolTip: "🔔 " + date.formatted(date: .complete, time: .shortened)
            ], range: m.range)
        }
        for m in detector.matches(in: p.string, range: p.full) {
            if let url = m.url { p.ts.addAttribute(.link, value: url, range: m.range) }
        }
    }
}

// MARK: - Simple mode: drawn checklist circles and bullets

extension NSAttributedString.Key {
    static let tackCheckbox = NSAttributedString.Key("tackCheckbox") // Bool: checked?
    static let tackBullet = NSAttributedString.Key("tackBullet")
}

extension Notification.Name {
    /// object = LineStyle.rawValue (formatting toolbar)
    static let tackEditorCommand = Notification.Name("TackEditorCommand")
}

enum LineStyle: String { case title, checklist, bullet, numbered }

final class TackLayoutManager: NSLayoutManager {
    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        guard let ts = textStorage, let tc = textContainers.first else { return }
        let chars = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)

        func rect(_ r: NSRange) -> NSRect {
            boundingRect(forGlyphRange: glyphRange(forCharacterRange: r, actualCharacterRange: nil), in: tc)
                .offsetBy(dx: origin.x, dy: origin.y)
        }

        ts.enumerateAttribute(.tackCheckbox, in: chars) { val, r, _ in
            guard let checked = val as? Bool else { return }
            let box = rect(r)
            let cfg = NSImage.SymbolConfiguration(pointSize: MarkdownStyle.fontSize * 1.1, weight: .regular)
                .applying(.init(paletteColors: checked ? [.white, .controlAccentColor] : [.secondaryLabelColor]))
            guard let img = NSImage(systemSymbolName: checked ? "checkmark.circle.fill" : "circle",
                                    accessibilityDescription: nil)?.withSymbolConfiguration(cfg) else { return }
            let sz = img.size
            img.draw(in: NSRect(x: box.minX + 1, y: box.midY - sz.height / 2, width: sz.width, height: sz.height),
                     from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        ts.enumerateAttribute(.tackBullet, in: chars) { val, r, _ in
            guard val != nil else { return }
            let b = rect(r)
            let dot = NSAttributedString(string: "•", attributes: [
                .font: NSFont.systemFont(ofSize: MarkdownStyle.fontSize * 1.35, weight: .regular),
                .foregroundColor: NSColor.labelColor,
            ])
            let sz = dot.size()
            dot.draw(at: NSPoint(x: b.minX + 1, y: b.midY - sz.height / 2))
        }
    }
}

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

    /// Toolbar / ⇧⌘L: applies a style to the selected lines (or removes it when already there).
    func toggleLineStyle(_ style: LineStyle) {
        let ns = string as NSString
        var lr = ns.lineRange(for: selectedRange())
        if lr.length > 0, ns.substring(with: NSRange(location: NSMaxRange(lr) - 1, length: 1)) == "\n" { lr.length -= 1 }
        let lines = ns.substring(with: lr).components(separatedBy: "\n")

        func split(_ line: String) -> (indent: String, rest: String) {
            let indent = String(line.prefix { $0 == " " || $0 == "\t" })
            return (indent, String(line.dropFirst(indent.count)))
        }
        func styleOf(_ rest: String) -> LineStyle? {
            if rest.range(of: #"^[-*+] \[[ xX]\]"#, options: .regularExpression) != nil { return .checklist }
            if rest.range(of: #"^[-*+] "#, options: .regularExpression) != nil { return .bullet }
            if rest.range(of: #"^\d+\. "#, options: .regularExpression) != nil { return .numbered }
            if rest.range(of: #"^#{1,6}\s"#, options: .regularExpression) != nil { return .title }
            return nil
        }
        let allSame = lines.allSatisfy { styleOf(split($0).rest) == style }
        var n = 0
        let out = lines.map { line -> String in
            var (indent, rest) = split(line)
            if let r = rest.range(of: #"^(?:[-*+] \[[ xX]\] ?|[-*+] |\d+\. |#{1,6}\s+)"#, options: .regularExpression) {
                rest.removeSubrange(r)
            }
            if allSame { return indent + rest }
            n += 1
            let prefix: String
            switch style {
            case .title: prefix = "# "; indent = ""
            case .checklist: prefix = "- [ ] "
            case .bullet: prefix = "- "
            case .numbered: prefix = "\(n). "
            }
            return indent + prefix + rest
        }.joined(separator: "\n")
        replace(lr, with: out, select: NSRange(location: lr.location + (out as NSString).length, length: 0))
    }

    // MARK: Simple mode — hidden prefixes

    private static let hiddenPrefixRe = RegexFactory.make(
        #"^[ \t]*((?:[-*+] \[[ xX]\] ?)|(?:[-*+] )|(?:#{1,3}[ \t]+))"#)

    /// Range of the hidden prefix (checkbox, bullet, #) on the line containing `loc`, in Simple mode.
    func hiddenPrefix(atLineOf loc: Int) -> (start: Int, end: Int, lineStart: Int)? {
        guard Prefs.editorMode == "simple" else { return nil }
        let ns = string as NSString
        let lr = ns.lineRange(for: NSRange(location: min(loc, ns.length), length: 0))
        guard let m = Self.hiddenPrefixRe.firstMatch(in: string, range: lr) else { return nil }
        let r = m.range(at: 1)
        return (r.location, NSMaxRange(r), lr.location)
    }

    /// ⌫ right after a hidden checkbox / bullet removes it (like Notes).
    func deleteHiddenPrefixIfNeeded() -> Bool {
        let sel = selectedRange()
        guard sel.length == 0, let p = hiddenPrefix(atLineOf: sel.location), sel.location == p.end else { return false }
        replace(NSRange(location: p.start, length: p.end - p.start), with: "", select: NSRange(location: p.start, length: 0))
        return true
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

    /// ↩ in a list continues it; ↩ on an empty item ends the list.
    func continueList() -> Bool {
        let ns = string as NSString
        let sel = selectedRange()
        guard sel.length == 0 else { return false }
        let lineRange = ns.lineRange(for: NSRange(location: sel.location, length: 0))
        let before = ns.substring(with: NSRange(location: lineRange.location, length: sel.location - lineRange.location))
        let bns = before as NSString
        guard let m = MarkdownStyle.listPrefix.firstMatch(in: before, range: NSRange(location: 0, length: bns.length)) else { return false }

        let fullLine = ns.substring(with: lineRange).trimmingCharacters(in: .newlines)
        let prefix = bns.substring(with: m.range)
        if fullLine.trimmingCharacters(in: .whitespaces) == prefix.trimmingCharacters(in: .whitespaces) {
            replace(NSRange(location: lineRange.location, length: (fullLine as NSString).length), with: "",
                    select: NSRange(location: lineRange.location, length: 0))
            return true
        }
        func g(_ i: Int) -> String? { m.range(at: i).location == NSNotFound ? nil : bns.substring(with: m.range(at: i)) }
        let indent = g(1) ?? ""
        var next = indent
        if let c = g(2) {
            next += c + " [ ] "
        } else if let b = g(3) {
            next += b + " "
        } else if let n = g(4), let num = Int(n) {
            next += "\(num + 1). "
        }
        insertText("\n" + next, replacementRange: sel)
        return true
    }
}

// MARK: - SwiftUI wrapper

struct MarkdownEditor: NSViewRepresentable {
    let noteID: UUID
    let text: String
    let focusToken: UUID?
    var styleKey = ""
    let onChange: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let tv = TackTextView(usingTextLayoutManager: false)
        tv.textContainer?.replaceLayoutManager(TackLayoutManager())
        tv.isRichText = false
        tv.allowsUndo = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: 14, height: 6)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.textContainer?.widthTracksTextView = true
        tv.typingAttributes = MarkdownStyle.baseAttributes
        tv.linkTextAttributes = [.foregroundColor: NSColor.linkColor, .underlineStyle: NSUnderlineStyle.single.rawValue,
                                 .cursor: NSCursor.pointingHand]
        tv.delegate = context.coordinator

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = tv

        context.coordinator.textView = tv
        context.coordinator.load(noteID: noteID, text: text)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let c = context.coordinator
        c.parent = self
        if c.noteID != noteID {
            c.load(noteID: noteID, text: text)
        } else if let tv = c.textView, tv.string != text, !tv.hasMarkedText() {
            let sel = tv.selectedRange()
            tv.string = text
            c.highlight()
            tv.setSelectedRange(NSRange(location: min(sel.location, (text as NSString).length), length: 0))
        }
        if c.styleKey != styleKey {
            c.styleKey = styleKey
            c.highlight()
        }
        if let token = focusToken, token != c.lastFocusToken {
            c.lastFocusToken = token
            DispatchQueue.main.async { c.textView?.window?.makeFirstResponder(c.textView) }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditor
        weak var textView: TackTextView?
        var noteID: UUID?
        var lastFocusToken: UUID?
        var styleKey = ""

        init(_ parent: MarkdownEditor) { self.parent = parent }

        func load(noteID: UUID, text: String) {
            guard let tv = textView else { return }
            self.noteID = noteID
            tv.string = text
            highlight()
            tv.undoManager?.removeAllActions()
            tv.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
            tv.scrollRangeToVisible(tv.selectedRange())
        }

        func highlight() {
            guard let tv = textView, let ts = tv.textStorage, !tv.hasMarkedText() else { return }
            MarkdownStyle.highlight(ts)
            tv.typingAttributes = MarkdownStyle.baseAttributes
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            parent.onChange(tv.string)
            highlight()
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard let tv = textView as? TackTextView else { return false }
            if selector == #selector(NSResponder.insertNewline(_:)) { return tv.continueList() }
            if selector == #selector(NSResponder.deleteBackward(_:)) { return tv.deleteHiddenPrefixIfNeeded() }
            return false
        }

        /// Simple mode: the caret never stops inside a hidden checkbox / bullet.
        func textView(_ textView: NSTextView, willChangeSelectionFromCharacterRange old: NSRange,
                      toCharacterRange new: NSRange) -> NSRange {
            guard new.length == 0, let tv = textView as? TackTextView,
                  let p = tv.hiddenPrefix(atLineOf: new.location),
                  new.location >= p.start, new.location < p.end else { return new }
            if old.length == 0, old.location == p.end, new.location < p.end {
                return NSRange(location: p.lineStart > 0 ? p.lineStart - 1 : p.end, length: 0)
            }
            return NSRange(location: p.end, length: 0)
        }
    }
}
