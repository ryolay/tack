import Foundation
import AppKit

extension NoteStore {
    // MARK: - Editing

    func index(_ id: UUID) -> Int? { notes.firstIndex { $0.id == id } }

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
        let message = nowArchived ? tr("Note archived") : tr("Note unarchived")
        showToast(UndoToast(message: message, noteID: id, kind: .archive))
        saveNow()
    }

    func toggleArchiveSelected() { if let id = selectedID { toggleArchive(id) } }

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
            let folder = note.archived ? dir.appendingPathComponent(tr("Archived")) : dir
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
}
