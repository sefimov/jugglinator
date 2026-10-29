import Foundation

/// A link to a specific chat, pasted by the user or read from a window.
public enum ChatLink: Equatable, Hashable, Sendable {
    /// Claude chat: lowercase UUID.
    case claude(conversationID: String)
    /// Claude Code session: lowercase `local_<uuid>`.
    case claudeCodeSession(sessionID: String)
    /// ChatGPT desktop thread: id as is (case preserved).
    case chatGPT(threadID: String)

    /// Link for opening in the desktop app.
    public var appURL: URL {
        switch self {
        case .claude(let id): return ChatLinkParser.claudeAppURL(conversationID: id)
        case .claudeCodeSession(let id): return ChatLinkParser.claudeCodeSessionAppURL(sessionID: id)
        case .chatGPT(let id): return ChatLinkParser.chatGPTAppURL(threadID: id)
        }
    }

    public var source: BindingSource {
        switch self {
        case .claude: return .claudeChat
        case .claudeCodeSession: return .claudeCodeSession
        case .chatGPT: return .chatGPTThread
        }
    }
}

/// Chat link parsing.
///
/// Accepted:
/// - `https://claude.ai/chat/<uuid>` (also `http`, `www.`, without a scheme, with `?query`/`#fragment`, with a trailing `/`);
/// - `claude://claude.ai/chat/<uuid>` and `claude://chat/<uuid>`;
/// - a bare UUID (treated as a Claude chat);
/// - Claude Code session: `https://claude.ai/epitaxy/local_<uuid>`, `claude://claude.ai/epitaxy/local_<uuid>`,
///   `claude://epitaxy/local_<uuid>` and a bare `local_<uuid>`;
/// - `codex://threads/<id>`.
///
/// "Share" links (`claude.ai/share/<id>`) are public copies, not a chat id: `parse` does not
/// accept them, and `isClaudeShareLink` lets us explain to the user why.
///
/// Whitespace, newlines, quotes and angle brackets at the edges are dropped.
public enum ChatLinkParser {
    public static func parse(_ raw: String) -> ChatLink? {
        let text = trimmed(raw)
        guard !text.isEmpty, !text.contains(where: { $0.isWhitespace }) else { return nil }

        if isUUID(text) { return .claude(conversationID: text.lowercased()) }
        if isClaudeCodeSessionID(text) { return .claudeCodeSession(sessionID: text.lowercased()) }

        let lower = text.lowercased()
        if lower.hasPrefix("codex://") {
            return parseCodex(String(text.dropFirst("codex://".count)))
        }
        if lower.hasPrefix("claude://") {
            var segments = pathSegments(String(text.dropFirst("claude://".count)))
            if let first = segments.first, isClaudeHost(first) { segments.removeFirst() }
            return claudeChat(in: segments)
        }
        guard var segments = webSegments(text) else { return nil }
        guard let host = segments.first, isClaudeHost(host) else { return nil }
        segments.removeFirst()
        return claudeChat(in: segments)
    }

    /// A Claude "Share" link (`https://claude.ai/share/<id>`): leads to a public copy
    /// of the conversation, not the chat itself, so it is not suitable for binding.
    public static func isClaudeShareLink(_ raw: String) -> Bool {
        let text = trimmed(raw)
        guard !text.isEmpty, !text.contains(where: { $0.isWhitespace }) else { return false }
        guard let segments = webSegments(text), segments.count >= 3, isClaudeHost(segments[0]) else { return false }
        return segments[1].lowercased() == "share"
    }

    /// `local_<uuid>` (any case) — a Claude Code session id.
    public static func isClaudeCodeSessionID(_ text: String) -> Bool {
        let prefix = "local_"
        guard text.count == prefix.count + 36, text.lowercased().hasPrefix(prefix) else { return false }
        return isUUID(String(text.dropFirst(prefix.count)))
    }

    /// A UUID of the form 8-4-4-4-12 hex digits (any case).
    public static func isUUID(_ text: String) -> Bool {
        let groups = text.split(separator: "-", omittingEmptySubsequences: false)
        guard groups.map(\.count) == [8, 4, 4, 4, 12] else { return false }
        return groups.allSatisfy { $0.allSatisfy(\.isHexDigit) }
    }

    /// `claude://claude.ai/chat/<id>` — the official Claude desktop link.
    public static func claudeAppURL(conversationID: String) -> URL {
        URL(string: "claude://claude.ai/chat/\(conversationID.lowercased())")!
    }

    /// `https://claude.ai/chat/<id>` — the same conversation in the browser.
    public static func claudeWebURL(conversationID: String) -> URL {
        URL(string: "https://claude.ai/chat/\(conversationID.lowercased())")!
    }

    /// `claude://claude.ai/epitaxy/<local_uuid>` — a Claude Code session in Claude desktop.
    public static func claudeCodeSessionAppURL(sessionID: String) -> URL {
        URL(string: "claude://claude.ai/epitaxy/\(sessionID.lowercased())")
            ?? URL(string: "claude://claude.ai/epitaxy/\(sessionID.lowercased().addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "")")!
    }

    /// `codex://threads/<id>` — a ChatGPT desktop thread.
    public static func chatGPTAppURL(threadID: String) -> URL {
        URL(string: "codex://threads/\(threadID)")
            ?? URL(string: "codex://threads/\(threadID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "")")!
    }

    // MARK: - Internals

    private static let wrappers: Set<Character> = ["\"", "'", "<", ">", "`", "«", "»", "(", ")", "[", "]"]

    private static func trimmed(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while let first = text.first, wrappers.contains(first) { text.removeFirst() }
        while let last = text.last, wrappers.contains(last) { text.removeLast() }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Segments of `https://`, `http://` or a scheme-less link (the first is the host); `nil` for another scheme.
    private static func webSegments(_ text: String) -> [String]? {
        let lower = text.lowercased()
        var rest = text
        for scheme in ["https://", "http://"] where lower.hasPrefix(scheme) {
            rest = String(text.dropFirst(scheme.count))
            break
        }
        if rest.contains("://") { return nil }
        return pathSegments(rest)
    }

    /// Path segments without query and fragment; empty segments (`//`, trailing `/`) are dropped.
    private static func pathSegments(_ text: String) -> [String] {
        let withoutFragment = text.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        let withoutQuery = withoutFragment.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        return withoutQuery.split(separator: "/").map(String.init)
    }

    private static func isClaudeHost(_ host: String) -> Bool {
        let h = host.lowercased()
        return h == "claude.ai" || h == "www.claude.ai"
    }

    /// Exactly `chat/<uuid>` or `epitaxy/local_<uuid>`: other sections (project, settings, share) do not count as a chat.
    private static func claudeChat(in segments: [String]) -> ChatLink? {
        guard segments.count == 2 else { return nil }
        switch segments[0].lowercased() {
        case "chat" where isUUID(segments[1]):
            return .claude(conversationID: segments[1].lowercased())
        case "epitaxy" where isClaudeCodeSessionID(segments[1]):
            return .claudeCodeSession(sessionID: segments[1].lowercased())
        default:
            return nil
        }
    }

    private static func parseCodex(_ rest: String) -> ChatLink? {
        let segments = pathSegments(rest)
        guard segments.count == 2, segments[0].lowercased() == "threads", isThreadID(segments[1]) else { return nil }
        return .chatGPT(threadID: segments[1])
    }

    private static func isThreadID(_ id: String) -> Bool {
        guard !id.isEmpty, id.count <= 200 else { return false }
        return id.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_" || scalar == ".")
        }
    }
}

/// Normalizes a tab URL for comparison: scheme and host case,
/// no `#fragment` and no trailing `/`. The query is kept — it often matters.
public enum URLNormalizer {
    public static func normalize(_ raw: String) -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: text), components.scheme != nil else {
            return text
        }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        components.fragment = nil
        while components.path.count > 1, components.path.hasSuffix("/") {
            components.path.removeLast()
        }
        if components.path == "/" { components.path = "" }
        return components.string ?? text
    }
}
