import Foundation

extension NoteStore {
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

    func load() {
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

    func scheduleSave() {
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
