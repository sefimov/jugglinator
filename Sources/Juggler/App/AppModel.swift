import Foundation
import JugglerCore

/// Общее состояние списка задач. Единственный владелец `TasksDocument`:
/// все изменения идут через `update`, после которого документ сохраняется на диск.
///
/// Логику операций (добавить, переименовать, переставить…) держите чистыми
/// функциями над `TasksDocument` в JugglerCore, а здесь только вызывайте их:
/// `model.update { TaskListOps.rename(&$0, id: id, to: title) }`.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var document: TasksDocument
    /// Итог последней загрузки: UI может сообщить о восстановлении битого файла.
    @Published private(set) var loadOutcome: TaskStore.LoadOutcome?
    /// Текст последней ошибки записи (на русском) или `nil`.
    @Published private(set) var lastSaveError: String?

    let store: TaskStore
    let clock: () -> Date

    init(store: TaskStore, clock: @escaping () -> Date = Date.init) {
        self.store = store
        self.clock = clock
        self.document = TasksDocument()
    }

    var tasks: [JugglerTask] { document.tasks }

    /// Последняя активная задача — её номер показывает иконка меню-бара.
    var currentTask: JugglerTask? { document.lastActiveTask }

    var currentTaskNumber: Int? {
        document.lastActiveTaskID.flatMap { document.number(of: $0) }
    }

    func load() {
        let result = store.load()
        document = result.document
        loadOutcome = result.outcome
        if result.outcome.isRecovery {
            JugglerLog.app.error("tasks.json восстановлен: \(String(describing: result.outcome), privacy: .public)")
        }
    }

    /// Изменить документ и сохранить его, если он действительно изменился.
    func update(_ mutate: (inout TasksDocument) -> Void) {
        var copy = document
        mutate(&copy)
        copy.normalize()
        guard copy != document else { return }
        document = copy
        save()
    }

    /// Отметить заход в задачу «сейчас».
    func markVisited(_ id: UUID) {
        let now = clock()
        update { $0.markVisited(id, at: now) }
    }

    // MARK: - Удаление с возвратом (D15)

    /// Последняя удалённая задача (только в памяти, до выхода из Juggler):
    /// её возвращает пункт меню «Вернуть удалённую задачу», а в окне отмены — и ⌃⌥§.
    @Published private(set) var lastRemoved: RemovedTask?

    /// Удалить задачу (удаление сразу сохраняется в tasks.json) и запомнить её для возврата.
    /// `undoableByToggle` — удалено переключателем ⌃⌥§, повтор хоткея в течение 5 с вернёт.
    @discardableResult
    func removeTask(_ id: UUID, undoableByToggle: Bool) -> RemovedTask? {
        let now = clock()
        var removed: RemovedTask?
        update { removed = TaskRemoval.remove(&$0, id: id, now: now, undoableByToggle: undoableByToggle) }
        if let removed { lastRemoved = removed }
        return removed
    }

    /// Вернуть последнюю удалённую задачу на прежнее место. `nil`, если возвращать нечего.
    @discardableResult
    func restoreLastRemoved() -> RemovedTask? {
        guard let removed = lastRemoved else { return nil }
        lastRemoved = nil
        var restored = false
        update { restored = TaskRemoval.restore(removed, into: &$0) }
        return restored ? removed : nil
    }

    /// Удалить все задачи и снять текущую (сохраняется сразу). Возврата очищенных задач нет:
    /// `lastRemoved` сбрасывается, чтобы «Вернуть удалённую задачу» не вернула задачу из очистки.
    @discardableResult
    func clearAllTasks() -> Int {
        var count = 0
        update { count = TaskListOps.clearAll(&$0) }
        lastRemoved = nil
        return count
    }

    private func save() {
        do {
            try store.save(document)
            lastSaveError = nil
        } catch {
            lastSaveError = String(localized: "Не удалось сохранить задачи: \(error.localizedDescription)")
            JugglerLog.app.error("Ошибка записи tasks.json: \(error.localizedDescription, privacy: .public)")
        }
    }
}
