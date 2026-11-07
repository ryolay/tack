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
    let store: NoteStore
    var keyMonitor: Any?
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
}
