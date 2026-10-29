import Foundation

// ⌃§ "mark done / back to work" (D24): pure logic.
//   - DoneToggle      — picks the task (exact match of the frontmost window, otherwise the current one) and toggles;
//   - DoneToggleTexts — card texts and the action name in hotkey settings.

/// Outcome of pressing ⌃§.
public enum DoneToggleResult: Equatable, Sendable {
    /// The mark was toggled. `isDone` is the new value.
    case changed(taskID: UUID, number: Int, title: String, isDone: Bool)
    /// No tasks: nothing changed.
    case noTasks
    /// There are tasks, but no current one (no ▸) and the frontmost window matched none: nothing changed.
    case noCurrentTask

    /// Whether the mark changed (otherwise — a sound and a card with an explanation).
    public var didChange: Bool {
        if case .changed = self { return true }
        return false
    }
}

public enum DoneToggle {
    /// Target: the task the frontmost window exactly matches (`ExactTaskMatcher`),
    /// otherwise the current task (▸ in the list — the last active one). `nil` if there is neither.
    public static func target(document: TasksDocument, context: FrontmostContext) -> UUID? {
        if let exact = ExactTaskMatcher.match(context: context, document: document) { return exact }
        guard let current = document.lastActiveTaskID, document.index(of: current) != nil else { return nil }
        return current
    }

    /// Toggles the "done" mark on the target. The context is read only if there are tasks.
    /// Without tasks and without a target the document is not changed.
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

/// ⌃§ texts: card and hotkey settings.
public enum DoneToggleTexts {
    /// Name of the ⌃§ action: hotkey settings, README.
    public static var actionTitle: String { loc("Отметить сделанной / вернуть в работу") }
    /// Card for an empty list.
    public static var noTasksMessage: String { loc("Задач пока нет: добавьте задачу в меню Juggler") }
    /// Card when there are tasks but no current one is selected.
    public static var noCurrentTaskMessage: String { loc("Текущей задачи нет: перейдите к одной из задач") }

    /// "Task 2 "Title" done" / "Task 2 "Title" back to work".
    public static func card(number: Int, title: String, isDone: Bool) -> String {
        let shown = TransitionCardBuilder.title(title)
        return isDone
            ? loc("Задача \(number) «\(shown)» сделана")
            : loc("Задача \(number) «\(shown)» вернулась в работу")
    }

    /// Card text for the outcome.
    public static func message(for result: DoneToggleResult) -> String {
        switch result {
        case .changed(_, let number, let title, let isDone): return card(number: number, title: title, isDone: isDone)
        case .noTasks: return noTasksMessage
        case .noCurrentTask: return noCurrentTaskMessage
        }
    }
}
