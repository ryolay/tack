import Foundation

/// One-time migration from the app's previous name (FastNote) to Tack:
/// copies the notes file and the user's settings so nothing is lost.
enum Migration {
    private static let legacyFolder = "FastNote"
    private static let legacyDefaultsDomain = "com.local.fastnote"
    private static let doneKey = "migratedFromFastNote"
    private static let keys = [
        "hotKeyCode", "hotKeyModifiers", "hotKeyDisplay", "openMode", "hideOnFocusLoss",
        "panelWidth", "panelHeight", "keepOpen", "showSidebar", "fontSize", "fontFamily",
        "theme", "reminderHour", "reminderSound", "language", "editorMode",
    ]

    static func run() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey) else { return }
        defer { defaults.set(true, forKey: doneKey) }

        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let oldFile = support.appendingPathComponent(legacyFolder).appendingPathComponent("notes.json")
        let newDir = NoteStore.defaultDirectory
        let newFile = newDir.appendingPathComponent("notes.json")
        if fm.fileExists(atPath: oldFile.path), !fm.fileExists(atPath: newFile.path) {
            try? fm.createDirectory(at: newDir, withIntermediateDirectories: true)
            try? fm.copyItem(at: oldFile, to: newFile)
        }

        if let old = UserDefaults(suiteName: legacyDefaultsDomain) {
            for key in keys where defaults.object(forKey: key) == nil {
                if let value = old.object(forKey: key) { defaults.set(value, forKey: key) }
            }
        }
    }
}
