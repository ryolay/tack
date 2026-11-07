import AppKit
import SwiftUI

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Non-activating floating panel: shows over full-screen apps,
/// on every Space, without switching away from the current one.
@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    let panel: FloatingPanel
    private let store: NoteStore
    private var keyMonitor: Any?
    private var lastHidden = Date.distantPast

    init(store: NoteStore) {
        self.store = store
        panel = FloatingPanel(
            contentRect: NSRect(origin: .zero, size: Prefs.panelSize),
            styleMask: [.nonactivatingPanel, .titled, .resizable, .fullSizeContentView, .closable],
            backing: .buffered,
            defer: false
        )
        super.init()
        store.onClose = { [weak self] in self?.hide() }

        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        [.closeButton, .miniaturizeButton, .zoomButton].forEach { panel.standardWindowButton($0)?.isHidden = true }
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow
        panel.minSize = NSSize(width: 400, height: 260)
        panel.delegate = self

        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active

        let host = NSHostingView(rootView: ContentView().environmentObject(store))
        host.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            host.topAnchor.constraint(equalTo: effect.topAnchor),
            host.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        panel.contentView = effect
    }

    var isShown: Bool { panel.isVisible }

    func toggle(fromHotKey: Bool) {
        if panel.isVisible && panel.isKeyWindow {
            hide()
        } else {
            // Avoid reopening right away when a click on the menu bar icon already closed the panel
            if !fromHotKey && Date().timeIntervalSince(lastHidden) < 0.3 { return }
            show(newNote: fromHotKey && Prefs.openMode == .newNote)
        }
    }

    func show(newNote: Bool) {
        if newNote { store.newNote() } else { store.ensureSelection() }
        if !panel.isVisible { position() }
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
        store.requestFocus(.editor)
        ReminderScheduler.shared.sync(notes: store.notes)
    }

    func hide() {
        guard panel.isVisible else { return }
        removeKeyMonitor()
        panel.orderOut(nil)
        store.freezeSelected()
        store.pruneEmpty()
        store.saveNow()
        lastHidden = Date()
    }

    private func position() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let vf = screen?.visibleFrame else { return }
        var size = Prefs.panelSize
        size.width = min(size.width, vf.width - 40)
        size.height = min(size.height, vf.height - 40)
        let origin = NSPoint(x: vf.midX - size.width / 2,
                             y: max(vf.minY + 20, vf.maxY - vf.height * 0.16 - size.height))
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    // MARK: - NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        store.freezeSelected()
        if Prefs.hideOnFocusLoss && !store.keepOpen && panel.isVisible && panel.attachedSheet == nil {
            hide()
        }
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        Prefs.panelSize = panel.frame.size
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }

    // MARK: - Keyboard

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            nonisolated(unsafe) let e = event
            let consumed: Bool = MainActor.assumeIsolated { self.handle(e) == nil }
            return consumed ? nil : event
        }
    }

    private func removeKeyMonitor() {
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
