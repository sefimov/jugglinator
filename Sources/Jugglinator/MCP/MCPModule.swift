import AppKit
import Foundation
import JugglerCore
import SwiftUI

// The Sources/Jugglinator/MCP/ folder belongs to the MCP task: the MCP server for AI assistants.
// `MCPModule` function signatures are a contract with the composition root (App/CompositionRoot.swift),
// the entry point (App/JugglerApp.swift), UI (the settings section) and the self-test (App/SelfTest.swift).
//
// Contents:
//   MCPServerController  — the "MCP server" setting, start/stop, config snippets;
//   MCPSocketServer      — Unix socket listener; requests are handled on the main thread;
//   LiveMCPBackend       — the tools over AppModel, BIND and the SWITCH switcher;
//   MCPStdioBridge       — `Jugglinator --mcp`: stdin/stdout ⇄ the socket, with a fallback when the app is off;
//   MCPSettingsSection   — the settings section;
//   UnixSocket           — POSIX helpers.
// Protocol logic (JSON-RPC, tools, schemas, snippets) is in JugglerCore/MCP and checked by JugglerChecks.

@MainActor
enum MCPModule {
    /// Reported in `serverInfo`: the app version, or "dev" under `swift run`.
    static var serverVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    /// `mcp.sock` next to the task file.
    static func socketPath(for store: TaskStore) -> String {
        MCPConfig.socketURL(dataDirectory: store.directoryURL).path
    }

    static func makeServer(model: AppModel, bind: BindServices, switcher: TaskSwitching, card: TransitionCardPresenting) -> MCPServerController {
        MCPServerController(socketPath: socketPath(for: model.store), serverVersion: serverVersion) {
            LiveMCPBackend(model: model, bind: bind, switcher: switcher, card: card)
        }
    }

    /// Settings section (UI embeds it as is). Empty if the environment has no server.
    static func settingsView(environment: AppEnvironment) -> AnyView {
        guard let controller = environment.mcp else { return AnyView(EmptyView()) }
        return AnyView(MCPSettingsSection(controller: controller))
    }

    /// `Jugglinator --mcp`: runs until stdin closes. Never touches AppKit.
    static func runStdioBridge() -> Int32 {
        MCPStdioBridge.run(socketPath: socketPath(for: TaskStore()), serverVersion: serverVersion)
    }

    /// Self-test: a real socket server over a temporary store with fake BIND and card; no windows, no permissions.
    static func selfTest() -> [SelfTestResult] {
        MCPSelfTest.run()
    }
}

// MARK: - Self-test

@MainActor
private enum MCPSelfTest {
    static func run() -> [SelfTestResult] {
        var results: [SelfTestResult] = []
        results.append(offlineRelay())
        results += overSocket()
        return results
    }

    /// The relay without the app: the handshake and the tool list work, a tool call explains how to turn the server on.
    private static func offlineRelay() -> SelfTestResult {
        let handler = MCPRequestHandler(backend: nil, serverVersion: "test")
        let initialized = handler.handle(line: #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}"#)
            .flatMap(JSONValue.init(text:))
        let tools = handler.handle(line: #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#).flatMap(JSONValue.init(text:))
        let call = handler.handle(line: #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"list_tasks"}}"#)
            .flatMap(JSONValue.init(text:))
        let ok = initialized?["result"]?["serverInfo"]?["name"]?.stringValue == "jugglinator"
            && tools?["result"]?["tools"]?.arrayValue?.count == MCPTools.catalog.count
            && call?["result"]?["isError"]?.boolValue == true
            && call?["result"]?["content"]?.arrayValue?.first?["text"]?.stringValue?.contains("MCP server") == true
        return SelfTestResult("MCP: без приложения relay отвечает на рукопожатие и объясняет, как включить сервер", passed: ok)
    }

    /// Socket server + live backend over a temporary store: list, switch, done, note, add current window.
    private static func overSocket() -> [SelfTestResult] {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("jugglinator-mcp-self-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let model = AppModel(store: TaskStore(fileURL: dir.appendingPathComponent("tasks.json")), clock: { t0.addingTimeInterval(600) })
        let b1 = TaskBinding.appWindow(AppWindowRef(bundleID: "com.example.one", windowTitle: "Один"))
        let b2 = TaskBinding.chatGPTThread(ChatGPTThreadRef(threadID: "th-2", title: "Два"))
        let t1 = JugglerTask(title: "Первая", note: "дальше: ответить", lastVisitedAt: t0, createdAt: t0, binding: b1)
        let t2 = JugglerTask(title: "Вторая", createdAt: t0, binding: b2)
        model.update { $0.tasks = [t1, t2]; $0.lastActiveTaskID = t2.id }

        let fake = MCPFakes(context: FrontmostContext(bundleID: "com.example.one", windowTitle: "Один"))
        let switcher = CycleTaskSwitcher(model: model, bind: fake.services, card: fake.card, bindHotkey: { nil }, beep: {})
        let backend = LiveMCPBackend(model: model, bind: fake.services, switcher: switcher, card: fake.card)
        // A short path: sockaddr_un holds 104 bytes.
        let socketPath = FileManager.default.temporaryDirectory.appendingPathComponent("jmcp-\(getpid()).sock").path
        let controller = MCPServerController(defaults: UserDefaults(suiteName: "com.sefimov.jugglinator.mcp-self-test") ?? .standard,
                                             socketPath: socketPath, serverVersion: "test") { backend }
        controller.start()
        defer { controller.stop() }
        guard controller.isListening, let client = MCPClient(path: socketPath) else {
            return [SelfTestResult("MCP: сервер слушает сокет", passed: false, detail: "\(controller.status)")]
        }
        defer { client.close() }

        var results: [SelfTestResult] = []
        let initialized = client.call(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","clientInfo":{"name":"self-test"}}}"#)
        client.notify(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#)
        let list = client.call(#"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#)
        results.append(SelfTestResult(
            "MCP: рукопожатие и список инструментов через сокет",
            passed: initialized?["result"]?["protocolVersion"]?.stringValue == "2025-03-26"
                && list?["result"]?["tools"]?.arrayValue?.map { $0["name"]?.stringValue ?? "" } == MCPTools.names,
            detail: "сокет \(socketPath)"))

        // list_tasks: current is task 1 (frontmost window), task 1 was visited 10 min ago.
        let listed = client.call(#"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"list_tasks","arguments":{}}}"#)
        let tasks = listed?["result"]?["structuredContent"]?["tasks"]?.arrayValue ?? []
        results.append(SelfTestResult(
            "MCP: list_tasks отдаёт номера, привязки, минуты и текущую",
            passed: tasks.count == 2 && tasks[0]["is_current"]?.boolValue == true && tasks[0]["binding"]?.stringValue == "appWindow"
                && tasks[0]["minutes_since_visit"]?.intValue == 10 && tasks[1]["minutes_since_visit"]?.isNull == true
                && tasks[1]["binding"]?.stringValue == "chatGPTThread" && tasks[0]["note"]?.stringValue == "дальше: ответить"
                && listed?["result"]?["structuredContent"]?["current_number"]?.intValue == 1,
            detail: (listed?["result"]?["content"]?.arrayValue?.first?["text"]?.stringValue ?? "нет ответа")
                .replacingOccurrences(of: "\n", with: " | ")))

        // switch_to_task 2: the binding is activated, the card shown, the visit recorded.
        let switched = client.call(#"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"switch_to_task","arguments":{"number":2}}}"#)
        results.append(SelfTestResult(
            "MCP: switch_to_task активирует привязку, показывает карточку и отмечает заход",
            passed: switched?["result"]?["isError"] == nil && fake.activator.activated == [b2]
                && fake.card.shown.last?.number == 2 && model.document.lastActiveTaskID == t2.id
                && model.document.task(withID: t2.id)?.lastVisitedAt != nil
                && switched?["result"]?["structuredContent"]?["task"]?["number"]?.intValue == 2))

        // mark_done by id, mark_in_progress by number, set_note.
        let id1 = t1.id.uuidString.lowercased()
        let done = client.call(#"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"mark_done","arguments":{"id":"\#(id1)"}}}"#)
        let doneOK = done?["result"]?["structuredContent"]?["task"]?["done"]?.boolValue == true
            && model.document.tasks[0].isDone && fake.card.messages.last == DoneToggleTexts.card(number: 1, title: "Первая", isDone: true)
        let back = client.call(#"{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"mark_in_progress","arguments":{"number":1}}}"#)
        let backOK = back?["result"]?["structuredContent"]?["task"]?["done"]?.boolValue == false && !model.document.tasks[0].isDone
        let noted = client.call(#"{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"set_note","arguments":{"number":2,"note":" проверить тесты \n"}}}"#)
        let noteOK = model.document.tasks[1].note == "проверить тесты"
            && noted?["result"]?["structuredContent"]?["task"]?["note"]?.stringValue == "проверить тесты"
            && model.store.load().document.tasks[1].note == "проверить тесты"
        results.append(SelfTestResult("MCP: mark_done, mark_in_progress и set_note меняют задачу и сохраняют tasks.json",
                                      passed: doneOK && backOK && noteOK))

        // add_current_window: a window that is not a task yet becomes task 3 and current; repeating finds it.
        fake.provider.context = FrontmostContext(bundleID: "com.example.new", windowTitle: "Новое")
        let added = client.call(#"{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"add_current_window"}}"#)
        let again = client.call(#"{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"add_current_window"}}"#)
        results.append(SelfTestResult(
            "MCP: add_current_window добавляет переднее окно задачей, повтор находит её",
            passed: added?["result"]?["structuredContent"]?["added"]?.boolValue == true && model.document.tasks.count == 3
                && model.document.tasks[2].title == "Новое" && model.document.lastActiveTaskID == model.document.tasks[2].id
                && fake.card.messages.last == TaskToggleTexts.addedCard(number: 3, title: "Новое")
                && again?["result"]?["structuredContent"]?["added"]?.boolValue == false && model.document.tasks.count == 3))

        // Errors: wrong number, unknown tool, garbage line.
        let wrong = client.call(#"{"jsonrpc":"2.0","id":10,"method":"tools/call","params":{"name":"switch_to_task","arguments":{"number":9}}}"#)
        let unknown = client.call(#"{"jsonrpc":"2.0","id":11,"method":"nope"}"#)
        let garbage = client.call("{not json")
        results.append(SelfTestResult(
            "MCP: ошибки — неверный номер, неизвестный метод, битая строка",
            passed: wrong?["result"]?["isError"]?.boolValue == true && unknown?["error"]?["code"]?.intValue == JSONRPCError.methodNotFound
                && garbage?["error"]?["code"]?.intValue == JSONRPCError.parseError))

        // Stop: the socket file is gone and the client sees end of stream.
        controller.stop()
        let closed = client.waitForEOF(timeout: 3)
        results.append(SelfTestResult(
            "MCP: остановка закрывает соединения и удаляет сокет",
            passed: closed && !FileManager.default.fileExists(atPath: socketPath) && !controller.isListening))
        return results
    }
}

/// A test client: writes a line, pumps the main run loop until the answer arrives
/// (the server handles requests on the main thread via `DispatchQueue.main.sync`).
private final class MCPClient: @unchecked Sendable {
    private let fd: Int32
    private let lock = NSLock()
    private var lines: [String] = []
    private var eof = false

    init?(path: String) {
        guard let fd = UnixSocket.connect(path: path) else { return nil }
        self.fd = fd
        let thread = Thread { [weak self] in self?.pump() }
        thread.start()
    }

    private func pump() {
        let reader = UnixSocket.LineReader()
        while let line = reader.next(from: fd) {
            lock.lock()
            lines.append(line)
            lock.unlock()
        }
        lock.lock()
        eof = true
        lock.unlock()
    }

    func notify(_ line: String) {
        _ = UnixSocket.writeLine(fd, line)
    }

    func call(_ line: String, timeout: TimeInterval = 5) -> JSONValue? {
        guard UnixSocket.writeLine(fd, line) else { return nil }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            lock.lock()
            let next = lines.isEmpty ? nil : lines.removeFirst()
            lock.unlock()
            if let next { return JSONValue(text: next) }
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        return nil
    }

    func waitForEOF(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            lock.lock()
            let done = eof
            lock.unlock()
            if done { return true }
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        return false
    }

    func close() {
        shutdown(fd, SHUT_RDWR)
        Darwin.close(fd)
    }
}

// MARK: - Fakes

@MainActor
private final class MCPFakes {
    final class Provider: FrontmostContextProviding {
        var context: FrontmostContext
        init(_ context: FrontmostContext) { self.context = context }
        func currentContext() -> FrontmostContext { context }
    }

    final class Capturer: BindingCapturing {
        func captureBinding(from context: FrontmostContext) -> BindingCaptureResult {
            guard context.bundleID == "com.example.new" else { return .failed("самопроверка") }
            return .captured(.appWindow(AppWindowRef(bundleID: "com.example.new", windowTitle: context.windowTitle ?? "")),
                             suggestedTitle: context.windowTitle ?? "")
        }
    }

    final class Activator: BindingActivating {
        var activated: [TaskBinding] = []
        func activate(_ binding: TaskBinding) -> ActivationResult {
            activated.append(binding)
            return .activated
        }
    }

    final class Permissions: PermissionsProviding {
        var isAccessibilityTrusted: Bool { false }
        func requestAccessibility() {}
    }

    final class Card: TransitionCardPresenting, TransitionMessagePresenting {
        var shown: [TransitionCardContent] = []
        var messages: [String] = []
        func show(_ content: TransitionCardContent) { shown.append(content) }
        func showMessage(_ text: String) { messages.append(text) }
        func showMessage(_ text: String, duration: TimeInterval) { messages.append(text) }
    }

    let provider: Provider
    let activator = Activator()
    let card = Card()
    let services: BindServices

    init(context: FrontmostContext) {
        provider = Provider(context)
        services = BindServices(contextProvider: provider, capturer: Capturer(), activator: activator, permissions: Permissions())
    }
}
