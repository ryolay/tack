import Foundation

struct Note: Identifiable, Codable, Equatable {
    var id = UUID()
    var text: String
    var created = Date()
    var updated = Date()
    var pinned = false
    var archived = false
    var deletedAt: Date?

    init(text: String, pinned: Bool = false) {
        self.text = text
        self.pinned = pinned
    }

    enum CodingKeys: String, CodingKey { case id, text, created, updated, pinned, archived, deletedAt }

    // Lenient decoding: older files without the newer fields stay readable.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        created = try c.decodeIfPresent(Date.self, forKey: .created) ?? Date()
        updated = try c.decodeIfPresent(Date.self, forKey: .updated) ?? created
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        archived = try c.decodeIfPresent(Bool.self, forKey: .archived) ?? false
        deletedAt = try c.decodeIfPresent(Date.self, forKey: .deletedAt)
    }

    var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var isTrashed: Bool { deletedAt != nil }

    private var lines: [Substring] {
        text.split(whereSeparator: \.isNewline).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private static func stripMarkers(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespaces)
        for pattern in [#"^#{1,6}\s*"#, #"^[-*+] \[[ xX]\]\s*"#, #"^[-*+]\s+"#, #"^>\s*"#] {
            if let r = t.range(of: pattern, options: .regularExpression) { t.removeSubrange(r) }
        }
        return t.replacingOccurrences(of: "**", with: "")
    }

    var title: String {
        guard let first = lines.first else { return L("Nouvelle note", "New Note") }
        let t = Note.stripMarkers(String(first))
        return t.isEmpty ? L("Nouvelle note", "New Note") : String(t.prefix(80))
    }

    var preview: String {
        lines.dropFirst().prefix(2).map { Note.stripMarkers(String($0)) }.joined(separator: " ")
    }

    var checklist: (done: Int, total: Int)? {
        var done = 0, total = 0
        for line in lines {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.count >= 5 else { continue }
            let head = t.prefix(5)
            if head == "- [ ]" || head == "* [ ]" {
                total += 1
            } else if ["- [x]", "- [X]", "* [x]", "* [X]"].contains(String(head)) {
                total += 1
                done += 1
            }
        }
        return total > 0 ? (done, total) : nil
    }

    var tags: [String] {
        let ns = text as NSString
        var seen = Set<String>(), out: [String] = []
        for m in MarkdownStyle.tag.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let t = ns.substring(with: m.range(at: 1)).lowercased()
            if seen.insert(t).inserted { out.append(t) }
        }
        return out
    }

    var nextReminder: Date? {
        guard !isTrashed else { return nil }
        let now = Date()
        return ReminderParser.reminders(in: self, now: now).map(\.date).filter { $0 > now }.min()
    }

    var shortDate: String {
        let cal = Calendar.current
        if cal.isDateInToday(updated) { return updated.formatted(date: .omitted, time: .shortened) }
        if cal.isDateInYesterday(updated) { return L("Hier", "Yesterday") }
        return updated.formatted(.dateTime.day().month(.abbreviated))
    }
}
