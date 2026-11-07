import Foundation
import AppKit

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

enum Scope: String, CaseIterable, Identifiable {
    case notes, archive, trash
    var id: String { rawValue }
    var label: String {
        switch self {
        case .notes: L("Notes", "Notes")
        case .archive: L("Archives", "Archive")
        case .trash: L("Corbeille", "Trash")
        }
    }
    var icon: String {
        switch self {
        case .notes: "doc.text"
        case .archive: "archivebox"
        case .trash: "trash"
        }
    }
}

enum FocusTarget: Hashable { case editor, search }

struct FocusRequest: Equatable {
    let target: FocusTarget
    let token = UUID()
}

struct UndoToast: Equatable {
    enum Kind { case trash, archive }
    let id = UUID()
    let message: String
    let noteID: UUID
    let kind: Kind
}

@MainActor
final class NoteStore: ObservableObject {
    @Published private(set) var notes: [Note] = []
    @Published var selectedID: UUID? {
        didSet { if oldValue != selectedID { freezeReminders(oldValue) } }
    }
    @Published var search = ""
    @Published private(set) var scope: Scope = .notes
    @Published var tagFilter: String?
    @Published var focusRequest: FocusRequest?
    @Published var toast: UndoToast?
    var onClose: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    @Published var notificationsDenied = false
    @Published var keepOpen = UserDefaults.standard.bool(forKey: "keepOpen") {
        didSet { UserDefaults.standard.set(keepOpen, forKey: "keepOpen") }
    }

    let fileURL: URL
    private(set) var isFirstLaunch = false
    private var saveWork: DispatchWorkItem?
    static let trashRetentionDays = 30

    init(directory: URL? = nil) {
        let dir = directory ?? NoteStore.defaultDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("notes.json")
        load()
    }

    nonisolated static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tack", isDirectory: true)
    }

    func close() { onClose?() }

    // MARK: - Derived

    private func inScope(_ n: Note, _ s: Scope) -> Bool {
        switch s {
        case .notes: !n.isTrashed && !n.archived
        case .archive: !n.isTrashed && n.archived
        case .trash: n.isTrashed
        }
    }

    func count(_ s: Scope) -> Int { notes.lazy.filter { self.inScope($0, s) && !$0.isEmpty }.count }

    /// Tags of the current view, most used first.
    var allTags: [(tag: String, count: Int)] {
        guard scope != .trash else { return [] }
        var counts: [String: Int] = [:]
        for n in notes where inScope(n, scope) {
            for t in n.tags { counts[t, default: 0] += 1 }
        }
        return counts.map { ($0.key, $0.value) }.sorted { $0.count != $1.count ? $0.count > $1.count : $0.tag < $1.tag }
    }

    var filtered: [Note] {
        var list = notes.filter { inScope($0, scope) }
        if let tag = tagFilter { list = list.filter { $0.tags.contains(tag) } }
        let q = search.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            list = list.filter { $0.text.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
        if scope == .trash {
            return list.sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
        }
        return list.sorted {
            if $0.pinned != $1.pinned { return $0.pinned }
            return $0.updated > $1.updated
        }
    }

    var selected: Note? {
        guard let id = selectedID else { return nil }
        return notes.first { $0.id == id }
    }

    // MARK: - Navigation

    func setScope(_ s: Scope) {
        scope = s
        tagFilter = nil
        selectedID = filtered.first?.id
    }

    func toggleTag(_ tag: String) {
        tagFilter = tagFilter == tag ? nil : tag
        if let sel = selected, !filtered.contains(where: { $0.id == sel.id }) {
            selectedID = filtered.first?.id
        }
    }

    func newNote() {
        search = ""
        tagFilter = nil
        scope = .notes
        if let empty = notes.first(where: { $0.isEmpty && !$0.isTrashed && !$0.archived }) {
            selectedID = empty.id
        } else {
            let note = Note(text: "")
            notes.insert(note, at: 0)
            selectedID = note.id
        }
        requestFocus(.editor)
    }

    func ensureSelection() {
        if let sel = selected, inScope(sel, scope) { return }
        if let first = filtered.first {
            selectedID = first.id
        } else if scope == .notes {
            newNote()
        } else {
            selectedID = nil
        }
    }

    func select(_ id: UUID) { selectedID = id }

    /// Shows a note wherever it lives (e.g. after clicking a notification).
    func reveal(_ id: UUID) {
        guard let n = notes.first(where: { $0.id == id }) else { return }
        search = ""
        tagFilter = nil
        scope = n.isTrashed ? .trash : (n.archived ? .archive : .notes)
        selectedID = id
    }

    func selectIndex(_ i: Int) {
        let list = filtered
        guard list.indices.contains(i) else { return }
        selectedID = list[i].id
        requestFocus(.editor)
    }

    func moveSelection(_ delta: Int) {
        let list = filtered
        guard !list.isEmpty else { return }
        let current = list.firstIndex { $0.id == selectedID } ?? -1
        selectedID = list[max(0, min(list.count - 1, current + delta))].id
    }

    /// After a note leaves the current view, select its neighbour.
    private func selectNeighbor(of id: UUID, in previous: [Note]) {
        guard selectedID == id else { return }
        let pos = previous.firstIndex { $0.id == id } ?? 0
        let remaining = filtered
        selectedID = remaining.isEmpty ? nil : remaining[min(pos, remaining.count - 1)].id
    }

    // MARK: - Editing

    private func index(_ id: UUID) -> Int? { notes.firstIndex { $0.id == id } }

    func updateSelected(text: String) {
        guard let id = selectedID, let i = index(id), notes[i].text != text else { return }
        notes[i].text = text
        notes[i].updated = Date()
        scheduleSave()
    }

    func togglePin(_ id: UUID) {
        guard let i = index(id) else { return }
        notes[i].pinned.toggle()
        scheduleSave()
    }

    func toggleArchive(_ id: UUID) {
        guard let i = index(id), !notes[i].isTrashed else { return }
        let before = filtered
        notes[i].archived.toggle()
        let nowArchived = notes[i].archived
        selectNeighbor(of: id, in: before)
        let message = nowArchived ? L("Note archivée", "Note archived") : L("Note désarchivée", "Note unarchived")
        showToast(UndoToast(message: message, noteID: id, kind: .archive))
        saveNow()
    }

    func toggleArchiveSelected() { if let id = selectedID { toggleArchive(id) } }

    func trash(_ id: UUID) {
        guard let i = index(id), !notes[i].isTrashed else { return }
        let before = filtered
        if notes[i].isEmpty {
            notes.remove(at: i)
        } else {
            notes[i].deletedAt = Date()
            showToast(UndoToast(message: L("Placée dans la corbeille", "Moved to Trash"), noteID: id, kind: .trash))
        }
        selectNeighbor(of: id, in: before)
        saveNow()
    }

    func deleteSelected() { if let id = selectedID { trash(id) } }

    func restore(_ id: UUID) {
        guard let i = index(id) else { return }
        let before = filtered
        notes[i].deletedAt = nil
        selectNeighbor(of: id, in: before)
        saveNow()
    }

    func deleteForever(_ id: UUID) {
        let before = filtered
        notes.removeAll { $0.id == id }
        selectNeighbor(of: id, in: before)
        saveNow()
    }

    func emptyTrash() {
        notes.removeAll(where: \.isTrashed)
        if scope == .trash { selectedID = nil }
        saveNow()
    }

    func undoToast() {
        guard let t = toast, let i = index(t.noteID) else { toast = nil; return }
        switch t.kind {
        case .trash: notes[i].deletedAt = nil
        case .archive: notes[i].archived.toggle()
        }
        toast = nil
        if inScope(notes[i], scope) { selectedID = t.noteID }
        saveNow()
        requestFocus(.editor)
    }

    private func showToast(_ t: UndoToast) {
        toast = t
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            if self?.toast?.id == t.id { self?.toast = nil }
        }
    }

    /// Freezes a note's relative reminders into exact dates (without touching its edit date).
    func freezeReminders(_ id: UUID?, base: Date = Date()) {
        guard let id, let i = index(id) else { return }
        let frozen = ReminderParser.freeze(notes[i].text, base: base)
        if frozen != notes[i].text {
            notes[i].text = frozen
            scheduleSave()
        }
    }

    func freezeSelected() { freezeReminders(selectedID) }

    /// Exports every note (except the Trash) as .md files. Returns how many were written.
    func exportMarkdown(to dir: URL) -> Int {
        let fm = FileManager.default
        var used = Set<String>(), count = 0
        for note in notes where !note.isTrashed && !note.isEmpty {
            let folder = note.archived ? dir.appendingPathComponent(L("Archives", "Archive")) : dir
            try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
            let base = String(note.title.map { "/:\\".contains($0) ? "-" : $0 }.prefix(60)).trimmingCharacters(in: .whitespaces)
            var name = base.isEmpty ? "Note" : base, i = 2
            while used.contains((folder.path + name).lowercased()) { name = "\(base) \(i)"; i += 1 }
            used.insert((folder.path + name).lowercased())
            if (try? note.text.write(to: folder.appendingPathComponent(name + ".md"), atomically: true, encoding: .utf8)) != nil {
                count += 1
            }
        }
        return count
    }

    func copySelected() {
        guard let text = selected?.text else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func pruneEmpty() {
        let before = notes.count
        notes.removeAll(where: \.isEmpty)
        if notes.count != before {
            if selected == nil { selectedID = nil }
            saveNow()
        }
    }

    func requestFocus(_ target: FocusTarget) {
        focusRequest = FocusRequest(target: target)
    }

    // MARK: - Persistence

    private static var welcomeText: String { L(welcomeFR, welcomeEN) }

    private static let welcomeFR = """
    # Bienvenue dans Tack 📌

    Ouvrir / fermer : ⌃⌥N — partout, même en plein écran

    ## Écrire
    - [ ] Clique sur une case pour la cocher (ou ⇧⌘L)
    - [x] Les listes continuent toutes seules avec ↩
    - **gras** (⌘B), *italique* (⌘I), `code`, # titres
    - Ajoute des #tags n'importe où pour filtrer
    - [ ] Rappel : @demain 14h, @14h30, @lundi 9h, @dans 30min

    ## Naviguer
    - ⌘N nouvelle note · ⌘F rechercher · ⌘1…9 aller à une note
    - ⌥⌘↑ / ⌥⌘↓ note précédente / suivante
    - ⌘⇧K garder la fenêtre ouverte · ⌘0 masquer la liste
    - ⌘⇧P favori · ⌘⇧A archiver · ⌘⇧⌫ corbeille (gardée 30 jours)
    - Échap fermer

    Réglages : ⌘, ou clic droit sur l'icône de la barre des menus
    """

    private static let welcomeEN = """
    # Welcome to Tack 📌

    Open / close: ⌃⌥N — anywhere, even over full-screen apps

    ## Writing
    - [ ] Click a box to check it (or ⇧⌘L)
    - [x] Lists continue automatically with ↩
    - **bold** (⌘B), *italic* (⌘I), `code`, # headings
    - Add #tags anywhere to filter
    - [ ] Reminder: @tomorrow 2pm, @14:30, @monday 9am, @in 30min

    ## Navigation
    - ⌘N new note · ⌘F search · ⌘1…9 jump to a note
    - ⌥⌘↑ / ⌥⌘↓ previous / next note
    - ⌘⇧K keep window open · ⌘0 hide the list
    - ⌘⇧P favorite · ⌘⇧A archive · ⌘⇧⌫ trash (kept 30 days)
    - Esc close

    Settings: ⌘, or right-click the menu bar icon
    """

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else {
            isFirstLaunch = true
            let welcome = Note(text: NoteStore.welcomeText, pinned: true)
            notes = [welcome]
            selectedID = welcome.id
            saveNow()
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            notes = try decoder.decode([Note].self, from: data)
            // Safety backup at every launch (only when the file is valid)
            try? data.write(to: fileURL.deletingLastPathComponent().appendingPathComponent("notes.backup.json"), options: .atomic)
        } catch {
            // Never overwrite an unreadable file: set it aside.
            let stamp = Int(Date().timeIntervalSince1970)
            try? FileManager.default.moveItem(at: fileURL, to: fileURL.deletingLastPathComponent()
                .appendingPathComponent("notes.unreadable-\(stamp).json"))
            notes = []
        }
        // Relative reminders not frozen yet (e.g. app quit while editing) → base = last edit
        for i in notes.indices {
            notes[i].text = ReminderParser.freeze(notes[i].text, base: notes[i].updated)
        }
        // Purge the Trash
        let limit = Date().addingTimeInterval(-Double(NoteStore.trashRetentionDays) * 86_400)
        notes.removeAll { ($0.deletedAt ?? .distantFuture) < limit }
        selectedID = filtered.first?.id
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.saveNow() }
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    func saveNow() {
        saveWork?.cancel()
        saveWork = nil
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        if let data = try? encoder.encode(notes) {
            try? data.write(to: fileURL, options: .atomic)
        }
        ReminderScheduler.shared.sync(notes: notes)
    }
}
