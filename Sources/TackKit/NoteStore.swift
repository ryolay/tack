import Foundation
import AppKit

@MainActor
final class NoteStore: ObservableObject {
    @Published var notes: [Note] = []
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
    var isFirstLaunch = false
    var saveWork: DispatchWorkItem?
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

    func inScope(_ n: Note, _ s: Scope) -> Bool {
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
    func selectNeighbor(of id: UUID, in previous: [Note]) {
        guard selectedID == id else { return }
        let pos = previous.firstIndex { $0.id == id } ?? 0
        let remaining = filtered
        selectedID = remaining.isEmpty ? nil : remaining[min(pos, remaining.count - 1)].id
    }
}
