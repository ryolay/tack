import AppKit

/// List editing: line styles, Simple mode hidden prefixes and list continuation.
extension TackTextView {
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
