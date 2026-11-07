import AppKit

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
