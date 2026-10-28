import Foundation
import JugglerCore

// «Очистить все задачи» (D25): операция над документом, вопрос с правильной формой слова, тексты.

extension UIChecks {
    static func checkClearAll(_ c: CheckRunner) {
        c.group("clearAll") {
            var (doc, ids) = sample()
            doc.lastActiveTaskID = ids[1]
            doc.tasks[0].isDone = true
            c.expectEqual(TaskListOps.clearAll(&doc), 4, "возвращает число удалённых задач")
            c.expect(doc.tasks.isEmpty, "список пуст")
            c.expectNil(doc.lastActiveTaskID, "текущая задача снята")
            c.expectEqual(TaskListOps.clearAll(&doc), 0, "очистка пустого списка — 0")
            doc.normalize()
            c.expect(doc.tasks.isEmpty && doc.lastActiveTaskID == nil, "после normalize документ по-прежнему пуст")
            c.expectEqual(MenuFooterItem.items(canRestore: false, hasTasks: !doc.tasks.isEmpty), [.currentWindow, .settings, .quit],
                          "после очистки пункта «Очистить все задачи» нет")

            // Сохранение пустого списка в tasks.json.
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("juggler-clear-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: dir) }
            let url = dir.appendingPathComponent("tasks.json")
            var saved = sample().0
            saved.lastActiveTaskID = ids[2]
            TaskListOps.clearAll(&saved)
            do {
                try TaskStore(fileURL: url).save(saved)
                let loaded = TaskStore(fileURL: url).load().document
                c.expect(loaded.tasks.isEmpty && loaded.lastActiveTaskID == nil, "очистка сохранилась в tasks.json")
            } catch {
                c.expect(false, "не удалось сохранить: \(error)")
            }

            // Вопрос: форма слова по правилам русского (без таблицы перевода — запасной вариант).
            let q = TaskListPresenter.clearAllConfirmation
            c.expectEqual(q(1), "Удалить 1 задачу?", "1 задача")
            c.expectEqual(q(2), "Удалить все 2 задачи?", "2 задачи")
            c.expectEqual(q(4), "Удалить все 4 задачи?", "4 задачи")
            c.expectEqual(q(5), "Удалить все 5 задач?", "5 задач")
            c.expectEqual(q(11), "Удалить все 11 задач?", "11 задач")
            c.expectEqual(q(21), "Удалить 21 задачу?", "21 задачу")
            c.expectEqual(q(22), "Удалить все 22 задачи?", "22 задачи")
            c.expectEqual(q(100), "Удалить все 100 задач?", "100 задач")
            c.expectEqual(TaskToggleTexts.clearAllMenuTitle, "Очистить все задачи", "пункт меню")
            c.expectEqual(TaskListPresenter.clearAllWarning, "Задачи, заметки и привязки будут удалены. Это нельзя отменить.", "пояснение")
        }
    }
}
