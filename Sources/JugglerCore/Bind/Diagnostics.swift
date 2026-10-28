import Foundation

/// Состояние управления приложением через Apple Events (AppleScript): Chrome и Терминал.
public enum AutomationStatus: String, Codable, Equatable, Sendable {
    /// Разрешено, скрипт выполнился.
    case granted
    /// Пользователь запретил управление (ошибка -1743, errAEEventNotPermitted).
    case denied
    /// Разрешение ещё не спрашивали (-1744): нужен системный запрос.
    case requiresConsent
    /// Приложение не запущено (-600, -609).
    case notRunning
    /// У приложения нет окна или вкладки (-1728, -1719).
    case noWindow
    /// Другая ошибка AppleScript.
    case failed

    /// Классификация кода ошибки Apple Events / AppleScript (`OSStatus` или `NSAppleScript.errorNumber`).
    public static func classify(code: Int) -> AutomationStatus {
        switch code {
        case 0: return .granted
        case -1743: return .denied
        case -1744: return .requiresConsent
        case -600, -609: return .notRunning
        case -1728, -1719: return .noWindow
        default: return .failed
        }
    }

    /// Признак отказа в разрешении: нужно показать инструкцию.
    public static func isPermissionDenied(code: Int) -> Bool { code == -1743 }
}

/// Что удалось узнать об id чата Claude через Accessibility.
public enum ClaudeChatReadStatus: String, Codable, Equatable, Sendable {
    /// Id прочитан из адреса веб-области окна (AXURL).
    case read
    /// Впереди вкладка Code: прочитан id сессии Claude Code (`claude.ai/epitaxy/local_<uuid>`), а не чата.
    case codeSession
    /// Нет разрешения Accessibility — читать нечего.
    case noAccessibility
    /// Дерево доступно, но адреса чата в нём нет (например, открыт не чат, а проект или настройки).
    case notFound
    /// Electron не отдал дерево веб-содержимого даже после `AXManualAccessibility`.
    case treeUnavailable
}

/// Диагностика последнего чтения контекста: что получилось, что нет и почему.
/// Печатается в `--probe-frontmost` и используется для сообщений пользователю.
public struct ContextDiagnostics: Codable, Equatable, Sendable {
    public var accessibilityTrusted: Bool
    /// Контекст взят у запомненного приложения, потому что впереди был сам Juggler.
    public var usedRememberedApp: Bool
    /// Заголовок окна прочитан через Accessibility.
    public var windowTitleRead: Bool
    public var chromeAutomation: AutomationStatus?
    public var chromeErrorCode: Int?
    /// Управление Терминалом (окно и tty вкладки читаются только с ним).
    public var terminalAutomation: AutomationStatus?
    public var terminalErrorCode: Int?
    public var claudeChat: ClaudeChatReadStatus?
    /// Адреса, найденные в дереве Accessibility Claude (для отладки).
    public var claudeCandidateURLs: [String]
    /// Поиск треда ChatGPT по заголовку окна в `~/.codex/session_index.jsonl` (только при привязке).
    public var chatGPTThread: ChatGPTThreadLookup?
    public var notes: [String]

    public init(
        accessibilityTrusted: Bool = false,
        usedRememberedApp: Bool = false,
        windowTitleRead: Bool = false,
        chromeAutomation: AutomationStatus? = nil,
        chromeErrorCode: Int? = nil,
        terminalAutomation: AutomationStatus? = nil,
        terminalErrorCode: Int? = nil,
        claudeChat: ClaudeChatReadStatus? = nil,
        claudeCandidateURLs: [String] = [],
        chatGPTThread: ChatGPTThreadLookup? = nil,
        notes: [String] = []
    ) {
        self.accessibilityTrusted = accessibilityTrusted
        self.usedRememberedApp = usedRememberedApp
        self.windowTitleRead = windowTitleRead
        self.chromeAutomation = chromeAutomation
        self.chromeErrorCode = chromeErrorCode
        self.terminalAutomation = terminalAutomation
        self.terminalErrorCode = terminalErrorCode
        self.claudeChat = claudeChat
        self.claudeCandidateURLs = claudeCandidateURLs
        self.chatGPTThread = chatGPTThread
        self.notes = notes
    }
}

/// Поиск id чата Claude или сессии Claude Code среди адресов, найденных в дереве Accessibility
/// (AXURL веб-областей, AXDocument окна). Берётся первый адрес, который является чатом или сессией.
public enum ClaudeChatURLExtractor {
    /// Первая ссылка на чат (`claude.ai/chat/<uuid>`) или сессию (`claude.ai/epitaxy/local_<uuid>`).
    /// Голые id не считаются: в дереве ищутся только адреса.
    public static func link(fromCandidates candidates: [String]) -> ChatLink? {
        for raw in candidates where raw.contains("/") {
            switch ChatLinkParser.parse(raw) {
            case let link? where link.source == .claudeChat || link.source == .claudeCodeSession: return link
            default: continue
            }
        }
        return nil
    }

    public static func conversationID(fromCandidates candidates: [String]) -> String? {
        if case .claude(let id)? = link(fromCandidates: candidates) { return id }
        return nil
    }

    public static func sessionID(fromCandidates candidates: [String]) -> String? {
        if case .claudeCodeSession(let id)? = link(fromCandidates: candidates) { return id }
        return nil
    }

    /// Итог чтения для диагностики.
    public static func status(candidates: [String], treeAvailable: Bool, accessibilityTrusted: Bool) -> ClaudeChatReadStatus {
        guard accessibilityTrusted else { return .noAccessibility }
        switch link(fromCandidates: candidates) {
        case .claude?: return .read
        case .claudeCodeSession?: return .codeSession
        default: return treeAvailable ? .notFound : .treeUnavailable
        }
    }
}
