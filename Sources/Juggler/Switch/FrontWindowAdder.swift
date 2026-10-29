import AppKit
import Foundation
import JugglerCore

/// Adds the frontmost window as a new task without dialogs: ⌃§ pressed in a window that is not in the list.
/// The task goes to the end of the list and becomes current; windows are not switched.
@MainActor
enum FrontWindowAdder {
    static func add(_ binding: TaskBinding, title: String, model: AppModel, card: TransitionCardPresenting) {
        let now = model.clock()
        var id: UUID?
        model.update { id = BindPlanner.createTask(in: &$0, title: title, binding: binding, now: now) }
        guard let id, let number = model.document.number(of: id), let task = model.document.task(withID: id) else { return }
        switchLog.info("Переднее окно не в списке: добавлено задачей \(number)")
        (card as? TransitionMessagePresenting)?.showMessage(TaskToggleTexts.addedCard(number: number, title: task.title))
    }
}
