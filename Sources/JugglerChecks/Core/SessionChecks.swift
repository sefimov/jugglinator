import Foundation
import JugglerCore

// Claude Code sessions (task SESSION): model, tasks.json compatibility, link parsing,
// current-task detection and the 1→2→3→1 cycle across sessions.

extension CoreChecks {
    static let sessionUUID = "fae5c400-6c06-4fa7-8cb8-eecc594fc296"
    static var sessionID: String { "local_\(sessionUUID)" }

    static func sessionChecks(_ c: CheckRunner) {
        sessionModelChecks(c)
        sessionLinkChecks(c)
        sessionResolverChecks(c)
    }

    static func sessionModelChecks(_ c: CheckRunner) {
        c.group("сессия Claude Code: модель и JSON") {
            let ref = ClaudeCodeSessionRef(sessionID: "LOCAL_\(sessionUUID.uppercased())", title: "Рефакторинг")
            c.expectEqual(ref.sessionID, sessionID, "id сессии хранится в нижнем регистре")
            c.expectEqual(ref.appURL.absoluteString, "claude://claude.ai/epitaxy/\(sessionID)", "ссылка для Claude desktop")
            let binding = TaskBinding.claudeCodeSession(ref)
            c.expectEqual(binding.source, .claudeCodeSession, "источник — сессия Claude Code")
            c.expectEqual(binding.title, "Рефакторинг", "заголовок привязки")

            let data = try JSONEncoder().encode(binding)
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            c.expectEqual(object?["kind"] as? String, "claudeCodeSession", "JSON: kind = claudeCodeSession")
            c.expectEqual((object?["claudeCodeSession"] as? [String: Any])?["sessionID"] as? String, sessionID, "JSON: sessionID в payload")
            c.expectEqual(try JSONDecoder().decode(TaskBinding.self, from: data), binding, "привязка-сессия переживает JSON")

            let noTitle = #"{"kind":"claudeCodeSession","claudeCodeSession":{"sessionID":"local_\#(sessionUUID)"}}"#
            c.expectEqual(try JSONDecoder().decode(TaskBinding.self, from: Data(noTitle.utf8)),
                          .claudeCodeSession(ClaudeCodeSessionRef(sessionID: sessionID)), "без title — пустое название")
            let noID = #"{"version":1,"tasks":[{"title":"Без id сессии","binding":{"kind":"claudeCodeSession","claudeCodeSession":{"title":"x"}}}]}"#
            let lenient = try TaskStore.decode(Data(noID.utf8))
            c.expectEqual(lenient.tasks.map(\.title), ["Без id сессии"], "сессия без id: задача читается")
            c.expectNil(lenient.tasks.first?.binding, "сессия без id → без привязки")
        }

        c.group("совместимость tasks.json") {
            // A file in the first-version format (before SESSION): all four old binding kinds.
            let legacy = """
            {"version":1,"lastActiveTaskID":"22222222-2222-2222-2222-222222222222","tasks":[
              {"id":"11111111-1111-1111-1111-111111111111","title":"Вкладка","note":"н","isDone":false,
               "createdAt":"2026-10-27T10:00:00.000Z","lastVisitedAt":"2026-10-27T10:01:00.000Z",
               "binding":{"kind":"chromeTab","chromeTab":{"tabID":5,"windowID":1,"url":"https://a.com","title":"A"}}},
              {"id":"22222222-2222-2222-2222-222222222222","title":"Чат","note":"","isDone":true,"createdAt":"2026-10-27T10:00:00.000Z",
               "binding":{"kind":"claudeChat","claudeChat":{"conversationID":"0f8fad5b-d9cb-469f-a165-70867728950e","title":"Чат - Claude"}}},
              {"id":"33333333-3333-3333-3333-333333333333","title":"Тред","note":"","isDone":false,"createdAt":"2026-10-27T10:00:00.000Z",
               "binding":{"kind":"chatGPTThread","chatGPTThread":{"threadID":"th-1","title":"Т"}}},
              {"id":"44444444-4444-4444-4444-444444444444","title":"Окно","note":"","isDone":false,"createdAt":"2026-10-27T10:00:00.000Z",
               "binding":{"kind":"appWindow","appWindow":{"bundleID":"com.anysphere.sand","windowTitle":"Grok","appName":"Grok Bot"}}},
              {"id":"55555555-5555-5555-5555-555555555555","title":"Пустая","note":"","isDone":false,"createdAt":"2026-10-27T10:00:00.000Z"}
            ]}
            """
            let doc = try TaskStore.decode(Data(legacy.utf8))
            c.expectEqual(doc.tasks.count, 5, "старый файл: все задачи прочитаны")
            c.expectEqual(doc.tasks.map { $0.binding?.source }, [.chromeTab, .claudeChat, .chatGPTThread, .appWindow, nil],
                          "старый файл: все привязки прочитаны")
            c.expectEqual(doc.tasks[1].binding, .claudeChat(ClaudeChatRef(conversationID: "0f8fad5b-d9cb-469f-a165-70867728950e", title: "Чат - Claude")),
                          "старый файл: чат Claude без потерь")
            c.expectEqual(doc.tasks[0].binding, .chromeTab(ChromeTabRef(tabID: 5, windowID: 1, url: "https://a.com", title: "A")),
                          "старый файл: вкладка без потерь")
            c.expectEqual(doc.lastActiveTaskID?.uuidString, "22222222-2222-2222-2222-222222222222", "старый файл: последняя активная")
            c.expect(doc.tasks[1].isDone && doc.tasks[0].note == "н", "старый файл: «сделано» и заметка")
            c.expectEqual(try TaskStore.decode(try TaskStore.encode(doc)), doc, "старый файл после перезаписи читается так же")

            var mixed = doc
            mixed.tasks.append(Fixture.task("Сессия", binding: .claudeCodeSession(ClaudeCodeSessionRef(sessionID: sessionID, title: "S"))))
            c.expectEqual(try TaskStore.decode(try TaskStore.encode(mixed)), mixed, "прежние привязки и сессия в одном файле")

            let unknown = #"{"version":1,"tasks":[{"title":"Из будущего","binding":{"kind":"claudeCloudSession","claudeCloudSession":{}}}]}"#
            let future = try TaskStore.decode(Data(unknown.utf8))
            c.expectEqual(future.tasks.map(\.title), ["Из будущего"], "неизвестный вид по-прежнему не роняет файл")
            c.expectNil(future.tasks.first?.binding, "неизвестный вид → без привязки")
        }
    }

    static func sessionLinkChecks(_ c: CheckRunner) {
        c.group("ссылки на сессии Claude Code") {
            let parse = ChatLinkParser.parse
            let session = ChatLink.claudeCodeSession(sessionID: sessionID)
            c.expectEqual(parse("https://claude.ai/epitaxy/\(sessionID)"), session, "https://claude.ai/epitaxy/local_<uuid>")
            c.expectEqual(parse("claude://claude.ai/epitaxy/\(sessionID)"), session, "claude://claude.ai/epitaxy/local_<uuid>")
            c.expectEqual(parse("claude://epitaxy/\(sessionID)"), session, "claude://epitaxy/local_<uuid>")
            c.expectEqual(parse(sessionID), session, "голый local_<uuid>")
            c.expectEqual(parse("  LOCAL_\(sessionUUID.uppercased())\n"), session, "голый id: верхний регистр и пробелы")
            c.expectEqual(parse("claude.ai/epitaxy/\(sessionID)/?x=1#y"), session, "без схемы, хвостовой /, query и fragment")
            c.expectEqual(parse("«https://www.claude.ai/epitaxy/\(sessionID)»"), session, "www и кавычки")
            c.expectEqual(session.source, .claudeCodeSession, "источник ссылки — сессия")
            c.expectEqual(session.appURL.absoluteString, "claude://claude.ai/epitaxy/\(sessionID)", "ссылка открытия сессии")

            c.expectNil(parse("https://claude.ai/epitaxy/\(sessionUUID)"), "epitaxy без local_ — не сессия")
            c.expectNil(parse("local_\(sessionUUID.dropLast())"), "local_ с неполным UUID")
            c.expectNil(parse("local_"), "local_ без UUID")
            c.expectNil(parse("remote_\(sessionUUID)"), "другой префикс")
            c.expectNil(parse("https://claude.ai/epitaxy/\(sessionID)/extra"), "лишний сегмент после id")
            c.expectNil(parse("https://claude.ai/chat/\(sessionID)"), "id сессии в /chat/ — не чат")
            c.expectNil(parse("https://evil.example/epitaxy/\(sessionID)"), "чужой хост")
            c.expectNil(parse("file:///Applications/Claude.app/Contents/Resources/index.html"), "адрес оболочки Claude — не сессия")
            c.expect(ChatLinkParser.isClaudeCodeSessionID("LOCAL_\(sessionUUID)"), "isClaudeCodeSessionID без учёта регистра")
            c.expect(!ChatLinkParser.isClaudeCodeSessionID("../\(sessionID)"), "id с путём — не id сессии")
            // The old chat behavior is unchanged.
            c.expectEqual(parse("claude://claude.ai/chat/\(sessionUUID)"), .claude(conversationID: sessionUUID), "чат Claude по-прежнему чат")
            c.expectEqual(parse(sessionUUID), .claude(conversationID: sessionUUID), "голый UUID по-прежнему чат")
        }

        c.group("ссылки «Поделиться» Claude") {
            let share = "https://claude.ai/share/0b6a1f53-1c2e-4f1e-9a1d-2b4c6d8e0f12"
            c.expect(ChatLinkParser.isClaudeShareLink(share), "claude.ai/share/<id> распознаётся")
            c.expect(ChatLinkParser.isClaudeShareLink(" claude.ai/share/abc?utm=1 "), "без схемы, с query")
            c.expect(ChatLinkParser.isClaudeShareLink("https://www.claude.ai/share/abc"), "www")
            c.expectNil(ChatLinkParser.parse(share), "ссылка «Поделиться» — не чат")
            c.expect(!ChatLinkParser.isClaudeShareLink("https://claude.ai/share"), "без id — не ссылка «Поделиться»")
            c.expect(!ChatLinkParser.isClaudeShareLink("https://claude.ai/chat/\(sessionUUID)"), "ссылка на чат — не «Поделиться»")
            c.expect(!ChatLinkParser.isClaudeShareLink("https://example.com/share/abc"), "чужой хост")
            c.expect(!ChatLinkParser.isClaudeShareLink("claude://claude.ai/share/abc"), "схема claude:// — не веб-ссылка «Поделиться»")
        }
    }

    static func sessionResolverChecks(_ c: CheckRunner) {
        c.group("текущая задача: сессии Claude Code") {
            let ids = ["11111111-aaaa-4aaa-8aaa-aaaaaaaaaaaa", "22222222-bbbb-4bbb-8bbb-bbbbbbbbbbbb", "33333333-cccc-4ccc-8ccc-cccccccccccc"]
                .map { "local_\($0)" }
            let chatUUID = "0f8fad5b-d9cb-469f-a165-70867728950e"
            let s1 = Fixture.task("s1", binding: .claudeCodeSession(ClaudeCodeSessionRef(sessionID: ids[0], title: "Первая")))
            let s2 = Fixture.task("s2", binding: .claudeCodeSession(ClaudeCodeSessionRef(sessionID: ids[1], title: "Вторая")))
            let s3 = Fixture.task("s3", binding: .claudeCodeSession(ClaudeCodeSessionRef(sessionID: ids[2], title: "Третья")))
            let chat = Fixture.task("chat", binding: .claudeChat(ClaudeChatRef(conversationID: chatUUID, title: "Чат - Claude")))
            let tasks = [s1, s2, s3]
            func ctx(_ session: String?, chat: String? = nil) -> FrontmostContext {
                FrontmostContext(bundleID: KnownBundleIDs.claude, windowTitle: "Claude", claudeConversationID: chat, claudeCodeSessionID: session)
            }
            func resolve(_ context: FrontmostContext, _ list: [JugglerTask] = tasks, fallback: UUID? = nil) -> UUID? {
                CurrentTaskResolver.resolve(context: context, tasks: list, fallbackID: fallback)
            }

            c.expectEqual(resolve(ctx(ids[1]), fallback: s1.id), s2.id, "по id сессии, а не по последней активной")
            c.expectEqual(resolve(ctx(ids[2].uppercased())), s3.id, "id сессии без учёта регистра")
            c.expectEqual(CurrentTaskResolver.score(s1.binding!, against: ctx(ids[0])), .sameID, "своя сессия — sameID")
            c.expectEqual(CurrentTaskResolver.score(s1.binding!, against: ctx(ids[1])), .sameApp, "чужая сессия в Claude — только приложение")
            c.expectEqual(CurrentTaskResolver.score(s1.binding!, against: FrontmostContext(bundleID: KnownBundleIDs.chrome)), .none,
                          "не Claude — нет совпадения")
            c.expectEqual(resolve(ctx("local_44444444-dddd-4ddd-8ddd-dddddddddddd"), fallback: s2.id), s2.id,
                          "непривязанная сессия впереди → последняя активная")

            let mixed = [chat, s1]
            c.expectEqual(resolve(ctx(ids[0]), mixed, fallback: chat.id), s1.id, "сессия не путается с чатом Claude")
            c.expectEqual(resolve(ctx(nil, chat: chatUUID), mixed, fallback: s1.id), chat.id, "чат по UUID, как раньше")

            // Cycle 1→2→3→1: after each switch the opened session is in front, current is found by its id.
            var front = ids[0]
            var visited: [UUID] = []
            var lastActive: UUID? = s1.id
            for _ in 0..<3 {
                let current = resolve(ctx(front), fallback: lastActive)
                guard let next = TaskCycler.neighbor(of: current, in: tasks, direction: .next),
                      case .claudeCodeSession(let ref)? = next.binding else { break }
                visited.append(next.id)
                lastActive = next.id
                front = ref.sessionID
            }
            c.expectEqual(visited, [s2.id, s3.id, s1.id], "круг 1→2→3→1 по сессиям Claude Code")

            // The last active one is stale (the user opened session 3 themselves): the cycle starts from the front window.
            let fromFront = TaskCycler.neighbor(of: resolve(ctx(ids[2]), fallback: s1.id), in: tasks, direction: .next)
            c.expectEqual(fromFront?.id, s1.id, "следующая считается от сессии в переднем окне")
        }
    }
}
