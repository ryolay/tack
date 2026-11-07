import XCTest
@testable import TackKit

final class NoteTests: XCTestCase {
    func testTitleStripsMarkdown() {
        XCTAssertEqual(Note(text: "# Groceries\nmilk").title, "Groceries")
        XCTAssertEqual(Note(text: "- [ ] **Buy** bread").title, "Buy bread")
        XCTAssertEqual(Note(text: "\n\n  Hello  ").title, "Hello")
    }

    func testPreviewUsesFollowingLines() {
        XCTAssertEqual(Note(text: "Title\n- [ ] one\ntwo\nthree").preview, "one two")
    }

    func testChecklistProgress() {
        let note = Note(text: "- [x] a\n- [ ] b\n* [X] c\nnot a task")
        XCTAssertEqual(note.checklist?.done, 2)
        XCTAssertEqual(note.checklist?.total, 3)
        XCTAssertNil(Note(text: "no tasks").checklist)
    }

    func testTags() {
        let note = Note(text: "#Work meeting #perso\nsee https://site.com/#anchor and #work again, #42 is not a tag")
        XCTAssertEqual(note.tags, ["work", "perso"])
    }

    func testDecodingOldFilesWithoutNewFields() throws {
        let json = #"[{"id":"5272526F-FD6E-45D3-8A5B-4E5D2A1A1A1A","text":"hi","created":"2026-11-07T18:00:00Z"}]"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let notes = try decoder.decode([Note].self, from: Data(json.utf8))
        XCTAssertEqual(notes.first?.text, "hi")
        XCTAssertEqual(notes.first?.archived, false)
        XCTAssertNil(notes.first?.deletedAt)
    }
}
