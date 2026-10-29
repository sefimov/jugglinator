import Foundation

/// Snapshot of the frontmost window at the moment the hotkey is pressed. Filled by BIND
/// (NSWorkspace, Accessibility, AppleScript); the core uses it to find the current task.
public struct FrontmostContext: Codable, Equatable, Sendable {
    public var bundleID: String?
    public var appName: String?
    public var windowTitle: String?
    /// The active tab, if Chrome is frontmost and AppleScript is allowed.
    public var chromeTab: ChromeTabRef?
    /// Claude desktop chat UUID, if it could be read.
    public var claudeConversationID: String?
    /// ChatGPT desktop thread id, if known.
    public var chatGPTThreadID: String?
    /// Claude Code session id (`local_<uuid>`), if the Code tab is frontmost and the id was read.
    public var claudeCodeSessionID: String?
    /// This session's title from its Claude metadata (`claude-code-sessions`), if found.
    public var claudeCodeSessionTitle: String?
    /// Front window and selected Terminal tab (window id, tty), if AppleScript is allowed.
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

    /// Empty context: nothing is known (no permissions, no window).
    public static let unknown = FrontmostContext()
}
