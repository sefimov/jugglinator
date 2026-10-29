import Foundation

/// A UI language selectable in settings: the folder code of `Localization/<code>.lproj`
/// and the language's name in itself (not translated: people must find their language in any UI).
public struct AppLanguage: Equatable, Hashable, Identifiable, Sendable {
    public let code: String
    public let nativeName: String

    public var id: String { code }

    public init(code: String, nativeName: String) {
        self.code = code
        self.nativeName = nativeName
    }

    /// 12 localization languages (match `Localization/*.lproj` and `CFBundleLocalizations`).
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

/// Language choice: "Same as system" (no value in the app domain) or one of `AppLanguage.all`.
public enum LanguageChoice: Equatable, Hashable, Sendable {
    case system
    case language(String)

    /// Which language the app shows for a given `AppleLanguages` preference list.
    /// Takes the first language in the list that has a translation: the full code ("pt-BR"),
    /// then without suffixes ("zh-Hans-CN" → "zh-Hans", "de-AT" → "de"), then any variant of the same
    /// language ("pt-PT" → "pt-BR"). If none has a translation — English (development region).
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

/// Stores the selected language for Juggler only: the `AppleLanguages` key in the app's own
/// defaults domain (`com.sefimov.juggler`). The global system language is not changed.
/// Juggler texts switch immediately (`Localizer`); system AppKit labels and Info.plist
/// pick up this value only on the next launch.
public struct LanguageSettings {
    public static let key = "AppleLanguages"

    /// The real app domain. Under `swift run` there is no bundle, so the process name is used.
    public static var app: LanguageSettings {
        LanguageSettings(
            defaults: .standard,
            domain: Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName)
    }

    /// System languages (global domain, without the Juggler domain value), in preference order.
    public static func systemPreferredLanguages(defaults: UserDefaults = .standard) -> [String] {
        if let global = defaults.persistentDomain(forName: UserDefaults.globalDomain)?[key] as? [String], !global.isEmpty {
            return global
        }
        return Locale.preferredLanguages
    }

    private let defaults: UserDefaults
    private let domain: String

    /// `defaults` and `domain` are a "store and its domain name" pair: for the app these are
    /// `UserDefaults.standard` and the bundle identifier, for checks — a separate suite,
    /// so the real settings are not affected.
    public init(defaults: UserDefaults, domain: String) {
        self.defaults = defaults
        self.domain = domain
    }

    /// The value written specifically in the app domain (not from the global domain and not the system language).
    public var storedOverride: [String]? {
        defaults.persistentDomain(forName: domain)?[Self.key] as? [String]
    }

    /// The effective choice: with a value in the domain — the language it sets; otherwise "Same as system".
    public var choice: LanguageChoice {
        guard let stored = storedOverride, !stored.isEmpty else { return .system }
        return LanguageChoice.resolving(preferred: stored)
    }

    /// Code of the language to show texts in: the selected one or, with "Same as system", the first system
    /// language that has a translation (otherwise English).
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

    /// "Same as system" removes the value; a language writes it as a single element.
    public func select(_ choice: LanguageChoice) {
        switch choice {
        case .system:
            defaults.removeObject(forKey: Self.key)
        case .language(let code):
            defaults.set([code], forKey: Self.key)
        }
    }
}

/// App relaunch: quit Juggler and open it again.
public enum AppRestart {
    /// A command that waits for process `pid` to exit (at most 10 s) and opens `bundlePath` as a new instance.
    /// `nil` if Juggler is not running from a `.app` (`swift run`): nothing to open.
    public static func relaunchCommand(bundlePath: String, pid: Int32) -> (executable: String, arguments: [String])? {
        guard bundlePath.hasSuffix(".app") else { return nil }
        let script = "i=0; while kill -0 \"$1\" 2>/dev/null && [ $i -lt 100 ]; do sleep 0.1; i=$((i+1)); done; exec /usr/bin/open -n \"$0\""
        return ("/bin/sh", ["-c", script, bundlePath, String(pid)])
    }
}
