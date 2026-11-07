import Foundation
import UserNotifications
import AppKit

struct Reminder {
    let noteID: UUID
    let text: String
    let noteTitle: String
    let date: Date
}

/// Syntax: @demain 14h · @14h30 · @lundi 9h · @25/12 10:00 · @dans 30min
///           @tomorrow 2pm · @friday · @in 2h
enum ReminderParser {
    private static let time = #"\d{1,2}(?:[h:]\d{0,2}|\s?[ap]m)"#
    private static let days = [
        "aujourd'hui", "auj", "today", "après-demain", "apres-demain", "demain", "tomorrow",
        "lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi", "dimanche",
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
        #"\d{1,2}[/.]\d{1,2}(?:[/.]\d{2,4})?"#
    ].joined(separator: "|")
    private static let relative = #"(?:dans|in)\s+(?<rn>\d+)\s*(?<ru>min|m|h)"#
    private static let dayAndTime = #"(?<day>\#(days))(?:\s+(?:à\s+|at\s+)?(?<t1>\#(time)))?"#

    static let regex = RegexFactory.make(
        #"(?<![\w@])@(?:\#(relative)|\#(dayAndTime)|(?<t2>\#(time)))(?![\w])"#,
        options: [.caseInsensitive]
    )

    private static let weekdays: [String: Int] = [
        "dimanche": 1, "lundi": 2, "mardi": 3, "mercredi": 4, "jeudi": 5, "vendredi": 6, "samedi": 7,
        "sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4, "thursday": 5, "friday": 6, "saturday": 7,
    ]

    static func date(from m: NSTextCheckingResult, in s: NSString, now: Date = Date()) -> Date? {
        func g(_ name: String) -> String? {
            let r = m.range(withName: name)
            return r.location == NSNotFound ? nil : s.substring(with: r).lowercased()
        }
        let cal = Calendar.current

        if let n = g("rn"), let v = Int(n), let unit = g("ru") {
            return now.addingTimeInterval(Double(v) * (unit == "h" ? 3600 : 60))
        }

        var hm: (Int, Int)?
        if let t = g("t1") ?? g("t2") {
            guard let parsed = parseTime(t) else { return nil }
            hm = parsed
        }
        let (h, mi) = hm ?? (Prefs.reminderHour, 0)

        if let d = g("day") {
            guard let day = parseDay(d, now: now) else { return nil }
            return cal.date(bySettingHour: h, minute: mi, second: 0, of: day)
        }
        guard var d = cal.date(bySettingHour: h, minute: mi, second: 0, of: now) else { return nil }
        if d <= now { d = cal.date(byAdding: .day, value: 1, to: d) ?? d }
        return d
    }

    private static func parseTime(_ t: String) -> (Int, Int)? {
        let s = t.replacingOccurrences(of: " ", with: "")
        if s.hasSuffix("am") || s.hasSuffix("pm") {
            guard var h = Int(s.dropLast(2)), (1...12).contains(h) else { return nil }
            if s.hasSuffix("pm") && h < 12 { h += 12 }
            if s.hasSuffix("am") && h == 12 { h = 0 }
            return (h, 0)
        }
        let parts = s.split(whereSeparator: { $0 == "h" || $0 == ":" }).map(String.init)
        guard let h = Int(parts.first ?? ""), h < 24 else { return nil }
        let mi = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        return mi < 60 ? (h, mi) : nil
    }

    private static func parseDay(_ d: String, now: Date) -> Date? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        switch d {
        case "aujourd'hui", "auj", "today": return today
        case "demain", "tomorrow": return cal.date(byAdding: .day, value: 1, to: today)
        case "après-demain", "apres-demain": return cal.date(byAdding: .day, value: 2, to: today)
        default: break
        }
        if let wd = weekdays[d] {
            return cal.nextDate(after: today, matching: DateComponents(weekday: wd), matchingPolicy: .nextTime)
        }
        let nums = d.split(whereSeparator: { $0 == "/" || $0 == "." }).compactMap { Int($0) }
        guard nums.count >= 2 else { return nil }
        var comps = DateComponents(year: cal.component(.year, from: now), month: nums[1], day: nums[0])
        if nums.count == 3 { comps.year = nums[2] < 100 ? 2000 + nums[2] : nums[2] }
        guard var date = cal.date(from: comps), cal.component(.day, from: date) == nums[0] else { return nil }
        // Without a year, use the closest occurrence (a recent past reminder stays in the past)
        if nums.count == 2, let limit = cal.date(byAdding: .day, value: -60, to: today), date < limit {
            date = cal.date(byAdding: .year, value: 1, to: date) ?? date
        }
        return date
    }

    static let checkedLine = RegexFactory.make(#"^\s*[-*+] \[[xX]\]"#)

    private static let canonical = RegexFactory.make(#"^@\d{2}/\d{2}(?:/\d{4})? \d{2}:\d{2}$"#)
    private static let canonicalFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "dd/MM HH:mm"
        return f
    }()

    /// Turns relative reminders (@demain 14h, @dans 30min…) into exact dates (@08/11 14:00)
    /// so they do not drift when the note is reopened on another day.
    static func freeze(_ text: String, base: Date) -> String {
        guard text.contains("@") else { return text }
        let ns = NSMutableString(string: text)
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        for m in matches.reversed() {
            let token = (text as NSString).substring(with: m.range)
            if canonical.firstMatch(in: token, range: NSRange(location: 0, length: (token as NSString).length)) != nil { continue }
            guard let date = date(from: m, in: text as NSString, now: base) else { continue }
            ns.replaceCharacters(in: m.range, with: "@" + canonicalFormat.string(from: date))
        }
        return ns as String
    }
    private static let linePrefix = #"^\s*(?:[-*+] \[[ xX]\]\s*|[-*+]\s+|#{1,6}\s+)"#

    static func reminders(in note: Note, now: Date = Date()) -> [Reminder] {
        guard note.text.contains("@") else { return [] }
        var out: [Reminder] = []
        for line in note.text.components(separatedBy: .newlines) where line.contains("@") {
            let ns = line as NSString
            let full = NSRange(location: 0, length: ns.length)
            if checkedLine.firstMatch(in: line, range: full) != nil { continue } // task already done
            for m in regex.matches(in: line, range: full) {
                guard let date = date(from: m, in: ns, now: now) else { continue }
                var text = ns.replacingCharacters(in: m.range, with: "")
                if let r = text.range(of: linePrefix, options: .regularExpression) { text.removeSubrange(r) }
                text = text.trimmingCharacters(in: .whitespaces)
                out.append(Reminder(noteID: note.id, text: text.isEmpty ? note.title : text, noteTitle: note.title, date: date))
            }
        }
        return out
    }
}

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
        center.removeAllPendingNotificationRequests()
        guard !items.isEmpty else { return }

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
            guard granted else { return }
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
