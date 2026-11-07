import Foundation
import SwiftUI

/// A language Tack is translated into.
struct AppLanguage: Identifiable, Hashable {
    let code: String
    let flag: String
    var id: String { code }

    /// The language's own name, e.g. "Deutsch", "日本語", "العربية".
    var nativeName: String {
        let locale = Locale(identifier: code)
        let name = locale.localizedString(forIdentifier: code) ?? code
        return name.prefix(1).uppercased() + name.dropFirst()
    }
}

/// UI language: follows the system, or the "language" setting when the user picks one.
/// Strings live in `Resources/Localizable.xcstrings` (English is the source language).
enum Lang {
    /// Every language Tack ships, in the order shown in Settings and in the README.
    static let all: [AppLanguage] = [
        ("en", "🇬🇧"), ("fr", "🇫🇷"), ("de", "🇩🇪"), ("es", "🇪🇸"), ("it", "🇮🇹"), ("pt-BR", "🇧🇷"),
        ("pt-PT", "🇵🇹"), ("nl", "🇳🇱"), ("ca", "🇦🇩"), ("da", "🇩🇰"), ("sv", "🇸🇪"), ("nb", "🇳🇴"),
        ("fi", "🇫🇮"), ("pl", "🇵🇱"), ("cs", "🇨🇿"), ("sk", "🇸🇰"), ("hu", "🇭🇺"), ("ro", "🇷🇴"),
        ("hr", "🇭🇷"), ("el", "🇬🇷"), ("tr", "🇹🇷"), ("ru", "🇷🇺"), ("uk", "🇺🇦"), ("ar", "🇸🇦"),
        ("he", "🇮🇱"), ("hi", "🇮🇳"), ("th", "🇹🇭"), ("vi", "🇻🇳"), ("id", "🇮🇩"), ("ms", "🇲🇾"),
        ("zh-Hans", "🇨🇳"), ("zh-Hant", "🇹🇼"), ("ja", "🇯🇵"), ("ko", "🇰🇷"),
    ].map { AppLanguage(code: $0.0, flag: $0.1) }

    /// The "language" setting: "system" or a language code.
    static var setting: String { UserDefaults.standard.string(forKey: "language") ?? "system" }

    /// The language actually used for the UI.
    static var code: String {
        if setting != "system", all.contains(where: { $0.code == setting }) { return setting }
        return Bundle.main.preferredLocalizations.first ?? "en"
    }

    static var isFrench: Bool { code.hasPrefix("fr") }

    /// Locale for dates and numbers: the user's region when following the system, else the chosen language.
    static var locale: Locale { setting == "system" ? .current : Locale(identifier: code) }

    /// Arabic and Hebrew are written right to left.
    static var isRightToLeft: Bool { Locale.Language(identifier: code).characterDirection == .rightToLeft }

    static var layoutDirection: LayoutDirection { isRightToLeft ? .rightToLeft : .leftToRight }

    /// The bundle holding the strings for `code` (the app bundle itself when following the system).
    static var bundle: Bundle {
        guard setting != "system",
              let path = Bundle.main.path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return .main }
        return bundle
    }
}

/// Translates an English UI string, e.g. `tr("New Note")`.
func tr(_ english: String) -> String {
    Lang.bundle.localizedString(forKey: english, value: english, table: "Localizable")
}

/// Translates a format string and fills it in, with plural rules, e.g. `trf("%lld words", count)`.
func trf(_ english: String, _ args: CVarArg...) -> String {
    String(format: tr(english), locale: Lang.locale, arguments: args)
}
