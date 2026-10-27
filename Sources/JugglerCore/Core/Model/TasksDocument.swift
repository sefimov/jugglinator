import Foundation

/// Содержимое `tasks.json`: упорядоченный список задач и последняя активная задача.
public struct TasksDocument: Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    /// Порядок списка задаёт номера (1, 2, 3…) и порядок переключения по кругу.
    public var tasks: [JugglerTask]
    /// Задача, активированная последней. Иконка меню-бара показывает её номер;
    /// она же служит запасным вариантом, если по переднему окну задачу определить не удалось.
    public var lastActiveTaskID: UUID?

    public init(tasks: [JugglerTask] = [], lastActiveTaskID: UUID? = nil, version: Int = TasksDocument.currentVersion) {
        self.version = version
        self.tasks = tasks
        self.lastActiveTaskID = lastActiveTaskID
    }

    public func index(of id: UUID) -> Int? {
        tasks.firstIndex { $0.id == id }
    }

    public func task(withID id: UUID) -> JugglerTask? {
        index(of: id).map { tasks[$0] }
    }

    /// Номер задачи для показа (позиция в списке с 1).
    public func number(of id: UUID) -> Int? {
        index(of: id).map { $0 + 1 }
    }

    public var lastActiveTask: JugglerTask? {
        lastActiveTaskID.flatMap { task(withID: $0) }
    }

    /// Отмечает заход в задачу: обновляет время и последнюю активную задачу.
    /// Возвращает `false`, если задачи с таким id нет.
    @discardableResult
    public mutating func markVisited(_ id: UUID, at date: Date) -> Bool {
        guard let i = index(of: id) else { return false }
        tasks[i].lastVisitedAt = date
        lastActiveTaskID = id
        return true
    }

    /// Приводит документ в согласованное состояние: убирает дубликаты id
    /// (остаётся первый) и висячую ссылку на последнюю активную задачу.
    public mutating func normalize() {
        var seen = Set<UUID>()
        tasks = tasks.filter { seen.insert($0.id).inserted }
        if let active = lastActiveTaskID, !seen.contains(active) {
            lastActiveTaskID = nil
        }
    }
}

extension TasksDocument: Codable {
    private enum CodingKeys: String, CodingKey {
        case version, tasks, lastActiveTaskID
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = (try? c.decodeIfPresent(Int.self, forKey: .version)) ?? TasksDocument.currentVersion
        // Список обязателен: без него это не наш файл, и его нужно считать битым.
        let lossy = try c.decode([Lossy<JugglerTask>].self, forKey: .tasks)
        tasks = lossy.compactMap(\.value)
        lastActiveTaskID = try? c.decodeIfPresent(UUID.self, forKey: .lastActiveTaskID)
        normalize()
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(tasks, forKey: .tasks)
        try c.encodeIfPresent(lastActiveTaskID, forKey: .lastActiveTaskID)
    }
}

/// Элемент массива, который не роняет разбор всего массива при ошибке.
private struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}
