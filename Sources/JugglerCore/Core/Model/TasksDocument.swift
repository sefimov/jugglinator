import Foundation

/// Contents of `tasks.json`: an ordered task list and the last active task.
public struct TasksDocument: Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    /// List order defines the numbers (1, 2, 3…) and the cycling order.
    public var tasks: [JugglerTask]
    /// The most recently activated task. The menu bar icon shows its number;
    /// it is also the fallback when the task cannot be determined from the frontmost window.
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

    /// Task number for display (1-based position in the list).
    public func number(of id: UUID) -> Int? {
        index(of: id).map { $0 + 1 }
    }

    public var lastActiveTask: JugglerTask? {
        lastActiveTaskID.flatMap { task(withID: $0) }
    }

    /// Records a visit to a task: updates the time and the last active task.
    /// Returns `false` if there is no task with this id.
    @discardableResult
    public mutating func markVisited(_ id: UUID, at date: Date) -> Bool {
        guard let i = index(of: id) else { return false }
        tasks[i].lastVisitedAt = date
        lastActiveTaskID = id
        return true
    }

    /// Brings the document to a consistent state: removes duplicate ids
    /// (the first one stays) and a dangling reference to the last active task.
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
        // The list is required: without it this is not our file and must be treated as broken.
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

/// An array element that does not fail decoding of the whole array on error.
private struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}
