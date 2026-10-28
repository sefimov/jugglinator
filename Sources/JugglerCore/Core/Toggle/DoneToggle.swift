import Foundation

// ⌃⌥D «отметить сделанной / вернуть в работу» (D24): чистая логика.
//   - DoneToggle      — выбор задачи (точное совпадение переднего окна, иначе текущая) и переключение;
//   - DoneToggleTexts — тексты карточки и название действия в настройках хоткеев.

/// Итог нажатия ⌃⌥D.
public enum DoneToggleResult: Equatable, Sendable {
    /// Отметка переключена. `isDone` — новое значение.
    case changed(taskID: UUID, number: Int, title: String, isDone: Bool)
    /// Задач нет: ничего не менялось.
    case noTasks
    /// Задачи есть, но текущей нет (▸ не стоит) и переднее окно ни с одной не совпало: ничего не менялось.
    case noCurrentTask

    /// Менялась ли отметка (иначе — звук и карточка с пояснением).
    public var didChange: Bool {
        if case .changed = self { return true }
        return false
    }
}

public enum DoneToggle {
    /// Цель: задача, которой точно соответствует переднее окно (`ExactTaskMatcher`),
    /// иначе текущая задача (▸ в списке — последняя активная). `nil`, если нет ни той, ни другой.
    public static func target(document: TasksDocument, context: FrontmostContext) -> UUID? {
        if let exact = ExactTaskMatcher.match(context: context, document: document) { return exact }
        guard let current = document.lastActiveTaskID, document.index(of: current) != nil else { return nil }
        return current
    }

    /// Переключает отметку «сделано» у цели. Контекст читается только если задачи есть.
    /// Без задач и без цели документ не меняется.
    @discardableResult
    public static func toggle(_ document: inout TasksDocument, context: () -> FrontmostContext) -> DoneToggleResult {
        guard !document.tasks.isEmpty else { return .noTasks }
        guard let id = target(document: document, context: context()),
              let isDone = TaskListOps.toggleDone(&document, id: id),
              let number = document.number(of: id), let task = document.task(withID: id) else {
            return .noCurrentTask
        }
        return .changed(taskID: id, number: number, title: task.title, isDone: isDone)
    }
}

/// Тексты ⌃⌥D: карточка и настройки хоткеев.
public enum DoneToggleTexts {
    /// Название действия ⌃⌥D: настройки хоткеев, README.
    public static var actionTitle: String { loc("Отметить сделанной / вернуть в работу") }
    /// Карточка при пустом списке.
    public static var noTasksMessage: String { loc("Задач пока нет: добавьте задачу в меню Juggler") }
    /// Карточка, когда задачи есть, но текущая не выбрана.
    public static var noCurrentTaskMessage: String { loc("Текущей задачи нет: перейдите к одной из задач") }

    /// «Задача 2 «Название» сделана» / «Задача 2 «Название» вернулась в работу».
    public static func card(number: Int, title: String, isDone: Bool) -> String {
        let shown = TransitionCardBuilder.title(title)
        return isDone
            ? loc("Задача \(number) «\(shown)» сделана")
            : loc("Задача \(number) «\(shown)» вернулась в работу")
    }

    /// Текст карточки по итогу.
    public static func message(for result: DoneToggleResult) -> String {
        switch result {
        case .changed(_, let number, let title, let isDone): return card(number: number, title: title, isDone: isDone)
        case .noTasks: return noTasksMessage
        case .noCurrentTask: return noCurrentTaskMessage
        }
    }
}
