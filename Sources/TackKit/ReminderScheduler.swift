import AppKit
import Foundation
import UserNotifications

/// Schedules macOS notifications from the @reminders in notes.
final class ReminderScheduler: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ReminderScheduler()
    var onOpenNote: ((UUID) -> Void)?

    /// Notifications only work from a real .app bundle (not from `swift test` or `swift run`).
    static var isAppBundle: Bool { Bundle.main.bundleURL.pathExtension == "app" }
    /// Called on the main thread with true when macOS denies notifications.
    var onDeniedChange: ((Bool) -> Void)?
    private var lastSignature = ""

    func start() {
        guard Self.isAppBundle else { return }
        UNUserNotificationCenter.current().delegate = self
    }

    func sync(notes: [Note]) {
        guard Self.isAppBundle else { return }
        let now = Date()
        let items = notes.filter { !$0.isTrashed }
            .flatMap { ReminderParser.reminders(in: $0, now: now) }
            .filter { $0.date > now }
            .sorted { $0.date < $1.date }
            .prefix(60)

        // Nothing changed → leave the scheduled notifications alone
        let signature = items.map { "\($0.noteID)|\($0.text)|\($0.date.timeIntervalSince1970)" }.joined(separator: "\n")
        guard signature != lastSignature else { return }
        lastSignature = signature

        let center = UNUserNotificationCenter.current()
        guard !items.isEmpty else {
            center.removeAllPendingNotificationRequests() // no reminder left in any note
            return
        }

        let requests: [UNNotificationRequest] = items.map { r in
            let content = UNMutableNotificationContent()
            content.title = r.text
            if r.text != r.noteTitle { content.subtitle = r.noteTitle }
            content.sound = Prefs.reminderSound ? .default : nil
            content.userInfo = ["noteID": r.noteID.uuidString]
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: r.date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            return UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        }
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async {
                self.onDeniedChange?(!granted)
                if !granted { self.lastSignature = "" } // retry once authorized
            }
            // Replace the scheduled reminders only once authorization is confirmed,
            // so a failed or denied request never wipes the existing ones.
            guard granted else { return }
            center.removeAllPendingNotificationRequests()
            requests.forEach { center.add($0) }
        }
    }

    static func openSystemSettings() {
        let id = Bundle.main.bundleIdentifier ?? ""
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)") {
            NSWorkspace.shared.open(url)
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let s = response.notification.request.content.userInfo["noteID"] as? String, let id = UUID(uuidString: s) {
            DispatchQueue.main.async { self.onOpenNote?(id) }
        }
        completionHandler()
    }
}
