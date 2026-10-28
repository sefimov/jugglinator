import Foundation
import JugglerCore

// ⌃⌥§ «добавить или удалить текущую задачу» (задача TOGGLE, D15): точное совпадение,
// решение переключателя, удаление с возвратом, окно отмены и тексты.

extension CoreChecks {
    static func toggleChecks(_ c: CheckRunner) {
        toggleExactChrome(c)
        toggleExactClaude(c)
        toggleExactChatGPT(c)
        toggleExactAppWindow(c)
        toggleExactPriority(c)
        toggleRemoval(c)
        toggleUndoWindow(c)
        toggleDecision(c)
        toggleTexts(c)
    }

    private static let toggleUUID = "0f8fad5b-d9cb-469f-a165-70867728950e"
    private static let otherUUID = "7c9e6679-7425-40de-944b-e07fc1f90ae7"

    private static func doc(_ bindings: [TaskBinding?], active: Int? = nil) -> TasksDocument {
        let tasks = bindings.enumerated().map { Fixture.task("Задача \($0.offset + 1)", binding: $0.element) }
        return TasksDocument(tasks: tasks, lastActiveTaskID: active.map { tasks[$0].id })
    }

    private static func matchIndex(_ context: FrontmostContext, _ document: TasksDocument) -> Int? {
        ExactTaskMatcher.match(context: context, document: document).flatMap { document.index(of: $0) }
    }

    static func toggleExactChrome(_ c: CheckRunner) {
        c.group("⌃⌥§: точное совпадение — Chrome") {
            let bound = TaskBinding.chromeTab(ChromeTabRef(tabID: 7, windowID: 1, url: "https://example.com/a/", title: "A"))
            let d = doc([bound])
            let sameID = FrontmostContext(bundleID: KnownBundleIDs.chrome, chromeTab: ChromeTabRef(tabID: 7, url: "https://other.com", title: "B"))
            c.expectEqual(matchIndex(sameID, d), 0, "тот же id вкладки")
            c.expectEqual(ExactTaskMatcher.strength(bound, against: sameID), .id, "сила — id")
            let sameURL = FrontmostContext(bundleID: KnownBundleIDs.chrome, chromeTab: ChromeTabRef(tabID: 9, url: "https://EXAMPLE.com/a#x", title: "A"))
            c.expectEqual(matchIndex(sameURL, d), 0, "другая вкладка с тем же адресом (без фрагмента, регистра хоста и «/»)")
            c.expectEqual(ExactTaskMatcher.strength(bound, against: sameURL), .url, "сила — адрес")
            let other = FrontmostContext(bundleID: KnownBundleIDs.chrome, windowTitle: "A - Google Chrome",
                                         chromeTab: ChromeTabRef(tabID: 9, url: "https://example.com/b", title: "A"))
            c.expectNil(matchIndex(other, d), "другая вкладка с тем же заголовком — не задача")
            let noTab = FrontmostContext(bundleID: KnownBundleIDs.chrome, windowTitle: "A - Google Chrome")
            c.expectNil(matchIndex(noTab, d), "без AppleScript (вкладка неизвестна) — не задача")
        }
    }

    static func toggleExactClaude(_ c: CheckRunner) {
        c.group("⌃⌥§: точное совпадение — Claude и Claude Code") {
            let chat = TaskBinding.claudeChat(ClaudeChatRef(conversationID: toggleUUID, title: "Ревью"))
            let session = TaskBinding.claudeCodeSession(ClaudeCodeSessionRef(sessionID: "local_\(otherUUID)", title: "Сессия"))
            let d = doc([chat, session])
            c.expectEqual(matchIndex(FrontmostContext(bundleID: KnownBundleIDs.claude, windowTitle: "Другое",
                                                      claudeConversationID: toggleUUID.uppercased()), d), 0,
                          "тот же UUID чата (регистр не важен)")
            c.expectNil(matchIndex(FrontmostContext(bundleID: KnownBundleIDs.claude, windowTitle: "Ревью",
                                                    claudeConversationID: otherUUID), d),
                        "другой чат с тем же заголовком — не задача")
            c.expectNil(matchIndex(FrontmostContext(bundleID: KnownBundleIDs.claude, windowTitle: "Ревью - Claude"), d),
                        "id не прочитан: одного заголовка мало")
            c.expectEqual(matchIndex(FrontmostContext(bundleID: KnownBundleIDs.chrome,
                                                      chromeTab: ChromeTabRef(tabID: 1, url: "https://claude.ai/chat/\(toggleUUID)")), d), 0,
                          "тот же чат на claude.ai в Chrome")
            c.expectEqual(matchIndex(FrontmostContext(bundleID: KnownBundleIDs.claude, windowTitle: "Claude",
                                                      claudeCodeSessionID: "LOCAL_\(otherUUID.uppercased())"), d), 1,
                          "та же сессия Claude Code")
            c.expectNil(matchIndex(FrontmostContext(bundleID: KnownBundleIDs.claude, windowTitle: "Сессия"), d),
                        "вкладка Code без id сессии — не задача")
            c.expectNil(matchIndex(FrontmostContext(bundleID: KnownBundleIDs.claude, windowTitle: "Claude",
                                                    claudeCodeSessionID: "local_\(toggleUUID)"), d),
                        "другая сессия — не задача (UUID чата не путается с сессией)")
        }
    }

    static func toggleExactChatGPT(_ c: CheckRunner) {
        c.group("⌃⌥§: точное совпадение — ChatGPT") {
            let thread = TaskBinding.chatGPTThread(ChatGPTThreadRef(threadID: "th-1", title: "План релиза"))
            let generic = TaskBinding.chatGPTThread(ChatGPTThreadRef(threadID: "th-2", title: "ChatGPT"))
            let d = doc([thread, generic])
            c.expectEqual(matchIndex(FrontmostContext(bundleID: KnownBundleIDs.chatGPT, windowTitle: "План релиза"), d), 0,
                          "то же название треда")
            c.expectEqual(matchIndex(FrontmostContext(bundleID: "com.openai.chat", windowTitle: "план релиза - ChatGPT"), d), 0,
                          "старый bundle id, хвост « - ChatGPT» и регистр не мешают")
            c.expectEqual(ExactTaskMatcher.strength(thread, against: FrontmostContext(bundleID: KnownBundleIDs.chatGPT, windowTitle: "План релиза")),
                          .title, "сила — название")
            c.expectNil(matchIndex(FrontmostContext(bundleID: KnownBundleIDs.chatGPT, windowTitle: "План отпуска"), d),
                        "другой тред — не задача")
            c.expectNil(matchIndex(FrontmostContext(bundleID: KnownBundleIDs.chatGPT, windowTitle: "ChatGPT"), d),
                        "окно без треда («ChatGPT») не совпадает и с привязкой «ChatGPT»")
            c.expectNil(matchIndex(FrontmostContext(bundleID: KnownBundleIDs.chatGPT), d), "заголовок не прочитан — не задача")
            c.expectNil(matchIndex(FrontmostContext(bundleID: "com.example.notes", windowTitle: "План релиза"), d),
                        "то же название в другом приложении — не задача")
            c.expectEqual(matchIndex(FrontmostContext(bundleID: KnownBundleIDs.chatGPT, windowTitle: "Переименован", chatGPTThreadID: "th-1"), d), 0,
                          "тот же id треда")
        }
    }

    static func toggleExactAppWindow(_ c: CheckRunner) {
        c.group("⌃⌥§: точное совпадение — окно приложения") {
            let grok = TaskBinding.appWindow(AppWindowRef(bundleID: KnownBundleIDs.grokBot, windowTitle: "Grok", appName: "Grok Bot"))
            let notes = TaskBinding.appWindow(AppWindowRef(bundleID: "com.example.notes", windowTitle: "Список - Notes"))
            let claudeWindow = TaskBinding.appWindow(AppWindowRef(bundleID: KnownBundleIDs.claude, windowTitle: "Claude"))
            let untitled = TaskBinding.appWindow(AppWindowRef(bundleID: "com.example.blank", windowTitle: ""))
            let d = doc([grok, notes, claudeWindow, untitled])
            c.expectEqual(matchIndex(FrontmostContext(bundleID: "COM.ANYSPHERE.SAND", windowTitle: " Grok "), d), 0,
                          "тот же bundle id и заголовок (заголовок из одного имени приложения сравнивается дословно)")
            c.expectEqual(matchIndex(FrontmostContext(bundleID: "com.example.notes", windowTitle: "список - Notes"), d), 1,
                          "очищенный заголовок без учёта регистра")
            c.expectNil(matchIndex(FrontmostContext(bundleID: "com.example.notes", windowTitle: "Другой"), d),
                        "то же приложение, другой заголовок — не задача")
            c.expectNil(matchIndex(FrontmostContext(bundleID: KnownBundleIDs.grokBot), d),
                        "без Accessibility (заголовок неизвестен) — не задача")
            c.expectNil(matchIndex(FrontmostContext(bundleID: "com.example.blank", windowTitle: ""), d),
                        "пустой заголовок не совпадает с пустым")
            c.expectNil(matchIndex(FrontmostContext(bundleID: "com.example.other", windowTitle: "Grok"), d),
                        "тот же заголовок в другом приложении — не задача")
            c.expectEqual(matchIndex(FrontmostContext(bundleID: KnownBundleIDs.claude, windowTitle: "Claude"), d), 2,
                          "окно Claude без прочитанного id — привязка «только окно» совпадает")
            c.expectNil(matchIndex(FrontmostContext(bundleID: KnownBundleIDs.claude, windowTitle: "Claude",
                                                    claudeConversationID: toggleUUID), d),
                        "в окне прочитан id чата — «только окно» не подставляется")
        }
    }

    static func toggleExactPriority(_ c: CheckRunner) {
        c.group("⌃⌥§: без запасной «последней активной», id важнее названия") {
            let a = TaskBinding.appWindow(AppWindowRef(bundleID: "com.example.one", windowTitle: "Один"))
            let d = doc([a, nil], active: 1)
            let unknown = FrontmostContext(bundleID: "com.example.unknown", windowTitle: "Что-то")
            c.expectEqual(CurrentTaskResolver.resolve(context: unknown, tasks: d.tasks, fallbackID: d.lastActiveTaskID), d.tasks[1].id,
                          "переключатель подставил бы последнюю активную…")
            c.expectNil(ExactTaskMatcher.match(context: unknown, document: d), "…а точное совпадение — нет")
            c.expectNil(ExactTaskMatcher.match(context: FrontmostContext(bundleID: "com.example.one", windowTitle: "Два"), document: d),
                        "«то же приложение» — не совпадение")
            c.expectNil(ExactTaskMatcher.match(context: .unknown, document: d), "пустой контекст")

            let byTitle = TaskBinding.chatGPTThread(ChatGPTThreadRef(threadID: "th-1", title: "Тред"))
            let byID = TaskBinding.chatGPTThread(ChatGPTThreadRef(threadID: "th-9", title: "Старое название"))
            let both = doc([byTitle, byID])
            let ctx = FrontmostContext(bundleID: KnownBundleIDs.chatGPT, windowTitle: "Тред", chatGPTThreadID: "th-9")
            c.expectEqual(matchIndex(ctx, both), 1, "совпадение по id важнее совпадения по названию")

            let twins = doc([byTitle, .chatGPTThread(ChatGPTThreadRef(threadID: "th-2", title: "Тред"))], active: 1)
            c.expectEqual(matchIndex(FrontmostContext(bundleID: KnownBundleIDs.chatGPT, windowTitle: "Тред"), twins), 1,
                          "равные совпадения — последняя активная из них")
            var noActive = twins
            noActive.lastActiveTaskID = nil
            c.expectEqual(matchIndex(FrontmostContext(bundleID: KnownBundleIDs.chatGPT, windowTitle: "Тред"), noActive), 0,
                          "иначе — первая по списку")
        }
    }

    static func toggleRemoval(_ c: CheckRunner) {
        c.group("⌃⌥§: удаление и возврат «как было»") {
            let t0 = Fixture.t0
            var original = doc([nil, .chatGPTThread(ChatGPTThreadRef(threadID: "th-1", title: "Тред")), nil], active: 1)
            original.tasks[1].note = "зачем / дальше"
            original.tasks[1].isDone = true
            original.tasks[1].lastVisitedAt = t0.addingTimeInterval(-600)
            let id = original.tasks[1].id

            var d = original
            let removed = TaskRemoval.remove(&d, id: id, now: t0, undoableByToggle: true)
            c.expectEqual(removed?.index, 1, "запомнена позиция")
            c.expectEqual(removed?.wasActive, true, "запомнено, что была текущей")
            c.expectEqual(removed?.task, original.tasks[1], "запомнена задача целиком")
            c.expectEqual(d.tasks.map(\.id), [original.tasks[0].id, original.tasks[2].id], "задача удалена из списка")
            c.expectNil(d.lastActiveTaskID, "отметка текущей снята")

            var restored = d
            c.expect(TaskRemoval.restore(removed!, into: &restored), "возврат выполнен")
            c.expectEqual(restored, original, "возвращена на место с id, заметкой, «сделано», привязкой, временем захода и отметкой текущей")
            c.expect(!TaskRemoval.restore(removed!, into: &restored), "повторный возврат не дублирует задачу")
            c.expectEqual(restored, original, "и ничего не меняет")

            var other = d
            other.lastActiveTaskID = other.tasks[0].id
            TaskRemoval.restore(removed!, into: &other)
            c.expectEqual(other.lastActiveTaskID, original.tasks[0].id, "текущая, выбранная после удаления, не перебивается")

            var shorter = d
            shorter.tasks.removeAll()
            TaskRemoval.restore(removed!, into: &shorter)
            c.expectEqual(shorter.tasks.map(\.id), [id], "список стал короче — задача в конце")

            var missing = original
            c.expectNil(TaskRemoval.remove(&missing, id: UUID(), now: t0, undoableByToggle: true), "нет такой задачи — нечего удалять")
            c.expectEqual(missing, original, "список не изменился")

            // Удаление сохраняется в tasks.json.
            let (store, dir) = Fixture.tempStore()
            defer { try? FileManager.default.removeItem(at: dir) }
            do {
                try store.save(d)
                c.expectEqual(store.load().document.tasks.map(\.id), d.tasks.map(\.id), "после удаления в tasks.json задачи нет")
                try store.save(restored)
                c.expectEqual(store.load().document, original, "после возврата tasks.json как до удаления")
            } catch {
                c.expect(false, "запись tasks.json: \(error)")
            }
        }
    }

    static func toggleUndoWindow(_ c: CheckRunner) {
        c.group("⌃⌥§: окно отмены 5 с") {
            let t0 = Fixture.t0
            let removed = RemovedTask(task: Fixture.task("Т"), index: 0, wasActive: false, removedAt: t0, undoableByToggle: true)
            c.expectEqual(TaskRemoval.undoWindow, 5, "окно — 5 с")
            c.expect(TaskRemoval.canUndoByToggle(removed, now: t0), "сразу после удаления")
            c.expect(TaskRemoval.canUndoByToggle(removed, now: t0.addingTimeInterval(4.9)), "через 4,9 с")
            c.expect(!TaskRemoval.canUndoByToggle(removed, now: t0.addingTimeInterval(5)), "через 5 с — уже нет")
            c.expect(!TaskRemoval.canUndoByToggle(removed, now: t0.addingTimeInterval(60)), "через минуту — нет")
            c.expect(!TaskRemoval.canUndoByToggle(removed, now: t0.addingTimeInterval(-1)), "часы ушли назад — нет")
            c.expect(!TaskRemoval.canUndoByToggle(nil, now: t0), "ничего не удалено — нет")
            var fromList = removed
            fromList.undoableByToggle = false
            c.expect(!TaskRemoval.canUndoByToggle(fromList, now: t0), "удалённую из списка меню хоткей не возвращает")
        }
    }

    static func toggleDecision(_ c: CheckRunner) {
        c.group("⌃⌥§: решение переключателя") {
            let t0 = Fixture.t0
            let binding = TaskBinding.appWindow(AppWindowRef(bundleID: "com.example.one", windowTitle: "Один"))
            let original = doc([nil, binding])
            let front = FrontmostContext(bundleID: "com.example.one", windowTitle: "Один")
            let elsewhere = FrontmostContext(bundleID: "com.example.two", windowTitle: "Два")

            c.expectEqual(TaskToggle.decide(document: original, lastRemoved: nil, now: t0) { front },
                          .remove(taskID: original.tasks[1].id, number: 2), "окно — задача → удалить")
            c.expectEqual(TaskToggle.decide(document: original, lastRemoved: nil, now: t0) { elsewhere },
                          .add(elsewhere), "окно — не задача → добавить (прежний сценарий)")

            var d = original
            let removed = TaskRemoval.remove(&d, id: original.tasks[1].id, now: t0, undoableByToggle: true)
            var contextRead = false
            let again = TaskToggle.decide(document: d, lastRemoved: removed, now: t0.addingTimeInterval(2)) {
                contextRead = true
                return elsewhere
            }
            c.expectEqual(again, .restore(removed!), "повтор в течение 5 с → вернуть (где бы ни был фокус)")
            c.expect(!contextRead, "контекст окна при возврате не читается")

            c.expectEqual(TaskToggle.decide(document: d, lastRemoved: removed, now: t0.addingTimeInterval(6)) { front },
                          .add(front), "через 5 с — обычный переключатель: окно снова добавляется")

            var fromList = removed!
            fromList.undoableByToggle = false
            c.expectEqual(TaskToggle.decide(document: d, lastRemoved: fromList, now: t0.addingTimeInterval(1)) { front },
                          .add(front), "после удаления из списка меню хоткей не возвращает")

            c.expectEqual(TaskToggle.decide(document: original, lastRemoved: removed, now: t0.addingTimeInterval(1)) { front },
                          .remove(taskID: original.tasks[1].id, number: 2), "задача уже на месте — возврата нет, обычный переключатель")
        }
    }

    static func toggleTexts(_ c: CheckRunner) {
        c.group("⌃⌥§: тексты") {
            let hotkey = Hotkey(keyCode: KeyCode.isoSection, modifiers: [.control, .option])
            c.expectEqual(TaskToggleTexts.removedCard(number: 2, title: "  План\nрелиза ", hotkey: hotkey),
                          "Задача 2 «План релиза» удалена — ⌃⌥§ в течение 5 с вернёт", "карточка удаления")
            c.expectEqual(TaskToggleTexts.removedCard(number: 1, title: "", hotkey: nil),
                          "Задача 1 «Без названия» удалена — вернуть: «Вернуть удалённую задачу» в меню Juggler",
                          "без назначенного хоткея — пункт меню")
            c.expectEqual(TaskToggleTexts.restoredCard(number: 3, title: "Тред"), "Задача 3 «Тред» возвращена", "карточка возврата")
            c.expectEqual(HotkeyAction.bindCurrentChat.displayName, "Добавить или удалить текущую задачу", "подпись в настройках хоткеев")
            c.expectEqual(TaskToggleTexts.restoreMenuTitle, "Вернуть удалённую задачу", "пункт меню возврата")
            let removed = RemovedTask(task: Fixture.task("Тред"), index: 1, wasActive: false, removedAt: Fixture.t0, undoableByToggle: true)
            c.expectEqual(TaskToggleTexts.restoreHelp(removed), "Вернуть «Тред» на место 2", "подсказка пункта возврата")
        }
    }
}
