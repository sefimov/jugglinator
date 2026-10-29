import Foundation

/// A ChatGPT desktop thread from `~/.codex/session_index.jsonl`: id and latest name.
public struct ChatGPTThreadEntry: Codable, Equatable, Sendable {
    /// Thread id — what goes into the `codex://threads/<id>` link.
    public var id: String
    /// Latest thread name (by `updated_at`).
    public var name: String
    /// `updated_at` as in the file (ISO 8601), if present.
    public var updatedAt: String?

    public init(id: String, name: String, updatedAt: String? = nil) {
        self.id = id
        self.name = name
        self.updatedAt = updatedAt
    }

    /// The link ChatGPT opens the thread with.
    public var link: String { ChatLinkParser.chatGPTAppURL(threadID: id).absoluteString }
}

/// What could be read from `session_index.jsonl`.
public enum ChatGPTSessionIndexRead: Equatable, Sendable {
    /// Threads (one per id, with the latest name), most recently updated first;
    /// `skippedLines` — how many non-empty lines were skipped as broken.
    case loaded([ChatGPTThreadEntry], skippedLines: Int)
    /// No file (ChatGPT is not installed or has not created the list yet).
    case missing
    /// The file is larger than `ChatGPTSessionIndex.maxFileSize` — not read.
    case tooLarge
    /// The file exists but cannot be read (permissions, it is a folder, etc.).
    case unreadable
}

/// Reads the ChatGPT desktop (`com.openai.codex`) thread list from `~/.codex/session_index.jsonl`.
///
/// Format: JSON Lines, one line per change: `{"id":"…","thread_name":"…","updated_at":"…Z"}`.
/// The same id appears several times (the thread was renamed) — the line with the latest
/// `updated_at` wins; on a tie or without a date — the last one in the file. Different ids may share a name.
///
/// Read-only: Juggler never writes there. Missing file, oversized file, broken lines —
/// no errors. The format is someone else's and may change, so parsing is lenient.
public enum ChatGPTSessionIndex {
    /// Files larger than this are not read: the real list is tens of kilobytes.
    public static let maxFileSize = 16 * 1024 * 1024

    /// `$CODEX_HOME/session_index.jsonl` if `CODEX_HOME` is set, otherwise `~/.codex/session_index.jsonl`.
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

    /// `maxSize` — file size limit (for checks; defaults to `maxFileSize`).
    public static func read(url: URL?, maxSize: Int = maxFileSize, fileManager: FileManager = .default) -> ChatGPTSessionIndexRead {
        guard let url else { return .missing }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return .missing }
        guard !isDirectory.boolValue,
              let size = (try? fileManager.attributesOfItem(atPath: url.path))?[.size] as? NSNumber else { return .unreadable }
        guard size.int64Value <= Int64(maxSize) else { return .tooLarge }
        guard let data = try? Data(contentsOf: url) else { return .unreadable }
        // The file may have grown between the size check and the read.
        guard data.count <= maxSize else { return .tooLarge }
        let parsed = parse(data)
        return .loaded(parsed.entries, skippedLines: parsed.skippedLines)
    }

    /// Parses the file contents: latest name per id, most recently updated first.
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
        // Total order: threads without a date count as oldest; on a tie, later in the file comes first.
        let ordered = latest.values.sorted { a, b in
            let da = a.date ?? .distantPast, db = b.date ?? .distantPast
            return da != db ? da > db : a.line > b.line
        }
        return (ordered.map(\.entry), skipped)
    }

    /// One JSON Lines line. Requires string `id` (valid for `codex://threads/<id>`) and `thread_name`;
    /// `updated_at` is optional. Otherwise `nil`.
    public static func parseLine(_ data: Data) -> ChatGPTThreadEntry? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any],
              let rawID = dict["id"] as? String,
              let name = dict["thread_name"] as? String else { return nil }
        let id = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
        // The id goes into a link: accept only what ChatLinkParser itself recognizes as a thread id.
        guard !id.isEmpty, ChatLinkParser.parse("codex://threads/\(id)") == .chatGPT(threadID: id) else { return nil }
        let updatedAt = (dict["updated_at"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return ChatGPTThreadEntry(id: id, name: name, updatedAt: updatedAt?.isEmpty == true ? nil : updatedAt)
    }

    /// ISO 8601 with any number of fractional digits (`2026-10-25T19:24:19.612216Z`) or none.
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

    // MARK: - Internals

    /// Whether the candidate is newer: compares dates if both exist; otherwise (or on a tie) — later in the file.
    private static func isNewer(existing: (date: Date?, line: Int), candidate: (date: Date?, line: Int)) -> Bool {
        if let a = existing.date, let b = candidate.date, a != b { return b > a }
        return candidate.line > existing.line
    }

    private static func isBlank(_ bytes: Data.SubSequence) -> Bool {
        bytes.allSatisfy { $0 == 0x20 || $0 == 0x09 || $0 == 0x0D }
    }
}

/// Result of looking up a ChatGPT thread by window title (printed in `--probe-frontmost`).
public struct ChatGPTThreadLookup: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Equatable, Sendable {
        /// Exactly one thread with this name — bound right away.
        case found
        /// Several different threads with this name — a dialog with a prefilled link to the most recently updated one.
        case ambiguous
        /// No thread with this name found.
        case notFound
        /// The window title was not read or is empty (e.g. without Accessibility).
        case noWindowTitle
        case indexMissing
        case indexTooLarge
        case indexUnreadable
    }

    public var status: Status
    /// The window title that was searched for.
    public var windowTitle: String?
    /// Path to `session_index.jsonl`.
    public var indexPath: String?
    /// How many threads are in the list (distinct ids).
    public var indexThreadCount: Int
    /// Skipped broken lines.
    public var skippedLines: Int
    /// Matched threads, most recently updated first.
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

    /// Thread to bind without a dialog: only on a single match.
    public var uniqueMatch: ChatGPTThreadEntry? { status == .found ? matches.first : nil }

    /// Link for the dialog on multiple matches: the most recently updated thread.
    public var prefillLink: String? { status == .ambiguous ? matches.first?.link : nil }

    /// Whether the lookup refers to the window with this title (guards against stale diagnostics).
    public func applies(toWindowTitle title: String?) -> Bool {
        ChatGPTThreadMatcher.normalize(windowTitle ?? "") == ChatGPTThreadMatcher.normalize(title ?? "")
    }
}

/// Looks up a thread by ChatGPT window title. The ChatGPT window title is the name of the open thread.
public enum ChatGPTThreadMatcher {
    /// Exact match without extra whitespace first; if none — case-insensitive
    /// and without suffixes like " - ChatGPT" (`TitleCleaner`). Different ids with one name — `ambiguous`.
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

    /// Matched threads in `entries` order (most recently updated first).
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

    /// Whitespace and newlines collapse into a single space; edges are trimmed.
    public static func normalize(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
    }
}
