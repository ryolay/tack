import Foundation

enum Scope: String, CaseIterable, Identifiable {
    case notes, archive, trash
    var id: String { rawValue }
    var label: String {
        switch self {
        case .notes: tr("Notes")
        case .archive: tr("Archived")
        case .trash: tr("Trash")
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
