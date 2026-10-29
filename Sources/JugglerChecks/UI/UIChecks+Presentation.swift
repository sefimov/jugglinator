import Foundation
import JugglerCore

extension UIChecks {
    static func checkRows(_ c: CheckRunner) {
        c.group("строки списка") {
            var (doc, ids) = sample()
            let now = t0.addingTimeInterval(3600)
            doc.tasks[0].lastVisitedAt = now.addingTimeInterval(-5 * 60)
            doc.tasks[1].lastVisitedAt = now.addingTimeInterval(-15 * 60)
            doc.tasks[2].lastVisitedAt = now.addingTimeInterval(-90 * 60)
            doc.tasks[1].isDone = true
            doc.tasks[1].note = "дальше: тесты"
            doc.tasks[2].binding = .chromeTab(ChromeTabRef(tabID: 7, url: "https://example.com", title: "Пример"))
            doc.tasks[3].title = ""
            doc.lastActiveTaskID = ids[2]

            let rows = TaskListPresenter.rows(for: doc, now: now, currentTaskID: ids[2])
            c.expectEqual(rows.map(\.number), [1, 2, 3, 4], "номера по порядку с 1")
            c.expectEqual(rows.map(\.id), ids, "id строк совпадают с задачами")
            c.expectEqual(rows.map(\.isCurrent), [false, false, true, false], "отметка только у текущей")
            c.expect(TaskListPresenter.rows(for: doc, now: now, currentTaskID: nil).allSatisfy { !$0.isCurrent },
                     "переднее окно не задача → ни одна не отмечена, хотя последняя активная есть")
            c.expectEqual(TaskListPresenter.currentTaskID(
                context: FrontmostContext(bundleID: KnownBundleIDs.chrome, chromeTab: ChromeTabRef(tabID: 7, url: "https://example.com")),
                document: doc), ids[2], "текущая в меню — задача переднего окна")
            c.expectNil(TaskListPresenter.currentTaskID(context: FrontmostContext(bundleID: "com.example.zzz", windowTitle: "Чужое"), document: doc),
                        "чужое окно → текущей нет")
            c.expectNil(TaskListPresenter.currentTaskID(context: nil, document: doc), "окно ещё не прочитано → текущей нет")
            c.expectEqual(rows.map(\.staleness), [.fresh, .aging, .forgotten, .never], "уровни старения")
            c.expectEqual(rows[0].absenceText, "не был 5 мин", "текст «не был N мин»")
            c.expectEqual(rows[3].absenceText, "ещё не был", "без захода")
            c.expect(rows[1].isDone, "отметка «сделано» в строке")
            c.expectEqual(rows[1].note, "дальше: тесты", "заметка в строке")
            c.expectEqual(rows[2].source, .chromeTab, "источник привязки")
            c.expectNil(rows[0].source, "без привязки — нет источника")
            c.expectEqual(rows[2].bindingHelp, "Chrome: Пример", "справка о привязке")
            c.expect(rows[0].bindingHelp.hasPrefix("Без привязки"), "справка без привязки")
            c.expectEqual(rows[3].title, "Без названия", "пустое название показывается как «Без названия»")
            c.expect(TaskListPresenter.rows(for: TasksDocument(), now: now, currentTaskID: nil).isEmpty, "пустой документ → нет строк")
            let custom = TaskListPresenter.rows(for: doc, now: now, currentTaskID: nil, thresholds: StalenessThresholds(agingMinutes: 1, staleMinutes: 2, forgottenMinutes: 200))
            c.expectEqual(custom[2].staleness, .stale, "пороги старения передаются")
            let heights = (1...30).map { n in TaskListPresenter.listHeight(rows: Array(TaskListPresenter.rows(for: doc, now: now, currentTaskID: nil).prefix(0)) + Array(repeating: rows[0], count: n)) }
            c.expectEqual(TaskListPresenter.listHeight(rows: []), TaskListPresenter.listPadding, "высота пустого списка — только запас")
            c.expectEqual(heights[0], TaskListPresenter.listPadding + TaskListPresenter.rowHeight, "одна строка без заметки")
            c.expect(heights[1] > heights[0], "высота растёт с числом строк")
            c.expectEqual(heights[29], TaskListPresenter.maxListHeight, "много строк — высота ограничена, дальше прокрутка")
        }
    }

    static func checkTexts(_ c: CheckRunner) {
        c.group("тексты списка") {
            var (doc, _) = sample()

            c.expectEqual(TaskListPresenter.summary(for: TasksDocument()), "Задач пока нет", "сводка: пусто")
            c.expectEqual(TaskListPresenter.summary(for: doc), "4 задачи", "сводка: 4 задачи")
            doc.tasks[0].isDone = true
            c.expectEqual(TaskListPresenter.summary(for: doc), "4 задачи, 1 сделана", "сводка со сделанными")
            doc.tasks[1].isDone = true
            c.expectEqual(TaskListPresenter.summary(for: doc), "4 задачи, 2 сделаны", "сводка: 2 сделаны")

            c.expectEqual(TaskListPresenter.deleteConfirmation(title: " Ревью\nPR "), "Удалить задачу «Ревью PR»?", "вопрос перед удалением")
            c.expectEqual(TaskListPresenter.deleteConfirmation(title: ""), "Удалить задачу «Без названия»?", "вопрос для пустого названия")

            c.expectNil(TaskListPresenter.loadNotice(.loaded), "нормальная загрузка — без уведомления")
            c.expectNil(TaskListPresenter.loadNotice(.missing), "первый запуск — без уведомления")
            c.expectNil(TaskListPresenter.loadNotice(nil), "ещё не загружено — без уведомления")
            c.expect(TaskListPresenter.loadNotice(.recoveredFromBackup(quarantinedURL: nil))?.contains("резервной копии") == true, "восстановление из копии")
            c.expect(TaskListPresenter.loadNotice(.resetAfterCorruption(quarantinedURL: nil)) != nil, "сброс после повреждения")
        }
        c.group("RussianPlural") {
            func f(_ n: Int) -> String { RussianPlural.form(n, one: "задача", few: "задачи", many: "задач") }
            c.expectEqual([0, 1, 2, 4, 5, 11, 12, 14, 21, 22, 25, 101, 111, 112].map(f),
                          ["задач", "задача", "задачи", "задачи", "задач", "задач", "задач", "задач",
                           "задача", "задачи", "задач", "задача", "задач", "задач"],
                          "формы после чисел")
        }
    }

    static func checkLoginItem(_ c: CheckRunner) {
        c.group("LoginItemState") {
            c.expect(LoginItemState.enabled.isOn, "включён → переключатель включён")
            c.expect(LoginItemState.requiresApproval.isOn, "ждёт одобрения → переключатель включён")
            c.expect(!LoginItemState.notRegistered.isOn, "не зарегистрирован → выключен")
            c.expect(!LoginItemState.notFound.isOn, "не найден → выключен")
            c.expect(LoginItemState.requiresApproval.needsSystemSettings, "ждёт одобрения → кнопка «Объекты входа»")
            c.expect(!LoginItemState.enabled.needsSystemSettings, "включён → кнопки нет")
            c.expectNil(LoginItemState.enabled.explanation, "включён — пояснения нет")
            c.expect(LoginItemState.notFound.explanation?.contains("Juggler.app") == true, "не найден → пояснение про .app")
        }
    }

    static func checkPersistence(_ c: CheckRunner) {
        c.group("сохранение между запусками") {
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("juggler-ui-checks-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: dir) }
            let url = dir.appendingPathComponent("tasks.json")

            var doc = TasksDocument()
            let a = TaskListOps.add(&doc, title: "Один", note: "зачем: проверить", now: t0)
            let b = TaskListOps.add(&doc, title: "Два", now: t0)
            let d = TaskListOps.add(&doc, title: "Три", now: t0)
            TaskListOps.rename(&doc, id: b, to: "Два (новое)")
            TaskListOps.setDone(&doc, id: d, true)
            TaskListOps.move(&doc, fromOffsets: IndexSet(integer: 2), toOffset: 0)
            doc.markVisited(a, at: t0.addingTimeInterval(60))
            try TaskStore(fileURL: url).save(doc)

            let loaded = TaskStore(fileURL: url).load()
            c.expectEqual(loaded.outcome, .loaded, "файл прочитан после «перезапуска»")
            c.expectEqual(loaded.document, doc, "документ совпадает после записи и чтения")
            c.expectEqual(loaded.document.tasks.map(\.id), [d, a, b], "порядок сохранился")

            var next = loaded.document
            TaskListOps.delete(&next, id: a)
            try TaskStore(fileURL: url).save(next)
            let reloaded = TaskStore(fileURL: url).load().document
            c.expectEqual(reloaded.tasks.map(\.title), ["Три", "Два (новое)"], "удаление сохранилось")
            c.expectNil(reloaded.lastActiveTaskID, "отметка текущей снята и сохранена")
        }
    }
}
