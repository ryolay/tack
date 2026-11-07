# Contributing to Tack

Thanks for helping! Tack aims to stay **quick, simple and private**: open, write, close. Every feature has to earn its place in a panel you open dozens of times a day.

## Getting started

You need macOS 14 or later and Xcode 16 or later (or the matching Swift toolchain).

```bash
git clone https://github.com/ryolay/tack.git
cd tack
swift test               # unit tests
./build.sh install       # build Tack.app, copy it to /Applications and launch it
```

The code lives in `Sources/TackKit` (everything testable) and `Sources/Tack` (the tiny executable that starts the app).

| File | What it does |
| --- | --- |
| `PanelController.swift` | The floating panel, full-screen behaviour and keyboard shortcuts |
| `MarkdownEditor.swift` | The text view: live styling, Simple mode drawing, lists and checkboxes |
| `NoteStore.swift` | Notes, search, tags, archive, Trash and persistence |
| `Reminders.swift` | `@reminder` parsing and macOS notifications |
| `SettingsView.swift` | The Settings window |

## Before you open a pull request

1. `swiftlint lint --strict` passes (Codacy runs the same rules from `.swiftlint.yml`).
2. `swift test` passes. New behaviour comes with a test in `Tests/TackKitTests`.
3. You tried the change in the real app with `./build.sh install`.
4. UI changes include a screenshot in the PR description (light **and** dark theme).
5. Keep the PR focused: one feature or fix per PR.

`main` is protected: every change goes through a pull request with green checks, and is merged with squash or rebase.

## Guidelines

- **Your notes are sacred.** Never overwrite the notes file blindly; destructive actions are undoable (Trash, undo toast).
- **No dependencies** without a very good reason. Tack is plain Swift, SwiftUI and AppKit.
- **Every UI string is translated**: use `L("Texte français", "English text")`.
- Write code, comments and commit messages in English. Commit messages follow [Conventional Commits](https://www.conventionalcommits.org) (`feat:`, `fix:`, `docs:`…).

## Releasing

Update `CHANGELOG.md` and the version in `Resources/Info.plist`, merge, then push a tag such as `v0.2.0`. The release workflow builds a universal app and publishes it with checksums.
