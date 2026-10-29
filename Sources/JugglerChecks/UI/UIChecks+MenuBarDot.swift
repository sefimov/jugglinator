import Foundation
import JugglerCore

extension UIChecks {
    static func checkMenuBarDot(_ c: CheckRunner) {
        c.group("кружок меню-бара") {
            let now = t0.addingTimeInterval(7200)
            func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }
            func color(_ doc: TasksDocument) -> MenuBarDot.Appearance {
                MenuBarDotPresenter.dot(for: doc, now: now).appearance
            }

            // Level-to-color mapping.
            c.expectEqual(MenuBarDotColor.color(for: .fresh), .green, "свежая — зелёный")
            c.expectEqual(MenuBarDotColor.color(for: .aging), .yellow, "пора вернуться — жёлтый")
            c.expectEqual(MenuBarDotColor.color(for: .stale), .orange, "давно — оранжевый")
            c.expectEqual(MenuBarDotColor.color(for: .forgotten), .red, "забыта — красный")
            c.expectEqual(MenuBarDotColor.color(for: .never), .green, "уровень «ни разу» не выпадает из палитры")

            // Number inside the dot: only for an exact match of the frontmost window.
            do {
                let tab = JugglerTask(title: "Вкладка", binding: .chromeTab(ChromeTabRef(tabID: 5, url: "https://a.example")))
                let win = JugglerTask(title: "Окно", binding: .appWindow(AppWindowRef(bundleID: "com.example.app", windowTitle: "Отчёт")))
                let numbered = TasksDocument(tasks: [JugglerTask(title: "Без привязки"), tab, win], lastActiveTaskID: win.id)
                func number(_ ctx: FrontmostContext?) -> Int? { MenuBarDotPresenter.frontWindowNumber(context: ctx, document: numbered) }
                c.expectEqual(number(FrontmostContext(bundleID: KnownBundleIDs.chrome, chromeTab: ChromeTabRef(tabID: 5, url: "https://a.example"))), 2,
                              "вкладка-задача → её номер")
                c.expectEqual(number(FrontmostContext(bundleID: "com.example.app", windowTitle: "Отчёт")), 3, "окно-задача → её номер")
                c.expectNil(number(FrontmostContext(bundleID: "com.example.app", windowTitle: "Другое")), "другое окно того же приложения → без номера")
                c.expectNil(number(.unknown), "окно не узнано → без номера, а не последняя активная")
                c.expectNil(number(nil), "контекст ещё не прочитан → без номера")
            }

            // Empty document and all done: gray outline.
            c.expectEqual(color(TasksDocument()), .outline, "нет задач — контур")
            var (doc, ids) = sample()
            for i in doc.tasks.indices { doc.tasks[i].isDone = true; doc.tasks[i].lastVisitedAt = ago(100) }
            doc.lastActiveTaskID = ids[0]
            c.expectEqual(color(doc), .outline, "все сделаны — контур")
            c.expectNil(MenuBarDotPresenter.dot(for: doc, now: now).taskID, "у контура нет задачи")
            c.expectEqual(MenuBarDotPresenter.dot(for: doc, now: now).tooltip, "Juggler: нет задач в работе", "подсказка контура")

            // A single undone task that is also current: green, even if not visited for a long time.
            (doc, ids) = sample()
            doc.tasks = [doc.tasks[0]]
            doc.tasks[0].lastVisitedAt = ago(500)
            doc.lastActiveTaskID = ids[0]
            c.expectEqual(color(doc), .filled(.green), "только текущая — зелёный, а не красный")
            c.expectEqual(MenuBarDotPresenter.dot(for: doc, now: now).tooltip, "Juggler: других задач в работе нет", "подсказка при одной задаче")
            doc.tasks[0].isDone = true
            c.expectEqual(color(doc), .outline, "единственная сделана — контур")

            // Three tasks: color by the most neglected one, the current one is ignored.
            (doc, ids) = sample()
            doc.tasks = Array(doc.tasks.prefix(3))
            doc.tasks[0].lastVisitedAt = ago(1)      // current
            doc.tasks[1].lastVisitedAt = ago(5)
            doc.tasks[2].lastVisitedAt = ago(12)
            doc.lastActiveTaskID = ids[0]
            c.expectEqual(color(doc), .filled(.yellow), "самая давняя 12 мин — жёлтый")
            c.expectEqual(MenuBarDotPresenter.dot(for: doc, now: now).taskID, ids[2], "выбрана задача 3")
            c.expectEqual(MenuBarDotPresenter.dot(for: doc, now: now).tooltip,
                          "Juggler: дольше всех ждёт задача 3 — C, не был 12 мин", "подсказка с задачей и минутами")

            doc.tasks[0].lastVisitedAt = ago(300)    // current, stale: not red
            c.expectEqual(color(doc), .filled(.yellow), "текущая не учитывается, как бы давно ни заходили")

            // Threshold boundaries: 9 → green, 10 → yellow, 29 → yellow, 30 → orange, 59 → orange, 60 → red.
            let boundaries: [(Double, MenuBarDotColor)] = [(9, .green), (10, .yellow), (29, .yellow), (30, .orange), (59, .orange), (60, .red), (600, .red)]
            for (minutes, expected) in boundaries {
                doc.tasks[2].lastVisitedAt = ago(minutes)
                doc.tasks[1].lastVisitedAt = ago(minutes)
                c.expectEqual(color(doc), .filled(expected), "\(minutes) мин → \(expected)")
            }

            // A done task is ignored; once back to work it counts again.
            doc.tasks[1].lastVisitedAt = ago(5)
            doc.tasks[2].lastVisitedAt = ago(70)
            doc.tasks[2].isDone = true
            c.expectEqual(color(doc), .filled(.green), "сделанная давняя не краснит кружок")
            doc.tasks[2].isDone = false
            c.expectEqual(color(doc), .filled(.red), "возвращённая в работу снова краснит")

            // Never opened: counted from creation time; after a visit: from the visit.
            doc.tasks[1].lastVisitedAt = ago(5)
            doc.tasks[2].lastVisitedAt = nil
            doc.tasks[2].createdAt = ago(35)
            c.expectEqual(color(doc), .filled(.orange), "ни разу не открытая считается от создания")
            c.expectEqual(MenuBarDotPresenter.dot(for: doc, now: now).tooltip,
                          "Juggler: дольше всех ждёт задача 3 — C, не был 35 мин", "подсказка от времени создания")
            doc.tasks[2].lastVisitedAt = ago(2)
            c.expectEqual(color(doc), .filled(.green), "после захода отсчёт с захода")
            c.expectEqual(MenuBarDotPresenter.dot(for: doc, now: now).taskID, ids[1], "теперь давнее — задача 2")

            // Without a current task all undone ones count; empty title; on a tie, the first one.
            doc.lastActiveTaskID = nil
            doc.tasks[0].lastVisitedAt = ago(65)
            c.expectEqual(color(doc), .filled(.red), "без текущей учитываются все")
            doc.tasks[0].title = ""
            c.expect(MenuBarDotPresenter.dot(for: doc, now: now).tooltip.contains("Без названия"), "пустое название в подсказке")
            doc.tasks[1].lastVisitedAt = ago(65)
            c.expectEqual(MenuBarDotPresenter.dot(for: doc, now: now).taskID, ids[0], "при равенстве — первая в списке")

            // The same thresholds as the list's are used.
            let custom = StalenessThresholds(agingMinutes: 1, staleMinutes: 2, forgottenMinutes: 3)
            c.expectEqual(MenuBarDotPresenter.dot(for: doc, now: now, thresholds: custom).appearance, .filled(.red), "пороги передаются")
        }
    }
}
