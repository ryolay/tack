import Foundation

/// UI language: the "language" setting (system · fr · en). Defaults to the system language (French, else English).
enum Lang {
    static let systemIsFrench: Bool = {
        let pref = Bundle.main.preferredLocalizations.first ?? Locale.preferredLanguages.first ?? "en"
        return pref.hasPrefix("fr")
    }()

    static var isFrench: Bool {
        switch UserDefaults.standard.string(forKey: "language") {
        case "fr": true
        case "en": false
        default: systemIsFrench
        }
    }
}

/// L("texte français", "English text") returns the string for the current language.
func L(_ fr: String, _ en: String) -> String { Lang.isFrench ? fr : en }
