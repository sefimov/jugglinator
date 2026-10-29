import Foundation

// ⌃§ "mark done / back to work" (D24): pure logic.
//   - DoneToggle      — toggles the mark on the frontmost window's task (`SwitchPlanner.frontWindow`);
//                       a window that is not a task is added instead, never the last active task toggled;
//   - DoneToggleTexts — card texts and the action name in hotkey settings.

/// The "done" mark was toggled. `isDone` is the new value.
public struct DoneToggleResult: Equatable, Sendable {
    public let taskID: UUID
    public let number: Int
    public let title: String
    public let isDone: Bool

    public init(taskID: UUID, number: Int, title: String, isDone: Bool) {
        self.taskID = taskID
        self.number = number
        self.title = title
        self.isDone = isDone
    }
}

public enum DoneToggle {
    /// Toggles the "done" mark on task `id` (the frontmost window's task); `nil` if there is no such task.
    @discardableResult
    public static func toggle(_ document: inout TasksDocument, id: UUID) -> DoneToggleResult? {
        guard let isDone = TaskListOps.toggleDone(&document, id: id),
              let number = document.number(of: id), let task = document.task(withID: id) else { return nil }
        return DoneToggleResult(taskID: id, number: number, title: task.title, isDone: isDone)
    }
}

/// ⌃§ texts: card and hotkey settings.
public enum DoneToggleTexts {
    /// Name of the ⌃§ action: hotkey settings, README.
    public static var actionTitle: String { loc("Отметить сделанной / вернуть в работу") }
    /// Card when the frontmost window is not a task and cannot be added (desktop, window without a title).
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
        card(number: result.number, title: result.title, isDone: result.isDone)
    }
}
