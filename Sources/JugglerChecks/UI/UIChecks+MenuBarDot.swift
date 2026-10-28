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

            // Соответствие уровней и цветов.
            c.expectEqual(MenuBarDotColor.color(for: .fresh), .green, "свежая — зелёный")
            c.expectEqual(MenuBarDotColor.color(for: .aging), .yellow, "пора вернуться — жёлтый")
            c.expectEqual(MenuBarDotColor.color(for: .stale), .orange, "давно — оранжевый")
            c.expectEqual(MenuBarDotColor.color(for: .forgotten), .red, "забыта — красный")
            c.expectEqual(MenuBarDotColor.color(for: .never), .green, "уровень «ни разу» не выпадает из палитры")

            // Пустой документ и все сделаны — серый контур.
            c.expectEqual(color(TasksDocument()), .outline, "нет задач — контур")
            var (doc, ids) = sample()
            for i in doc.tasks.indices { doc.tasks[i].isDone = true; doc.tasks[i].lastVisitedAt = ago(100) }
            doc.lastActiveTaskID = ids[0]
            c.expectEqual(color(doc), .outline, "все сделаны — контур")
            c.expectNil(MenuBarDotPresenter.dot(for: doc, now: now).taskID, "у контура нет задачи")
            c.expectEqual(MenuBarDotPresenter.dot(for: doc, now: now).tooltip, "Juggler: нет задач в работе", "подсказка контура")

            // Одна несделанная задача, она же текущая — зелёный, даже если давно не заходили.
            (doc, ids) = sample()
            doc.tasks = [doc.tasks[0]]
            doc.tasks[0].lastVisitedAt = ago(500)
            doc.lastActiveTaskID = ids[0]
            c.expectEqual(color(doc), .filled(.green), "только текущая — зелёный, а не красный")
            c.expectEqual(MenuBarDotPresenter.dot(for: doc, now: now).tooltip, "Juggler: других задач в работе нет", "подсказка при одной задаче")
            doc.tasks[0].isDone = true
            c.expectEqual(color(doc), .outline, "единственная сделана — контур")

            // Три задачи: цвет по самой заброшенной, текущая не учитывается.
            (doc, ids) = sample()
            doc.tasks = Array(doc.tasks.prefix(3))
            doc.tasks[0].lastVisitedAt = ago(1)      // текущая
            doc.tasks[1].lastVisitedAt = ago(5)
            doc.tasks[2].lastVisitedAt = ago(12)
            doc.lastActiveTaskID = ids[0]
            c.expectEqual(color(doc), .filled(.yellow), "самая давняя 12 мин — жёлтый")
            c.expectEqual(MenuBarDotPresenter.dot(for: doc, now: now).taskID, ids[2], "выбрана задача 3")
            c.expectEqual(MenuBarDotPresenter.dot(for: doc, now: now).tooltip,
                          "Juggler: дольше всех ждёт задача 3 — C, не был 12 мин", "подсказка с задачей и минутами")

            doc.tasks[0].lastVisitedAt = ago(300)    // текущая давно — не краснеет
            c.expectEqual(color(doc), .filled(.yellow), "текущая не учитывается, как бы давно ни заходили")

            // Границы порогов: 9 → зелёный, 10 → жёлтый, 29 → жёлтый, 30 → оранжевый, 59 → оранжевый, 60 → красный.
            let boundaries: [(Double, MenuBarDotColor)] = [(9, .green), (10, .yellow), (29, .yellow), (30, .orange), (59, .orange), (60, .red), (600, .red)]
            for (minutes, expected) in boundaries {
                doc.tasks[2].lastVisitedAt = ago(minutes)
                doc.tasks[1].lastVisitedAt = ago(minutes)
                c.expectEqual(color(doc), .filled(expected), "\(minutes) мин → \(expected)")
            }

            // Сделанная задача не учитывается; вернули в работу — снова считается.
            doc.tasks[1].lastVisitedAt = ago(5)
            doc.tasks[2].lastVisitedAt = ago(70)
            doc.tasks[2].isDone = true
            c.expectEqual(color(doc), .filled(.green), "сделанная давняя не краснит кружок")
            doc.tasks[2].isDone = false
            c.expectEqual(color(doc), .filled(.red), "возвращённая в работу снова краснит")

            // Ни разу не открытая — от времени создания; после захода — от захода.
            doc.tasks[1].lastVisitedAt = ago(5)
            doc.tasks[2].lastVisitedAt = nil
            doc.tasks[2].createdAt = ago(35)
            c.expectEqual(color(doc), .filled(.orange), "ни разу не открытая считается от создания")
            c.expectEqual(MenuBarDotPresenter.dot(for: doc, now: now).tooltip,
                          "Juggler: дольше всех ждёт задача 3 — C, не был 35 мин", "подсказка от времени создания")
            doc.tasks[2].lastVisitedAt = ago(2)
            c.expectEqual(color(doc), .filled(.green), "после захода отсчёт с захода")
            c.expectEqual(MenuBarDotPresenter.dot(for: doc, now: now).taskID, ids[1], "теперь давнее — задача 2")

            // Без текущей задачи учитываются все несделанные; пустое название; ничья — первая.
            doc.lastActiveTaskID = nil
            doc.tasks[0].lastVisitedAt = ago(65)
            c.expectEqual(color(doc), .filled(.red), "без текущей учитываются все")
            doc.tasks[0].title = ""
            c.expect(MenuBarDotPresenter.dot(for: doc, now: now).tooltip.contains("Без названия"), "пустое название в подсказке")
            doc.tasks[1].lastVisitedAt = ago(65)
            c.expectEqual(MenuBarDotPresenter.dot(for: doc, now: now).taskID, ids[0], "при равенстве — первая в списке")

            // Пороги берутся те же, что у списка.
            let custom = StalenessThresholds(agingMinutes: 1, staleMinutes: 2, forgottenMinutes: 3)
            c.expectEqual(MenuBarDotPresenter.dot(for: doc, now: now, thresholds: custom).appearance, .filled(.red), "пороги передаются")
        }
    }
}
