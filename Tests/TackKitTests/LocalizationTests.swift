import XCTest
@testable import TackKit

/// Guards the String Catalog: every UI string is translated into every shipped language,
/// placeholders survive translation, and the catalog matches the code.
final class LocalizationTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private struct Catalog {
        /// key → language → every translated variant (one value, or one per plural form)
        let strings: [String: [String: [String]]]
    }

    private func loadCatalog() throws -> Catalog {
        let url = Self.root.appendingPathComponent("Resources/Localizable.xcstrings")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let raw = try XCTUnwrap(json["strings"] as? [String: [String: Any]])
        var strings: [String: [String: [String]]] = [:]
        for (key, entry) in raw {
            let locs = entry["localizations"] as? [String: [String: Any]] ?? [:]
            strings[key] = locs.mapValues(Self.values)
        }
        return Catalog(strings: strings)
    }

    private static func values(_ loc: [String: Any]) -> [String] {
        if let unit = loc["stringUnit"] as? [String: Any], let value = unit["value"] as? String { return [value] }
        let plural = (loc["variations"] as? [String: Any])?["plural"] as? [String: [String: Any]] ?? [:]
        return plural.values.compactMap { ($0["stringUnit"] as? [String: Any])?["value"] as? String }
    }

    private static func placeholders(_ s: String) -> [String] {
        let re = RegexFactory.make("%(?:@|lld|d)")
        return re.matches(in: s, range: NSRange(s.startIndex..., in: s))
            .map { (s as NSString).substring(with: $0.range) }.sorted()
    }

    func testEveryStringIsTranslatedIntoEveryLanguage() throws {
        let catalog = try loadCatalog()
        let languages = Lang.all.map(\.code).filter { $0 != "en" }
        for (key, locs) in catalog.strings {
            for lang in languages {
                let values = locs[lang] ?? []
                XCTAssertFalse(values.isEmpty, "\(lang) is missing: \(key.prefix(60))")
                XCTAssertFalse(values.contains { $0.trimmingCharacters(in: .whitespaces).isEmpty },
                               "\(lang) has an empty translation for: \(key.prefix(60))")
            }
        }
    }

    func testPlaceholdersSurviveTranslation() throws {
        for (key, locs) in try loadCatalog().strings {
            let expected = Self.placeholders(key)
            for (lang, values) in locs {
                for value in values {
                    XCTAssertEqual(Self.placeholders(value), expected, "\(lang): \(value)")
                }
            }
        }
    }

    func testWelcomeNoteKeepsItsMarkdown() throws {
        let welcome = try XCTUnwrap(try loadCatalog().strings.first { $0.key.hasPrefix("# Welcome to Tack") })
        for (lang, values) in welcome.value {
            let text = try XCTUnwrap(values.first)
            XCTAssertTrue(text.hasPrefix("# "), "\(lang): the title must stay a heading")
            XCTAssertTrue(text.contains("- [ ]") && text.contains("- [x]"), "\(lang): checkboxes must survive")
            XCTAssertTrue(text.contains("⌃⌥N"), "\(lang): the shortcut must survive")
        }
    }

    func testEveryKeyUsedInCodeIsInTheCatalog() throws {
        let catalog = try loadCatalog()
        let sources = Self.root.appendingPathComponent("Sources/TackKit")
        let files = try FileManager.default.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)
        let call = RegexFactory.make(#"\btrf?\(\s*"((?:[^"\\]|\\.)*)""#)
        for file in files where file.pathExtension == "swift" {
            let code = try String(contentsOf: file, encoding: .utf8)
            for match in call.matches(in: code, range: NSRange(code.startIndex..., in: code)) {
                let key = (code as NSString).substring(with: match.range(at: 1))
                    .replacingOccurrences(of: "\\n", with: "\n").replacingOccurrences(of: "\\\"", with: "\"")
                XCTAssertNotNil(catalog.strings[key], "\(file.lastPathComponent): \(key) is not in Localizable.xcstrings")
            }
        }
    }

    func testRightToLeftLanguages() {
        let rtl = Lang.all.filter { Locale.Language(identifier: $0.code).characterDirection == .rightToLeft }.map(\.code)
        XCTAssertEqual(Set(rtl), ["ar", "he"])
    }
}
