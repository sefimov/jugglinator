import Foundation

/// Binding source: determines the icon in the list and the activation method.
public enum BindingSource: String, Codable, CaseIterable, Sendable {
    case chromeTab
    case claudeChat
    /// A Claude Code session on the Code tab in Claude desktop.
    case claudeCodeSession
    case chatGPTThread
    /// A Terminal.app window and tab: window id and tab tty from AppleScript.
    case terminalWindow
    case appWindow

    /// Short source name for the UI.
    public var displayName: String {
        switch self {
        case .chromeTab: return "Chrome"
        case .claudeChat: return "Claude"
        case .claudeCodeSession: return "Claude Code"
        case .chatGPTThread: return "ChatGPT"
        case .terminalWindow: return loc("Терминал")
        case .appWindow: return loc("Окно приложения")
        }
    }

    /// SF Symbol name for the source icon.
    public var symbolName: String {
        switch self {
        case .chromeTab: return "globe"
        case .claudeChat: return "sparkles"
        case .claudeCodeSession: return "terminal"
        case .chatGPTThread: return "bubble.left.and.bubble.right"
        case .terminalWindow: return "terminal.fill"
        case .appWindow: return "macwindow"
        }
    }
}

/// A Chrome tab. `tabID`/`windowID` are numeric ids from AppleScript (`id of tab`);
/// they live until Chrome restarts, so the URL is always stored too.
public struct ChromeTabRef: Codable, Equatable, Hashable, Sendable {
    public var tabID: Int?
    public var windowID: Int?
    public var url: String
    public var title: String

    public init(tabID: Int? = nil, windowID: Int? = nil, url: String, title: String = "") {
        self.tabID = tabID
        self.windowID = windowID
        self.url = url
        self.title = title
    }
}

/// A Claude desktop chat. `conversationID` is a lowercase UUID.
public struct ClaudeChatRef: Codable, Equatable, Hashable, Sendable {
    public var conversationID: String
    public var title: String

    public init(conversationID: String, title: String = "") {
        self.conversationID = conversationID.lowercased()
        self.title = title
    }

    /// The official link that opens the chat in Claude desktop.
    public var appURL: URL { ChatLinkParser.claudeAppURL(conversationID: conversationID) }
}

/// A Claude Code session (Code tab in Claude desktop). `sessionID` is a lowercase
/// `local_<uuid>`; `title` is the session title at binding time (may be empty).
public struct ClaudeCodeSessionRef: Equatable, Hashable, Sendable {
    public var sessionID: String
    public var title: String

    public init(sessionID: String, title: String = "") {
        self.sessionID = sessionID.lowercased()
        self.title = title
    }

    /// The official link that opens the session in Claude desktop.
    public var appURL: URL { ChatLinkParser.claudeCodeSessionAppURL(sessionID: sessionID) }
}

extension ClaudeCodeSessionRef: Codable {
    private enum CodingKeys: String, CodingKey { case sessionID, title }

    /// Without an id the binding is meaningless (an error, and the task is read without a binding); without a title — empty.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(sessionID: try c.decode(String.self, forKey: .sessionID),
                  title: (try? c.decodeIfPresent(String.self, forKey: .title)) ?? "")
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(sessionID, forKey: .sessionID)
        try c.encode(title, forKey: .title)
    }
}

/// A ChatGPT desktop thread (`codex://threads/<id>`).
public struct ChatGPTThreadRef: Codable, Equatable, Hashable, Sendable {
    public var threadID: String
    public var title: String

    public init(threadID: String, title: String = "") {
        self.threadID = threadID
        self.title = title
    }

    public var appURL: URL { ChatLinkParser.chatGPTAppURL(threadID: threadID) }
}

/// A Terminal.app window and tab (`com.apple.Terminal`).
///
/// `windowID` is `id of window` from AppleScript, `tty` is `tty of tab` (e.g. `/dev/ttys003`).
/// Both live until the window/tab is closed or Terminal restarts, so the window title at binding time
/// is stored too — a fallback when neither the tty nor the id can be found anymore.
public struct TerminalWindowRef: Equatable, Hashable, Sendable {
    public var windowID: Int?
    public var tty: String
    public var title: String

    public init(windowID: Int? = nil, tty: String = "", title: String = "") {
        self.windowID = windowID
        self.tty = tty.trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = title
    }

    /// Whether there is at least one persistent identifier (tty or window id).
    public var hasIdentity: Bool { windowID != nil || !tty.isEmpty }
}

extension TerminalWindowRef: Codable {
    private enum CodingKeys: String, CodingKey { case windowID, tty, title }

    /// All fields are optional: missing ones read as empty instead of breaking the task.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(windowID: (try? c.decodeIfPresent(Int.self, forKey: .windowID)) ?? nil,
                  tty: (try? c.decodeIfPresent(String.self, forKey: .tty)) ?? "",
                  title: (try? c.decodeIfPresent(String.self, forKey: .title)) ?? "")
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(windowID, forKey: .windowID)
        try c.encode(tty, forKey: .tty)
        try c.encode(title, forKey: .title)
    }
}

/// A window of any app (Grok Bot and others): bundle id and window title.
public struct AppWindowRef: Codable, Equatable, Hashable, Sendable {
    public var bundleID: String
    public var windowTitle: String
    public var appName: String

    public init(bundleID: String, windowTitle: String = "", appName: String = "") {
        self.bundleID = bundleID
        self.windowTitle = windowTitle
        self.appName = appName
    }
}

/// A task's binding to a chat, tab or window.
///
/// JSON: `{"kind": "<BindingSource>", "<kind>": { ...payload... }}`.
/// New kinds are only ever added: old files read as before, and an unknown
/// kind (a file from a newer version) turns into "no binding" (`JugglerTask`).
public enum TaskBinding: Equatable, Hashable, Sendable {
    case chromeTab(ChromeTabRef)
    case claudeChat(ClaudeChatRef)
    case claudeCodeSession(ClaudeCodeSessionRef)
    case chatGPTThread(ChatGPTThreadRef)
    case terminalWindow(TerminalWindowRef)
    case appWindow(AppWindowRef)

    public var source: BindingSource {
        switch self {
        case .chromeTab: return .chromeTab
        case .claudeChat: return .claudeChat
        case .claudeCodeSession: return .claudeCodeSession
        case .chatGPTThread: return .chatGPTThread
        case .terminalWindow: return .terminalWindow
        case .appWindow: return .appWindow
        }
    }

    /// Title saved at binding time (may be empty).
    public var title: String {
        switch self {
        case .chromeTab(let ref): return ref.title
        case .claudeChat(let ref): return ref.title
        case .claudeCodeSession(let ref): return ref.title
        case .chatGPTThread(let ref): return ref.title
        case .terminalWindow(let ref): return ref.title
        case .appWindow(let ref): return ref.windowTitle
        }
    }
}

extension TaskBinding: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, chromeTab, claudeChat, claudeCodeSession, chatGPTThread, terminalWindow, appWindow
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(String.self, forKey: .kind)
        switch BindingSource(rawValue: kind) {
        case .chromeTab: self = .chromeTab(try c.decode(ChromeTabRef.self, forKey: .chromeTab))
        case .claudeChat: self = .claudeChat(try c.decode(ClaudeChatRef.self, forKey: .claudeChat))
        case .claudeCodeSession: self = .claudeCodeSession(try c.decode(ClaudeCodeSessionRef.self, forKey: .claudeCodeSession))
        case .chatGPTThread: self = .chatGPTThread(try c.decode(ChatGPTThreadRef.self, forKey: .chatGPTThread))
        case .terminalWindow: self = .terminalWindow(try c.decode(TerminalWindowRef.self, forKey: .terminalWindow))
        case .appWindow: self = .appWindow(try c.decode(AppWindowRef.self, forKey: .appWindow))
        case nil:
            throw DecodingError.dataCorruptedError(
                forKey: .kind, in: c, debugDescription: "Неизвестный вид привязки: \(kind)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(source.rawValue, forKey: .kind)
        switch self {
        case .chromeTab(let ref): try c.encode(ref, forKey: .chromeTab)
        case .claudeChat(let ref): try c.encode(ref, forKey: .claudeChat)
        case .claudeCodeSession(let ref): try c.encode(ref, forKey: .claudeCodeSession)
        case .chatGPTThread(let ref): try c.encode(ref, forKey: .chatGPTThread)
        case .terminalWindow(let ref): try c.encode(ref, forKey: .terminalWindow)
        case .appWindow(let ref): try c.encode(ref, forKey: .appWindow)
        }
    }
}

/// Bundle ids of known apps.
public enum KnownBundleIDs {
    public static let chrome = "com.google.Chrome"
    public static let claude = "com.anthropic.claudefordesktop"
    /// ChatGPT desktop: currently ships as `com.openai.codex` (scheme `codex`).
    public static let chatGPT = "com.openai.codex"
    /// All ChatGPT desktop bundle ids: the current one and the old `com.openai.chat`.
    public static let chatGPTAll = ["com.openai.codex", "com.openai.chat"]
    public static let grokBot = "com.anysphere.sand"
    public static let terminal = "com.apple.Terminal"

    /// Is this ChatGPT desktop (any of the known bundle ids)?
    public static func isChatGPT(_ bundleID: String?) -> Bool {
        chatGPTAll.contains { same(bundleID, $0) }
    }

    /// Case-insensitive bundle id comparison.
    public static func same(_ a: String?, _ b: String?) -> Bool {
        guard let a, let b, !a.isEmpty, !b.isEmpty else { return false }
        return a.caseInsensitiveCompare(b) == .orderedSame
    }
}
