import AppKit
import Foundation
import JugglerCore

/// Переключатель задач. Выбор соседней задачи и тексты карточки — в JugglerCore
/// (`SwitchPlanner`, `TransitionCardBuilder`); здесь только связка с BIND и карточкой.
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
        // Контекст читается в момент нажатия: текущая задача — по переднему окну или вкладке.
        let context = bind.contextProvider.currentContext()
        guard let target = SwitchPlanner.target(direction: direction, context: context, document: model.document) else {
            beep()
            let text = model.tasks.isEmpty
                ? "Задач пока нет: добавьте задачу в меню Juggler"
                : "Все задачи отмечены «сделано»"
            (card as? TransitionMessagePresenting)?.showMessage(text)
            return
        }
        activateTask(id: target)
    }

    func activateTask(id: UUID) {
        guard let task = model.document.task(withID: id) else { return }
        // «не был N мин» — на момент перехода, до обновления времени захода.
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
    }
}
