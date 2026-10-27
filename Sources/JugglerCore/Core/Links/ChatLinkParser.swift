import Foundation

/// Ссылка на конкретный чат, вставленная пользователем или прочитанная из окна.
public enum ChatLink: Equatable, Hashable, Sendable {
    /// Чат Claude: UUID в нижнем регистре.
    case claude(conversationID: String)
    /// Тред ChatGPT desktop: id как есть (регистр сохраняется).
    case chatGPT(threadID: String)

    /// Ссылка для открытия в desktop-приложении.
    public var appURL: URL {
        switch self {
        case .claude(let id): return ChatLinkParser.claudeAppURL(conversationID: id)
        case .chatGPT(let id): return ChatLinkParser.chatGPTAppURL(threadID: id)
        }
    }

    public var source: BindingSource {
        switch self {
        case .claude: return .claudeChat
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
/// - `codex://threads/<id>`.
///
/// Пробелы, переводы строк, кавычки и угловые скобки по краям отбрасываются.
public enum ChatLinkParser {
    public static func parse(_ raw: String) -> ChatLink? {
        let text = trimmed(raw)
        guard !text.isEmpty, !text.contains(where: { $0.isWhitespace }) else { return nil }

        if isUUID(text) { return .claude(conversationID: text.lowercased()) }

        let lower = text.lowercased()
        if lower.hasPrefix("codex://") {
            return parseCodex(String(text.dropFirst("codex://".count)))
        }
        if lower.hasPrefix("claude://") {
            var segments = pathSegments(String(text.dropFirst("claude://".count)))
            if let first = segments.first, isClaudeHost(first) { segments.removeFirst() }
            return claudeChat(in: segments)
        }
        var rest = text
        for scheme in ["https://", "http://"] where lower.hasPrefix(scheme) {
            rest = String(text.dropFirst(scheme.count))
            break
        }
        if rest.contains("://") { return nil }
        var segments = pathSegments(rest)
        guard let host = segments.first, isClaudeHost(host) else { return nil }
        segments.removeFirst()
        return claudeChat(in: segments)
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

    /// Ровно `chat/<uuid>`: другие разделы (project, settings) не считаются чатом.
    private static func claudeChat(in segments: [String]) -> ChatLink? {
        guard segments.count == 2, segments[0].lowercased() == "chat", isUUID(segments[1]) else { return nil }
        return .claude(conversationID: segments[1].lowercased())
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
