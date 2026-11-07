import XCTest
@testable import TackKit

final class ReminderParserTests: XCTestCase {
    /// Saturday 7 November 2026, 19:00 local time.
    private let now: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 11; c.day = 7; c.hour = 19; c.minute = 0
        return Calendar.current.date(from: c)!
    }()

    private func reminderDates(_ text: String) -> [DateComponents] {
        ReminderParser.reminders(in: Note(text: text), now: now).map {
            Calendar.current.dateComponents([.month, .day, .hour, .minute], from: $0.date)
        }
    }

    private func expect(_ text: String, day: Int, month: Int = 11, hour: Int, minute: Int = 0,
                        file: StaticString = #filePath, line: UInt = #line) {
        let dates = reminderDates(text)
        XCTAssertEqual(dates.count, 1, "no reminder found in \(text)", file: file, line: line)
        guard let d = dates.first else { return }
        XCTAssertEqual([d.month, d.day, d.hour, d.minute], [month, day, hour, minute], text, file: file, line: line)
    }

    func testFrenchExpressions() {
        expect("@demain 14h", day: 8, hour: 14)
        expect("@demain à 8h15", day: 8, hour: 8, minute: 15)
        expect("@lundi 9h", day: 9, hour: 9)
        expect("@aujourd'hui 23h", day: 7, hour: 23)
        expect("@après-demain 10h", day: 9, hour: 10)
        expect("@dans 30min", day: 7, hour: 19, minute: 30)
    }

    func testEnglishExpressions() {
        expect("@tomorrow 2pm", day: 8, hour: 14)
        expect("@friday", day: 13, hour: 9)
        expect("@in 2h", day: 7, hour: 21)
        expect("@9am", day: 8, hour: 9)
    }

    func testTimeOnlyRollsToTomorrowWhenPast() {
        expect("@14h30", day: 8, hour: 14, minute: 30)
        expect("@21:15", day: 7, hour: 21, minute: 15)
    }

    func testExplicitDates() {
        expect("@25/12 10:00", day: 25, month: 12, hour: 10)
        expect("@08/11/2026 14:00", day: 8, hour: 14)
    }

    func testIgnoredText() {
        XCTAssertTrue(reminderDates("mail@test.com").isEmpty)
        XCTAssertTrue(reminderDates("@31/02").isEmpty)
        XCTAssertTrue(reminderDates("@25h").isEmpty)
        XCTAssertTrue(reminderDates("- [x] done @demain 14h").isEmpty, "checked tasks must not remind")
    }

    func testReminderTextDropsMarkersAndToken() {
        let r = ReminderParser.reminders(in: Note(text: "- [ ] call Marc @demain 14h"), now: now)
        XCTAssertEqual(r.first?.text, "call Marc")
    }

    func testFreezeTurnsRelativeIntoAbsoluteAndIsStable() {
        let frozen = ReminderParser.freeze("- [ ] call @demain 14h and @dans 30min", base: now)
        XCTAssertEqual(frozen, "- [ ] call @08/11 14:00 and @07/11 19:30")
        let later = now.addingTimeInterval(3 * 86_400)
        XCTAssertEqual(ReminderParser.freeze(frozen, base: later), frozen, "freezing must be idempotent")
    }
}
