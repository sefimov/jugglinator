import AppKit
import Foundation
import JugglerCore
import SwiftUI
import os

// Папка Sources/Juggler/Switch/ принадлежит задаче SWITCH.
// Сигнатуры функций `SwitchModule` — контракт с корнем композиции (App/CompositionRoot.swift),
// UI (раздел хоткеев в настройках) и самопроверкой (App/SelfTest.swift).
// Тела и типы ниже — простые реализации по умолчанию, которые SWITCH заменяет.

@MainActor
enum SwitchModule {
    static func makeCardPresenter() -> TransitionCardPresenting {
        LoggingCardPresenter()
    }

    static func makeSwitcher(model: AppModel, bind: BindServices, card: TransitionCardPresenting) -> TaskSwitching {
        BasicTaskSwitcher(model: model, bind: bind, card: card)
    }

    static func makeHotkeys() -> HotkeyRegistering {
        NoopHotkeys()
    }

    /// Раздел хоткеев для окна настроек (UI встраивает его как есть).
    static func hotkeySettingsView(environment: AppEnvironment) -> AnyView {
        AnyView(Text("Настройка хоткеев появится позже").foregroundStyle(.secondary))
    }

    static func selfTest() -> [SelfTestResult] {
        []
    }
}

private let log = Logger(subsystem: JugglerLog.subsystem, category: "switch")

/// Переключатель по умолчанию: вся логика выбора — в JugglerCore.
private final class BasicTaskSwitcher: TaskSwitching {
    private let model: AppModel
    private let bind: BindServices
    private let card: TransitionCardPresenting

    init(model: AppModel, bind: BindServices, card: TransitionCardPresenting) {
        self.model = model
        self.bind = bind
        self.card = card
    }

    func switchTask(_ direction: CycleDirection) {
        let tasks = model.tasks
        let context = bind.contextProvider.currentContext()
        let current = CurrentTaskResolver.resolve(context: context, tasks: tasks, fallbackID: model.document.lastActiveTaskID)
        guard let target = TaskCycler.neighbor(of: current, in: tasks, direction: direction) else {
            NSSound.beep()
            return
        }
        activateTask(id: target.id)
    }

    func activateTask(id: UUID) {
        guard let task = model.document.task(withID: id), let number = model.document.number(of: id) else { return }
        let now = model.clock()
        card.show(TransitionCardContent(
            number: number,
            title: task.title,
            note: task.note,
            absenceText: Staleness.absenceText(lastVisited: task.lastVisitedAt, now: now),
            staleness: Staleness.level(lastVisited: task.lastVisitedAt, now: now),
            source: task.binding?.source,
            hint: task.binding == nil ? "Нет привязки: откройте чат и нажмите ⌃⌥§" : nil))
        if let binding = task.binding {
            let result = bind.activator.activate(binding)
            if !result.succeeded { log.info("Активация не удалась: \(String(describing: result), privacy: .public)") }
        }
        model.markVisited(id)
    }
}

/// Карточка по умолчанию: только запись в журнал.
private final class LoggingCardPresenter: TransitionCardPresenting {
    func show(_ content: TransitionCardContent) {
        log.info("Карточка: \(content.number, privacy: .public). \(content.title, privacy: .public)")
    }
}

private final class NoopHotkeys: HotkeyRegistering {
    func start(handler: @escaping (HotkeyAction) -> Void) {}
    func stop() {}
}
