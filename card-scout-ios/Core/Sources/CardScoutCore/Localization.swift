import Foundation

/// Stable interpolation keys; user/card data is passed as arguments, never used as a key.
public struct ScoutText: ExpressibleByStringLiteral, ExpressibleByStringInterpolation, Sendable {
    public let key: String
    public let arguments: [String]
    public init(stringLiteral value: String) { key = value; arguments = [] }
    public init(stringInterpolation: StringInterpolation) { key = stringInterpolation.key; arguments = stringInterpolation.arguments }
    public struct StringInterpolation: StringInterpolationProtocol {
        var key = ""
        var arguments: [String] = []
        public init(literalCapacity: Int, interpolationCount: Int) { key.reserveCapacity(literalCapacity); arguments.reserveCapacity(interpolationCount) }
        public mutating func appendLiteral(_ literal: String) { key += literal.replacingOccurrences(of: "%", with: "%%") }
        public mutating func appendInterpolation<T>(_ value: T) { arguments.append(String(describing: value)); key += "%\(arguments.count)$@" }
    }
}

public enum ScoutLocalization {
    public static let preferenceKey = "scoutLanguage"
    public static func resolve(preference: String, preferredLanguages: [String]) -> String {
        if ["de", "en"].contains(preference) { return preference }
        for language in preferredLanguages {
            let code = language.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init) ?? ""
            if ["de", "en"].contains(code) { return code }
        }
        return "en"
    }
    public static var language: String { resolve(preference: UserDefaults.standard.string(forKey: preferenceKey) ?? "system", preferredLanguages: Locale.preferredLanguages) }
    public static var locale: Locale { Locale(identifier: language) }
    private static let bundles: [String: Bundle] = ["de", "en"].reduce(into: [:]) { result, code in
        if let path = Bundle.main.path(forResource: code, ofType: "lproj"), let bundle = Bundle(path: path) { result[code] = bundle }
    }
    private static func lookup(_ key: String) -> String { (bundles[language] ?? Bundle.main).localizedString(forKey: key, value: key, table: "Localizable") }
    public static func text(_ value: ScoutText) -> String {
        let format = lookup(value.key)
        guard !value.arguments.isEmpty else { return format }
        return String(format: format, locale: locale, arguments: value.arguments.map { $0 as NSString })
    }
    /// Presentation-only labels returned by the core. Unrecognized research/user text stays as provided.
    public static func display(_ value: String) -> String {
        let exact = lookup(value)
        if exact != value { return exact }
        guard language == "en" else { return value }
        for template in templates {
            let range = NSRange(value.startIndex..., in: value)
            guard let match = template.regex.firstMatch(in: value, range: range) else { continue }
            let arguments: [CVarArg] = (1..<match.numberOfRanges).map { index in
                let text = Range(match.range(at: index), in: value).map { String(value[$0]) } ?? ""
                return lookup(text) as NSString
            }
            let format = lookup(template.key)
            guard format != template.key else { continue }
            return String(format: format, locale: locale, arguments: arguments)
        }
        return value
    }
    private struct Template: Sendable { let key: String; let regex: NSRegularExpression }
    private static let templates: [Template] = {
        guard let url = Bundle.main.url(forResource: "LocalizableTemplates", withExtension: "json"),
              let data = try? Data(contentsOf: url), let keys = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return keys.compactMap { key in
            let parts = key.components(separatedBy: try! NSRegularExpression(pattern: "%[0-9]+\\$@"))
            let pattern = "^" + parts.map { NSRegularExpression.escapedPattern(for: $0.replacingOccurrences(of: "%%", with: "%")) }.joined(separator: "(.*?)") + "$"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return nil }
            return Template(key: key, regex: regex)
        }
    }()
}

private extension String {
    func components(separatedBy regex: NSRegularExpression) -> [String] {
        var result: [String] = []; var start = startIndex
        for match in regex.matches(in: self, range: NSRange(startIndex..., in: self)) {
            guard let range = Range(match.range, in: self) else { continue }
            result.append(String(self[start..<range.lowerBound])); start = range.upperBound
        }
        result.append(String(self[start...])); return result
    }
}


public extension Date {
    func scoutFormatted(date: Date.FormatStyle.DateStyle, time: Date.FormatStyle.TimeStyle) -> String {
        formatted(Date.FormatStyle(date: date, time: time).locale(ScoutLocalization.locale))
    }
}
