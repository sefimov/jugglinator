import Foundation

/// State of controlling an app via Apple Events (AppleScript): Chrome and Terminal.
public enum AutomationStatus: String, Codable, Equatable, Sendable {
    /// Allowed, the script ran.
    case granted
    /// The user denied control (error -1743, errAEEventNotPermitted).
    case denied
    /// Permission has not been asked yet (-1744): a system prompt is needed.
    case requiresConsent
    /// The app is not running (-600, -609).
    case notRunning
    /// The app has no window or tab (-1728, -1719).
    case noWindow
    /// Another AppleScript error.
    case failed

    /// Classifies an Apple Events / AppleScript error code (`OSStatus` or `NSAppleScript.errorNumber`).
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

    /// Permission denied: instructions need to be shown.
    public static func isPermissionDenied(code: Int) -> Bool { code == -1743 }
}

/// What was learned about the Claude chat id via Accessibility.
public enum ClaudeChatReadStatus: String, Codable, Equatable, Sendable {
    /// The id was read from the window's web area URL (AXURL).
    case read
    /// The Code tab is frontmost: a Claude Code session id was read (`claude.ai/epitaxy/local_<uuid>`), not a chat id.
    case codeSession
    /// No Accessibility permission — nothing to read.
    case noAccessibility
    /// The tree is available but contains no chat URL (e.g. a project or settings is open, not a chat).
    case notFound
    /// Electron did not expose the web content tree even after `AXManualAccessibility`.
    case treeUnavailable
}

/// Diagnostics of the last context read: what worked, what did not, and why.
/// Printed in `--probe-frontmost` and used for user-facing messages.
public struct ContextDiagnostics: Codable, Equatable, Sendable {
    public var accessibilityTrusted: Bool
    /// The context was taken from the remembered app because Juggler itself was frontmost.
    public var usedRememberedApp: Bool
    /// The window title was read via Accessibility.
    public var windowTitleRead: Bool
    public var chromeAutomation: AutomationStatus?
    public var chromeErrorCode: Int?
    /// Terminal control (the window and tab tty are read only with it).
    public var terminalAutomation: AutomationStatus?
    public var terminalErrorCode: Int?
    public var claudeChat: ClaudeChatReadStatus?
    /// URLs found in Claude's Accessibility tree (for debugging).
    public var claudeCandidateURLs: [String]
    /// ChatGPT thread lookup by window title in `~/.codex/session_index.jsonl` (only when binding).
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

/// Finds a Claude chat id or Claude Code session id among URLs found in the Accessibility tree
/// (AXURL of web areas, the window's AXDocument). The first URL that is a chat or session wins.
public enum ClaudeChatURLExtractor {
    /// The first link to a chat (`claude.ai/chat/<uuid>`) or session (`claude.ai/epitaxy/local_<uuid>`).
    /// Bare ids do not count: only URLs are searched for in the tree.
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

    /// Read outcome for diagnostics.
    public static func status(candidates: [String], treeAvailable: Bool, accessibilityTrusted: Bool) -> ClaudeChatReadStatus {
        guard accessibilityTrusted else { return .noAccessibility }
        switch link(fromCandidates: candidates) {
        case .claude?: return .read
        case .claudeCodeSession?: return .codeSession
        default: return treeAvailable ? .notFound : .treeUnavailable
        }
    }
}
