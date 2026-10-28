import Foundation

/// Сведения о сессии Claude Code из метаданных Claude desktop.
public struct ClaudeCodeSessionInfo: Equatable, Sendable {
    /// `local_<uuid>` в нижнем регистре.
    public var sessionID: String
    /// Название сессии; пустое, если его нет.
    public var title: String
    /// Рабочая папка сессии, если указана.
    public var cwd: String?
    public var isArchived: Bool

    public init(sessionID: String, title: String = "", cwd: String? = nil, isArchived: Bool = false) {
        self.sessionID = sessionID.lowercased()
        self.title = title
        self.cwd = cwd
        self.isArchived = isArchived
    }
}

/// Чтение метаданных сессий Claude Code, которые хранит Claude desktop:
/// `~/Library/Application Support/Claude/claude-code-sessions/<uuid>/<uuid>/local_<uuid>.json`
/// (поля `sessionId`, `title`, `cwd`, `isArchived` и другие).
///
/// Только чтение: Juggler туда ничего не пишет. Нет папки, файла или поля — `nil`/пустое значение,
/// без ошибок. Формат чужой и может меняться, поэтому разбор терпимый.
public enum ClaudeCodeSessionMetadata {
    /// Файлы больше этого размера не читаются: настоящие метаданные — десятки килобайт.
    public static let maxFileSize = 4 * 1024 * 1024

    /// Папка `claude-code-sessions` текущего пользователя.
    public static func defaultRoot(fileManager: FileManager = .default) -> URL? {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Claude", isDirectory: true)
            .appendingPathComponent("claude-code-sessions", isDirectory: true)
    }

    /// Сведения о сессии или `nil`, если id неверный, файла нет или он не читается.
    public static func info(sessionID: String, root: URL?, fileManager: FileManager = .default) -> ClaudeCodeSessionInfo? {
        guard let root, let url = fileURL(sessionID: sessionID, root: root, fileManager: fileManager) else { return nil }
        guard let size = (try? fileManager.attributesOfItem(atPath: url.path))?[.size] as? NSNumber,
              size.intValue <= maxFileSize,
              let data = try? Data(contentsOf: url),
              let info = parse(data) else { return nil }
        // Файл с чужим id внутри не считаем метаданными этой сессии.
        guard info.sessionID.isEmpty || info.sessionID == sessionID.lowercased() else { return nil }
        return ClaudeCodeSessionInfo(sessionID: sessionID, title: info.title, cwd: info.cwd, isArchived: info.isArchived)
    }

    /// Путь к файлу `<id>.json`: сначала по известной раскладке `root/*/*/`, затем поиском
    /// не глубже `maxDepth` уровней. Id проверяется (`local_<uuid>`), поэтому выйти за `root` нельзя.
    public static func fileURL(sessionID: String, root: URL, fileManager: FileManager = .default, maxDepth: Int = 4) -> URL? {
        guard ChatLinkParser.isClaudeCodeSessionID(sessionID) else { return nil }
        let name = sessionID.lowercased() + ".json"
        for first in subdirectories(of: root, fileManager: fileManager) {
            for second in subdirectories(of: first, fileManager: fileManager) {
                let candidate = second.appendingPathComponent(name)
                if isRegularFile(candidate, fileManager: fileManager) { return candidate }
            }
        }
        // Запасной путь, если Claude поменяет вложенность.
        guard let enumerator = fileManager.enumerator(
            at: root, includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return nil }
        for case let url as URL in enumerator {
            if enumerator.level > maxDepth { enumerator.skipDescendants(); continue }
            if url.lastPathComponent.lowercased() == name, isRegularFile(url, fileManager: fileManager) { return url }
        }
        return nil
    }

    /// Разбор JSON метаданных. Нужен объект; все поля необязательны.
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

    // MARK: - Внутреннее

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
