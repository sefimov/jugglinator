import Foundation
import JugglerCore

extension CoreChecks {
    static func modelChecks(_ c: CheckRunner) {
        c.group("модель") {
            let a = Fixture.task("A"), b = Fixture.task("B")
            var doc = TasksDocument(tasks: [a, b])
            c.expectEqual(doc.number(of: b.id), 2, "номер задачи — позиция с 1")
            c.expectNil(doc.number(of: UUID()), "номер неизвестной задачи — nil")

            let visited = Fixture.t0.addingTimeInterval(60)
            c.expect(doc.markVisited(b.id, at: visited), "markVisited известной задачи")
            c.expectEqual(doc.tasks[1].lastVisitedAt, visited, "markVisited ставит время захода")
            c.expectEqual(doc.lastActiveTaskID, b.id, "markVisited ставит последнюю активную")
            c.expect(!doc.markVisited(UUID(), at: visited), "markVisited неизвестной задачи → false")

            var dup = TasksDocument(tasks: [a, a, b], lastActiveTaskID: UUID())
            dup.normalize()
            c.expectEqual(dup.tasks.map(\.id), [a.id, b.id], "normalize убирает дубликаты id")
            c.expectNil(dup.lastActiveTaskID, "normalize сбрасывает висячую последнюю активную")
        }

        c.group("кодирование привязок") {
            let bindings: [TaskBinding] = [
                .chromeTab(ChromeTabRef(tabID: 42, windowID: 7, url: "https://example.com/a", title: "Пример")),
                .claudeChat(ClaudeChatRef(conversationID: "0F8FAD5B-D9CB-469F-A165-70867728950E", title: "Чат")),
                .chatGPTThread(ChatGPTThreadRef(threadID: "abc_123", title: "Тред")),
                .appWindow(AppWindowRef(bundleID: "com.example.grok", windowTitle: "Grok", appName: "Grok Bot")),
            ]
            let tasks = bindings.map { Fixture.task("T", binding: $0) } + [Fixture.task("без привязки")]
            let doc = TasksDocument(tasks: tasks, lastActiveTaskID: tasks[2].id)
            let decoded = try TaskStore.decode(try TaskStore.encode(doc))
            c.expectEqual(decoded, doc, "документ со всеми видами привязок переживает JSON")
            c.expectEqual(ClaudeChatRef(conversationID: "0F8FAD5B-D9CB-469F-A165-70867728950E").conversationID,
                          "0f8fad5b-d9cb-469f-a165-70867728950e", "UUID чата Claude хранится в нижнем регистре")

            let json = """
            {"version":1,"tasks":[
              {"id":"11111111-1111-1111-1111-111111111111","title":"Старая","binding":{"kind":"telegram","telegram":{}}},
              {"title":"Без id"},
              42
            ]}
            """
            let lossy = try TaskStore.decode(Data(json.utf8))
            c.expectEqual(lossy.tasks.count, 2, "битый элемент списка пропускается, остальные читаются")
            c.expectNil(lossy.tasks.first?.binding, "неизвестный вид привязки → задача без привязки")
            c.expectEqual(lossy.tasks.last?.note, "", "отсутствующие поля получают значения по умолчанию")
        }
    }
}
