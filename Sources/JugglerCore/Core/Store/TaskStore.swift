import Foundation

/// Хранилище `tasks.json`.
///
/// - Запись атомарная: данные пишутся во временный файл и подменяют основной
///   (`Data.write(options: .atomic)`), так что при сбое остаётся старая или новая версия целиком.
/// - Перед каждой записью предыдущая исправная версия копируется в `tasks.backup.json`.
/// - Битый файл при загрузке переименовывается в `tasks.corrupt-<время>.json`
///   (данные не теряются), затем делается попытка восстановиться из резервной копии;
///   если и она негодна, начинаем с пустого списка.
public final class TaskStore {
    public enum LoadOutcome: Equatable, Sendable {
        /// Основной файл прочитан.
        case loaded
        /// Файла ещё нет (первый запуск): пустой список.
        case missing
        /// Основной файл был битым или пропал; данные взяты из резервной копии.
        case recoveredFromBackup(quarantinedURL: URL?)
        /// Основной файл битый, резервной копии нет или она тоже битая: пустой список.
        case resetAfterCorruption(quarantinedURL: URL?)

        public var isRecovery: Bool {
            switch self {
            case .loaded, .missing: return false
            case .recoveredFromBackup, .resetAfterCorruption: return true
            }
        }
    }

    public struct LoadResult: Equatable, Sendable {
        public var document: TasksDocument
        public var outcome: LoadOutcome
    }

    public let fileURL: URL
    private let fileManager: FileManager
    private let now: () -> Date

    /// `~/Library/Application Support/Juggler/tasks.json`.
    public static var defaultFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Juggler", isDirectory: true).appendingPathComponent("tasks.json")
    }

    public init(fileURL: URL = TaskStore.defaultFileURL, fileManager: FileManager = .default, now: @escaping () -> Date = Date.init) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.now = now
    }

    public var directoryURL: URL { fileURL.deletingLastPathComponent() }

    /// `tasks.backup.json` рядом с основным файлом.
    public var backupURL: URL {
        directoryURL.appendingPathComponent(baseName + ".backup.json")
    }

    private var baseName: String { fileURL.deletingPathExtension().lastPathComponent }

    // MARK: - Загрузка

    public func load() -> LoadResult {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            if let backup = readDocument(at: backupURL) {
                return LoadResult(document: backup, outcome: .recoveredFromBackup(quarantinedURL: nil))
            }
            return LoadResult(document: TasksDocument(), outcome: .missing)
        }
        if let document = readDocument(at: fileURL) {
            return LoadResult(document: document, outcome: .loaded)
        }
        let quarantined = quarantineMainFile()
        if let backup = readDocument(at: backupURL) {
            return LoadResult(document: backup, outcome: .recoveredFromBackup(quarantinedURL: quarantined))
        }
        return LoadResult(document: TasksDocument(), outcome: .resetAfterCorruption(quarantinedURL: quarantined))
    }

    // MARK: - Запись

    public func save(_ document: TasksDocument) throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        var document = document
        document.normalize()
        let data = try TaskStore.encode(document)
        // Резервная копия — только из исправного файла, чтобы не затереть её мусором.
        if let current = try? Data(contentsOf: fileURL), (try? TaskStore.decode(current)) != nil, current != data {
            try? current.write(to: backupURL, options: .atomic)
        }
        try data.write(to: fileURL, options: .atomic)
    }

    // MARK: - Кодирование

    public static func encode(_ document: TasksDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(ISO8601.string(from: date))
        }
        return try encoder.encode(document)
    }

    public static func decode(_ data: Data) throws -> TasksDocument {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            if let seconds = try? c.decode(Double.self) {
                return Date(timeIntervalSince1970: seconds)
            }
            let string = try c.decode(String.self)
            guard let date = ISO8601.date(from: string) else {
                throw DecodingError.dataCorruptedError(in: c, debugDescription: "Неверная дата: \(string)")
            }
            return date
        }
        return try decoder.decode(TasksDocument.self, from: data)
    }

    // MARK: - Внутреннее

    private func readDocument(at url: URL) -> TasksDocument? {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        return try? TaskStore.decode(data)
    }

    /// Переименовывает битый основной файл, чтобы его можно было разобрать вручную.
    private func quarantineMainFile() -> URL? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: now())
        var candidate = directoryURL.appendingPathComponent("\(baseName).corrupt-\(stamp).json")
        var counter = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directoryURL.appendingPathComponent("\(baseName).corrupt-\(stamp)-\(counter).json")
            counter += 1
        }
        do {
            try fileManager.moveItem(at: fileURL, to: candidate)
            return candidate
        } catch {
            return nil
        }
    }
}

/// ISO 8601 с миллисекундами при записи; при чтении принимаются оба варианта.
enum ISO8601 {
    static func string(from date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }

    static func date(from string: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: string) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: string)
    }
}
