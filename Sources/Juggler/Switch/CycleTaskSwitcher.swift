import AppKit
import Foundation
import JugglerCore

/// Task switcher. Picking the neighboring task and the card texts live in JugglerCore
/// (`SwitchPlanner`, `TransitionCardBuilder`); this only wires them to BIND and the card.
@MainActor
final class CycleTaskSwitcher: TaskSwitching {
    private let model: AppModel
    private let bind: BindServices
    private let card: TransitionCardPresenting
    private let bindHotkey: () -> Hotkey?
    private let beep: () -> Void

    init(
        model: AppModel, bind: BindServices, card: TransitionCardPresenting,
        bindHotkey: @escaping () -> Hotkey?, beep: @escaping () -> Void = { NSSound.beep() }
    ) {
        self.model = model
        self.bind = bind
        self.card = card
        self.bindHotkey = bindHotkey
        self.beep = beep
    }

    func switchTask(_ direction: CycleDirection) {
        // Context is read at key-press time: the current task comes from the front window or tab.
        let context = bind.contextProvider.currentContext()
        guard let target = SwitchPlanner.target(direction: direction, context: context, document: model.document) else {
            beep()
            let text = model.tasks.isEmpty
                ? loc("Задач пока нет: добавьте задачу в меню Juggler")
                : loc("Все задачи отмечены «сделано»")
            (card as? TransitionMessagePresenting)?.showMessage(text)
            return
        }
        activateTask(id: target)
    }

    func activateTask(id: UUID) {
        activate(id: id)
    }

    /// `activateTask` that also reports how the binding opened (for the MCP server);
    /// `nil` for a task without a binding or an unknown id.
    @discardableResult
    func activate(id: UUID) -> ActivationResult? {
        guard let task = model.document.task(withID: id) else { return nil }
        // "away N min" — as of the switch, before the visit time is updated.
        let now = model.clock()
        let activation = task.binding.map { bind.activator.activate($0) }
        if let activation, !activation.succeeded {
            switchLog.info("Активация не удалась: \(String(describing: activation), privacy: .public)")
        }
        if let content = TransitionCardBuilder.content(
            for: id, in: model.document, now: now, bindHotkey: bindHotkey(), activation: activation) {
            card.show(content)
        }
        model.markVisited(id)
        return activation
    }
}
