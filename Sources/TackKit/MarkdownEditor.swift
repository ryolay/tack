import AppKit
import SwiftUI

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
