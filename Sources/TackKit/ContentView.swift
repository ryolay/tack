import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: NoteStore
    @AppStorage("language") private var language = "system"

    var body: some View {
        MainView()
            .environment(\.layoutDirection, Lang.layoutDirection)
            .environment(\.locale, Lang.locale)
            .id(language) // rebuild everything when the language changes
    }
}

private struct MainView: View {
    @EnvironmentObject var store: NoteStore
    @AppStorage("showSidebar") private var showSidebar = true
    @AppStorage("fontSize") private var fontSize = 15.0
    @AppStorage("fontFamily") private var fontFamily = "system"
    @AppStorage("editorMode") private var editorMode = "simple"
    @FocusState private var searchFocused: Bool
    @State private var showHelp = false

    var body: some View {
        HStack(spacing: 0) {
            if showSidebar {
                sidebar
                    .frame(width: 236)
                    .background(Color.primary.opacity(0.035))
                    .transition(.move(edge: .leading).combined(with: .opacity))
                Divider()
            }
            editor
        }
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.85))
        .ignoresSafeArea()
        .animation(.easeOut(duration: 0.15), value: showSidebar)
        .onChange(of: store.focusRequest) { _, req in
            guard let req else { return }
            if req.target == .search && !showSidebar { showSidebar = true }
            DispatchQueue.main.async { searchFocused = req.target == .search }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 8) {
            searchField.padding(.top, 14)

            if store.scope != .notes {
                Button { store.setScope(.notes) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                        Text(store.scope.label).fontWeight(.semibold)
                        Spacer()
                    }
                    .font(.system(size: 12))
                    .padding(.horizontal, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            let tags = store.allTags
            if !tags.isEmpty { tagBar(tags) }

            noteList

            if store.scope == .trash, store.count(.trash) > 0 {
                Button(tr("Empty Trash"), role: .destructive) { store.emptyTrash() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.red)
            }

            newNoteButton

            if store.scope == .notes {
                HStack {
                    scopeLink(.archive)
                    Spacer()
                    scopeLink(.trash)
                }
                .padding(.horizontal, 4)
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 12)
    }

    private func scopeLink(_ s: Scope) -> some View {
        let n = store.count(s)
        return Button { store.setScope(s) } label: {
            HStack(spacing: 4) {
                Image(systemName: s.icon)
                Text(s.label)
                if n > 0 { Text("\(n)").monospacedDigit().foregroundStyle(.tertiary) }
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(tr("Search"), text: $store.search)
                .textFieldStyle(.plain)
                .focused($searchFocused)
            if !store.search.isEmpty {
                Button { store.search = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }.buttonStyle(.plain)
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 9).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.07)))
    }

    private func tagBar(_ tags: [(tag: String, count: Int)]) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 4) {
                ForEach(tags, id: \.tag) { t in
                    let active = store.tagFilter == t.tag
                    Button { store.toggleTag(t.tag) } label: {
                        Text("#" + t.tag)
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Capsule().fill(active ? Color.accentColor : Color.accentColor.opacity(0.12)))
                            .foregroundStyle(active ? Color.white : Color.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollIndicators(.never)
    }

    private var noteList: some View {
        let list = store.filtered
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(list) { note in
                        NoteRow(note: note, selected: note.id == store.selectedID)
                            .id(note.id)
                            .onTapGesture {
                                store.select(note.id)
                                store.requestFocus(.editor)
                            }
                            .contextMenu { noteMenu(note) }
                    }
                }
            }
            .scrollIndicators(.never)
            .onChange(of: store.selectedID) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(id) }
            }
            .overlay {
                if list.isEmpty {
                    Text(emptyMessage)
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
            }
        }
    }

    private var emptyMessage: String {
        if !store.search.isEmpty { return tr("No results") }
        switch store.scope {
        case .notes: return tr("No notes")
        case .archive: return tr("Nothing archived")
        case .trash: return tr("Trash is empty\nEmptied after 30 days")
        }
    }

    /// Shared menu: right-click in the list and the editor's "…" button.
    @ViewBuilder
    private func noteMenu(_ note: Note) -> some View {
        if note.isTrashed {
            Button(tr("Restore")) { store.restore(note.id) }
            Button(tr("Delete Permanently"), role: .destructive) { store.deleteForever(note.id) }
        } else {
            Button { store.togglePin(note.id) } label: {
                Label(note.pinned ? tr("Remove from Favorites") : tr("Add to Favorites"),
                      systemImage: note.pinned ? "star.slash" : "star")
            }
            Button { store.toggleArchive(note.id) } label: {
                Label(note.archived ? tr("Unarchive") : tr("Archive"), systemImage: "archivebox")
            }
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(note.text, forType: .string)
            } label: {
                Label(tr("Copy Text"), systemImage: "doc.on.doc")
            }
            Divider()
            Button(role: .destructive) { store.trash(note.id) } label: {
                Label(tr("Move to Trash"), systemImage: "trash")
            }
        }
    }

    private var newNoteButton: some View {
        Button { store.newNote() } label: {
            HStack {
                Image(systemName: "plus")
                Text(tr("New Note"))
                Spacer()
                Text("⌘N").foregroundStyle(.tertiary)
            }
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 10).padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
    }

    // MARK: - Editor

    @ViewBuilder
    private var editor: some View {
        VStack(spacing: 0) {
            header
            if let note = store.selected {
                if note.isTrashed {
                    HStack {
                        Image(systemName: "trash")
                        Text(tr("This note is in the Trash"))
                        Spacer()
                        Button(tr("Restore")) { store.restore(note.id) }
                    }
                    .font(.system(size: 12))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.15)))
                    .padding(.horizontal, 16).padding(.bottom, 4)
                }
                MarkdownEditor(
                    noteID: note.id,
                    text: note.text,
                    focusToken: store.focusRequest?.target == .editor ? store.focusRequest?.token : nil,
                    styleKey: "\(fontSize)-\(fontFamily)-\(editorMode)",
                    onChange: { store.updateSelected(text: $0) }
                )
                footer(note)
            } else {
                VStack(spacing: 10) {
                    Text(tr("No note selected")).foregroundStyle(.secondary)
                    Button(tr("New Note")) { store.newNote() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .overlay(alignment: .bottom) { toastView }
    }

    private var header: some View {
        HStack(spacing: 10) {
            IconButton(symbol: "sidebar.left", active: !showSidebar,
                       help: tr("Show / hide list (⌘0)")) {
                showSidebar.toggle()
            }
            if let note = store.selected, !note.isTrashed {
                Divider().frame(height: 14)
                formatButton("textformat", tr("Title"), .title)
                formatButton("checklist", tr("Checklist (⇧⌘L)"), .checklist)
                formatButton("list.bullet", tr("Bulleted list"), .bullet)
                formatButton("list.number", tr("Numbered list"), .numbered)
            }
            Spacer()
            IconButton(symbol: store.keepOpen ? "pin.fill" : "pin", active: store.keepOpen,
                       help: store.keepOpen ? tr("Window stays on top (⌘⇧K)")
                                            : tr("Keep window open (⌘⇧K)")) {
                store.keepOpen.toggle()
            }
            Menu {
                if let note = store.selected { noteMenu(note); Divider() }
                Button { showHelp = true } label: { Label(tr("Shortcuts"), systemImage: "keyboard") }
                Button { store.onOpenSettings?() } label: { Label(tr("Settings…"), systemImage: "gearshape") }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(tr("More"))
            .popover(isPresented: $showHelp, arrowEdge: .bottom) { HelpView() }
            IconButton(symbol: "xmark", help: tr("Close (Esc)")) { store.close() }
        }
        .padding(.horizontal, 14)
        .padding(.top, 11)
        .padding(.bottom, 4)
    }

    private func formatButton(_ symbol: String, _ help: String, _ style: LineStyle) -> some View {
        IconButton(symbol: symbol, help: help) {
            NotificationCenter.default.post(name: .tackEditorCommand, object: style.rawValue)
        }
    }

    private func footer(_ note: Note) -> some View {
        HStack(spacing: 12) {
            Text(trf("Edited %@", note.updated.formatted(.relative(presentation: .named).locale(Lang.locale))))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            if note.nextReminder != nil, store.notificationsDenied {
                Button { ReminderScheduler.openSystemSettings() } label: {
                    Label(tr("Notifications off — enable"), systemImage: "bell.slash.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
            } else if let next = note.nextReminder {
                Label(trf("Reminder %@", next.formatted(.relative(presentation: .named).locale(Lang.locale))), systemImage: "bell.fill")
                    .foregroundStyle(.orange)
                    .help(next.formatted(Date.FormatStyle(date: .complete, time: .shortened).locale(Lang.locale)))
            }
            Spacer()
            Text(stats(note.text)).foregroundStyle(.tertiary)
        }
        .font(.system(size: 10))
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var toastView: some View {
        if let t = store.toast {
            HStack(spacing: 12) {
                Text(t.message)
                Button(tr("Undo")) { store.undoToast() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .fontWeight(.semibold)
            }
            .font(.system(size: 12))
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Capsule().fill(.regularMaterial).shadow(radius: 4, y: 1))
            .padding(.bottom, 34)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func stats(_ text: String) -> String {
        let words = text.split { $0.isWhitespace || $0.isNewline }.count
        return trf("%lld words", words)
    }
}

struct HelpView: View {
    private var sections: [(String, [(String, String)])] {
        [
            (tr("Writing"), [
                ("- [ ]", tr("Checkbox (or ⇧⌘L)")),
                ("# ## ###", tr("Headings")),
                ("⌘B  ⌘I", tr("Bold, italic")),
                ("#tag", tr("Tag to filter")),
                (tr("@tomorrow 2pm"), tr("Reminder")),
            ]),
            (tr("Navigate"), [
                ("⌘N", tr("New note")),
                ("⌘F", tr("Search")),
                ("⌘1…9", tr("Jump to note")),
                ("⌘0", tr("Hide list")),
                ("⌘⇧K", tr("Keep window open")),
                ("Esc", tr("Close")),
            ]),
            (tr("Organize"), [
                ("⌘⇧P", tr("Favorite")),
                ("⌘⇧A", tr("Archive")),
                ("⌘⇧⌫", tr("Trash")),
            ]),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(sections, id: \.0) { section in
                VStack(alignment: .leading, spacing: 5) {
                    Text(section.0).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
                        ForEach(section.1, id: \.0) { r in
                            GridRow {
                                Text(r.0).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                                    .frame(minWidth: 96, alignment: .leading)
                                Text(r.1).font(.system(size: 12))
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
    }
}

struct NoteRow: View {
    let note: Note
    let selected: Bool

    static func shortReminder(_ d: Date) -> String {
        let cal = Calendar.current
        let time = d.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(Lang.locale))
        if cal.isDateInToday(d) { return time }
        if cal.isDateInTomorrow(d) { return trf("Tomorrow %@", time) }
        return d.formatted(.dateTime.day().month(.abbreviated).locale(Lang.locale)) + " " + time
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(note.isEmpty ? tr("New Note") : note.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if note.pinned {
                    Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(.yellow)
                }
            }
            HStack(spacing: 6) {
                Text(note.shortDate).fixedSize()
                if let r = note.nextReminder {
                    Label(Self.shortReminder(r), systemImage: "bell.fill")
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(.orange)
                }
                if let c = note.checklist {
                    Label("\(c.done)/\(c.total)", systemImage: c.done == c.total ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(c.done == c.total ? Color.green : Color.accentColor)
                        .monospacedDigit()
                        .fixedSize()
                }
                Text(note.preview).lineLimit(1).layoutPriority(-1)
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 7).fill(selected ? Color.accentColor.opacity(0.22) : .clear))
        .contentShape(Rectangle())
    }
}

struct IconButton: View {
    let symbol: String
    var active = false
    let help: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(active ? Color.accentColor : (hover ? Color.primary : Color.secondary))
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: 5).fill(hover ? Color.primary.opacity(0.08) : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(help)
    }
}
