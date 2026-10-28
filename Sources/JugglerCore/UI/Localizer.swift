import Foundation

/// Перевод строки интерфейса на язык, выбранный сейчас (а не на язык запуска, как `String(localized:)`).
///
///     loc("Выйти")                          // «Quit», если выбран английский
///     loc("Задача \(number) «\(title)» сделана")
///
/// Ключ — русская строка, как в `Localization/<язык>.lproj/Localizable.strings`. Интерполяции дают
/// в ключе спецификаторы так же, как `String(localized:)`: `Int` → `%lld`, `Int32` → `%d`, остальное → `%@`.
/// Ключи ищет `scripts/check-localization.py`, поэтому аргумент — всегда литерал.
public func loc(_ text: LocalizedText) -> String {
    Localizer.shared.string(text)
}

/// Литерал для `loc(_:)`: ключ перевода и значения интерполяций.
public struct LocalizedText: ExpressibleByStringInterpolation {
    /// Ключ таблицы перевода: литерал, интерполяции заменены спецификаторами.
    public let key: String
    /// Значения интерполяций по порядку.
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
            // Как в String.LocalizationValue: «%» в тексте ключа — «%%» в формате.
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

/// Таблицы перевода `<язык>.lproj` и выбранный язык. Язык меняется на ходу (`setLanguage`):
/// следующий `loc(_:)` уже переводит на новый язык, перезапуск не нужен.
///
/// Перевод ищется в таблице выбранного языка, затем в английской (язык разработки, `CFBundleDevelopmentRegion`),
/// затем возвращается сам ключ — русская строка. Для русского английский пропускается: ключ и есть русский текст.
/// Без таблиц (нет папок `.lproj`) — всегда ключ.
public final class Localizer: @unchecked Sendable {
    /// Язык разработки: запасной перевод для отсутствующих ключей.
    public static let developmentLanguage = "en"
    /// Язык ключей: русские строки в коде.
    public static let keyLanguage = "ru"

    /// Переводчик приложения: таблицы из пакета `.app` (или из `Localization/` репозитория под `swift run`),
    /// язык — выбранный в настройках Juggler или язык системы.
    public static let shared = Localizer(
        resourcesURL: defaultResourcesURL(),
        language: LanguageSettings.app.effectiveLanguage(systemPreferred: LanguageSettings.systemPreferredLanguages()))

    /// Папка с `<язык>.lproj` или `nil`, если переводов нет.
    public let resourcesURL: URL?

    private let lock = NSLock()
    private var current: String
    private var bundles: [String: Bundle] = [:]

    public init(resourcesURL: URL?, language: String) {
        self.resourcesURL = resourcesURL
        self.current = language
    }

    /// Код выбранного языка («ru», «pt-BR»…).
    public var language: String {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    /// Локаль выбранного языка: правила склонений и формат чисел в переведённых строках.
    public var locale: Locale { Locale(identifier: language) }

    /// Сменить язык. Возвращает `true`, если язык действительно изменился.
    @discardableResult
    public func setLanguage(_ code: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard code != current else { return false }
        current = code
        return true
    }

    /// Языки, в которых ищется перевод, по порядку.
    public func lookupOrder(for code: String) -> [String] {
        code == Self.keyLanguage || code == Self.developmentLanguage ? [code] : [code, Self.developmentLanguage]
    }

    /// Есть ли таблица перевода для языка.
    public func hasTable(for code: String) -> Bool {
        bundle(for: code) != nil
    }

    /// Перевод ключа без подстановки значений; `nil`, если ключа нет ни в одной таблице.
    public func translation(forKey key: String) -> String? {
        lookup(key)?.format
    }

    /// Перевод с подстановкой значений; при отсутствии перевода — ключ (русский текст).
    public func string(_ text: LocalizedText) -> String {
        guard let (format, code) = lookup(text.key) else {
            return text.arguments.isEmpty ? text.key : String(format: text.key, locale: Locale(identifier: Self.keyLanguage), arguments: text.arguments)
        }
        return text.arguments.isEmpty ? format : String(format: format, locale: Locale(identifier: code), arguments: text.arguments)
    }

    /// Строка со склонением из `Localizable.stringsdict` («3 задачи»); `nil`, если ключа нет.
    /// Форма слова выбирается по правилам языка таблицы, а не региона системы.
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

    /// Пакет на папку `<язык>.lproj`: её Localizable.strings и .stringsdict лежат в корне пакета.
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

    /// Где лежат переводы: ресурсы `.app`; под `swift run` (пакета нет) — папка `Localization/` репозитория
    /// рядом со сборкой (`.build/<платформа>/debug/Juggler` → четыре уровня вверх). `nil`, если не найдено.
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
