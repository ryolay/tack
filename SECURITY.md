# Security policy

## Reporting a vulnerability

Please **do not open a public issue**. Use GitHub's private reporting instead: **Security › Report a vulnerability** on this repository. Include steps to reproduce and the impact you expect.

You should get a first answer within a week.

## How Tack treats your data

- Notes are stored locally in `~/Library/Application Support/Tack/notes.json`, with a copy in `notes.backup.json` taken at every launch. A file that cannot be read is set aside, never overwritten.
- Tack makes **no network requests**: no account, no sync server, no analytics, no telemetry.
- The global shortcut uses the Carbon hotkey API, so Tack needs **no Accessibility permission** and never sees what you type in other apps.
- Reminders are scheduled with the system notification center on your Mac.
- Release builds are ad-hoc signed and built by GitHub Actions from the tagged commit; the `SHA256SUMS.txt` file attached to each release lets you check your download.
