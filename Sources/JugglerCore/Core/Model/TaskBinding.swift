import Foundation

/// Источник привязки: определяет значок в списке и способ активации.
public enum BindingSource: String, Codable, CaseIterable, Sendable {
    case chromeTab
    case claudeChat
    case chatGPTThread
    case appWindow

    /// Короткое название источника для интерфейса.
    public var displayName: String {
        switch self {
        case .chromeTab: return "Chrome"
        case .claudeChat: return "Claude"
        case .chatGPTThread: return "ChatGPT"
        case .appWindow: return "Окно приложения"
        }
    }

    /// Имя SF Symbol для значка источника.
    public var symbolName: String {
        switch self {
        case .chromeTab: return "globe"
        case .claudeChat: return "sparkles"
        case .chatGPTThread: return "bubble.left.and.bubble.right"
        case .appWindow: return "macwindow"
        }
    }
}

/// Вкладка Chrome. `tabID`/`windowID` — числовые id из AppleScript (`id of tab`);
/// они живут до перезапуска Chrome, поэтому всегда хранится и адрес.
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

/// Чат Claude desktop. `conversationID` — UUID в нижнем регистре.
public struct ClaudeChatRef: Codable, Equatable, Hashable, Sendable {
    public var conversationID: String
    public var title: String

    public init(conversationID: String, title: String = "") {
        self.conversationID = conversationID.lowercased()
        self.title = title
    }

    /// Официальная ссылка, которая открывает чат в Claude desktop.
    public var appURL: URL { ChatLinkParser.claudeAppURL(conversationID: conversationID) }
}

/// Тред ChatGPT desktop (`codex://threads/<id>`).
public struct ChatGPTThreadRef: Codable, Equatable, Hashable, Sendable {
    public var threadID: String
    public var title: String

    public init(threadID: String, title: String = "") {
        self.threadID = threadID
        self.title = title
    }

    public var appURL: URL { ChatLinkParser.chatGPTAppURL(threadID: threadID) }
}

/// Окно любого приложения (Grok Bot и прочие): bundle id и заголовок окна.
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

/// Привязка задачи к чату, вкладке или окну.
///
/// JSON: `{"kind": "<BindingSource>", "<kind>": { ...payload... }}`.
public enum TaskBinding: Equatable, Hashable, Sendable {
    case chromeTab(ChromeTabRef)
    case claudeChat(ClaudeChatRef)
    case chatGPTThread(ChatGPTThreadRef)
    case appWindow(AppWindowRef)

    public var source: BindingSource {
        switch self {
        case .chromeTab: return .chromeTab
        case .claudeChat: return .claudeChat
        case .chatGPTThread: return .chatGPTThread
        case .appWindow: return .appWindow
        }
    }

    /// Заголовок, сохранённый при привязке (может быть пустым).
    public var title: String {
        switch self {
        case .chromeTab(let ref): return ref.title
        case .claudeChat(let ref): return ref.title
        case .chatGPTThread(let ref): return ref.title
        case .appWindow(let ref): return ref.windowTitle
        }
    }
}

extension TaskBinding: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, chromeTab, claudeChat, chatGPTThread, appWindow
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(String.self, forKey: .kind)
        switch BindingSource(rawValue: kind) {
        case .chromeTab: self = .chromeTab(try c.decode(ChromeTabRef.self, forKey: .chromeTab))
        case .claudeChat: self = .claudeChat(try c.decode(ClaudeChatRef.self, forKey: .claudeChat))
        case .chatGPTThread: self = .chatGPTThread(try c.decode(ChatGPTThreadRef.self, forKey: .chatGPTThread))
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
        case .chatGPTThread(let ref): try c.encode(ref, forKey: .chatGPTThread)
        case .appWindow(let ref): try c.encode(ref, forKey: .appWindow)
        }
    }
}

/// Bundle id известных приложений.
public enum KnownBundleIDs {
    public static let chrome = "com.google.Chrome"
    public static let claude = "com.anthropic.claudefordesktop"
    public static let chatGPT = "com.openai.chat"

    /// Сравнение bundle id без учёта регистра.
    public static func same(_ a: String?, _ b: String?) -> Bool {
        guard let a, let b, !a.isEmpty, !b.isEmpty else { return false }
        return a.caseInsensitiveCompare(b) == .orderedSame
    }
}
