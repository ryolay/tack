import AppKit

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
