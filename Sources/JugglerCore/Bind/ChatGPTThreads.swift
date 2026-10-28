import Foundation

/// Тред ChatGPT desktop из `~/.codex/session_index.jsonl`: id и последнее название.
public struct ChatGPTThreadEntry: Codable, Equatable, Sendable {
    /// Id треда — то, что идёт в ссылку `codex://threads/<id>`.
    public var id: String
    /// Последнее название треда (по `updated_at`).
    public var name: String
    /// `updated_at` как в файле (ISO 8601), если есть.
    public var updatedAt: String?

    public init(id: String, name: String, updatedAt: String? = nil) {
        self.id = id
        self.name = name
        self.updatedAt = updatedAt
    }

    /// Ссылка, по которой ChatGPT открывает тред.
    public var link: String { ChatLinkParser.chatGPTAppURL(threadID: id).absoluteString }
}

/// Что получилось прочитать из `session_index.jsonl`.
public enum ChatGPTSessionIndexRead: Equatable, Sendable {
    /// Треды (по одному на id, с последним названием), сначала недавно обновлённые;
    /// `skippedLines` — сколько непустых строк пропущено как битые.
    case loaded([ChatGPTThreadEntry], skippedLines: Int)
    /// Файла нет (ChatGPT не установлен или ещё не создал список).
    case missing
    /// Файл больше `ChatGPTSessionIndex.maxFileSize` — не читается.
    case tooLarge
    /// Файл есть, но не читается (права, это папка и т. п.).
    case unreadable
}

/// Чтение списка тредов ChatGPT desktop (`com.openai.codex`) из `~/.codex/session_index.jsonl`.
///
/// Формат — JSON Lines, по строке на изменение: `{"id":"…","thread_name":"…","updated_at":"…Z"}`.
/// Один id встречается несколько раз (тред переименовывали) — берётся строка с самым поздним
/// `updated_at`, при равенстве или без даты — последняя в файле. Разные id могут иметь одно название.
///
/// Только чтение: Juggler туда ничего не пишет. Нет файла, слишком большой файл, битые строки —
/// без ошибок. Формат чужой и может меняться, поэтому разбор терпимый.
public enum ChatGPTSessionIndex {
    /// Файлы больше этого размера не читаются: настоящий список — десятки килобайт.
    public static let maxFileSize = 16 * 1024 * 1024

    /// `$CODEX_HOME/session_index.jsonl`, если `CODEX_HOME` задан, иначе `~/.codex/session_index.jsonl`.
    public static func defaultURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        let codexHome: URL
        if let custom = environment["CODEX_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty {
            codexHome = URL(fileURLWithPath: (custom as NSString).expandingTildeInPath, isDirectory: true)
        } else {
            codexHome = home.appendingPathComponent(".codex", isDirectory: true)
        }
        return codexHome.appendingPathComponent("session_index.jsonl")
    }

    /// `maxSize` — предел размера файла (для проверок; по умолчанию `maxFileSize`).
    public static func read(url: URL?, maxSize: Int = maxFileSize, fileManager: FileManager = .default) -> ChatGPTSessionIndexRead {
        guard let url else { return .missing }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return .missing }
        guard !isDirectory.boolValue,
              let size = (try? fileManager.attributesOfItem(atPath: url.path))?[.size] as? NSNumber else { return .unreadable }
        guard size.int64Value <= Int64(maxSize) else { return .tooLarge }
        guard let data = try? Data(contentsOf: url) else { return .unreadable }
        // Файл мог вырасти между проверкой размера и чтением.
        guard data.count <= maxSize else { return .tooLarge }
        let parsed = parse(data)
        return .loaded(parsed.entries, skippedLines: parsed.skippedLines)
    }

    /// Разбор содержимого файла: последнее название по каждому id, сначала недавно обновлённые.
    public static func parse(_ data: Data) -> (entries: [ChatGPTThreadEntry], skippedLines: Int) {
        var latest: [String: (entry: ChatGPTThreadEntry, date: Date?, line: Int)] = [:]
        var skipped = 0
        var lineNumber = 0
        for rawLine in data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true) {
            lineNumber += 1
            guard let entry = parseLine(Data(rawLine)) else {
                if !isBlank(rawLine) { skipped += 1 }
                continue
            }
            let date = entry.updatedAt.flatMap(parseDate)
            if let existing = latest[entry.id], !isNewer(existing: (existing.date, existing.line), candidate: (date, lineNumber)) {
                continue
            }
            latest[entry.id] = (entry, date, lineNumber)
        }
        // Порядок полный: треды без даты — как самые старые, при равенстве — позже в файле выше.
        let ordered = latest.values.sorted { a, b in
            let da = a.date ?? .distantPast, db = b.date ?? .distantPast
            return da != db ? da > db : a.line > b.line
        }
        return (ordered.map(\.entry), skipped)
    }

    /// Одна строка JSON Lines. Нужны строковые `id` (годный для `codex://threads/<id>`) и `thread_name`;
    /// `updated_at` необязателен. Иначе `nil`.
    public static func parseLine(_ data: Data) -> ChatGPTThreadEntry? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any],
              let rawID = dict["id"] as? String,
              let name = dict["thread_name"] as? String else { return nil }
        let id = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
        // Id попадёт в ссылку: принимаем только то, что ChatLinkParser сам распознаёт как id треда.
        guard !id.isEmpty, ChatLinkParser.parse("codex://threads/\(id)") == .chatGPT(threadID: id) else { return nil }
        let updatedAt = (dict["updated_at"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return ChatGPTThreadEntry(id: id, name: name, updatedAt: updatedAt?.isEmpty == true ? nil : updatedAt)
    }

    /// ISO 8601 с любым числом знаков дробной части (`2026-10-25T19:24:19.612216Z`) или без неё.
    public static func parseDate(_ text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var base = trimmed
        var fraction = 0.0
        if let dot = trimmed.firstIndex(of: ".") {
            let afterDot = trimmed[trimmed.index(after: dot)...]
            let digits = afterDot.prefix(while: { $0.isASCII && $0.isNumber })
            guard !digits.isEmpty else { return nil }
            fraction = Double("0." + digits) ?? 0
            base = String(trimmed[..<dot]) + String(afterDot.dropFirst(digits.count))
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: base).map { $0.addingTimeInterval(fraction) }
    }

    // MARK: - Внутреннее

    /// Новее ли кандидат: сравниваются даты, если обе есть; иначе (или при равенстве) — позже в файле.
    private static func isNewer(existing: (date: Date?, line: Int), candidate: (date: Date?, line: Int)) -> Bool {
        if let a = existing.date, let b = candidate.date, a != b { return b > a }
        return candidate.line > existing.line
    }

    private static func isBlank(_ bytes: Data.SubSequence) -> Bool {
        bytes.allSatisfy { $0 == 0x20 || $0 == 0x09 || $0 == 0x0D }
    }
}

/// Итог поиска треда ChatGPT по заголовку окна (печатается в `--probe-frontmost`).
public struct ChatGPTThreadLookup: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Equatable, Sendable {
        /// Ровно один тред с таким названием — привязывается сразу.
        case found
        /// Несколько разных тредов с таким названием — диалог с уже вставленной ссылкой на последний обновлённый.
        case ambiguous
        /// Тред с таким названием не найден.
        case notFound
        /// Заголовок окна не прочитан или пустой (например, без Accessibility).
        case noWindowTitle
        case indexMissing
        case indexTooLarge
        case indexUnreadable
    }

    public var status: Status
    /// Заголовок окна, по которому искали.
    public var windowTitle: String?
    /// Путь к `session_index.jsonl`.
    public var indexPath: String?
    /// Сколько тредов в списке (разных id).
    public var indexThreadCount: Int
    /// Пропущенные битые строки.
    public var skippedLines: Int
    /// Совпавшие треды, сначала недавно обновлённые.
    public var matches: [ChatGPTThreadEntry]

    public init(status: Status, windowTitle: String? = nil, indexPath: String? = nil,
                indexThreadCount: Int = 0, skippedLines: Int = 0, matches: [ChatGPTThreadEntry] = []) {
        self.status = status
        self.windowTitle = windowTitle
        self.indexPath = indexPath
        self.indexThreadCount = indexThreadCount
        self.skippedLines = skippedLines
        self.matches = matches
    }

    /// Тред для привязки без диалога: только при единственном совпадении.
    public var uniqueMatch: ChatGPTThreadEntry? { status == .found ? matches.first : nil }

    /// Ссылка для диалога при нескольких совпадениях: последний обновлённый тред.
    public var prefillLink: String? { status == .ambiguous ? matches.first?.link : nil }

    /// Относится ли поиск к окну с этим заголовком (защита от устаревшей диагностики).
    public func applies(toWindowTitle title: String?) -> Bool {
        ChatGPTThreadMatcher.normalize(windowTitle ?? "") == ChatGPTThreadMatcher.normalize(title ?? "")
    }
}

/// Поиск треда по заголовку окна ChatGPT. Заголовок окна ChatGPT — название открытого треда.
public enum ChatGPTThreadMatcher {
    /// Сначала точное совпадение без лишних пробелов; если его нет — без учёта регистра
    /// и хвостов вида « - ChatGPT» (`TitleCleaner`). Разные id с одним названием — `ambiguous`.
    public static func lookup(windowTitle: String?, index: ChatGPTSessionIndexRead, indexPath: String? = nil) -> ChatGPTThreadLookup {
        let title = windowTitle.map(normalize)
        var result = ChatGPTThreadLookup(status: .notFound, windowTitle: title, indexPath: indexPath)
        let entries: [ChatGPTThreadEntry]
        switch index {
        case .loaded(let list, let skipped):
            entries = list
            result.indexThreadCount = list.count
            result.skippedLines = skipped
        case .missing: result.status = .indexMissing; return result
        case .tooLarge: result.status = .indexTooLarge; return result
        case .unreadable: result.status = .indexUnreadable; return result
        }
        guard let title, !title.isEmpty else { result.status = .noWindowTitle; return result }
        result.matches = matches(title: title, in: entries)
        switch result.matches.count {
        case 0: result.status = .notFound
        case 1: result.status = .found
        default: result.status = .ambiguous
        }
        return result
    }

    /// Совпавшие треды в порядке `entries` (сначала недавно обновлённые).
    public static func matches(title: String, in entries: [ChatGPTThreadEntry]) -> [ChatGPTThreadEntry] {
        let target = normalize(title)
        guard !target.isEmpty else { return [] }
        let exact = entries.filter { normalize($0.name) == target }
        if !exact.isEmpty { return exact }
        let cleaned = TitleCleaner.clean(target)
        guard !cleaned.isEmpty else { return [] }
        return entries.filter {
            let name = TitleCleaner.clean($0.name)
            return !name.isEmpty && name.caseInsensitiveCompare(cleaned) == .orderedSame
        }
    }

    /// Пробелы и переводы строк схлопываются в один пробел, по краям — обрезаются.
    public static func normalize(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
    }
}
