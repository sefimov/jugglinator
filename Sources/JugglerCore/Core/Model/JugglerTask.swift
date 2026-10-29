import Foundation

/// A task is a row of the list. The task number is not stored: it is the position in the list (1-based).
///
/// Named `JugglerTask`, not `Task`, to avoid confusion with `Swift.Task`.
public struct JugglerTask: Identifiable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    /// The "why / next" note.
    public var note: String
    /// The "done" mark: such tasks are skipped when switching.
    public var isDone: Bool
    /// Time of the last visit (task activation).
    public var lastVisitedAt: Date?
    public var createdAt: Date
    /// Optional binding to a chat, tab or window.
    public var binding: TaskBinding?

    public init(
        id: UUID = UUID(),
        title: String,
        note: String = "",
        isDone: Bool = false,
        lastVisitedAt: Date? = nil,
        createdAt: Date = Date(),
        binding: TaskBinding? = nil
    ) {
        self.id = id
        self.title = title
        self.note = note
        self.isDone = isDone
        self.lastVisitedAt = lastVisitedAt
        self.createdAt = createdAt
        self.binding = binding
    }
}

extension JugglerTask: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, title, note, isDone, lastVisitedAt, createdAt, binding
    }

    /// Lenient decoding: missing fields get default values,
    /// and an unrecognized binding becomes "no binding" instead of failing the whole file.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        note = (try? c.decodeIfPresent(String.self, forKey: .note)) ?? ""
        isDone = (try? c.decodeIfPresent(Bool.self, forKey: .isDone)) ?? false
        lastVisitedAt = try? c.decodeIfPresent(Date.self, forKey: .lastVisitedAt)
        createdAt = (try? c.decodeIfPresent(Date.self, forKey: .createdAt)) ?? Date()
        binding = try? c.decodeIfPresent(TaskBinding.self, forKey: .binding)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(note, forKey: .note)
        try c.encode(isDone, forKey: .isDone)
        try c.encodeIfPresent(lastVisitedAt, forKey: .lastVisitedAt)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(binding, forKey: .binding)
    }
}
