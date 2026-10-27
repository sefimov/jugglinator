import AppKit
import Foundation
import JugglerCore
import ServiceManagement

/// Самопроверка UI: логика списка, сохранение через `AppModel` и перезапуск,
/// значки меню-бара, чтение статуса запуска при входе. Окон не показывает,
/// разрешений не запрашивает, запуск при входе не меняет.
@MainActor
enum UISelfTest {
    static func run() -> [SelfTestResult] {
        [listOperations(), persistenceAcrossRestart(), menuBarSymbols(), loginItemStatus()]
    }

    private static func listOperations() -> SelfTestResult {
        var doc = TasksDocument()
        let now = Date()
        let a = TaskListOps.add(&doc, title: "Первая", now: now)
        let b = TaskListOps.add(&doc, title: "", now: now)
        TaskListOps.rename(&doc, id: b, to: "Вторая")
        TaskListOps.move(&doc, id: b, by: -1)
        TaskListOps.toggleDone(&doc, id: a)
        doc.markVisited(b, at: now)
        let rows = TaskListPresenter.rows(for: doc, now: now)
        let ok = rows.map(\.title) == ["Вторая", "Первая"] && rows[0].isCurrent && rows[1].isDone
        return SelfTestResult("UI: операции со списком", passed: ok)
    }

    private static func persistenceAcrossRestart() -> SelfTestResult {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("juggler-ui-self-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = TaskStore(fileURL: dir.appendingPathComponent("tasks.json"))

        let first = AppModel(store: store)
        first.load()
        var ids: [UUID] = []
        first.update { doc in
            ids.append(TaskListOps.add(&doc, title: "Один", now: Date()))
            ids.append(TaskListOps.add(&doc, title: "Два", now: Date()))
        }
        first.update { doc in
            TaskListOps.setNote(&doc, id: ids[0], to: "дальше: ответить")
            TaskListOps.setDone(&doc, id: ids[1], true)
            TaskListOps.move(&doc, fromOffsets: IndexSet(integer: 1), toOffset: 0)
        }

        let second = AppModel(store: store)
        second.load()
        let tasks = second.tasks
        let ok = second.loadOutcome == .loaded
            && tasks.map(\.id) == [ids[1], ids[0]]
            && tasks.first?.isDone == true
            && tasks.last?.note == "дальше: ответить"
            && first.lastSaveError == nil
        return SelfTestResult("UI: изменения списка переживают перезапуск", passed: ok,
                              detail: ok ? "" : "получено \(tasks.map(\.title))")
    }

    private static func menuBarSymbols() -> SelfTestResult {
        let names = [1, 2, 9, 10, 50].compactMap { TaskListPresenter.menuBarSymbol(currentNumber: $0) }
            + [TaskListPresenter.menuBarEmptySymbol]
        let missing = names.filter { NSImage(systemSymbolName: $0, accessibilityDescription: nil) == nil }
        return SelfTestResult("UI: значки меню-бара есть в SF Symbols", passed: missing.isEmpty,
                              detail: missing.isEmpty ? "" : "нет: \(missing.joined(separator: ", "))")
    }

    private static func loginItemStatus() -> SelfTestResult {
        let state = LoginItemController.map(SMAppService.mainApp.status)
        return SelfTestResult("UI: статус запуска при входе читается", passed: true, detail: state.rawValue)
    }
}
