import Foundation

/// Translates a UI string into the currently selected language (not the launch language, as `String(localized:)` does).
///
///     loc("Выйти")                          // "Quit" if English is selected
///     loc("Задача \(number) «\(title)» сделана")
///
/// The key is the Russian string, as in `Localization/<lang>.lproj/Localizable.strings`. Interpolations put
/// specifiers into the key just like `String(localized:)`: `Int` → `%lld`, `Int32` → `%d`, everything else → `%@`.
/// Keys are collected by `scripts/check-localization.py`, so the argument is always a literal.
public func loc(_ text: LocalizedText) -> String {
    Localizer.shared.string(text)
}

/// Literal for `loc(_:)`: the translation key and interpolation values.
public struct LocalizedText: ExpressibleByStringInterpolation {
    /// Translation table key: the literal with interpolations replaced by specifiers.
    public let key: String
    /// Interpolation values in order.
    public let arguments: [CVarArg]

    public init(key: String, arguments: [CVarArg] = []) {
        self.key = key
        self.arguments = arguments
    }

    public init(stringLiteral value: String) {
        self.init(key: value)
    }

    public init(stringInterpolation: StringInterpolation) {
        self.init(key: stringInterpolation.key, arguments: stringInterpolation.arguments)
    }

    public struct StringInterpolation: StringInterpolationProtocol {
        var key = ""
        var arguments: [CVarArg] = []

        public init(literalCapacity: Int, interpolationCount: Int) {
            key.reserveCapacity(literalCapacity + interpolationCount * 4)
        }

        public mutating func appendLiteral(_ literal: String) {
            // As in String.LocalizationValue: "%" in the key text becomes "%%" in the format.
            key += literal.replacingOccurrences(of: "%", with: "%%")
        }

        public mutating func appendInterpolation(_ value: Int) {
            key += "%lld"
            arguments.append(value)
        }

        public mutating func appendInterpolation(_ value: Int32) {
            key += "%d"
            arguments.append(value)
        }

        public mutating func appendInterpolation(_ value: String) {
            key += "%@"
            arguments.append(value as NSString)
        }

        public mutating func appendInterpolation<T: CustomStringConvertible>(_ value: T) {
            appendInterpolation(value.description)
        }
    }
}

/// `<lang>.lproj` translation tables and the selected language. The language changes on the fly (`setLanguage`):
/// the next `loc(_:)` already translates into the new language, no restart needed.
///
/// A translation is looked up in the selected language's table, then in English (development language, `CFBundleDevelopmentRegion`),
/// then the key itself — the Russian string — is returned. For Russian, English is skipped: the key is the Russian text.
/// Without tables (no `.lproj` folders) — always the key.
public final class Localizer: @unchecked Sendable {
    /// Development language: fallback translation for missing keys.
    public static let developmentLanguage = "en"
    /// Key language: Russian strings in code.
    public static let keyLanguage = "ru"

    /// The app's translator: tables from the `.app` bundle (or from the repo's `Localization/` under `swift run`),
    /// language — the one selected in Jugglinator settings or the system language.
    public static let shared = Localizer(
        resourcesURL: defaultResourcesURL(),
        language: LanguageSettings.app.effectiveLanguage(systemPreferred: LanguageSettings.systemPreferredLanguages()))

    /// Folder with `<lang>.lproj`, or `nil` if there are no translations.
    public let resourcesURL: URL?

    private let lock = NSLock()
    private var current: String
    private var bundles: [String: Bundle] = [:]

    public init(resourcesURL: URL?, language: String) {
        self.resourcesURL = resourcesURL
        self.current = language
    }

    /// Code of the selected language ("ru", "pt-BR"…).
    public var language: String {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    /// Locale of the selected language: plural rules and number format in translated strings.
    public var locale: Locale { Locale(identifier: language) }

    /// Changes the language. Returns `true` if the language actually changed.
    @discardableResult
    public func setLanguage(_ code: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard code != current else { return false }
        current = code
        return true
    }

    /// Languages to look up translations in, in order.
    public func lookupOrder(for code: String) -> [String] {
        code == Self.keyLanguage || code == Self.developmentLanguage ? [code] : [code, Self.developmentLanguage]
    }

    /// Whether there is a translation table for the language.
    public func hasTable(for code: String) -> Bool {
        bundle(for: code) != nil
    }

    /// Translation of a key without substituting values; `nil` if the key is in no table.
    public func translation(forKey key: String) -> String? {
        lookup(key)?.format
    }

    /// Translation with values substituted; without a translation — the key (Russian text).
    public func string(_ text: LocalizedText) -> String {
        guard let (format, code) = lookup(text.key) else {
            return text.arguments.isEmpty ? text.key : String(format: text.key, locale: Locale(identifier: Self.keyLanguage), arguments: text.arguments)
        }
        return text.arguments.isEmpty ? format : String(format: format, locale: Locale(identifier: code), arguments: text.arguments)
    }

    /// Pluralized string from `Localizable.stringsdict` ("3 tasks"); `nil` if there is no key.
    /// The word form follows the table language's rules, not the system region.
    public func plural(_ key: String, _ n: Int) -> String? {
        guard let (format, code) = lookup(key) else { return nil }
        return String(format: format, locale: Locale(identifier: code), n)
    }

    private func lookup(_ key: String) -> (format: String, language: String)? {
        let missing = "\u{1}"
        for code in lookupOrder(for: language) {
            guard let bundle = bundle(for: code) else { continue }
            let value = bundle.localizedString(forKey: key, value: missing, table: nil)
            if value != missing { return (value, code) }
        }
        return nil
    }

    /// A bundle for a `<lang>.lproj` folder: its Localizable.strings and .stringsdict are at the bundle root.
    private func bundle(for code: String) -> Bundle? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = bundles[code] { return cached }
        guard let dir = resourcesURL?.appendingPathComponent("\(code).lproj", isDirectory: true),
              FileManager.default.fileExists(atPath: dir.appendingPathComponent("Localizable.strings").path),
              let bundle = Bundle(url: dir) else { return nil }
        bundles[code] = bundle
        return bundle
    }

    /// Where translations live: `.app` resources; under `swift run` (no bundle) — the repo's `Localization/` folder
    /// next to the build (`.build/<platform>/debug/Jugglinator` → four levels up). `nil` if not found.
    public static func defaultResourcesURL(bundle: Bundle = .main) -> URL? {
        func hasTables(_ url: URL) -> Bool {
            FileManager.default.fileExists(
                atPath: url.appendingPathComponent("\(developmentLanguage).lproj/Localizable.strings").path)
        }
        if let resources = bundle.resourceURL, hasTables(resources) { return resources }
        var dir = (bundle.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])).resolvingSymlinksInPath()
        for _ in 0..<6 {
            dir = dir.deletingLastPathComponent()
            let candidate = dir.appendingPathComponent("Localization", isDirectory: true)
            if hasTables(candidate) { return candidate }
        }
        return nil
    }
}
