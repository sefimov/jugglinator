import Foundation
import JugglerCore

/// Shared task list state. The sole owner of `TasksDocument`:
/// all changes go through `update`, after which the document is saved to disk.
///
/// Keep operation logic (add, rename, reorder…) as pure
/// functions over `TasksDocument` in JugglerCore, and only call them here:
/// `model.update { TaskListOps.rename(&$0, id: id, to: title) }`.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var document: TasksDocument
    /// Result of the last load: the UI can report recovery of a corrupted file.
    @Published private(set) var loadOutcome: TaskStore.LoadOutcome?
    /// Text of the last write error (localized) or `nil`.
    @Published private(set) var lastSaveError: String?

    let store: TaskStore
    let clock: () -> Date

    init(store: TaskStore, clock: @escaping () -> Date = Date.init) {
        self.store = store
        self.clock = clock
        self.document = TasksDocument()
    }

    var tasks: [JugglerTask] { document.tasks }

    /// The last active task — the menu bar icon shows its number.
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

    /// Modify the document and save it if it actually changed.
    func update(_ mutate: (inout TasksDocument) -> Void) {
        var copy = document
        mutate(&copy)
        copy.normalize()
        guard copy != document else { return }
        document = copy
        save()
    }

    /// Mark a visit to the task "now".
    func markVisited(_ id: UUID) {
        let now = clock()
        update { $0.markVisited(id, at: now) }
    }

    // MARK: - Removal with undo (D15)

    /// The last removed task (in memory only, until Jugglinator quits):
    /// restored by the "Restore removed task" menu item, and within the undo window also by ⌃⌥⇥.
    @Published private(set) var lastRemoved: RemovedTask?

    /// Remove a task (the removal is saved to tasks.json immediately) and remember it for restoring.
    /// `undoableByToggle` — removed by the ⌃⌥⇥ toggle; repeating the hotkey within 5 s restores it.
    @discardableResult
    func removeTask(_ id: UUID, undoableByToggle: Bool) -> RemovedTask? {
        let now = clock()
        var removed: RemovedTask?
        update { removed = TaskRemoval.remove(&$0, id: id, now: now, undoableByToggle: undoableByToggle) }
        if let removed { lastRemoved = removed }
        return removed
    }

    /// Restore the last removed task to its previous position. `nil` if there is nothing to restore.
    @discardableResult
    func restoreLastRemoved() -> RemovedTask? {
        guard let removed = lastRemoved else { return nil }
        lastRemoved = nil
        var restored = false
        update { restored = TaskRemoval.restore(removed, into: &$0) }
        return restored ? removed : nil
    }

    /// Remove all tasks and clear the current one (saved immediately). Cleared tasks can't be restored:
    /// `lastRemoved` is reset so that "Restore removed task" doesn't bring back a task from the clear.
    @discardableResult
    func clearAllTasks() -> Int {
        var count = 0
        update { count = TaskListOps.clearAll(&$0) }
        lastRemoved = nil
        return count
    }

    /// Remove every task marked "done" (saved immediately). Like a clear, this can't be undone;
    /// a task removed earlier stays restorable via "Restore removed task".
    @discardableResult
    func clearDoneTasks() -> Int {
        var count = 0
        update { count = TaskListOps.clearDone(&$0) }
        return count
    }

    private func save() {
        do {
            try store.save(document)
            lastSaveError = nil
        } catch {
            lastSaveError = loc("Не удалось сохранить задачи: \(error.localizedDescription)")
            JugglerLog.app.error("Ошибка записи tasks.json: \(error.localizedDescription, privacy: .public)")
        }
    }
}
