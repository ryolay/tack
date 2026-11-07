import SwiftUI
import ServiceManagement
import UserNotifications

struct SettingsView: View {
    @AppStorage("language") private var language = "system"

    var body: some View {
        SettingsTabs()
            .environment(\.layoutDirection, Lang.layoutDirection)
            .environment(\.locale, Lang.locale)
            .id(language)
    }
}

private struct SettingsTabs: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label(tr("General"), systemImage: "gearshape") }
            AppearanceSettings()
                .tabItem { Label(tr("Appearance"), systemImage: "paintbrush") }
            ReminderSettings()
                .tabItem { Label(tr("Reminders"), systemImage: "bell") }
            DataSettings()
                .tabItem { Label(tr("Data"), systemImage: "externaldrive") }
        }
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @AppStorage("openMode") private var openMode = OpenMode.newNote.rawValue
    @AppStorage("hideOnFocusLoss") private var hideOnFocusLoss = true
    @AppStorage("language") private var language = "system"
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                LabeledContent(tr("Shortcut to open")) { HotKeyRecorder() }
                Picker(tr("Shortcut opens"), selection: $openMode) {
                    Text(tr("A new note")).tag(OpenMode.newNote.rawValue)
                    Text(tr("The last note")).tag(OpenMode.lastNote.rawValue)
                }
                Toggle(tr("Close when clicking elsewhere"), isOn: $hideOnFocusLoss)
            }
            Section {
                Toggle(tr("Open Tack at login"), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            loginError = nil
                        } catch {
                            loginError = tr("Failed: the app must be in /Applications")
                        }
                    }
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
                Picker(tr("Language"), selection: $language) {
                    Text(tr("Same as system")).tag("system")
                    Divider()
                    ForEach(Lang.all) { lang in
                        Text("\(lang.flag)  \(lang.nativeName)").tag(lang.code)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Appearance

private struct AppearanceSettings: View {
    @AppStorage("theme") private var theme = "system"
    @AppStorage("fontFamily") private var fontFamily = "system"
    @AppStorage("fontSize") private var fontSize = 15.0
    @AppStorage("showSidebar") private var showSidebar = true
    @AppStorage("editorMode") private var editorMode = "simple"

    private var previewFont: Font {
        let design: Font.Design = switch fontFamily {
        case "serif": .serif
        case "rounded": .rounded
        case "mono": .monospaced
        default: .default
        }
        return .system(size: fontSize, design: design)
    }

    var body: some View {
        Form {
            Section {
                Picker(tr("Writing style"), selection: $editorMode) {
                    Text(tr("Simple")).tag("simple")
                    Text("Markdown").tag("markdown")
                }
                .pickerStyle(.segmented)
                Text(editorMode == "simple"
                     ? tr("Like Notes: tick circles, bullets and titles, no visible symbols.")
                     : tr("Markdown symbols stay visible: - [ ], #, **bold**…"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Picker(tr("Theme"), selection: $theme) {
                    Text(tr("Auto")).tag("system")
                    Text(tr("Light")).tag("light")
                    Text(tr("Dark")).tag("dark")
                }
                .pickerStyle(.segmented)
            }
            Section {
                Picker(tr("Font"), selection: $fontFamily) {
                    Text(tr("System")).tag("system")
                    Text("Serif").tag("serif")
                    Text(tr("Rounded")).tag("rounded")
                    Text("Mono").tag("mono")
                }
                LabeledContent(tr("Size")) {
                    HStack {
                        Slider(value: $fontSize, in: 12...22, step: 1).frame(width: 180)
                        Text("\(Int(fontSize))").monospacedDigit().frame(width: 24)
                    }
                }
                Text(tr("The quick brown fox jumps over the lazy dog."))
                    .font(previewFont)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle(tr("Show the notes list (⌘0)"), isOn: $showSidebar)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Reminders

private struct ReminderSettings: View {
    @AppStorage("reminderHour") private var reminderHour = 9
    @AppStorage("reminderSound") private var reminderSound = true
    @State private var status: UNAuthorizationStatus?

    var body: some View {
        Form {
            Section {
                LabeledContent(tr("Notifications")) {
                    switch status {
                    case .authorized, .provisional:
                        Label(tr("On"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    case .denied:
                        Button(tr("Enable in System Settings")) {
                            ReminderScheduler.openSystemSettings()
                        }
                    default:
                        Text(tr("Asked on first reminder")).foregroundStyle(.secondary)
                    }
                }
                Toggle(tr("Play a sound"), isOn: $reminderSound)
                Picker(tr("Time when none is given"), selection: $reminderHour) {
                    ForEach(6..<22, id: \.self) { h in Text(String(format: "%02d:00", h)).tag(h) }
                }
            }
            Section(tr("How to write a reminder")) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Lang.isFrench
                            ? ["@demain 14h", "@14h30", "@lundi 9h", "@25/12 10:00", "@dans 30min"]
                            : ["@tomorrow 2pm", "@14:30", "@monday 9am", "@25/12 10:00", "@in 30min"], id: \.self) {
                        Text($0).font(.system(size: 12, design: .monospaced)).foregroundStyle(.orange)
                    }
                    Text(tr("A checked task sends no reminder."))
                        .font(.caption).foregroundStyle(.secondary).padding(.top, 2)
                }
            }
        }
        .formStyle(.grouped)
        .task {
            let s = await UNUserNotificationCenter.current().notificationSettings()
            status = s.authorizationStatus
        }
    }
}

// MARK: - Data

private struct DataSettings: View {
    @EnvironmentObject var store: NoteStore
    @State private var exportResult: String?

    var body: some View {
        Form {
            Section {
                LabeledContent(tr("Your notes")) {
                    Button(tr("Show in Finder")) {
                        NSWorkspace.shared.activateFileViewerSelecting([store.fileURL])
                    }
                }
                LabeledContent(tr("Export as Markdown")) {
                    Button(tr("Export…")) { export() }
                }
                if let exportResult { Text(exportResult).font(.caption).foregroundStyle(.secondary) }
            }
            Section {
                LabeledContent(tr("Trash")) {
                    Button(tr("Empty now"), role: .destructive) { store.emptyTrash() }
                        .disabled(store.count(.trash) == 0)
                }
                Text(tr("Notes in the Trash are deleted after 30 days. A backup is made at every launch."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func export() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = tr("Export here")
        guard panel.runModal() == .OK, let dir = panel.url else { return }
        let n = store.exportMarkdown(to: dir)
        exportResult = trf("%lld notes exported", n)
        NSWorkspace.shared.open(dir)
    }
}

// MARK: - Shortcut recorder

struct HotKeyRecorder: View {
    @State private var recording = false
    @State private var display = Prefs.hotKeyDisplay
    @State private var monitor: Any?
    @State private var error: String?

    var body: some View {
        HStack(spacing: 8) {
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            Button(recording ? tr("Type your shortcut…") : display) {
                recording ? stop() : start()
            }
            .frame(minWidth: 130)
        }
    }

    private func start() {
        error = nil
        recording = true
        HotKeyManager.shared.unregister()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            if e.keyCode == 53 { stop(); return nil } // Esc cancels
            let flags = e.modifierFlags.intersection([.command, .option, .control, .shift])
            let hasMainModifier = !flags.isDisjoint(with: [.command, .option, .control])
            guard hasMainModifier || HotKeyManager.isFunctionKey(e.keyCode) else {
                error = tr("Add ⌘, ⌥ or ⌃")
                return nil
            }
            let mods = HotKeyManager.carbonModifiers(from: flags)
            if HotKeyManager.shared.register(keyCode: UInt32(e.keyCode), modifiers: mods) {
                Prefs.hotKeyCode = UInt32(e.keyCode)
                Prefs.hotKeyModifiers = mods
                Prefs.hotKeyDisplay = HotKeyManager.display(for: e)
                display = Prefs.hotKeyDisplay
                error = nil
            } else {
                error = tr("Already in use")
            }
            stop()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
        HotKeyManager.shared.registerFromPrefs()
    }
}
