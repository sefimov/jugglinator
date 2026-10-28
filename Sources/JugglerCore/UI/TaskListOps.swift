import Foundation

/// Операции со списком задач для меню-бара (задача UI).
///
/// Чистые функции над `TasksDocument`; приложение вызывает их внутри
/// `model.update { TaskListOps.rename(&$0, id: id, to: title) }`.
/// Номер задачи — её позиция в списке, поэтому перестановка меняет номера
/// и порядок переключения по кругу.
public enum TaskListOps {
    /// Максимальная длина названия (в символах) после очистки.
    public static let maxTitleLength = 200

    /// Очистка названия: переводы строк и повторные пробелы схлопываются в один пробел,
    /// края обрезаются, слишком длинное название укорачивается.
    public static func cleanTitle(_ raw: String) -> String {
        let words = raw.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        let joined = words.joined(separator: " ")
        return joined.count > maxTitleLength ? String(joined.prefix(maxTitleLength)) : joined
    }

    /// Очистка заметки: обрезаются пробелы и пустые строки по краям, переносы внутри сохраняются.
    public static func cleanNote(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Название по умолчанию для новой задачи: «Задача N», где N — её будущий номер.
    public static func defaultTitle(for document: TasksDocument) -> String {
        String(localized: "Задача \(document.tasks.count + 1)")
    }

    // MARK: - Добавление, правка, удаление

    /// Добавляет задачу в конец списка. Пустое название заменяется на «Задача N».
    /// Возвращает id новой задачи.
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

    /// Переименовывает задачу. Пустое после очистки название не принимается.
    /// Возвращает `true`, если название изменилось.
    @discardableResult
    public static func rename(_ document: inout TasksDocument, id: UUID, to title: String) -> Bool {
        let cleaned = cleanTitle(title)
        guard !cleaned.isEmpty, let i = document.index(of: id), document.tasks[i].title != cleaned else {
            return false
        }
        document.tasks[i].title = cleaned
        return true
    }

    /// Меняет заметку «зачем / дальше». Пустая заметка допустима (очистка).
    @discardableResult
    public static func setNote(_ document: inout TasksDocument, id: UUID, to note: String) -> Bool {
        let cleaned = cleanNote(note)
        guard let i = document.index(of: id), document.tasks[i].note != cleaned else { return false }
        document.tasks[i].note = cleaned
        return true
    }

    /// Удаляет задачу. Если она была последней активной, отметка текущей снимается.
    @discardableResult
    public static func delete(_ document: inout TasksDocument, id: UUID) -> Bool {
        guard let i = document.index(of: id) else { return false }
        document.tasks.remove(at: i)
        if document.lastActiveTaskID == id {
            document.lastActiveTaskID = nil
        }
        return true
    }

    /// Удаляет все задачи и снимает отметку текущей. Возвращает, сколько задач было удалено.
    @discardableResult
    public static func clearAll(_ document: inout TasksDocument) -> Int {
        let count = document.tasks.count
        document.tasks.removeAll()
        document.lastActiveTaskID = nil
        return count
    }

    /// Ставит или снимает отметку «сделано».
    @discardableResult
    public static func setDone(_ document: inout TasksDocument, id: UUID, _ done: Bool) -> Bool {
        guard let i = document.index(of: id), document.tasks[i].isDone != done else { return false }
        document.tasks[i].isDone = done
        return true
    }

    /// Переключает отметку «сделано». Возвращает новое значение или `nil`, если задачи нет.
    @discardableResult
    public static func toggleDone(_ document: inout TasksDocument, id: UUID) -> Bool? {
        guard let i = document.index(of: id) else { return nil }
        document.tasks[i].isDone.toggle()
        return document.tasks[i].isDone
    }

    /// Снимает привязку: задача остаётся, но больше никуда не ведёт.
    @discardableResult
    public static func clearBinding(_ document: inout TasksDocument, id: UUID) -> Bool {
        guard let i = document.index(of: id), document.tasks[i].binding != nil else { return false }
        document.tasks[i].binding = nil
        return true
    }

    // MARK: - Порядок

    /// Перестановка в стиле SwiftUI `onMove`: элементы с позиций `offsets` ставятся
    /// перед элементом, который до перестановки стоял на позиции `destination`
    /// (`destination == count` — в конец). Неверные позиции игнорируются.
    /// Возвращает `true`, если порядок изменился.
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

    /// Сдвигает задачу на `delta` позиций (−1 — выше, +1 — ниже), не выходя за края списка.
    @discardableResult
    public static func move(_ document: inout TasksDocument, id: UUID, by delta: Int) -> Bool {
        guard let from = document.index(of: id), delta != 0 else { return false }
        let to = min(max(from + delta, 0), document.tasks.count - 1)
        guard to != from else { return false }
        let task = document.tasks.remove(at: from)
        document.tasks.insert(task, at: to)
        return true
    }

    /// Ставит задачу перед задачей `targetID` (перетаскивание на строку);
    /// `nil` или неизвестный `targetID` — в конец списка.
    @discardableResult
    public static func move(_ document: inout TasksDocument, id: UUID, before targetID: UUID?) -> Bool {
        guard let from = document.index(of: id) else { return false }
        let destination = targetID.flatMap { document.index(of: $0) } ?? document.tasks.count
        return move(&document, fromOffsets: IndexSet(integer: from), toOffset: destination)
    }
}
