import Foundation

/// Claude Code session info from Claude desktop metadata.
public struct ClaudeCodeSessionInfo: Equatable, Sendable {
    /// Lowercase `local_<uuid>`.
    public var sessionID: String
    /// Session title; empty if there is none.
    public var title: String
    /// Session working directory, if specified.
    public var cwd: String?
    public var isArchived: Bool

    public init(sessionID: String, title: String = "", cwd: String? = nil, isArchived: Bool = false) {
        self.sessionID = sessionID.lowercased()
        self.title = title
        self.cwd = cwd
        self.isArchived = isArchived
    }
}

/// Reads Claude Code session metadata stored by Claude desktop:
/// `~/Library/Application Support/Claude/claude-code-sessions/<uuid>/<uuid>/local_<uuid>.json`
/// (fields `sessionId`, `title`, `cwd`, `isArchived` and others).
///
/// Read-only: Jugglinator never writes there. Missing folder, file or field — `nil`/empty value,
/// no errors. The format is someone else's and may change, so parsing is lenient.
public enum ClaudeCodeSessionMetadata {
    /// Files larger than this are not read: real metadata is tens of kilobytes.
    public static let maxFileSize = 4 * 1024 * 1024

    /// The current user's `claude-code-sessions` folder.
    public static func defaultRoot(fileManager: FileManager = .default) -> URL? {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Claude", isDirectory: true)
            .appendingPathComponent("claude-code-sessions", isDirectory: true)
    }

    /// Session info, or `nil` if the id is invalid, the file is missing or unreadable.
    public static func info(sessionID: String, root: URL?, fileManager: FileManager = .default) -> ClaudeCodeSessionInfo? {
        guard let root, let url = fileURL(sessionID: sessionID, root: root, fileManager: fileManager) else { return nil }
        guard let size = (try? fileManager.attributesOfItem(atPath: url.path))?[.size] as? NSNumber,
              size.intValue <= maxFileSize,
              let data = try? Data(contentsOf: url),
              let info = parse(data) else { return nil }
        // A file with a different id inside is not treated as this session's metadata.
        guard info.sessionID.isEmpty || info.sessionID == sessionID.lowercased() else { return nil }
        return ClaudeCodeSessionInfo(sessionID: sessionID, title: info.title, cwd: info.cwd, isArchived: info.isArchived)
    }

    /// Path to the `<id>.json` file: first by the known `root/*/*/` layout, then by searching
    /// no deeper than `maxDepth` levels. The id is validated (`local_<uuid>`), so escaping `root` is impossible.
    public static func fileURL(sessionID: String, root: URL, fileManager: FileManager = .default, maxDepth: Int = 4) -> URL? {
        guard ChatLinkParser.isClaudeCodeSessionID(sessionID) else { return nil }
        let name = sessionID.lowercased() + ".json"
        for first in subdirectories(of: root, fileManager: fileManager) {
            for second in subdirectories(of: first, fileManager: fileManager) {
                let candidate = second.appendingPathComponent(name)
                if isRegularFile(candidate, fileManager: fileManager) { return candidate }
            }
        }
        // Fallback in case Claude changes the nesting.
        guard let enumerator = fileManager.enumerator(
            at: root, includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return nil }
        for case let url as URL in enumerator {
            if enumerator.level > maxDepth { enumerator.skipDescendants(); continue }
            if url.lastPathComponent.lowercased() == name, isRegularFile(url, fileManager: fileManager) { return url }
        }
        return nil
    }

    /// Parses metadata JSON. Requires an object; all fields are optional.
    public static func parse(_ data: Data) -> ClaudeCodeSessionInfo? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any] else { return nil }
        let rawID = (dict["sessionId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = (dict["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let cwd = (dict["cwd"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let archived = (dict["isArchived"] as? Bool) ?? false
        return ClaudeCodeSessionInfo(
            sessionID: ChatLinkParser.isClaudeCodeSessionID(rawID) ? rawID : "",
            title: title, cwd: cwd, isArchived: archived)
    }

    // MARK: - Internals

    private static func subdirectories(of url: URL, fileManager: FileManager) -> [URL] {
        let items = (try? fileManager.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        return items.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
    }

    private static func isRegularFile(_ url: URL, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && !isDirectory.boolValue
    }
}
