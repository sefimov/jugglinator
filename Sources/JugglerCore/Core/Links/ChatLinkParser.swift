import Foundation

/// Ссылка на конкретный чат, вставленная пользователем или прочитанная из окна.
public enum ChatLink: Equatable, Hashable, Sendable {
    /// Чат Claude: UUID в нижнем регистре.
    case claude(conversationID: String)
    /// Сессия Claude Code: `local_<uuid>` в нижнем регистре.
    case claudeCodeSession(sessionID: String)
    /// Тред ChatGPT desktop: id как есть (регистр сохраняется).
    case chatGPT(threadID: String)

    /// Ссылка для открытия в desktop-приложении.
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

/// Разбор ссылок на чаты.
///
/// Принимается:
/// - `https://claude.ai/chat/<uuid>` (также `http`, `www.`, без схемы, с `?query`/`#fragment`, с хвостовым `/`);
/// - `claude://claude.ai/chat/<uuid>` и `claude://chat/<uuid>`;
/// - голый UUID (считается чатом Claude);
/// - сессия Claude Code: `https://claude.ai/epitaxy/local_<uuid>`, `claude://claude.ai/epitaxy/local_<uuid>`,
///   `claude://epitaxy/local_<uuid>` и голый `local_<uuid>`;
/// - `codex://threads/<id>`.
///
/// Ссылки «Поделиться» (`claude.ai/share/<id>`) — это публичные копии, а не id чата: `parse` их
/// не принимает, а `isClaudeShareLink` позволяет объяснить пользователю, почему.
///
/// Пробелы, переводы строк, кавычки и угловые скобки по краям отбрасываются.
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

    /// Ссылка «Поделиться» Claude (`https://claude.ai/share/<id>`): ведёт на публичную копию
    /// беседы, а не на сам чат, поэтому для привязки не подходит.
    public static func isClaudeShareLink(_ raw: String) -> Bool {
        let text = trimmed(raw)
        guard !text.isEmpty, !text.contains(where: { $0.isWhitespace }) else { return false }
        guard let segments = webSegments(text), segments.count >= 3, isClaudeHost(segments[0]) else { return false }
        return segments[1].lowercased() == "share"
    }

    /// `local_<uuid>` (любой регистр) — id сессии Claude Code.
    public static func isClaudeCodeSessionID(_ text: String) -> Bool {
        let prefix = "local_"
        guard text.count == prefix.count + 36, text.lowercased().hasPrefix(prefix) else { return false }
        return isUUID(String(text.dropFirst(prefix.count)))
    }

    /// UUID вида 8-4-4-4-12 шестнадцатеричных цифр (любой регистр).
    public static func isUUID(_ text: String) -> Bool {
        let groups = text.split(separator: "-", omittingEmptySubsequences: false)
        guard groups.map(\.count) == [8, 4, 4, 4, 12] else { return false }
        return groups.allSatisfy { $0.allSatisfy(\.isHexDigit) }
    }

    /// `claude://claude.ai/chat/<id>` — официальная ссылка Claude desktop.
    public static func claudeAppURL(conversationID: String) -> URL {
        URL(string: "claude://claude.ai/chat/\(conversationID.lowercased())")!
    }

    /// `https://claude.ai/chat/<id>` — та же беседа в браузере.
    public static func claudeWebURL(conversationID: String) -> URL {
        URL(string: "https://claude.ai/chat/\(conversationID.lowercased())")!
    }

    /// `claude://claude.ai/epitaxy/<local_uuid>` — сессия Claude Code в Claude desktop.
    public static func claudeCodeSessionAppURL(sessionID: String) -> URL {
        URL(string: "claude://claude.ai/epitaxy/\(sessionID.lowercased())")
            ?? URL(string: "claude://claude.ai/epitaxy/\(sessionID.lowercased().addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "")")!
    }

    /// `codex://threads/<id>` — тред ChatGPT desktop.
    public static func chatGPTAppURL(threadID: String) -> URL {
        URL(string: "codex://threads/\(threadID)")
            ?? URL(string: "codex://threads/\(threadID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "")")!
    }

    // MARK: - Внутреннее

    private static let wrappers: Set<Character> = ["\"", "'", "<", ">", "`", "«", "»", "(", ")", "[", "]"]

    private static func trimmed(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while let first = text.first, wrappers.contains(first) { text.removeFirst() }
        while let last = text.last, wrappers.contains(last) { text.removeLast() }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Сегменты `https://`, `http://` или ссылки без схемы (первый — хост); `nil` для другой схемы.
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

    /// Сегменты пути без query и fragment; пустые сегменты (`//`, хвостовой `/`) отбрасываются.
    private static func pathSegments(_ text: String) -> [String] {
        let withoutFragment = text.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        let withoutQuery = withoutFragment.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        return withoutQuery.split(separator: "/").map(String.init)
    }

    private static func isClaudeHost(_ host: String) -> Bool {
        let h = host.lowercased()
        return h == "claude.ai" || h == "www.claude.ai"
    }

    /// Ровно `chat/<uuid>` или `epitaxy/local_<uuid>`: другие разделы (project, settings, share) не считаются чатом.
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

/// Нормализация адреса вкладки для сравнения: регистр схемы и хоста,
/// без `#fragment` и без хвостового `/`. Query сохраняется — он часто значим.
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
