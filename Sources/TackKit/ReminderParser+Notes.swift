import Foundation

/// Reminders found in notes, and freezing relative ones into exact dates.
extension ReminderParser {
    static let checkedLine = RegexFactory.make(#"^\s*[-*+] \[[xX]\]"#)

    private static let canonical = RegexFactory.make(#"^@\d{2}/\d{2}(?:/\d{4})? \d{2}:\d{2}$"#)
    private static let canonicalFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "dd/MM HH:mm"
        return f
    }()

    /// Turns relative reminders (@demain 14h, @dans 30min…) into exact dates (@08/11 14:00)
    /// so they do not drift when the note is reopened on another day.
    static func freeze(_ text: String, base: Date) -> String {
        guard text.contains("@") else { return text }
        let ns = NSMutableString(string: text)
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        for m in matches.reversed() {
            let token = (text as NSString).substring(with: m.range)
            if canonical.firstMatch(in: token, range: NSRange(location: 0, length: (token as NSString).length)) != nil { continue }
            guard let date = date(from: m, in: text as NSString, now: base) else { continue }
            ns.replaceCharacters(in: m.range, with: "@" + canonicalFormat.string(from: date))
        }
        return ns as String
    }
    private static let linePrefix = #"^\s*(?:[-*+] \[[ xX]\]\s*|[-*+]\s+|#{1,6}\s+)"#

    static func reminders(in note: Note, now: Date = Date()) -> [Reminder] {
        guard note.text.contains("@") else { return [] }
        var out: [Reminder] = []
        for line in note.text.components(separatedBy: .newlines) where line.contains("@") {
            let ns = line as NSString
            let full = NSRange(location: 0, length: ns.length)
            if checkedLine.firstMatch(in: line, range: full) != nil { continue } // task already done
            for m in regex.matches(in: line, range: full) {
                guard let date = date(from: m, in: ns, now: now) else { continue }
                var text = ns.replacingCharacters(in: m.range, with: "")
                if let r = text.range(of: linePrefix, options: .regularExpression) { text.removeSubrange(r) }
                text = text.trimmingCharacters(in: .whitespaces)
                out.append(Reminder(noteID: note.id, text: text.isEmpty ? note.title : text, noteTitle: note.title, date: date))
            }
        }
        return out
    }
}
