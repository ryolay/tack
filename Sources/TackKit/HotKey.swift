import AppKit
import Carbon.HIToolbox

/// Global hotkey through Carbon: needs no Accessibility permission.
final class HotKeyManager {
    static let shared = HotKeyManager()
    var onTrigger: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerInstalled = false

    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32) -> Bool {
        unregister()
        if !handlerInstalled {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async { HotKeyManager.shared.onTrigger?() }
                return noErr
            }, 1, &spec, nil, nil)
            handlerInstalled = true
        }
        let id = EventHotKeyID(signature: OSType(0x464E_5445), id: 1) // 'FNTE'
        let status = RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
        return status == noErr
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    func registerFromPrefs() {
        if !register(keyCode: Prefs.hotKeyCode, modifiers: Prefs.hotKeyModifiers) {
            NSLog("Tack: could not register hotkey \(Prefs.hotKeyDisplay)")
        }
    }

    // MARK: - Conversion helpers

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        if flags.contains(.option) { m |= UInt32(optionKey) }
        if flags.contains(.control) { m |= UInt32(controlKey) }
        if flags.contains(.shift) { m |= UInt32(shiftKey) }
        return m
    }

    static func display(for event: NSEvent) -> String {
        let flags = event.modifierFlags
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option) { s += "⌥" }
        if flags.contains(.shift) { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        return s + keyName(event)
    }

    private static func keyName(_ event: NSEvent) -> String {
        let special: [UInt16: String] = [
            49: tr("Space"), 36: "↩", 48: "⇥", 51: "⌫", 117: "⌦",
            123: "←", 124: "→", 125: "↓", 126: "↑",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        ]
        if let name = special[event.keyCode] { return name }
        return (event.charactersIgnoringModifiers ?? "?").uppercased()
    }

    static func isFunctionKey(_ keyCode: UInt16) -> Bool {
        [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111].contains(keyCode)
    }
}

enum OpenMode: String, CaseIterable {
    case newNote = "new"
    case lastNote = "last"
}

enum Prefs {
    private static let d = UserDefaults.standard

    static var hotKeyCode: UInt32 {
        get { UInt32(d.object(forKey: "hotKeyCode") as? Int ?? kVK_ANSI_N) }
        set { d.set(Int(newValue), forKey: "hotKeyCode") }
    }

    static var hotKeyModifiers: UInt32 {
        get { UInt32(d.object(forKey: "hotKeyModifiers") as? Int ?? (controlKey | optionKey)) }
        set { d.set(Int(newValue), forKey: "hotKeyModifiers") }
    }

    static var hotKeyDisplay: String {
        get { d.string(forKey: "hotKeyDisplay") ?? "⌃⌥N" }
        set { d.set(newValue, forKey: "hotKeyDisplay") }
    }

    static var openMode: OpenMode {
        OpenMode(rawValue: d.string(forKey: "openMode") ?? "") ?? .newNote
    }

    static var hideOnFocusLoss: Bool {
        d.object(forKey: "hideOnFocusLoss") as? Bool ?? true
    }

    static var fontSize: Double { d.object(forKey: "fontSize") as? Double ?? 15 }
    /// system · serif · rounded · mono
    static var fontFamily: String { d.string(forKey: "fontFamily") ?? "system" }
    /// system · light · dark
    static var theme: String { d.string(forKey: "theme") ?? "system" }
    /// simple (like Notes) · markdown
    static var editorMode: String { d.string(forKey: "editorMode") ?? "simple" }
    static var reminderHour: Int { d.object(forKey: "reminderHour") as? Int ?? 9 }
    static var reminderSound: Bool { d.object(forKey: "reminderSound") as? Bool ?? true }

    static var panelSize: NSSize {
        get {
            let w = d.double(forKey: "panelWidth"), h = d.double(forKey: "panelHeight")
            return w > 0 && h > 0 ? NSSize(width: w, height: h) : NSSize(width: 780, height: 480)
        }
        set {
            d.set(newValue.width, forKey: "panelWidth")
            d.set(newValue.height, forKey: "panelHeight")
        }
    }
}
