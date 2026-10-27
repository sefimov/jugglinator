import Foundation
import JugglerCore

extension UIChecks {
    static func checkTitles(_ c: CheckRunner) {
        c.group("cleanTitle / cleanNote") {
            c.expectEqual(TaskListOps.cleanTitle("  Ревью  PR  "), "Ревью PR", "края и двойные пробелы")
            c.expectEqual(TaskListOps.cleanTitle("Первая\nвторая\tтретья"), "Первая вторая третья", "переводы строк и табы → пробел")
            c.expectEqual(TaskListOps.cleanTitle(" \n\t "), "", "только пробелы → пусто")
            let long = String(repeating: "я", count: 500)
            c.expectEqual(TaskListOps.cleanTitle(long).count, TaskListOps.maxTitleLength, "длинное название укорачивается")
            c.expectEqual(TaskListOps.cleanNote("\n  зачем: x\n  дальше: y  \n\n"), "зачем: x\n  дальше: y", "заметка: края обрезаны, переносы внутри сохранены")
        }
    }

    static func checkAdd(_ c: CheckRunner) {
        c.group("add") {
            var doc = TasksDocument()
            let first = TaskListOps.add(&doc, title: "  Статья  ", note: " план ", now: t0)
            c.expectEqual(doc.tasks.count, 1, "задача добавлена")
            c.expectEqual(doc.tasks[0].id, first, "возвращён id новой задачи")
            c.expectEqual(doc.tasks[0].title, "Статья", "название очищено")
            c.expectEqual(doc.tasks[0].note, "план", "заметка очищена")
            c.expectEqual(doc.tasks[0].createdAt, t0, "время создания из параметра")
            c.expectNil(doc.tasks[0].binding, "новая задача без привязки")
            c.expect(!doc.tasks[0].isDone, "новая задача не сделана")
            c.expectNil(doc.tasks[0].lastVisitedAt, "у новой задачи нет захода")

            TaskListOps.add(&doc, title: "   ", now: t0)
            c.expectEqual(doc.tasks[1].title, "Задача 2", "пустое название → «Задача N» по номеру")
            TaskListOps.add(&doc, title: "Третья", now: t0)
            c.expectEqual(titles(doc), ["Статья", "Задача 2", "Третья"], "добавление в конец списка")
            c.expectNil(doc.lastActiveTaskID, "добавление не меняет текущую задачу")

            let binding = TaskBinding.claudeChat(ClaudeChatRef(conversationID: "ABC", title: "Чат"))
            let bound = TaskListOps.add(&doc, title: "С привязкой", binding: binding, now: t0)
            c.expectEqual(doc.task(withID: bound)?.binding, binding, "привязка сохраняется при добавлении")
        }
    }

    static func checkEdit(_ c: CheckRunner) {
        c.group("rename / setNote") {
            var (doc, ids) = sample()
            c.expect(TaskListOps.rename(&doc, id: ids[1], to: " Бэ  новое "), "переименование возвращает true")
            c.expectEqual(doc.tasks[1].title, "Бэ новое", "название очищено при переименовании")
            c.expect(!TaskListOps.rename(&doc, id: ids[1], to: "Бэ новое"), "то же название → false")
            c.expect(!TaskListOps.rename(&doc, id: ids[1], to: "  \n "), "пустое название не принимается")
            c.expectEqual(doc.tasks[1].title, "Бэ новое", "после пустого название не изменилось")
            c.expect(!TaskListOps.rename(&doc, id: UUID(), to: "X"), "неизвестный id → false")

            c.expect(TaskListOps.setNote(&doc, id: ids[0], to: " дальше: ответить "), "заметка задана")
            c.expectEqual(doc.tasks[0].note, "дальше: ответить", "заметка очищена")
            c.expect(TaskListOps.setNote(&doc, id: ids[0], to: "   "), "заметку можно стереть")
            c.expectEqual(doc.tasks[0].note, "", "заметка пустая")
            c.expect(!TaskListOps.setNote(&doc, id: ids[0], to: ""), "та же заметка → false")
            c.expect(!TaskListOps.setNote(&doc, id: UUID(), to: "x"), "заметка неизвестной задачи → false")
        }
    }

    static func checkDelete(_ c: CheckRunner) {
        c.group("delete") {
            var (doc, ids) = sample()
            doc.lastActiveTaskID = ids[2]
            c.expect(TaskListOps.delete(&doc, id: ids[0]), "удаление возвращает true")
            c.expectEqual(titles(doc), ["B", "C", "D"], "задача удалена, порядок остальных сохранён")
            c.expectEqual(doc.number(of: ids[2]), 2, "номера сдвинулись")
            c.expectEqual(doc.lastActiveTaskID, ids[2], "текущая задача не тронута при удалении другой")
            c.expect(TaskListOps.delete(&doc, id: ids[2]), "удаление текущей")
            c.expectNil(doc.lastActiveTaskID, "удаление текущей снимает отметку")
            c.expect(!TaskListOps.delete(&doc, id: ids[2]), "повторное удаление → false")
            c.expectEqual(titles(doc), ["B", "D"], "остались B и D")
        }
    }

    static func checkDone(_ c: CheckRunner) {
        c.group("сделано и привязка") {
            var (doc, ids) = sample()
            c.expect(TaskListOps.setDone(&doc, id: ids[1], true), "отметка «сделано»")
            c.expect(doc.tasks[1].isDone, "задача сделана")
            c.expect(!TaskListOps.setDone(&doc, id: ids[1], true), "повторная отметка → false")
            c.expectEqual(TaskListOps.toggleDone(&doc, id: ids[1]), false, "переключение возвращает в работу")
            c.expect(!doc.tasks[1].isDone, "задача снова в работе")
            c.expectEqual(TaskListOps.toggleDone(&doc, id: ids[1]), true, "переключение снова ставит «сделано»")
            c.expectNil(TaskListOps.toggleDone(&doc, id: UUID()), "переключение неизвестной → nil")
            let next = TaskCycler.neighbor(of: ids[0], in: doc.tasks, direction: .next)
            c.expectEqual(next?.id, ids[2], "сделанная задача пропускается при переключении")

            doc.tasks[3].binding = .appWindow(AppWindowRef(bundleID: "com.example", windowTitle: "Окно"))
            c.expect(TaskListOps.clearBinding(&doc, id: ids[3]), "привязка снята")
            c.expectNil(doc.tasks[3].binding, "привязки больше нет")
            c.expect(!TaskListOps.clearBinding(&doc, id: ids[3]), "снять отсутствующую привязку → false")
        }
    }

    static func checkMoveOffsets(_ c: CheckRunner) {
        c.group("move(fromOffsets:toOffset:) как SwiftUI onMove") {
            func moved(_ offsets: [Int], _ to: Int) -> [String] {
                var (doc, _) = sample()
                TaskListOps.move(&doc, fromOffsets: IndexSet(offsets), toOffset: to)
                return titles(doc)
            }
            c.expectEqual(moved([0], 2), ["B", "A", "C", "D"], "первую на место после второй")
            c.expectEqual(moved([0], 4), ["B", "C", "D", "A"], "первую в конец")
            c.expectEqual(moved([3], 0), ["D", "A", "B", "C"], "последнюю в начало")
            c.expectEqual(moved([2], 1), ["A", "C", "B", "D"], "вверх на одну")
            c.expectEqual(moved([1, 3], 0), ["B", "D", "A", "C"], "несколько в начало")
            c.expectEqual(moved([0, 2], 4), ["B", "D", "A", "C"], "несколько в конец")
            c.expectEqual(moved([1], 1), ["A", "B", "C", "D"], "на своё место — без изменений")
            c.expectEqual(moved([1], 2), ["A", "B", "C", "D"], "сразу за собой — без изменений")
            c.expectEqual(moved([0], 99), ["B", "C", "D", "A"], "позиция за концом ограничивается")
            c.expectEqual(moved([9], 0), ["A", "B", "C", "D"], "неверный индекс игнорируется")

            var (doc, ids) = sample()
            doc.lastActiveTaskID = ids[0]
            c.expect(!TaskListOps.move(&doc, fromOffsets: IndexSet(integer: 1), toOffset: 1), "без изменений → false")
            c.expect(TaskListOps.move(&doc, fromOffsets: IndexSet(integer: 0), toOffset: 4), "перестановка → true")
            c.expectEqual(doc.number(of: ids[0]), 4, "номер задачи = новая позиция")
            c.expectEqual(doc.lastActiveTaskID, ids[0], "текущая задача сохраняется при перестановке")
            var empty = TasksDocument()
            c.expect(!TaskListOps.move(&empty, fromOffsets: IndexSet(integer: 0), toOffset: 0), "пустой список не ломается")
        }
    }

    static func checkMoveByAndBefore(_ c: CheckRunner) {
        c.group("move(by:) и move(before:)") {
            var (doc, ids) = sample()
            c.expect(TaskListOps.move(&doc, id: ids[2], by: -1), "выше на одну")
            c.expectEqual(titles(doc), ["A", "C", "B", "D"], "C поднялась")
            c.expect(!TaskListOps.move(&doc, id: ids[0], by: -1), "первую выше нельзя")
            c.expect(!TaskListOps.move(&doc, id: ids[3], by: 1), "последнюю ниже нельзя")
            c.expect(TaskListOps.move(&doc, id: ids[0], by: 10), "большой сдвиг ограничен краем")
            c.expectEqual(titles(doc), ["C", "B", "D", "A"], "A в конце")
            c.expect(!TaskListOps.move(&doc, id: UUID(), by: 1), "неизвестный id → false")

            var (doc2, ids2) = sample()
            c.expect(TaskListOps.move(&doc2, id: ids2[3], before: ids2[1]), "D перед B")
            c.expectEqual(titles(doc2), ["A", "D", "B", "C"], "D встала перед B")
            c.expect(TaskListOps.move(&doc2, id: ids2[0], before: nil), "A в конец (цель nil)")
            c.expectEqual(titles(doc2), ["D", "B", "C", "A"], "A в конце")
            c.expect(TaskListOps.move(&doc2, id: ids2[3], before: UUID()), "неизвестная цель → в конец")
            c.expectEqual(titles(doc2), ["B", "C", "A", "D"], "D в конце")
            c.expect(!TaskListOps.move(&doc2, id: ids2[1], before: ids2[1]), "перед собой — без изменений")
        }
    }
}
