import Foundation
import JugglerCore

extension CoreChecks {
    static func cyclerChecks(_ c: CheckRunner) {
        c.group("круговой выбор") {
            let t1 = Fixture.task("1"), t2 = Fixture.task("2"), t3 = Fixture.task("3")
            let tasks = [t1, t2, t3]
            func next(_ id: UUID?, _ list: [JugglerTask] = tasks) -> UUID? {
                TaskCycler.neighbor(of: id, in: list, direction: .next)?.id
            }
            func prev(_ id: UUID?, _ list: [JugglerTask] = tasks) -> UUID? {
                TaskCycler.neighbor(of: id, in: list, direction: .previous)?.id
            }

            c.expectEqual([next(t1.id), next(t2.id), next(t3.id)], [t2.id, t3.id, t1.id], "следующая: 1→2→3→1")
            c.expectEqual([prev(t1.id), prev(t2.id), prev(t3.id)], [t3.id, t1.id, t2.id], "предыдущая: 1→3→2→1")
            c.expectEqual(next(nil), t1.id, "текущая неизвестна: следующая — первая")
            c.expectEqual(prev(nil), t3.id, "текущая неизвестна: предыдущая — последняя")
            c.expectEqual(next(UUID()), t1.id, "текущей нет в списке: следующая — первая")

            let withDone = [t1, Fixture.task("2", done: true), t3]
            c.expectEqual(next(t1.id, withDone), t3.id, "«сделано» пропускается вперёд")
            c.expectEqual(prev(t3.id, withDone), t1.id, "«сделано» пропускается назад")

            let doneFirst = [Fixture.task("1", done: true), t2, t3]
            c.expectEqual(next(nil, doneFirst), t2.id, "без текущей: первая несделанная")
            c.expectEqual(next(t3.id, doneFirst), t2.id, "с конца по кругу через сделанную")

            var currentDone = t2
            currentDone.isDone = true
            c.expectEqual(next(t2.id, [t1, currentDone, t3]), t3.id, "текущая сама «сделано»: отсчёт от её позиции")

            let single = [Fixture.task("1", done: true), t2, Fixture.task("3", done: true)]
            c.expectEqual(next(t2.id, single), t2.id, "единственная несделанная и текущая → она же")
            c.expectNil(next(t1.id, tasks.map { var t = $0; t.isDone = true; return t }), "все «сделано» → nil")
            c.expectNil(next(nil, []), "пустой список → nil")
            c.expectEqual(next(t1.id, [t1]), t1.id, "одна задача → она же")
        }
    }

    static func resolverChecks(_ c: CheckRunner) {
        c.group("текущая задача по переднему окну") {
            let uuid = "0f8fad5b-d9cb-469f-a165-70867728950e"
            let chrome = Fixture.task("chrome", binding: .chromeTab(ChromeTabRef(tabID: 10, url: "https://example.com/doc#top", title: "Док")))
            let claude = Fixture.task("claude", binding: .claudeChat(ClaudeChatRef(conversationID: uuid, title: "План релиза")))
            let gpt = Fixture.task("gpt", binding: .chatGPTThread(ChatGPTThreadRef(threadID: "th-1", title: "Код")))
            let grokA = Fixture.task("grokA", binding: .appWindow(AppWindowRef(bundleID: "com.x.grok", windowTitle: "Исследование")))
            let grokB = Fixture.task("grokB", binding: .appWindow(AppWindowRef(bundleID: "com.x.grok", windowTitle: "Перевод")))
            let plain = Fixture.task("без привязки")
            let tasks = [chrome, claude, gpt, grokA, grokB, plain]
            func resolve(_ ctx: FrontmostContext, fallback: UUID? = nil) -> UUID? {
                CurrentTaskResolver.resolve(context: ctx, tasks: tasks, fallbackID: fallback)
            }

            let chromeCtx = { (id: Int?, url: String) in
                FrontmostContext(bundleID: KnownBundleIDs.chrome, chromeTab: ChromeTabRef(tabID: id, url: url))
            }
            c.expectEqual(resolve(chromeCtx(10, "https://other.example")), chrome.id, "Chrome: совпал id вкладки")
            c.expectEqual(resolve(chromeCtx(99, "https://EXAMPLE.com/doc/")), chrome.id, "Chrome: id другой, адрес совпал после нормализации")
            c.expectNil(resolve(chromeCtx(99, "https://example.com/other")), "Chrome: чужая вкладка → nil")

            c.expectEqual(resolve(FrontmostContext(bundleID: KnownBundleIDs.claude, claudeConversationID: uuid.uppercased())),
                          claude.id, "Claude: совпал UUID чата без учёта регистра")
            c.expectEqual(resolve(chromeCtx(5, "https://claude.ai/chat/\(uuid)")), claude.id, "Claude в браузере: UUID из адреса вкладки")
            c.expectEqual(resolve(FrontmostContext(bundleID: KnownBundleIDs.claude, windowTitle: "План релиза - Claude")),
                          claude.id, "Claude: без UUID — по очищенному заголовку окна")

            c.expectEqual(resolve(FrontmostContext(bundleID: KnownBundleIDs.chatGPT, chatGPTThreadID: "th-1")), gpt.id, "ChatGPT: совпал id треда")
            c.expectEqual(resolve(FrontmostContext(bundleID: "COM.X.GROK", windowTitle: "Перевод")), grokB.id, "окно: bundle id без регистра и заголовок")
            c.expectEqual(resolve(FrontmostContext(bundleID: "com.x.grok", windowTitle: "Другое")), grokA.id, "окно: только приложение → первая по порядку")
            c.expectEqual(resolve(FrontmostContext(bundleID: "com.x.grok", windowTitle: "Другое"), fallback: grokB.id), grokB.id,
                          "окно: при равенстве выигрывает последняя активная")
            c.expectEqual(resolve(FrontmostContext(bundleID: "com.apple.finder"), fallback: plain.id), plain.id,
                          "нет совпадений → последняя активная")
            c.expectNil(resolve(FrontmostContext(bundleID: "com.apple.finder"), fallback: UUID()), "запасная задача не из списка → nil")
            c.expectNil(resolve(.unknown), "пустой контекст без запасной → nil")
        }
    }
}
