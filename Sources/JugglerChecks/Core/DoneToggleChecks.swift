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
            func plan(_ d: TasksDocument, _ ctx: FrontmostContext) -> FrontWindowPlan {
                SwitchPlanner.frontWindow(context: ctx, document: d) { BindingCapture.capture(context: $0) }
            }
            let d = doneDoc(active: 1)
            c.expectEqual(plan(d, frontOne), .task(d.tasks[0].id), "точное совпадение важнее текущей")
            // The bug: a window that is not a task toggled the last active task. Now it is added instead.
            c.expectEqual(plan(d, frontNone), .add(.appWindow(AppWindowRef(bundleID: "com.example.zzz", windowTitle: "Чужое")), title: "Чужое"),
                          "нет совпадения — окно добавляется, текущая (▸) не трогается")
            let noCurrent = doneDoc(active: nil)
            c.expectEqual(plan(noCurrent, frontOne), .task(noCurrent.tasks[0].id), "без текущей точное совпадение всё равно работает")
            c.expectEqual(plan(TasksDocument(), frontNone), .add(.appWindow(AppWindowRef(bundleID: "com.example.zzz", windowTitle: "Чужое")), title: "Чужое"),
                          "пустой список — окно добавляется")
            // Same app, different window: not the task, a new one.
            let sameApp = FrontmostContext(bundleID: "com.example.one", windowTitle: "Другое")
            c.expectEqual(plan(d, sameApp), .add(.appWindow(AppWindowRef(bundleID: "com.example.one", windowTitle: "Другое")), title: "Другое"),
                          "то же приложение, другое окно — новая задача")
            // A done task is also a target: repeating brings it back to work.
            let allDone = doneDoc(active: 2, done: [true, true, true])
            c.expectEqual(plan(allDone, frontOne), .task(allDone.tasks[0].id), "сделанная задача окна — всё равно цель")
        }
    }

    static func doneToggling(_ c: CheckRunner) {
        c.group("⌃§: переключатель") {
            var d = doneDoc(active: 1)
            let id = d.tasks[0].id
            let first = DoneToggle.toggle(&d, id: id)
            c.expectEqual(first, DoneToggleResult(taskID: id, number: 1, title: "Первая", isDone: true), "первое нажатие — «сделано»")
            c.expect(d.tasks[0].isDone && !d.tasks[1].isDone, "отмечена задача переднего окна")
            c.expectEqual(d.lastActiveTaskID, d.tasks[1].id, "текущая задача не меняется")
            let second = DoneToggle.toggle(&d, id: id)
            c.expectEqual(second, DoneToggleResult(taskID: id, number: 1, title: "Первая", isDone: false), "повтор — снова в работе")
            c.expect(!d.tasks[0].isDone, "отметка снята")

            let before = d
            c.expectNil(DoneToggle.toggle(&d, id: UUID()), "задачи с таким id нет")
            c.expectEqual(d, before, "документ не изменился")

            // Persisted to tasks.json via the regular document write.
            let (store, dir) = Fixture.tempStore()
            defer { try? FileManager.default.removeItem(at: dir) }
            var saved = doneDoc(active: 1)
            DoneToggle.toggle(&saved, id: saved.tasks[0].id)
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
            c.expect(!DoneToggleTexts.noCurrentTaskMessage.isEmpty, "пояснение, когда окно добавить нельзя")
            c.expectEqual(DoneToggleTexts.message(for: DoneToggleResult(taskID: UUID(), number: 4, title: "Х", isDone: true)),
                          "Задача 4 «Х» сделана", "текст по итогу")
        }
    }
}
