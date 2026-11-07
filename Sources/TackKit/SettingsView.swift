import SwiftUI
import ServiceManagement
import UserNotifications

struct SettingsView: View {
    @AppStorage("language") private var language = "system"

    var body: some View {
        SettingsTabs().id(language)
    }
}

private struct SettingsTabs: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label(L("Général", "General"), systemImage: "gearshape") }
            AppearanceSettings()
                .tabItem { Label(L("Apparence", "Appearance"), systemImage: "paintbrush") }
            ReminderSettings()
                .tabItem { Label(L("Rappels", "Reminders"), systemImage: "bell") }
            DataSettings()
                .tabItem { Label(L("Données", "Data"), systemImage: "externaldrive") }
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
                LabeledContent(L("Raccourci pour ouvrir", "Shortcut to open")) { HotKeyRecorder() }
                Picker(L("Le raccourci ouvre", "Shortcut opens"), selection: $openMode) {
                    Text(L("Une nouvelle note", "A new note")).tag(OpenMode.newNote.rawValue)
                    Text(L("La dernière note", "The last note")).tag(OpenMode.lastNote.rawValue)
                }
                Toggle(L("Fermer quand je clique ailleurs", "Close when clicking elsewhere"), isOn: $hideOnFocusLoss)
            }
            Section {
                Toggle(L("Ouvrir Tack au démarrage du Mac", "Open Tack at login"), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            loginError = nil
                        } catch {
                            loginError = L("Impossible : l'app doit être dans /Applications",
                                           "Failed: the app must be in /Applications")
                        }
                    }
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
                Picker(L("Langue", "Language"), selection: $language) {
                    Text(L("Comme le système", "Same as system")).tag("system")
                    Text("Français").tag("fr")
                    Text("English").tag("en")
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
                Picker(L("Style d'écriture", "Writing style"), selection: $editorMode) {
                    Text(L("Simple", "Simple")).tag("simple")
                    Text("Markdown").tag("markdown")
                }
                .pickerStyle(.segmented)
                Text(editorMode == "simple"
                     ? L("Comme Notes : ronds à cocher, puces et titres, sans symboles visibles.",
                         "Like Notes: tick circles, bullets and titles, no visible symbols.")
                     : L("Les symboles Markdown restent visibles : - [ ], #, **gras**…",
                         "Markdown symbols stay visible: - [ ], #, **bold**…"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Picker(L("Thème", "Theme"), selection: $theme) {
                    Text(L("Auto", "Auto")).tag("system")
                    Text(L("Clair", "Light")).tag("light")
                    Text(L("Sombre", "Dark")).tag("dark")
                }
                .pickerStyle(.segmented)
            }
            Section {
                Picker(L("Police", "Font"), selection: $fontFamily) {
                    Text(L("Système", "System")).tag("system")
                    Text("Serif").tag("serif")
                    Text(L("Arrondie", "Rounded")).tag("rounded")
                    Text("Mono").tag("mono")
                }
                LabeledContent(L("Taille", "Size")) {
                    HStack {
                        Slider(value: $fontSize, in: 12...22, step: 1).frame(width: 180)
                        Text("\(Int(fontSize))").monospacedDigit().frame(width: 24)
                    }
                }
                Text(L("Le renard brun rapide saute par-dessus le chien.", "The quick brown fox jumps over the lazy dog."))
                    .font(previewFont)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle(L("Afficher la liste des notes (⌘0)", "Show the notes list (⌘0)"), isOn: $showSidebar)
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
                LabeledContent(L("Notifications", "Notifications")) {
                    switch status {
                    case .authorized, .provisional:
                        Label(L("Activées", "On"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    case .denied:
                        Button(L("Activer dans Réglages Système", "Enable in System Settings")) {
                            ReminderScheduler.openSystemSettings()
                        }
                    default:
                        Text(L("Demandées au premier rappel", "Asked on first reminder")).foregroundStyle(.secondary)
                    }
                }
                Toggle(L("Jouer un son", "Play a sound"), isOn: $reminderSound)
                Picker(L("Heure si aucune n'est précisée", "Time when none is given"), selection: $reminderHour) {
                    ForEach(6..<22, id: \.self) { h in Text(String(format: "%02d:00", h)).tag(h) }
                }
            }
            Section(L("Comment écrire un rappel", "How to write a reminder")) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Lang.isFrench
                            ? ["@demain 14h", "@14h30", "@lundi 9h", "@25/12 10:00", "@dans 30min"]
                            : ["@tomorrow 2pm", "@14:30", "@monday 9am", "@25/12 10:00", "@in 30min"], id: \.self) {
                        Text($0).font(.system(size: 12, design: .monospaced)).foregroundStyle(.orange)
                    }
                    Text(L("Une tâche cochée n'envoie pas de rappel.", "A checked task sends no reminder."))
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
                LabeledContent(L("Tes notes", "Your notes")) {
                    Button(L("Afficher dans le Finder", "Show in Finder")) {
                        NSWorkspace.shared.activateFileViewerSelecting([store.fileURL])
                    }
                }
                LabeledContent(L("Exporter en Markdown", "Export as Markdown")) {
                    Button(L("Exporter…", "Export…")) { export() }
                }
                if let exportResult { Text(exportResult).font(.caption).foregroundStyle(.secondary) }
            }
            Section {
                LabeledContent(L("Corbeille", "Trash")) {
                    Button(L("Vider maintenant", "Empty now"), role: .destructive) { store.emptyTrash() }
                        .disabled(store.count(.trash) == 0)
                }
                Text(L("Les notes de la corbeille sont supprimées après 30 jours. Une sauvegarde est faite à chaque lancement.",
                       "Notes in the Trash are deleted after 30 days. A backup is made at every launch."))
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
        panel.prompt = L("Exporter ici", "Export here")
        guard panel.runModal() == .OK, let dir = panel.url else { return }
        let n = store.exportMarkdown(to: dir)
        exportResult = L("\(n) note(s) exportée(s)", "\(n) note(s) exported")
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
            Button(recording ? L("Tape ton raccourci…", "Type your shortcut…") : display) {
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
                error = L("Ajoute ⌘, ⌥ ou ⌃", "Add ⌘, ⌥ or ⌃")
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
                error = L("Déjà utilisé", "Already in use")
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
