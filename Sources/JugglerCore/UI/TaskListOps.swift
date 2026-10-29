import Foundation

/// Task list operations for the menu bar (UI task).
///
/// Pure functions over `TasksDocument`; the app calls them inside
/// `model.update { TaskListOps.rename(&$0, id: id, to: title) }`.
/// A task's number is its position in the list, so reordering changes the numbers
/// and the cycling order.
public enum TaskListOps {
    /// Maximum title length (in characters) after cleaning.
    public static let maxTitleLength = 200

    /// Title cleaning: newlines and repeated spaces collapse into a single space,
    /// edges are trimmed, a title that is too long is shortened.
    public static func cleanTitle(_ raw: String) -> String {
        let words = raw.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        let joined = words.joined(separator: " ")
        return joined.count > maxTitleLength ? String(joined.prefix(maxTitleLength)) : joined
    }

    /// Note cleaning: whitespace and blank lines at the edges are trimmed, inner line breaks are kept.
    public static func cleanNote(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Default title for a new task: "Task N", where N is its future number.
    public static func defaultTitle(for document: TasksDocument) -> String {
        loc("Задача \(document.tasks.count + 1)")
    }

    // MARK: - Add, edit, delete

    /// Adds a task to the end of the list. An empty title is replaced with "Task N".
    /// Returns the new task's id.
    @discardableResult
    public static func add(
        _ document: inout TasksDocument,
        title: String,
        note: String = "",
        binding: TaskBinding? = nil,
        now: Date
    ) -> UUID {
        let cleaned = cleanTitle(title)
        let task = JugglerTask(
            title: cleaned.isEmpty ? defaultTitle(for: document) : cleaned,
            note: cleanNote(note),
            createdAt: now,
            binding: binding)
        document.tasks.append(task)
        return task.id
    }

    /// Renames a task. A title that is empty after cleaning is rejected.
    /// Returns `true` if the title changed.
    @discardableResult
    public static func rename(_ document: inout TasksDocument, id: UUID, to title: String) -> Bool {
        let cleaned = cleanTitle(title)
        guard !cleaned.isEmpty, let i = document.index(of: id), document.tasks[i].title != cleaned else {
            return false
        }
        document.tasks[i].title = cleaned
        return true
    }

    /// Changes the "why / next" note. An empty note is allowed (clearing).
    @discardableResult
    public static func setNote(_ document: inout TasksDocument, id: UUID, to note: String) -> Bool {
        let cleaned = cleanNote(note)
        guard let i = document.index(of: id), document.tasks[i].note != cleaned else { return false }
        document.tasks[i].note = cleaned
        return true
    }

    /// Deletes a task. If it was the last active one, the current marker is cleared.
    @discardableResult
    public static func delete(_ document: inout TasksDocument, id: UUID) -> Bool {
        guard let i = document.index(of: id) else { return false }
        document.tasks.remove(at: i)
        if document.lastActiveTaskID == id {
            document.lastActiveTaskID = nil
        }
        return true
    }

    /// Deletes all tasks and clears the current marker. Returns how many tasks were deleted.
    @discardableResult
    public static func clearAll(_ document: inout TasksDocument) -> Int {
        let count = document.tasks.count
        document.tasks.removeAll()
        document.lastActiveTaskID = nil
        return count
    }

    /// Deletes every task marked "done". The current marker is cleared if it pointed at one of them.
    /// Returns how many tasks were deleted.
    @discardableResult
    public static func clearDone(_ document: inout TasksDocument) -> Int {
        let before = document.tasks.count
        document.tasks.removeAll(where: \.isDone)
        if let active = document.lastActiveTaskID, document.index(of: active) == nil {
            document.lastActiveTaskID = nil
        }
        return before - document.tasks.count
    }

    /// Sets or clears the "done" mark.
    @discardableResult
    public static func setDone(_ document: inout TasksDocument, id: UUID, _ done: Bool) -> Bool {
        guard let i = document.index(of: id), document.tasks[i].isDone != done else { return false }
        document.tasks[i].isDone = done
        return true
    }

    /// Toggles the "done" mark. Returns the new value, or `nil` if there is no such task.
    @discardableResult
    public static func toggleDone(_ document: inout TasksDocument, id: UUID) -> Bool? {
        guard let i = document.index(of: id) else { return nil }
        document.tasks[i].isDone.toggle()
        return document.tasks[i].isDone
    }

    /// Removes the binding: the task stays but no longer leads anywhere.
    @discardableResult
    public static func clearBinding(_ document: inout TasksDocument, id: UUID) -> Bool {
        guard let i = document.index(of: id), document.tasks[i].binding != nil else { return false }
        document.tasks[i].binding = nil
        return true
    }

    // MARK: - Order

    /// SwiftUI `onMove`-style reordering: elements at `offsets` are placed
    /// before the element that was at position `destination` before the move
    /// (`destination == count` — at the end). Invalid positions are ignored.
    /// Returns `true` if the order changed.
    @discardableResult
    public static func move(_ document: inout TasksDocument, fromOffsets offsets: IndexSet, toOffset destination: Int) -> Bool {
        let count = document.tasks.count
        let valid = offsets.filter { $0 >= 0 && $0 < count }.sorted()
        guard !valid.isEmpty else { return false }
        let target = min(max(destination, 0), count)
        let validSet = Set(valid)
        let moving = valid.map { document.tasks[$0] }
        var remaining = document.tasks.enumerated().filter { !validSet.contains($0.offset) }.map(\.element)
        let insertAt = target - valid.filter { $0 < target }.count
        remaining.insert(contentsOf: moving, at: insertAt)
        guard remaining != document.tasks else { return false }
        document.tasks = remaining
        return true
    }

    /// Moves a task by `delta` positions (−1 — up, +1 — down), staying within the list bounds.
    @discardableResult
    public static func move(_ document: inout TasksDocument, id: UUID, by delta: Int) -> Bool {
        guard let from = document.index(of: id), delta != 0 else { return false }
        let to = min(max(from + delta, 0), document.tasks.count - 1)
        guard to != from else { return false }
        let task = document.tasks.remove(at: from)
        document.tasks.insert(task, at: to)
        return true
    }

    /// Places a task before task `targetID` (dragging onto a row);
    /// `nil` or an unknown `targetID` — at the end of the list.
    @discardableResult
    public static func move(_ document: inout TasksDocument, id: UUID, before targetID: UUID?) -> Bool {
        guard let from = document.index(of: id) else { return false }
        let destination = targetID.flatMap { document.index(of: $0) } ?? document.tasks.count
        return move(&document, fromOffsets: IndexSet(integer: from), toOffset: destination)
    }
}
