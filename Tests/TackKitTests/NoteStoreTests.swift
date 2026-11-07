import XCTest
@testable import TackKit

@MainActor
final class NoteStoreTests: XCTestCase {
    private var dir: URL!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("TackTests-\(UUID().uuidString)")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeStore(with texts: [String] = []) -> NoteStore {
        let store = NoteStore(directory: dir)
        for text in texts {
            store.newNote()
            store.updateSelected(text: text)
        }
        return store
    }

    func testFirstLaunchCreatesWelcomeNote() {
        let store = NoteStore(directory: dir)
        XCTAssertTrue(store.isFirstLaunch)
        XCTAssertEqual(store.notes.count, 1)
        XCTAssertTrue(store.notes[0].pinned)
    }

    func testNewNoteReusesAnEmptyNote() {
        let store = makeStore()
        store.newNote()
        let count = store.notes.count
        store.newNote()
        XCTAssertEqual(store.notes.count, count, "a second empty note must not be created")
    }

    func testTrashUndoAndRestore() throws {
        let store = makeStore(with: ["keep me"])
        let id = try XCTUnwrap(store.selectedID)
        store.trash(id)
        XCTAssertTrue(store.notes.first { $0.id == id }!.isTrashed)
        XCTAssertNotNil(store.toast)
        store.undoToast()
        XCTAssertFalse(store.notes.first { $0.id == id }!.isTrashed)

        store.trash(id)
        store.restore(id)
        XCTAssertFalse(store.notes.first { $0.id == id }!.isTrashed)
    }

    func testArchiveMovesNoteOutOfNotesScope() throws {
        let store = makeStore(with: ["archive me"])
        let id = try XCTUnwrap(store.selectedID)
        store.toggleArchive(id)
        XCTAssertFalse(store.filtered.contains { $0.id == id })
        store.setScope(.archive)
        XCTAssertTrue(store.filtered.contains { $0.id == id })
    }

    func testSearchAndTagFilter() {
        let store = makeStore(with: ["Buy coffee #home", "Call the bank #work"])
        store.search = "COFFEE"
        XCTAssertEqual(store.filtered.map(\.title), ["Buy coffee #home"])
        store.search = ""
        store.toggleTag("work")
        XCTAssertEqual(store.filtered.map(\.title), ["Call the bank #work"])
    }

    func testPersistenceRoundTrip() {
        let store = makeStore(with: ["persisted"])
        store.saveNow()
        let reloaded = NoteStore(directory: dir)
        XCTAssertTrue(reloaded.notes.contains { $0.text == "persisted" })
        XCTAssertFalse(reloaded.isFirstLaunch)
    }

    func testUnreadableFileIsSetAsideNotOverwritten() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: dir.appendingPathComponent("notes.json"))
        _ = NoteStore(directory: dir)
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertTrue(files.contains { $0.hasPrefix("notes.unreadable-") })
    }

    func testExportMarkdown() throws {
        let store = makeStore(with: ["# Groceries\nmilk", "Ideas/plans"])
        let out = dir.appendingPathComponent("export")
        XCTAssertEqual(store.exportMarkdown(to: out), 3) // + welcome note
        let files = try FileManager.default.contentsOfDirectory(atPath: out.path)
        XCTAssertTrue(files.contains("Groceries.md"))
        XCTAssertTrue(files.contains("Ideas-plans.md"))
    }
}
