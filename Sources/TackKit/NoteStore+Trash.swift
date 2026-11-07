import Foundation

/// Trash, restore and the undo toast.
extension NoteStore {
    func trash(_ id: UUID) {
        guard let i = index(id), !notes[i].isTrashed else { return }
        let before = filtered
        if notes[i].isEmpty {
            notes.remove(at: i)
        } else {
            notes[i].deletedAt = Date()
            showToast(UndoToast(message: tr("Moved to Trash"), noteID: id, kind: .trash))
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

    func showToast(_ t: UndoToast) {
        toast = t
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            if self?.toast?.id == t.id { self?.toast = nil }
        }
    }
}
