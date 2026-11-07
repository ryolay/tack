import AppKit

extension PanelController {
    // MARK: - Keyboard

    func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            nonisolated(unsafe) let e = event
            let consumed: Bool = MainActor.assumeIsolated { self.handle(e) == nil }
            return consumed ? nil : event
        }
    }

    func removeKeyMonitor() {
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
        keyMonitor = nil
    }

    private func perform(_ selector: Selector) -> Bool {
        panel.firstResponder?.tryToPerform(selector, with: nil) ?? false
    }

    private func handle(_ e: NSEvent) -> NSEvent? {
        guard e.window === panel else { return e }
        let flags = e.modifierFlags.intersection([.command, .option, .control, .shift])
        let chars = e.charactersIgnoringModifiers?.lowercased() ?? ""
        let handled: Bool
        switch flags {
        case []: handled = handlePlainKey(e)
        case .command: handled = handleCommandKey(e, chars: chars)
        case [.command, .shift]: handled = handleCommandShiftKey(e, chars: chars)
        case [.command, .option]: handled = handleCommandOptionKey(e)
        default: handled = false
        }
        return handled ? nil : e
    }

    private var inSearchField: Bool { (panel.firstResponder as? NSTextView)?.isFieldEditor == true }

    /// Esc closes; in the search field ↑ ↓ pick a note and ↩ jumps into it.
    private func handlePlainKey(_ e: NSEvent) -> Bool {
        switch e.keyCode {
        case 53: // Esc
            if inSearchField && !store.search.isEmpty { store.search = "" } else { hide() }
            return true
        case 125 where inSearchField: store.moveSelection(1); return true   // ↓
        case 126 where inSearchField: store.moveSelection(-1); return true  // ↑
        case 36 where inSearchField: // ↩
            store.ensureSelection()
            store.requestFocus(.editor)
            return true
        default:
            return false
        }
    }

    /// ⌘1…⌘9 by key code, so they also work on AZERTY / QWERTZ layouts.
    private static let digitKeys: [UInt16: Int] = [18: 0, 19: 1, 20: 2, 21: 3, 23: 4, 22: 5, 26: 6, 28: 7, 25: 8]

    /// Standard editing commands, sent explicitly because the panel never activates the app.
    private static let editActions: [String: Selector] = [
        "c": #selector(NSText.copy(_:)), "v": #selector(NSText.paste(_:)), "x": #selector(NSText.cut(_:)),
        "a": #selector(NSText.selectAll(_:)), "z": Selector(("undo:"))
    ]

    private func handleCommandKey(_ e: NSEvent, chars: String) -> Bool {
        if let idx = Self.digitKeys[e.keyCode] { store.selectIndex(idx); return true }
        if e.keyCode == 29 { toggleSidebar(); return true } // ⌘0
        if let action = Self.editActions[chars] { return perform(action) }
        switch chars {
        case "n": store.newNote()
        case "f": store.requestFocus(.search)
        case "w": hide()
        case ",": store.onOpenSettings?()
        default: return false
        }
        return true
    }

    private func handleCommandShiftKey(_ e: NSEvent, chars: String) -> Bool {
        if e.keyCode == 51 { // ⌘⇧⌫
            store.deleteSelected()
            store.requestFocus(.editor)
            return true
        }
        switch chars {
        case "z": return perform(Selector(("redo:")))
        case "c": store.copySelected()
        case "a": store.toggleArchiveSelected()
        case "k": store.keepOpen.toggle()
        case "p": if let id = store.selectedID { store.togglePin(id) }
        default: return false
        }
        return true
    }

    private func handleCommandOptionKey(_ e: NSEvent) -> Bool {
        switch e.keyCode {
        case 125: store.moveSelection(1)
        case 126: store.moveSelection(-1)
        default: return false
        }
        return true
    }

    private func toggleSidebar() {
        let defaults = UserDefaults.standard
        defaults.set(!(defaults.object(forKey: "showSidebar") as? Bool ?? true), forKey: "showSidebar")
    }
}
