import Foundation
import JugglerCore

// Checks for the pure MCP logic (Sources/JugglerCore/MCP/): JSON values, JSON-RPC parsing,
// the handshake, tool schemas, task selection, tool results and the config snippets.

enum MCPChecks: CheckSuite {
    static let name = "MCP"

    static func run(_ c: CheckRunner) {
        jsonValueChecks(c)
        jsonRPCChecks(c)
        handshakeChecks(c)
        toolListChecks(c)
        selectorChecks(c)
        toolCallChecks(c)
        unavailableChecks(c)
        configChecks(c)
    }

    // MARK: - Fixtures

    static let winOne = TaskBinding.appWindow(AppWindowRef(bundleID: "com.example.one", windowTitle: "Один"))
    static let thread = TaskBinding.chatGPTThread(ChatGPTThreadRef(threadID: "th-2", title: "Два"))

    static func document() -> TasksDocument {
        let t0 = Fixture.t0
        let tasks = [
            JugglerTask(title: "Первая", note: " дальше: ответить\n", lastVisitedAt: t0.addingTimeInterval(-25 * 60), createdAt: t0, binding: winOne),
            JugglerTask(title: "Вторая", isDone: true, createdAt: t0, binding: thread),
            JugglerTask(title: "Третья", lastVisitedAt: t0.addingTimeInterval(-30), createdAt: t0),
        ]
        return TasksDocument(tasks: tasks, lastActiveTaskID: tasks[2].id)
    }

    /// Records what the tools asked for; `switchOutcome` and `addOutcome` are what it answers.
    final class FakeBackend: MCPTaskBackend {
        var doc: TasksDocument
        var now: Date
        var current: UUID?
        var switched: [UUID] = []
        var switchOutcome = MCPActionOutcome.done(warning: nil)
        var addOutcome: MCPAddOutcome

        init(doc: TasksDocument, now: Date = Fixture.t0, current: UUID?) {
            self.doc = doc
            self.now = now
            self.current = current
            self.addOutcome = .failed("нет окна")
        }

        func snapshot() -> MCPSnapshot { MCPSnapshot(document: doc, now: now, currentTaskID: current) }

        func switchToTask(id: UUID) -> MCPActionOutcome {
            switched.append(id)
            if case .done = switchOutcome { doc.markVisited(id, at: now); current = id }
            return switchOutcome
        }

        func addCurrentWindow() -> MCPAddOutcome {
            if case .added = addOutcome {
                let id = BindPlanner.createTask(in: &doc, title: "Новое", binding: .appWindow(AppWindowRef(bundleID: "com.example.new", windowTitle: "Новое")), now: now)
                current = id
                return .added(id)
            }
            return addOutcome
        }

        func setDone(id: UUID, _ done: Bool) -> Bool {
            guard doc.task(withID: id) != nil else { return false }
            TaskListOps.setDone(&doc, id: id, done)
            return true
        }

        func setNote(id: UUID, _ note: String) -> Bool {
            guard doc.task(withID: id) != nil else { return false }
            TaskListOps.setNote(&doc, id: id, to: note)
            return true
        }
    }

    static func request(_ id: Int, _ method: String, _ params: JSONValue? = nil) -> JSONRPCRequest {
        JSONRPCRequest(id: .number(Double(id)), method: method, params: params)
    }

    static func call(_ handler: MCPRequestHandler, _ tool: String, _ arguments: JSONValue? = nil) -> JSONValue? {
        var params: [String: JSONValue] = ["name": .string(tool)]
        if let arguments { params["arguments"] = arguments }
        return handler.handle(request(9, "tools/call", .object(params)))?["result"]
    }

    static func text(_ result: JSONValue?) -> String {
        result?["content"]?.arrayValue?.first?["text"]?.stringValue ?? ""
    }

    // MARK: - JSONValue

    static func jsonValueChecks(_ c: CheckRunner) {
        c.group("JSON: разбор и запись") {
            let parsed = JSONValue(text: #"{"b":true,"n":3,"f":2.5,"s":"тест","a":[1,null],"o":{"k":"v"}}"#)
            c.expectEqual(parsed?["b"], .bool(true), "булево остаётся булевым")
            c.expectEqual(parsed?["n"]?.intValue, 3, "целое число")
            c.expectNil(parsed?["f"]?.intValue, "дробное — не целое")
            c.expectEqual(parsed?["f"]?.doubleValue, 2.5, "дробное число")
            c.expectEqual(parsed?["s"]?.stringValue, "тест", "строка")
            c.expectEqual(parsed?["a"], [1, nil], "массив с null")
            c.expectEqual(parsed?["o"]?["k"], "v", "вложенный объект")
            c.expectEqual(parsed?.text(), #"{"a":[1,null],"b":true,"f":2.5,"n":3,"o":{"k":"v"},"s":"тест"}"#, "запись: ключи отсортированы, 3 без .0")
            c.expectNil(JSONValue(text: "{nope"), "битый JSON → nil")
            c.expectEqual(JSONValue(text: "42")?.intValue, 42, "фрагмент: число")
            c.expectEqual(JSONValue.int(nil), .null, "int(nil) → null")
            c.expectEqual(JSONValue.string("x"), .string("x"), "string(\"x\")")
            c.expectEqual(JSONValue(text: "[1,2]")?.arrayValue?.count, 2, "массив верхнего уровня")
        }
    }

    // MARK: - JSON-RPC

    static func jsonRPCChecks(_ c: CheckRunner) {
        c.group("JSON-RPC: разбор запросов") {
            c.expectEqual(JSONRPC.parse(#"{"jsonrpc":"2.0","id":1,"method":"ping"}"#),
                          .success(JSONRPCRequest(id: 1, method: "ping")), "запрос с числовым id")
            c.expectEqual(JSONRPC.parse(#"{"jsonrpc":"2.0","id":"a","method":"x","params":{"p":1}}"#),
                          .success(JSONRPCRequest(id: "a", method: "x", params: ["p": 1])), "строковый id и параметры")
            c.expectEqual(JSONRPC.parse(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#),
                          .success(JSONRPCRequest(id: nil, method: "notifications/initialized")), "уведомление без id")
            if case .failure(let e) = JSONRPC.parse("[]") { c.expectEqual(e.code, JSONRPCError.invalidRequest, "пакет (массив) отвергается") } else { c.expect(false, "пакет (массив) отвергается") }
            if case .failure(let e) = JSONRPC.parse(#"{"jsonrpc":"1.0","id":1,"method":"ping"}"#) { c.expectEqual(e.code, JSONRPCError.invalidRequest, "не 2.0") } else { c.expect(false, "не 2.0") }
            if case .failure(let e) = JSONRPC.parse(#"{"jsonrpc":"2.0","id":1}"#) { c.expectEqual(e.code, JSONRPCError.invalidRequest, "без method") } else { c.expect(false, "без method") }
            if case .failure(let e) = JSONRPC.parse(#"{"jsonrpc":"2.0","id":1,"method":"m","params":"x"}"#) { c.expectEqual(e.code, JSONRPCError.invalidRequest, "params не объект") } else { c.expect(false, "params не объект") }
            if case .failure(let e) = JSONRPC.parse("{") { c.expectEqual(e.code, JSONRPCError.parseError, "битый JSON → parse error") } else { c.expect(false, "битый JSON → parse error") }
            c.expectEqual(JSONRPC.requestID(of: #"{"id":7,"method":"m"}"#), 7, "id из строки без проверки")
            c.expectNil(JSONRPC.requestID(of: #"{"method":"m"}"#), "нет id → nil")
            c.expectEqual(JSONRPC.response(id: 1, result: ["ok": true]).text(), #"{"id":1,"jsonrpc":"2.0","result":{"ok":true}}"#, "ответ")
            c.expectEqual(JSONRPC.errorResponse(id: nil, error: .methodNotFound("x")).text(),
                          #"{"error":{"code":-32601,"message":"Method not found: x"},"id":null,"jsonrpc":"2.0"}"#, "ошибка с null id")
        }
    }

    // MARK: - Handshake

    static func handshakeChecks(_ c: CheckRunner) {
        c.group("MCP: рукопожатие") {
            let handler = MCPRequestHandler(backend: FakeBackend(doc: document(), current: nil), serverVersion: "1.2.3")
            let result = handler.handle(request(1, "initialize", ["protocolVersion": "2025-06-18", "clientInfo": ["name": "test"]]))
            c.expectEqual(result?["id"], 1, "ответ с тем же id")
            c.expectEqual(result?["result"]?["protocolVersion"], "2025-06-18", "версия протокола")
            c.expectEqual(result?["result"]?["serverInfo"]?["name"], "juggler", "имя сервера")
            c.expectEqual(result?["result"]?["serverInfo"]?["version"], "1.2.3", "версия приложения")
            c.expect(result?["result"]?["capabilities"]?["tools"] != nil, "заявлены инструменты")
            c.expect(result?["result"]?["instructions"]?.stringValue?.contains("list_tasks") == true, "инструкция упоминает list_tasks")
            c.expectEqual(handler.clientInfo?["name"], "test", "clientInfo запомнен")

            let older = MCPRequestHandler(backend: nil, serverVersion: "x")
            c.expectEqual(older.handle(request(1, "initialize", ["protocolVersion": "2024-11-05"]))?["result"]?["protocolVersion"], "2024-11-05",
                          "поддерживаемая старая версия возвращается как есть")
            c.expectEqual(older.handle(request(1, "initialize", ["protocolVersion": "1999-01-01"]))?["result"]?["protocolVersion"], "2025-06-18",
                          "неизвестная версия → наша")
            c.expectEqual(older.handle(request(1, "initialize"))?["result"]?["protocolVersion"], "2025-06-18", "без версии → наша")

            c.expect(!handler.isInitialized, "до уведомления не инициализирован")
            c.expectNil(handler.handle(JSONRPCRequest(id: nil, method: "notifications/initialized")), "уведомление без ответа")
            c.expect(handler.isInitialized, "после уведомления инициализирован")
            c.expectNil(handler.handle(JSONRPCRequest(id: nil, method: "notifications/cancelled")), "другие уведомления игнорируются")
            c.expectEqual(handler.handle(request(2, "ping"))?["result"], [:], "ping → {}")
            c.expectEqual(handler.handle(request(3, "resources/list"))?["error"]?["code"]?.intValue, JSONRPCError.methodNotFound, "неизвестный метод")
            c.expectEqual(handler.handle(line: "  \n"), nil, "пустая строка игнорируется")
            c.expect(handler.handle(line: "{bad")?.contains(#""code":-32700"#) == true, "битая строка → parse error")
            c.expect(handler.handle(line: #"{"jsonrpc":"2.0","id":5,"method":"nope"}"#)?.contains(#""id":5"#) == true, "ответ строкой с тем же id")
        }
    }

    // MARK: - tools/list

    static func toolListChecks(_ c: CheckRunner) {
        c.group("MCP: tools/list") {
            let handler = MCPRequestHandler(backend: nil, serverVersion: "x")
            let tools = handler.handle(request(1, "tools/list"))?["result"]?["tools"]?.arrayValue ?? []
            c.expectEqual(tools.map { $0["name"]?.stringValue ?? "" },
                          ["list_tasks", "switch_to_task", "add_current_window", "mark_done", "mark_in_progress", "set_note"], "шесть инструментов")
            for tool in tools {
                let name = tool["name"]?.stringValue ?? "?"
                c.expect(!(tool["description"]?.stringValue ?? "").isEmpty, "\(name): есть описание")
                c.expectEqual(tool["inputSchema"]?["type"], "object", "\(name): схема — объект")
                c.expect(tool["annotations"]?["readOnlyHint"]?.boolValue != nil, "\(name): есть аннотации")
            }
            let selector = tools.first { $0["name"] == "switch_to_task" }?["inputSchema"]?["properties"]
            c.expectEqual(selector?["number"]?["type"], "integer", "switch_to_task: number — integer")
            c.expectEqual(selector?["id"]?["type"], "string", "switch_to_task: id — string")
            let note = tools.first { $0["name"] == "set_note" }?["inputSchema"]
            c.expectEqual(note?["required"], ["note"], "set_note: note обязателен")
            c.expectEqual(note?["properties"]?["note"]?["type"], "string", "set_note: note — string")
            c.expectEqual(tools.first { $0["name"] == "list_tasks" }?["annotations"]?["readOnlyHint"], true, "list_tasks — только чтение")
            c.expectEqual(tools.first { $0["name"] == "mark_done" }?["annotations"]?["readOnlyHint"], false, "mark_done — меняет")
            c.expectEqual(MCPTools.definition(named: "set_note")?.title, "Set a task's note", "definition(named:)")
            c.expectNil(MCPTools.definition(named: "nope"), "неизвестное имя → nil")
        }
    }

    // MARK: - Task selection

    static func selectorChecks(_ c: CheckRunner) {
        c.group("MCP: выбор задачи по number или id") {
            let d = document()
            c.expectEqual(MCPTools.resolveTask(["number": 2], in: d), .task(d.tasks[1].id), "по номеру")
            c.expectEqual(MCPTools.resolveTask(["number": "3"], in: d), .task(d.tasks[2].id), "номер строкой")
            c.expectEqual(MCPTools.resolveTask(["id": .string(d.tasks[0].id.uuidString.lowercased())], in: d), .task(d.tasks[0].id), "по id в нижнем регистре")
            c.expectEqual(MCPTools.resolveTask(["id": .string(d.tasks[0].id.uuidString)], in: d), .task(d.tasks[0].id), "по id в верхнем регистре")
            c.expectEqual(MCPTools.resolveTask(["number": 1, "id": "garbage"], in: d), .task(d.tasks[0].id), "номер важнее id")
            c.expectEqual(MCPTools.resolveTask(["number": 4], in: d), .invalid("There is no task 4: the list has 3 tasks (1…3)."), "номер больше списка")
            c.expectEqual(MCPTools.resolveTask(["number": 0], in: d), .invalid("There is no task 0: the list has 3 tasks (1…3)."), "номер 0")
            c.expectEqual(MCPTools.resolveTask(["number": 1], in: TasksDocument()), .invalid("The task list is empty."), "пустой список")
            c.expectEqual(MCPTools.resolveTask(["number": 1.5], in: d), .invalid("Argument number must be an integer, got 1.5."), "дробный номер")
            if case .invalid(let m) = MCPTools.resolveTask(["id": "not-a-uuid"], in: d) { c.expect(m.hasPrefix("Argument id must be a UUID"), "не UUID") } else { c.expect(false, "не UUID") }
            if case .invalid(let m) = MCPTools.resolveTask(["id": .string(UUID().uuidString)], in: d) { c.expect(m.contains("no task with id"), "чужой id") } else { c.expect(false, "чужой id") }
            c.expectEqual(MCPTools.resolveTask([:], in: d), .invalid("Pass the task as number (1-based) or id (UUID) from list_tasks."), "без аргументов")
            c.expectEqual(MCPTools.resolveTask(["number": nil], in: d), .invalid("Pass the task as number (1-based) or id (UUID) from list_tasks."), "number: null — как без аргумента")
        }
    }

    // MARK: - tools/call

    static func toolCallChecks(_ c: CheckRunner) {
        c.group("MCP: list_tasks") {
            let d = document()
            let backend = FakeBackend(doc: d, current: d.tasks[0].id)
            let handler = MCPRequestHandler(backend: backend, serverVersion: "x")
            let result = call(handler, "list_tasks", [:])
            c.expectNil(result?["isError"], "не ошибка")
            let tasks = result?["structuredContent"]?["tasks"]?.arrayValue ?? []
            c.expectEqual(tasks.count, 3, "три задачи")
            c.expectEqual(tasks.first, [
                "number": 1, "id": .string(d.tasks[0].id.uuidString.lowercased()), "title": "Первая", "note": " дальше: ответить\n",
                "done": false, "binding": "appWindow", "binding_title": "Один", "minutes_since_visit": 25, "is_current": true,
            ], "поля первой задачи")
            c.expectEqual(tasks[1]["binding"], "chatGPTThread", "вид привязки ChatGPT")
            c.expectEqual(tasks[1]["done"], true, "сделанная")
            c.expectEqual(tasks[1]["minutes_since_visit"], .null, "без заходов — null")
            c.expectEqual(tasks[2]["binding"], .null, "без привязки — null")
            c.expectEqual(tasks[2]["minutes_since_visit"], 0, "меньше минуты — 0")
            c.expectEqual(result?["structuredContent"]?["current_number"], 1, "номер текущей")
            c.expectEqual(result?["structuredContent"]?["count"], 3, "количество")
            let text = text(result)
            c.expect(text.hasPrefix("3 tasks, current: 1:"), "текст: заголовок")
            c.expect(text.contains("1. Первая [current] · appWindow · away 25 min\n   note: дальше: ответить"), "текст: первая строка с заметкой")
            c.expect(text.contains("2. Вторая [done] · chatGPTThread · never visited"), "текст: сделанная без заходов")
            c.expect(text.contains("3. Третья · visited just now"), "текст: без привязки")

            let empty = call(MCPRequestHandler(backend: FakeBackend(doc: TasksDocument(), current: nil), serverVersion: "x"), "list_tasks")
            c.expectEqual(self.text(empty), "The Juggler task list is empty.", "пустой список — текст")
            c.expectEqual(empty?["structuredContent"]?["current_number"], .null, "пустой список — нет текущей")
        }

        c.group("MCP: switch_to_task") {
            let d = document()
            let backend = FakeBackend(doc: d, current: d.tasks[0].id)
            let handler = MCPRequestHandler(backend: backend, serverVersion: "x")
            let result = call(handler, "switch_to_task", ["number": 3])
            c.expectEqual(backend.switched, [d.tasks[2].id], "переключение на третью")
            c.expectEqual(text(result), "Switched to task 3 «Третья».", "текст")
            c.expectEqual(result?["structuredContent"]?["task"]?["is_current"], true, "после переключения она текущая")
            c.expectNil(result?["structuredContent"]?["warning"], "без предупреждения")

            backend.switchOutcome = .done(warning: "Вкладка найдена по адресу.")
            let warned = call(handler, "switch_to_task", ["id": .string(d.tasks[0].id.uuidString)])
            c.expectEqual(text(warned), "Switched to task 1 «Первая». Note: Вкладка найдена по адресу.", "предупреждение от BIND в тексте")
            c.expectEqual(warned?["structuredContent"]?["warning"], "Вкладка найдена по адресу.", "предупреждение в данных")

            backend.switchOutcome = .failed("окно закрыто")
            let failed = call(handler, "switch_to_task", ["number": 2])
            c.expectEqual(failed?["isError"], true, "отказ → isError")
            c.expectEqual(text(failed), "Could not switch to task 2 «Вторая»: окно закрыто", "текст отказа")

            let wrong = call(handler, "switch_to_task", ["number": 7])
            c.expectEqual(wrong?["isError"], true, "неверный номер → isError")
            c.expectEqual(backend.switched.count, 3, "неверный номер не переключает")
            c.expectEqual(call(handler, "switch_to_task")?["isError"], true, "без аргументов → isError")
        }

        c.group("MCP: add_current_window") {
            let d = document()
            let backend = FakeBackend(doc: d, current: nil)
            let handler = MCPRequestHandler(backend: backend, serverVersion: "x")
            let failed = call(handler, "add_current_window")
            c.expectEqual(failed?["isError"], true, "нет окна → isError")
            c.expectEqual(text(failed), "Could not add the frontmost window: нет окна", "текст отказа")

            backend.addOutcome = .added(UUID())
            let added = call(handler, "add_current_window")
            c.expectEqual(added?["structuredContent"]?["added"], true, "добавлено")
            c.expectEqual(added?["structuredContent"]?["task"]?["number"], 4, "новая задача — четвёртая")
            c.expectEqual(added?["structuredContent"]?["task"]?["is_current"], true, "и текущая")
            c.expectEqual(text(added), "Added the frontmost window as task 4 «Новое».", "текст")

            backend.addOutcome = .alreadyTask(d.tasks[1].id)
            let already = call(handler, "add_current_window")
            c.expectEqual(already?["structuredContent"]?["added"], false, "уже задача — added: false")
            c.expectEqual(text(already), "The frontmost window already is task 2 «Вторая».", "текст про существующую")
        }

        c.group("MCP: mark_done, mark_in_progress, set_note") {
            let d = document()
            let backend = FakeBackend(doc: d, current: nil)
            let handler = MCPRequestHandler(backend: backend, serverVersion: "x")
            let done = call(handler, "mark_done", ["number": 1])
            c.expect(backend.doc.tasks[0].isDone, "первая отмечена")
            c.expectEqual(text(done), "Task 1 «Первая» is now done.", "текст «сделано»")
            c.expectEqual(done?["structuredContent"]?["task"]?["done"], true, "done в данных")
            let again = call(handler, "mark_done", ["number": 1])
            c.expectNil(again?["isError"], "повтор — не ошибка")
            let back = call(handler, "mark_in_progress", ["number": 2])
            c.expect(!backend.doc.tasks[1].isDone, "вторая снова в работе")
            c.expectEqual(text(back), "Task 2 «Вторая» is now in progress.", "текст «в работе»")

            let noted = call(handler, "set_note", ["number": 3, "note": "  проверить\n"])
            c.expectEqual(backend.doc.tasks[2].note, "проверить", "заметка очищена от пробелов")
            c.expectEqual(text(noted), "Set the note of task 3 «Третья» to: проверить", "текст заметки")
            let cleared = call(handler, "set_note", ["id": .string(d.tasks[0].id.uuidString), "note": ""])
            c.expectEqual(backend.doc.tasks[0].note, "", "пустая заметка очищает")
            c.expectEqual(text(cleared), "Cleared the note of task 1 «Первая».", "текст очистки")
            c.expectEqual(call(handler, "set_note", ["number": 3])?["isError"], true, "без note → isError")
            c.expectEqual(text(call(handler, "set_note", ["number": 3, "note": 5])), "Missing argument: note (string).", "note не строка")
            c.expectEqual(call(handler, "set_note", ["note": "x"])?["isError"], true, "без задачи → isError")

            let unknown = call(handler, "delete_task", [:])
            c.expectEqual(unknown?["isError"], true, "неизвестный инструмент → isError, не ошибка протокола")
            c.expect(text(unknown).hasPrefix("Unknown tool: delete_task."), "текст про неизвестный инструмент")
            c.expectEqual(handler.handle(request(1, "tools/call", [:]))?["error"]?["code"]?.intValue, JSONRPCError.invalidParams, "без name → invalid params")
        }
    }

    // MARK: - Without the app

    static func unavailableChecks(_ c: CheckRunner) {
        c.group("MCP: приложение не запущено") {
            let handler = MCPRequestHandler(backend: nil, serverVersion: "x")
            c.expect(handler.handle(request(1, "initialize"))?["result"] != nil, "рукопожатие работает")
            c.expectEqual(handler.handle(request(2, "tools/list"))?["result"]?["tools"]?.arrayValue?.count, 6, "инструменты видны")
            let result = call(handler, "list_tasks")
            c.expectEqual(result?["isError"], true, "вызов → ошибка инструмента")
            c.expectEqual(text(result), MCPRequestHandler.defaultUnavailableMessage, "сообщение, как включить сервер")
            c.expect(MCPRequestHandler.defaultUnavailableMessage.contains("Settings"), "сообщение указывает на настройки")
            let custom = MCPRequestHandler(backend: nil, serverVersion: "x", unavailableMessage: "выключен")
            c.expectEqual(text(call(custom, "mark_done", ["number": 1])), "выключен", "своё сообщение")
        }
    }

    // MARK: - Config snippets

    static func configChecks(_ c: CheckRunner) {
        c.group("MCP: конфигурация клиентов") {
            let path = "/Applications/Juggler.app/Contents/MacOS/Juggler"
            let snippet = MCPConfig.claudeDesktopSnippet(executablePath: path)
            c.expectEqual(JSONValue(text: snippet)?["mcpServers"]?["juggler"],
                          ["command": .string(path), "args": ["--mcp"]], "Claude Desktop: mcpServers.juggler")
            c.expect(snippet.contains("\n"), "Claude Desktop: отформатировано")
            c.expectEqual(MCPConfig.claudeCodeCommand(executablePath: path),
                          "claude mcp add juggler -- /Applications/Juggler.app/Contents/MacOS/Juggler --mcp", "Claude Code: команда")
            c.expectEqual(MCPConfig.claudeCodeCommand(executablePath: "/Users/me/My Apps/Juggler.app/Contents/MacOS/Juggler"),
                          "claude mcp add juggler -- '/Users/me/My Apps/Juggler.app/Contents/MacOS/Juggler' --mcp", "Claude Code: путь с пробелом в кавычках")
            c.expectEqual(MCPConfig.shellQuoted("it's"), "'it'\\''s'", "апостроф в пути")
            c.expectEqual(MCPConfig.codexSnippet(executablePath: path),
                          "[mcp_servers.juggler]\ncommand = \"/Applications/Juggler.app/Contents/MacOS/Juggler\"\nargs = [\"--mcp\"]", "Codex: TOML")
            c.expectEqual(MCPConfig.socketURL(dataDirectory: URL(fileURLWithPath: "/tmp/j")).path, "/tmp/j/mcp.sock", "сокет рядом с tasks.json")
            c.expect(MCPConfig.isSocketPathUsable(String(repeating: "a", count: 103)), "103 байта помещаются в sun_path")
            c.expect(!MCPConfig.isSocketPathUsable(String(repeating: "a", count: 104)), "104 — нет")
            c.expectEqual(MCPConfig.flag, "--mcp", "флаг")
            c.expectEqual(MCPConfig.enabledKey, "mcpServerEnabled", "ключ настройки")
        }
    }
}
