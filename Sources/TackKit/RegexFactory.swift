import Foundation

/// Builds the app's constant regular expressions.
/// Every pattern is a literal checked by the unit tests, so a failure is a programming error.
enum RegexFactory {
    static func make(_ pattern: String, options: NSRegularExpression.Options = []) -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern, options: options)
        } catch {
            preconditionFailure("Invalid regular expression \(pattern): \(error)")
        }
    }

    static let linkDetector: NSDataDetector = {
        do {
            return try NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        } catch {
            preconditionFailure("Cannot create the link detector: \(error)")
        }
    }()
}
