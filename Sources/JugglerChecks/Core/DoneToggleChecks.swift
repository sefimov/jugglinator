import Foundation
import JugglerCore

// ⌃§ "mark done / back to work" (task DONEKEY, D24): target choice, toggle, texts.

extension CoreChecks {
    static func doneToggleChecks(_ c: CheckRunner) {
        doneTarget(c)
        doneToggling(c)
        doneTexts(c)
    }

    private static let winOne = TaskBinding.appWindow(AppWindowRef(bundleID: "com.example.one", windowTitle: "Один"))
    private static let winTwo = TaskBinding.appWindow(AppWindowRef(bundleID: "com.example.two", windowTitle: "Два"))
    private static let frontOne = FrontmostContext(bundleID: "com.example.one", windowTitle: "Один")
    private static let frontNone = FrontmostContext(bundleID: "com.example.zzz", windowTitle: "Чужое")

    private static func doneDoc(active: Int? = nil, done: [Bool] = [false, false, false]) -> TasksDocument {
        let tasks = [
            Fixture.task("Первая", done: done[0], binding: winOne),
            Fixture.task("Вторая", done: done[1], binding: winTwo),
            Fixture.task("Третья", done: done[2]),
        ]
        return TasksDocument(tasks: tasks, lastActiveTaskID: active.map { tasks[$0].id })
    }

    static func doneTarget(_ c: CheckRunner) {
        c.group("⌃§: выбор задачи") {
            let d = doneDoc(active: 1)
            c.expectEqual(DoneToggle.target(document: d, context: frontOne), d.tasks[0].id, "точное совпадение важнее текущей")
            c.expectEqual(DoneToggle.target(document: d, context: frontNone), d.tasks[1].id, "нет совпадения — текущая (▸)")
            let noCurrent = doneDoc(active: nil)
            c.expectEqual(DoneToggle.target(document: noCurrent, context: frontOne), noCurrent.tasks[0].id, "без текущей точное совпадение всё равно работает")
            c.expectNil(DoneToggle.target(document: doneDoc(active: nil), context: frontNone), "ни совпадения, ни текущей — цели нет")
            // A weak match (same app, different title) is not exact: the current task is taken.
            let sameApp = FrontmostContext(bundleID: "com.example.one", windowTitle: "Другое")
            c.expectEqual(DoneToggle.target(document: d, context: sameApp), d.tasks[1].id, "то же приложение, другое окно — текущая")
            // A current task that is no longer in the list is not a target.
            let stale = TasksDocument(tasks: d.tasks, lastActiveTaskID: UUID())
            c.expectNil(DoneToggle.target(document: stale, context: frontNone), "устаревший id текущей — цели нет")
            // A done task is also a target: repeating brings it back to work.
            let allDone = doneDoc(active: 2, done: [true, true, true])
            c.expectEqual(DoneToggle.target(document: allDone, context: frontNone), allDone.tasks[2].id, "сделанная текущая — всё равно цель")
        }
    }

    static func doneToggling(_ c: CheckRunner) {
        c.group("⌃§: переключатель") {
            var d = doneDoc(active: 1)
            var reads = 0
            let ctx: () -> FrontmostContext = { reads += 1; return frontOne }
            let first = DoneToggle.toggle(&d, context: ctx)
            c.expectEqual(first, .changed(taskID: d.tasks[0].id, number: 1, title: "Первая", isDone: true), "первое нажатие — «сделано»")
            c.expect(d.tasks[0].isDone && !d.tasks[1].isDone, "отмечена задача переднего окна")
            c.expectEqual(d.lastActiveTaskID, d.tasks[1].id, "текущая задача не меняется")
            let second = DoneToggle.toggle(&d, context: ctx)
            c.expectEqual(second, .changed(taskID: d.tasks[0].id, number: 1, title: "Первая", isDone: false), "повтор — снова в работе")
            c.expect(!d.tasks[0].isDone, "отметка снята")
            c.expect(first.didChange && second.didChange, "обе попытки меняют отметку")

            d = doneDoc(active: 1)
            let current = DoneToggle.toggle(&d) { frontNone }
            c.expectEqual(current, .changed(taskID: d.tasks[1].id, number: 2, title: "Вторая", isDone: true), "иначе — текущая задача")

            var empty = TasksDocument()
            reads = 0
            c.expectEqual(DoneToggle.toggle(&empty) { reads += 1; return frontOne }, .noTasks, "задач нет")
            c.expectEqual(reads, 0, "без задач контекст не читается")
            c.expect(empty == TasksDocument() && !DoneToggleResult.noTasks.didChange, "документ не изменился")

            var nobody = doneDoc(active: nil)
            let before = nobody
            c.expectEqual(DoneToggle.toggle(&nobody) { frontNone }, .noCurrentTask, "задачи есть, цели нет")
            c.expectEqual(nobody, before, "документ не изменился")

            // Persisted to tasks.json via the regular document write.
            let (store, dir) = Fixture.tempStore()
            defer { try? FileManager.default.removeItem(at: dir) }
            var saved = doneDoc(active: 1)
            _ = DoneToggle.toggle(&saved) { frontOne }
            try store.save(saved)
            c.expectEqual(store.load().document.tasks.map(\.isDone), [true, false, false], "«сделано» читается из tasks.json")
        }
    }

    static func doneTexts(_ c: CheckRunner) {
        c.group("⌃§: тексты") {
            c.expectEqual(DoneToggleTexts.card(number: 2, title: "  План\nрелиза ", isDone: true), "Задача 2 «План релиза» сделана", "карточка «сделана»")
            c.expectEqual(DoneToggleTexts.card(number: 3, title: "Тред", isDone: false), "Задача 3 «Тред» вернулась в работу", "карточка «в работе»")
            c.expectEqual(DoneToggleTexts.card(number: 1, title: "", isDone: true), "Задача 1 «Без названия» сделана", "пустое название")
            c.expectEqual(HotkeyAction.toggleDone.displayName, "Отметить сделанной / вернуть в работу", "подпись в настройках хоткеев")
            c.expectEqual(DoneToggleTexts.message(for: .noTasks), "Задач пока нет: добавьте задачу в меню Juggler", "пояснение без задач")
            c.expect(!DoneToggleTexts.message(for: .noCurrentTask).isEmpty, "пояснение без текущей задачи")
            c.expectEqual(DoneToggleTexts.message(for: .changed(taskID: UUID(), number: 4, title: "Х", isDone: true)),
                          "Задача 4 «Х» сделана", "текст по итогу")
        }
    }
}
