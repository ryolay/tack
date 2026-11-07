import AppKit
import SwiftUI

/// Entry point, called by the `Tack` executable target.
public enum TackApp {
    @MainActor
    public static func run() {
        Migration.run()
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = NoteStore()
    private var panel: PanelController!
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        panel = PanelController(store: store)
        setupStatusItem()

        HotKeyManager.shared.onTrigger = { [weak self] in
            MainActor.assumeIsolated { self?.panel.toggle(fromHotKey: true) }
        }
        HotKeyManager.shared.registerFromPrefs()

        store.onOpenSettings = { [weak self] in self?.showSettings() }
        applyTheme()
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyTheme() }
        }

        ReminderScheduler.shared.start()
        ReminderScheduler.shared.onOpenNote = { [weak self] id in
            MainActor.assumeIsolated {
                self?.store.reveal(id)
                self?.panel.show(newNote: false)
            }
        }
        ReminderScheduler.shared.onDeniedChange = { [weak self] denied in
            MainActor.assumeIsolated { self?.store.notificationsDenied = denied }
        }
        ReminderScheduler.shared.sync(notes: store.notes)

        if store.isFirstLaunch {
            panel.show(newNote: false)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.saveNow()
    }

    // MARK: - Status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "Tack")
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            let menu = NSMenu()
            let newTitle = tr("New Note") + "   \(Prefs.hotKeyDisplay)"
            menu.addItem(withTitle: newTitle, action: #selector(newNoteFromMenu), keyEquivalent: "")
            menu.addItem(withTitle: tr("Show Notes"), action: #selector(showNotes), keyEquivalent: "")
            menu.addItem(.separator())
            menu.addItem(withTitle: tr("Settings…"), action: #selector(showSettings), keyEquivalent: ",")
            menu.addItem(.separator())
            menu.addItem(withTitle: tr("Quit Tack"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            menu.items.forEach { if $0.action != #selector(NSApplication.terminate(_:)) { $0.target = self } }
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            panel.toggle(fromHotKey: false)
        }
    }

    @objc private func newNoteFromMenu() { panel.show(newNote: true) }
    @objc private func showNotes() { panel.show(newNote: false) }

    private func applyTheme() {
        let target: NSAppearance? = switch Prefs.theme {
        case "light": NSAppearance(named: .aqua)
        case "dark": NSAppearance(named: .darkAqua)
        default: nil
        }
        if NSApp.appearance?.name != target?.name { NSApp.appearance = target }
    }

    @objc private func showSettings() {
        panel.hide()
        if settingsWindow == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView().environmentObject(store)))
            w.title = tr("Tack Settings")
            w.styleMask = [.titled, .closable]
            w.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            w.isReleasedWhenClosed = false
            w.center()
            settingsWindow = w
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Main menu (needed for ⌘C/⌘V/⌘Z in the Settings window)

    private func setupMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: tr("Quit Tack"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: tr("Edit"))
        edit.addItem(withTitle: tr("Undo"), action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: tr("Redo"), action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: tr("Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: tr("Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: tr("Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: tr("Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }
}
