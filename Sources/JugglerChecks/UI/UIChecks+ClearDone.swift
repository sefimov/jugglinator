import Foundation
import JugglerCore

// "Delete done tasks": document operation, the menu item, the prompt with the correct word form, texts.

extension UIChecks {
    static func checkClearDone(_ c: CheckRunner) {
        c.group("clearDone") {
            var (doc, ids) = sample()
            doc.tasks[0].isDone = true
            doc.tasks[2].isDone = true
            doc.lastActiveTaskID = ids[1]
            c.expectEqual(TaskListOps.clearDone(&doc), 2, "возвращает число удалённых сделанных задач")
            c.expectEqual(titles(doc), ["B", "D"], "остались только несделанные, порядок сохранён")
            c.expectEqual(doc.lastActiveTaskID, ids[1], "текущая несделанная задача остаётся текущей")
            c.expectEqual(TaskListOps.clearDone(&doc), 0, "без сделанных — 0, список не меняется")
            c.expectEqual(titles(doc), ["B", "D"], "список не тронут")

            var (d2, ids2) = sample()
            d2.tasks[1].isDone = true
            d2.lastActiveTaskID = ids2[1]
            TaskListOps.clearDone(&d2)
            c.expectNil(d2.lastActiveTaskID, "текущая была сделанной — маркер снят")
            c.expectEqual(titles(d2), ["A", "C", "D"], "удалена только сделанная")

            var all = sample().0
            for i in all.tasks.indices { all.tasks[i].isDone = true }
            c.expectEqual(TaskListOps.clearDone(&all), 4, "все сделаны — удалены все")
            c.expect(all.tasks.isEmpty, "список пуст")

            c.expectEqual(MenuFooterItem.items(canRestore: false, hasTasks: true, hasDone: true),
                          [.currentWindow, .clearDone, .clearAll, .settings, .quit], "пункт перед «Очистить все задачи»")
            c.expectEqual(MenuFooterItem.items(canRestore: true, hasTasks: true, hasDone: true),
                          [.currentWindow, .restoreRemoved, .clearDone, .clearAll, .settings, .quit], "после «Вернуть удалённую»")
            c.expectEqual(MenuFooterItem.items(canRestore: false, hasTasks: true, hasDone: false),
                          [.currentWindow, .clearAll, .settings, .quit], "без сделанных пункта нет")
            c.expectEqual(MenuFooterItem.items(canRestore: false, hasTasks: true),
                          [.currentWindow, .clearAll, .settings, .quit], "по умолчанию hasDone = false")

            // The prompt: word form by Russian rules (no translation table: the fallback).
            let q = TaskListPresenter.clearDoneConfirmation
            c.expectEqual(q(1), "Удалить 1 сделанную задачу?", "1 задача")
            c.expectEqual(q(3), "Удалить 3 сделанные задачи?", "3 задачи")
            c.expectEqual(q(5), "Удалить 5 сделанных задач?", "5 задач")
            c.expectEqual(q(21), "Удалить 21 сделанную задачу?", "21 задачу")
            c.expectEqual(TaskToggleTexts.clearDoneMenuTitle, "Удалить сделанные задачи", "пункт меню")
        }
    }
}
