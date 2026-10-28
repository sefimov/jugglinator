import Foundation

/// Снимок переднего окна в момент нажатия хоткея. Заполняет BIND
/// (NSWorkspace, Accessibility, AppleScript); ядро по нему ищет текущую задачу.
public struct FrontmostContext: Codable, Equatable, Sendable {
    public var bundleID: String?
    public var appName: String?
    public var windowTitle: String?
    /// Активная вкладка, если впереди Chrome и AppleScript разрешён.
    public var chromeTab: ChromeTabRef?
    /// UUID чата Claude desktop, если его удалось прочитать.
    public var claudeConversationID: String?
    /// Id треда ChatGPT desktop, если он известен.
    public var chatGPTThreadID: String?
    /// Id сессии Claude Code (`local_<uuid>`), если впереди вкладка Code и id прочитан.
    public var claudeCodeSessionID: String?
    /// Название этой сессии из её метаданных Claude (`claude-code-sessions`), если найдено.
    public var claudeCodeSessionTitle: String?
    /// Переднее окно и выбранная вкладка Терминала (id окна, tty), если AppleScript разрешён.
    public var terminalWindow: TerminalWindowRef?

    public init(
        bundleID: String? = nil,
        appName: String? = nil,
        windowTitle: String? = nil,
        chromeTab: ChromeTabRef? = nil,
        claudeConversationID: String? = nil,
        chatGPTThreadID: String? = nil,
        claudeCodeSessionID: String? = nil,
        claudeCodeSessionTitle: String? = nil,
        terminalWindow: TerminalWindowRef? = nil
    ) {
        self.bundleID = bundleID
        self.appName = appName
        self.windowTitle = windowTitle
        self.chromeTab = chromeTab
        self.claudeConversationID = claudeConversationID
        self.chatGPTThreadID = chatGPTThreadID
        self.claudeCodeSessionID = claudeCodeSessionID
        self.claudeCodeSessionTitle = claudeCodeSessionTitle
        self.terminalWindow = terminalWindow
    }

    /// Пустой контекст: ничего не известно (нет разрешений, нет окна).
    public static let unknown = FrontmostContext()
}
