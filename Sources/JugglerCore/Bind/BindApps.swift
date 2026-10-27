import Foundation

// Папка Sources/JugglerCore/Bind/ принадлежит задаче BIND: чистая логика (только Foundation),
// которую проверяет JugglerChecks (Sources/JugglerChecks/Bind/).

/// Какие приложения BIND различает при привязке и активации.
public enum BindAppKind: String, Codable, Equatable, Sendable {
    case chrome
    case claude
    case chatGPT
    /// Grok Bot и любое другое приложение: привязка к окну.
    case other
}

/// Bundle id приложений, проверенные на маке пользователя (Info.plist в /Applications).
///
/// ChatGPT desktop сейчас поставляется как `com.openai.codex` (схема `codex`);
/// старый `com.openai.chat` оставлен для совместимости.
public enum BindApps {
    public static let chrome = "com.google.Chrome"
    public static let claude = "com.anthropic.claudefordesktop"
    public static let chatGPTBundleIDs = ["com.openai.codex", "com.openai.chat"]
    public static let grokBot = "com.anysphere.sand"
    public static let juggler = "com.sefimov.juggler"

    public static func kind(of bundleID: String?) -> BindAppKind {
        guard let bundleID, !bundleID.isEmpty else { return .other }
        if same(bundleID, chrome) { return .chrome }
        if same(bundleID, claude) { return .claude }
        if chatGPTBundleIDs.contains(where: { same(bundleID, $0) }) { return .chatGPT }
        return .other
    }

    public static func isChatGPT(_ bundleID: String?) -> Bool { kind(of: bundleID) == .chatGPT }

    /// Сравнение bundle id без учёта регистра; пустые и `nil` не равны ничему.
    public static func same(_ a: String?, _ b: String?) -> Bool {
        guard let a, let b, !a.isEmpty, !b.isEmpty else { return false }
        return a.caseInsensitiveCompare(b) == .orderedSame
    }
}

/// Приложение-кандидат в «переднее» (для выбора, чьё окно привязывать).
public struct AppIdentity: Codable, Equatable, Sendable {
    public var bundleID: String?
    public var name: String?
    public var pid: Int32

    public init(bundleID: String?, name: String?, pid: Int32) {
        self.bundleID = bundleID
        self.name = name
        self.pid = pid
    }
}

/// Выбор приложения, чей контекст читать.
///
/// Когда «Сделать задачей текущий чат» нажимают в меню Juggler, впереди может оказаться
/// сам Juggler. Тогда берётся последнее активное приложение, кроме Juggler.
public enum FrontmostAppChooser {
    public static func isOwn(_ app: AppIdentity, ownBundleID: String?, ownPID: Int32) -> Bool {
        if app.pid == ownPID { return true }
        if BindApps.same(app.bundleID, ownBundleID) { return true }
        return BindApps.same(app.bundleID, BindApps.juggler)
    }

    /// - Returns: приложение и признак того, что взято запомненное, а не текущее переднее.
    public static func choose(
        frontmost: AppIdentity?, remembered: AppIdentity?, ownBundleID: String?, ownPID: Int32
    ) -> (app: AppIdentity, usedRemembered: Bool)? {
        if let frontmost, !isOwn(frontmost, ownBundleID: ownBundleID, ownPID: ownPID) {
            return (frontmost, false)
        }
        if let remembered, !isOwn(remembered, ownBundleID: ownBundleID, ownPID: ownPID) {
            return (remembered, true)
        }
        return nil
    }
}
