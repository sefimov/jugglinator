import Foundation

/// Язык интерфейса, который можно выбрать в настройках: код папки `Localization/<код>.lproj`
/// и название языка на нём самом (не переводится: человек должен найти свой язык в любом интерфейсе).
public struct AppLanguage: Equatable, Hashable, Identifiable, Sendable {
    public let code: String
    public let nativeName: String

    public var id: String { code }

    public init(code: String, nativeName: String) {
        self.code = code
        self.nativeName = nativeName
    }

    /// 12 языков локализации (совпадают с `Localization/*.lproj` и `CFBundleLocalizations`).
    public static let all: [AppLanguage] = [
        AppLanguage(code: "ru", nativeName: "Русский"),
        AppLanguage(code: "en", nativeName: "English"),
        AppLanguage(code: "de", nativeName: "Deutsch"),
        AppLanguage(code: "es", nativeName: "Español"),
        AppLanguage(code: "fr", nativeName: "Français"),
        AppLanguage(code: "it", nativeName: "Italiano"),
        AppLanguage(code: "pt-BR", nativeName: "Português (Brasil)"),
        AppLanguage(code: "ja", nativeName: "日本語"),
        AppLanguage(code: "ko", nativeName: "한국어"),
        AppLanguage(code: "zh-Hans", nativeName: "简体中文"),
        AppLanguage(code: "ar", nativeName: "العربية"),
        AppLanguage(code: "hi", nativeName: "हिन्दी"),
    ]

    public static func named(_ code: String) -> AppLanguage? {
        all.first { $0.code == code }
    }
}

/// Выбор языка: «Как в системе» (значения в домене приложения нет) или один из `AppLanguage.all`.
public enum LanguageChoice: Equatable, Hashable, Sendable {
    case system
    case language(String)

    /// Какой язык показывает приложение при списке предпочтений `AppleLanguages`.
    /// Берётся первый язык из списка, для которого есть перевод: код целиком («pt-BR»),
    /// затем без хвостов («zh-Hans-CN» → «zh-Hans», «de-AT» → «de»), затем любой вариант того же
    /// языка («pt-PT» → «pt-BR»). Если перевода нет ни для одного — английский (регион разработки).
    public static func resolving(preferred: [String]) -> LanguageChoice {
        for entry in preferred {
            if let code = supportedCode(for: entry) { return .language(code) }
        }
        return .language("en")
    }

    static func supportedCode(for entry: String) -> String? {
        let parts = entry.replacingOccurrences(of: "_", with: "-")
            .split(separator: "-").map(String.init)
        guard let first = parts.first else { return nil }
        var length = parts.count
        while length >= 1 {
            let candidate = parts.prefix(length).joined(separator: "-").lowercased()
            if let match = AppLanguage.all.first(where: { $0.code.lowercased() == candidate }) {
                return match.code
            }
            length -= 1
        }
        let base = first.lowercased()
        return AppLanguage.all.first { $0.code.split(separator: "-")[0].lowercased() == base }?.code
    }
}

/// Хранение выбранного языка только для Juggler: ключ `AppleLanguages` в собственном домене
/// настроек приложения (`com.sefimov.juggler`). Глобальный язык системы не меняется.
/// Тексты Juggler переключаются сразу (`Localizer`); системные надписи AppKit и Info.plist
/// берут это значение только при следующем запуске.
public struct LanguageSettings {
    public static let key = "AppleLanguages"

    /// Настоящий домен приложения. Под `swift run` пакета нет, берётся имя процесса.
    public static var app: LanguageSettings {
        LanguageSettings(
            defaults: .standard,
            domain: Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName)
    }

    /// Языки системы (глобальный домен, без значения из домена Juggler), по порядку предпочтения.
    public static func systemPreferredLanguages(defaults: UserDefaults = .standard) -> [String] {
        if let global = defaults.persistentDomain(forName: UserDefaults.globalDomain)?[key] as? [String], !global.isEmpty {
            return global
        }
        return Locale.preferredLanguages
    }

    private let defaults: UserDefaults
    private let domain: String

    /// `defaults` и `domain` — пара «хранилище и имя его домена»: для приложения это
    /// `UserDefaults.standard` и идентификатор пакета, для проверок — отдельный suite,
    /// чтобы настоящие настройки не затрагивались.
    public init(defaults: UserDefaults, domain: String) {
        self.defaults = defaults
        self.domain = domain
    }

    /// Значение, записанное именно в домен приложения (не из глобального домена и не язык системы).
    public var storedOverride: [String]? {
        defaults.persistentDomain(forName: domain)?[Self.key] as? [String]
    }

    /// Действующий выбор: при значении в домене — язык, который оно задаёт; иначе «Как в системе».
    public var choice: LanguageChoice {
        guard let stored = storedOverride, !stored.isEmpty else { return .system }
        return LanguageChoice.resolving(preferred: stored)
    }

    /// Код языка, на котором показывать тексты: выбранный или, при «Как в системе», первый из языков
    /// системы, для которого есть перевод (иначе английский).
    public func effectiveLanguage(systemPreferred: [String]) -> String {
        Self.code(for: choice, systemPreferred: systemPreferred)
    }

    public static func code(for choice: LanguageChoice, systemPreferred: [String]) -> String {
        switch choice {
        case .language(let code): return code
        case .system:
            guard case .language(let code) = LanguageChoice.resolving(preferred: systemPreferred) else {
                return Localizer.developmentLanguage
            }
            return code
        }
    }

    /// «Как в системе» убирает значение, язык — записывает его одним элементом.
    public func select(_ choice: LanguageChoice) {
        switch choice {
        case .system:
            defaults.removeObject(forKey: Self.key)
        case .language(let code):
            defaults.set([code], forKey: Self.key)
        }
    }
}

/// Перезапуск приложения: закрыть Juggler и открыть его снова.
public enum AppRestart {
    /// Команда, которая ждёт выхода процесса `pid` (не дольше 10 с) и открывает `bundlePath` новым экземпляром.
    /// `nil`, если Juggler запущен не из `.app` (`swift run`): открывать нечего.
    public static func relaunchCommand(bundlePath: String, pid: Int32) -> (executable: String, arguments: [String])? {
        guard bundlePath.hasSuffix(".app") else { return nil }
        let script = "i=0; while kill -0 \"$1\" 2>/dev/null && [ $i -lt 100 ]; do sleep 0.1; i=$((i+1)); done; exec /usr/bin/open -n \"$0\""
        return ("/bin/sh", ["-c", script, bundlePath, String(pid)])
    }
}
