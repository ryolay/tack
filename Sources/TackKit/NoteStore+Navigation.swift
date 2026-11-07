import Foundation

extension NoteStore {
    // MARK: - Navigation

    func setScope(_ s: Scope) {
        applyScope(s)
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
        applyScope(.notes)
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
        applyScope(n.isTrashed ? .trash : (n.archived ? .archive : .notes))
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
    func selectNeighbor(of id: UUID, in previous: [Note]) {
        guard selectedID == id else { return }
        let pos = previous.firstIndex { $0.id == id } ?? 0
        let remaining = filtered
        selectedID = remaining.isEmpty ? nil : remaining[min(pos, remaining.count - 1)].id
    }
}
