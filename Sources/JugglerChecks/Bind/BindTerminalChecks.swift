import Foundation
import JugglerCore

// Окна и вкладки Terminal.app (задача TERM): модель и JSON, заголовки, вывод AppleScript,
// привязка, текущая задача, переключатель ⌃⌥§ и поиск вкладки при переходе.

extension BindChecks {
    static let terminalTitle = "sergejefimov — sergejefimov@MacBook-Pro-Sergej — -zsh — 214×24"

    static func terminal(_ c: CheckRunner) {
        terminalModel(c)
        terminalTitles(c)
        terminalScripts(c)
        terminalCapture(c)
        terminalResolver(c)
        terminalToggle(c)
        terminalMatcher(c)
    }

    static func terminalContext(windowID: Int? = 7, tty: String = "/dev/ttys003", title: String = terminalTitle,
                                axTitle: String? = nil) -> FrontmostContext {
        FrontmostContext(bundleID: BindApps.terminal, appName: "Терминал", windowTitle: axTitle ?? title,
                         terminalWindow: windowID == nil && tty.isEmpty ? nil : TerminalWindowRef(windowID: windowID, tty: tty, title: title))
    }

    static func terminalModel(_ c: CheckRunner) {
        c.group("Терминал: модель и JSON") {
            c.expectEqual(BindApps.kind(of: "com.apple.Terminal"), .terminal, "Terminal.app — свой вид")
            c.expectEqual(BindApps.kind(of: "COM.APPLE.TERMINAL"), .terminal, "без учёта регистра")
            c.expectEqual(BindingSource.terminalWindow.displayName, "Терминал", "название источника")
            let symbols = BindingSource.allCases.map(\.symbolName)
            c.expectEqual(Set(symbols).count, symbols.count, "у каждого источника свой значок")
            c.expectEqual(BindingSource.terminalWindow.symbolName, "apple.terminal", "значок Терминала")

            let ref = TerminalWindowRef(windowID: 7, tty: " /dev/ttys003\n", title: terminalTitle)
            c.expectEqual(ref.tty, "/dev/ttys003", "tty без пробелов")
            let task = Fixture.task("Терминал", binding: .terminalWindow(ref))
            let doc = TasksDocument(tasks: [task, Fixture.task("Окно", binding: .appWindow(AppWindowRef(bundleID: BindApps.terminal, windowTitle: "x")))])
            let data = try TaskStore.encode(doc)
            c.expectEqual(try TaskStore.decode(data), doc, "окно Терминала переживает JSON")
            let text = String(decoding: data, as: UTF8.self)
            c.expect(text.contains("\"kind\" : \"terminalWindow\"") || text.contains("\"kind\":\"terminalWindow\""), "вид в JSON — terminalWindow")

            // Файл до TERM: те же виды и ключи — читается без потерь.
            let old = """
            {"version":1,"lastActiveTaskID":"22222222-2222-2222-2222-222222222222","tasks":[
              {"id":"11111111-1111-1111-1111-111111111111","title":"Вкладка","note":"заметка","isDone":true,
               "binding":{"kind":"chromeTab","chromeTab":{"tabID":1,"windowID":2,"url":"https://example.com","title":"Пример"}}},
              {"id":"22222222-2222-2222-2222-222222222222","title":"Терминал как окно",
               "binding":{"kind":"appWindow","appWindow":{"bundleID":"com.apple.Terminal","windowTitle":"\(terminalTitle)","appName":"Терминал"}}}
            ]}
            """
            let decoded = try TaskStore.decode(Data(old.utf8))
            c.expectEqual(decoded.tasks.count, 2, "старый файл: все задачи на месте")
            c.expectEqual(decoded.tasks.first?.note, "заметка", "старый файл: заметка")
            c.expectEqual(decoded.tasks.first?.isDone, true, "старый файл: «сделано»")
            c.expectEqual(decoded.tasks.last?.binding,
                          .appWindow(AppWindowRef(bundleID: BindApps.terminal, windowTitle: terminalTitle, appName: "Терминал")),
                          "старая привязка Терминала как окна читается как была")
            c.expectEqual(decoded.lastActiveTaskID, decoded.tasks.last?.id, "старый файл: последняя активная")

            let partial = """
            {"version":1,"tasks":[
              {"id":"33333333-3333-3333-3333-333333333333","title":"Только tty","binding":{"kind":"terminalWindow","terminalWindow":{"tty":"/dev/ttys009"}}},
              {"id":"44444444-4444-4444-4444-444444444444","title":"Пусто","binding":{"kind":"terminalWindow","terminalWindow":{}}}
            ]}
            """
            let lenient = try TaskStore.decode(Data(partial.utf8))
            c.expectEqual(lenient.tasks.first?.binding, .terminalWindow(TerminalWindowRef(tty: "/dev/ttys009")), "недостающие поля — пустые")
            c.expectEqual(lenient.tasks.count, 2, "пустая привязка Терминала не ломает задачу")

            // Контекст переднего окна без нового поля (например, старый JSON пробы) читается.
            let context = try JSONDecoder().decode(FrontmostContext.self, from: Data(#"{"bundleID":"com.apple.Terminal"}"#.utf8))
            c.expectNil(context.terminalWindow, "FrontmostContext без terminalWindow")
        }
    }

    static func terminalTitles(_ c: CheckRunner) {
        c.group("Терминал: заголовки") {
            c.expectEqual(TerminalTitle.clean(terminalTitle), "sergejefimov", "без пользователя@хоста, оболочки и размера")
            c.expectEqual(TerminalTitle.taskTitle(from: terminalTitle), "sergejefimov", "название задачи с мака пользователя")
            c.expectEqual(TerminalTitle.clean("juggler — ✳ Ревью PR — claude — 214×24"), "juggler — Ревью PR — claude",
                          "значок Claude Code в начале части убирается, процесс остаётся")
            c.expectEqual(TerminalTitle.taskTitle(from: "juggler — ✳ Ревью PR — claude — 214×24"), "juggler — Ревью PR",
                          "в названии задачи — без хвоста «claude»")
            c.expectEqual(TerminalTitle.clean("⠂ Сборка — node — 80x24"), "Сборка — node", "спиннер и размер через x")
            c.expectEqual(TerminalTitle.clean("proj — vim main.swift — ttys004 — 120×40"), "proj — vim main.swift", "tty и размер")
            c.expectEqual(TerminalTitle.clean("~ — /bin/bash --login — 80×24"), "~", "оболочка с путём и ключом")
            c.expectEqual(TerminalTitle.clean("-zsh — 80×24"), "", "только шум → пусто")
            c.expectEqual(TerminalTitle.taskTitle(from: "-zsh — 80×24"), "Терминал", "только шум → «Терминал»")
            c.expectEqual(TerminalTitle.taskTitle(from: nil), "Терминал", "без заголовка → «Терминал»")
            c.expectEqual(TerminalTitle.clean("zshrc — vim"), "zshrc — vim", "похожее на оболочку слово — не шум")
            c.expect(TerminalTitle.same(terminalTitle, "sergejefimov — sergejefimov@MacBook-Pro-Sergej — -zsh — 80×24"),
                     "смена размера не меняет заголовок без шума")
            c.expect(!TerminalTitle.same("-zsh — 80×24", "-zsh — 80×24"), "пустые без шума не совпадают")
            c.expect(!TerminalTitle.same("a — -zsh — 80×24", "b — -zsh — 80×24"), "разные папки — разные окна")
        }
    }

    static func terminalScripts(_ c: CheckRunner) {
        c.group("Терминал: вывод AppleScript") {
            let front = TerminalScripts.parseFrontWindow("7\(sep)/dev/ttys003\(sep)\(terminalTitle)\n")
            c.expectEqual(front, TerminalWindowRef(windowID: 7, tty: "/dev/ttys003", title: terminalTitle), "переднее окно")
            c.expectEqual(TerminalScripts.parseFrontWindow("7.0\(sep)\(sep)Заголовок")?.windowID, 7, "окно без вкладки, id как real")
            c.expectNil(TerminalScripts.parseFrontWindow(""), "окон нет")
            c.expectNil(TerminalScripts.parseFrontWindow("x\(sep)\(sep)T"), "ни id, ни tty")
            c.expectEqual(TerminalScripts.parseFrontWindow("5\(sep)/dev/ttys001\(sep)a — b")?.title, "a — b", "заголовок с « — »")

            let listing = "7\(sep)1\(sep)/dev/ttys003\(sep)A — -zsh — 80×24\(rec)7\(sep)2\(sep)/dev/ttys004\(sep)A — -zsh — 80×24\(rec)"
                + "9\(sep)1\(sep)/dev/ttys005\(sep)B\(rec)bad\(rec)9\(sep)0\(sep)/dev/ttys006\(sep)B\(rec)"
            let entries = TerminalScripts.parseTabListing(listing)
            c.expectEqual(entries.count, 3, "неполные записи и индекс 0 пропущены")
            c.expectEqual(entries[1], TerminalTabEntry(windowID: 7, index: 2, tty: "/dev/ttys004", windowTitle: "A — -zsh — 80×24"), "вторая вкладка окна 7")

            let focus = TerminalScripts.focusSource(windowID: 7, tabIndex: 2)
            c.expect(focus.contains("window id 7") && focus.contains("set selected tab of w to tab 2 of w"), "переход выбирает вкладку")
            c.expect(!TerminalScripts.focusSource(windowID: 7, tabIndex: nil).contains("selected tab"), "без вкладки — только окно")
            c.expect(TerminalScripts.frontWindowSource().contains("tell application id \"com.apple.Terminal\""), "скрипт для com.apple.Terminal")
        }
    }

    static func terminalCapture(_ c: CheckRunner) {
        c.group("Терминал: привязка") {
            let captured = BindingCapture.capture(context: terminalContext())
            c.expectEqual(captured, .captured(.terminalWindow(TerminalWindowRef(windowID: 7, tty: "/dev/ttys003", title: terminalTitle)),
                                              suggestedTitle: "sergejefimov"),
                          "окно и вкладка сразу, название без шума")

            // Без разрешения AppleScript: обычное окно, но название тоже без шума.
            let noAccess = BindingCapture.capture(context: FrontmostContext(bundleID: BindApps.terminal, appName: "Терминал",
                                                                            windowTitle: "juggler — -zsh — 214×24"))
            c.expectEqual(noAccess, .captured(.appWindow(AppWindowRef(bundleID: BindApps.terminal, windowTitle: "juggler — -zsh — 214×24", appName: "Терминал")),
                                              suggestedTitle: "juggler"),
                          "без разрешения — обычное окно")
            let blank = BindingCapture.capture(context: FrontmostContext(bundleID: BindApps.terminal, appName: "Терминал"))
            c.expectEqual(blank, .captured(.appWindow(AppWindowRef(bundleID: BindApps.terminal, appName: "Терминал")), suggestedTitle: "Терминал"),
                          "ни AppleScript, ни Accessibility — окно без заголовка, задача «Терминал»")

            let onlyTitleFromScript = BindingCapture.capture(context: FrontmostContext(
                bundleID: BindApps.terminal, terminalWindow: TerminalWindowRef(windowID: 3, title: "")))
            if case .captured(.terminalWindow(let ref), _) = onlyTitleFromScript {
                c.expectEqual(ref.windowID, 3, "только id окна — тоже привязка к окну Терминала")
            } else {
                c.expect(false, "только id окна: нет привязки")
            }
            let ctxWithAX = FrontmostContext(bundleID: BindApps.terminal, windowTitle: "AX — -zsh — 80×24",
                                             terminalWindow: TerminalWindowRef(windowID: 3, tty: "/dev/ttys001"))
            if case .captured(.terminalWindow(let ref), _) = BindingCapture.capture(context: ctxWithAX) {
                c.expectEqual(ref.title, "AX — -zsh — 80×24", "пустой заголовок из AppleScript дополняется заголовком окна")
                if case .captured(_, let title) = BindingCapture.capture(context: ctxWithAX) {
                    c.expectEqual(title, "AX", "и название задачи — из него")
                }
            } else {
                c.expect(false, "заголовок из AX: нет привязки")
            }

            let a = TaskBinding.terminalWindow(TerminalWindowRef(windowID: 7, tty: "/dev/ttys003", title: "A — 80×24"))
            let sameTab = TaskBinding.terminalWindow(TerminalWindowRef(windowID: 8, tty: "/dev/ttys003", title: "B"))
            let otherTab = TaskBinding.terminalWindow(TerminalWindowRef(windowID: 7, tty: "/dev/ttys004", title: "A — 80×24"))
            let windowOnly = TaskBinding.terminalWindow(TerminalWindowRef(windowID: 7, title: "C"))
            c.expect(BindPlanner.sameTarget(a, sameTab), "тот же tty — та же вкладка")
            c.expect(!BindPlanner.sameTarget(a, otherTab), "другой tty в том же окне — другая вкладка")
            c.expect(BindPlanner.sameTarget(a, windowOnly), "tty неизвестен — сравнение по id окна")
            c.expect(BindPlanner.sameTarget(
                .appWindow(AppWindowRef(bundleID: BindApps.terminal, windowTitle: "juggler — -zsh — 214×24")),
                .appWindow(AppWindowRef(bundleID: BindApps.terminal, windowTitle: "juggler — -zsh — 80×24"))),
                "Терминал как окно: размер не мешает")
            c.expectEqual(WindowTitleMatcher.bestIndex(of: "juggler — -zsh — 214×24", in: ["x — -zsh — 80×24", "juggler — node — 80×24", "juggler — -zsh — 100×30"],
                                                       bundleID: BindApps.terminal), 2,
                          "окно Терминала по заголовку без размера")
        }
    }

    static func terminalResolver(_ c: CheckRunner) {
        c.group("Терминал: текущая задача") {
            let tab = Fixture.task("Вкладка", binding: .terminalWindow(TerminalWindowRef(windowID: 7, tty: "/dev/ttys003", title: terminalTitle)))
            let other = Fixture.task("Соседняя", binding: .terminalWindow(TerminalWindowRef(windowID: 7, tty: "/dev/ttys004", title: terminalTitle)))
            let tasks = [other, tab]
            // Команда и размер сменились — заголовок другой, tty тот же.
            let changed = terminalContext(title: "sergejefimov — vim notes.md — 100×30")
            c.expectEqual(CurrentTaskResolver.match(context: changed, tasks: tasks), tab.id, "по tty, хотя заголовок другой")
            c.expectEqual(CurrentTaskResolver.score(tab.binding!, against: changed), .sameID, "tty — как id")
            c.expectEqual(CurrentTaskResolver.match(context: terminalContext(tty: "/dev/ttys004"), tasks: tasks), other.id, "соседняя вкладка того же окна")

            let windowOnly = Fixture.task("Окно", binding: .terminalWindow(TerminalWindowRef(windowID: 9, title: "X")))
            c.expectEqual(CurrentTaskResolver.score(windowOnly.binding!, against: terminalContext(windowID: 9, title: "Y")), .sameURL,
                          "tty привязки неизвестен — по id окна")
            c.expectEqual(CurrentTaskResolver.score(tab.binding!, against: terminalContext(windowID: 8, tty: "/dev/ttys099")), .sameApp,
                          "другое окно и вкладка — только то же приложение")
            c.expectEqual(CurrentTaskResolver.score(tab.binding!, against: FrontmostContext(bundleID: BindApps.chrome, windowTitle: terminalTitle)),
                          .none, "не Терминал — нет совпадения")
            c.expectEqual(CurrentTaskResolver.score(tab.binding!, against: FrontmostContext(bundleID: BindApps.terminal,
                                                                                           windowTitle: "sergejefimov — -zsh — 80×24")),
                          .sameTitle, "без AppleScript — по заголовку без шума")

            let legacy = Fixture.task("Старое окно", binding: .appWindow(AppWindowRef(bundleID: BindApps.terminal, windowTitle: terminalTitle)))
            c.expectEqual(CurrentTaskResolver.score(legacy.binding!, against: FrontmostContext(bundleID: BindApps.terminal,
                                                                                              windowTitle: "sergejefimov — -zsh — 80×24")),
                          .sameTitle, "Терминал как окно: смена размера не ломает")
            c.expectEqual(CurrentTaskResolver.match(context: changed, tasks: [legacy, tab]), tab.id, "tty сильнее старой привязки окна")
        }
    }

    static func terminalToggle(_ c: CheckRunner) {
        c.group("Терминал: ⌃⌥§") {
            let tab = Fixture.task("Вкладка", binding: .terminalWindow(TerminalWindowRef(windowID: 7, tty: "/dev/ttys003", title: terminalTitle)))
            let doc = TasksDocument(tasks: [Fixture.task("Другая"), tab])
            let resized = terminalContext(title: "sergejefimov — node — 80×24")
            c.expectEqual(ExactTaskMatcher.match(context: resized, document: doc), tab.id, "та же вкладка при смене команды и размера")
            c.expectEqual(ExactTaskMatcher.strength(tab.binding!, against: resized), .id, "tty — точное совпадение")
            if case .remove(let id, let number) = TaskToggle.decide(document: doc, lastRemoved: nil, now: Fixture.t0, context: { resized }) {
                c.expectEqual(id, tab.id, "⌃⌥§ удаляет задачу этой вкладки")
                c.expectEqual(number, 2, "номер задачи")
            } else {
                c.expect(false, "⌃⌥§ в привязанной вкладке должен удалить задачу")
            }

            let sameTitleOtherTab = terminalContext(tty: "/dev/ttys004")
            c.expectNil(ExactTaskMatcher.match(context: sameTitleOtherTab, document: doc), "другая вкладка с тем же заголовком — не задача")
            c.expectEqual(TaskToggle.decide(document: doc, lastRemoved: nil, now: Fixture.t0, context: { sameTitleOtherTab }),
                          .add(sameTitleOtherTab), "⌃⌥§ в другой вкладке — добавить")
            c.expectNil(ExactTaskMatcher.match(context: terminalContext(windowID: 8, tty: "/dev/ttys009", title: terminalTitle), document: doc),
                        "другое окно с тем же заголовком — не задача")

            let byWindow = TasksDocument(tasks: [Fixture.task("Окно", binding: .terminalWindow(TerminalWindowRef(windowID: 7, title: "A")))])
            c.expectEqual(ExactTaskMatcher.strength(byWindow.tasks[0].binding!, against: terminalContext(title: "B")), .url,
                          "tty привязки неизвестен — по id окна")

            // Старая привязка Терминала как окна: AppleScript дал id — окно-привязка не совпадает (как у Chrome).
            let legacy = TasksDocument(tasks: [Fixture.task("Старое", binding: .appWindow(AppWindowRef(bundleID: BindApps.terminal, windowTitle: terminalTitle)))])
            c.expectNil(ExactTaskMatcher.match(context: terminalContext(), document: legacy), "есть tty — старая привязка окна не точная")
            let noScript = FrontmostContext(bundleID: BindApps.terminal, windowTitle: "sergejefimov — sergejefimov@MacBook-Pro-Sergej — -zsh — 80×24")
            c.expectEqual(ExactTaskMatcher.match(context: noScript, document: legacy), legacy.tasks[0].id,
                          "без AppleScript — старая привязка по заголовку без размера")
            c.expectEqual(ExactTaskMatcher.strength(tab.binding!, against: noScript), .title, "без AppleScript — окно Терминала по заголовку")
            c.expectNil(ExactTaskMatcher.strength(tab.binding!, against: FrontmostContext(bundleID: BindApps.terminal, windowTitle: "-zsh — 80×24")),
                        "одни шум в заголовке — не совпадение")
        }
    }

    static func terminalMatcher(_ c: CheckRunner) {
        c.group("Терминал: поиск вкладки при переходе") {
            let entries = [
                TerminalTabEntry(windowID: 7, index: 1, tty: "/dev/ttys003", windowTitle: "A — -zsh — 80×24"),
                TerminalTabEntry(windowID: 7, index: 2, tty: "/dev/ttys004", windowTitle: "A — -zsh — 80×24"),
                TerminalTabEntry(windowID: 9, index: 1, tty: "/dev/ttys005", windowTitle: "B — -zsh — 120×40"),
            ]
            let byTTY = TerminalTabMatcher.find(TerminalWindowRef(windowID: 9, tty: "/dev/ttys004", title: "B"), in: entries)
            c.expectEqual(byTTY, .init(windowID: 7, tabIndex: 2, kind: .byTTY), "сначала по tty (вкладку могли перенести в другое окно)")
            let byWindow = TerminalTabMatcher.find(TerminalWindowRef(windowID: 9, tty: "/dev/ttys099", title: "A"), in: entries)
            c.expectEqual(byWindow, .init(windowID: 9, tabIndex: nil, kind: .byWindowID), "вкладка закрыта — по id окна")
            let byTitle = TerminalTabMatcher.find(TerminalWindowRef(windowID: 1, tty: "/dev/ttys099", title: "B — -zsh — 80×24"), in: entries)
            c.expectEqual(byTitle, .init(windowID: 9, tabIndex: nil, kind: .byTitle), "затем по заголовку без размера")
            c.expectNil(TerminalTabMatcher.find(TerminalWindowRef(windowID: 1, tty: "/dev/ttys099", title: "C"), in: entries), "окно закрыто")
            c.expectNil(TerminalTabMatcher.find(TerminalWindowRef(windowID: 1, tty: "", title: "-zsh — 80×24"), in: entries),
                        "заголовок из одного шума не совпадает ни с чем")
            c.expectNil(TerminalTabMatcher.find(TerminalWindowRef(windowID: 7), in: []), "Терминал без окон")
            c.expect(!BindTexts.terminalWindowClosed.isEmpty && BindTexts.terminalWindowClosed.contains("закрыто"),
                     "честный текст карточки, если окно закрыто")
        }
    }
}
