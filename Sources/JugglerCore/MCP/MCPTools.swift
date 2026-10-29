import Foundation

// MCP tools over the task list: their schemas, argument parsing and result formatting.
// Side effects (activating a binding, reading the frontmost window, saving) go through
// `MCPTaskBackend`, which the app implements over `AppModel`, the switcher and BIND.

/// What the tools need from the app. All calls happen on the thread the handler runs on (main in the app).
public protocol MCPTaskBackend: AnyObject {
    /// The list, the clock and the current task as the hotkey cycle sees it (frontmost window, then last active).
    func snapshot() -> MCPSnapshot
    /// The same as the hotkey cycle landing on the task: activate the binding, show the card, record the visit.
    func switchToTask(id: UUID) -> MCPActionOutcome
    /// The same as ⌃⌥⇥ in a window that is not a task yet.
    func addCurrentWindow() -> MCPAddOutcome
    /// Sets or clears the "done" mark (saved to tasks.json). Returns `false` if there is no such task.
    func setDone(id: UUID, _ done: Bool) -> Bool
    /// Replaces the "why / next" note (saved to tasks.json). Returns `false` if there is no such task.
    func setNote(id: UUID, _ note: String) -> Bool
}

public struct MCPSnapshot: Equatable, Sendable {
    public var document: TasksDocument
    public var now: Date
    public var currentTaskID: UUID?

    public init(document: TasksDocument, now: Date, currentTaskID: UUID?) {
        self.document = document
        self.now = now
        self.currentTaskID = currentTaskID
    }
}

public enum MCPActionOutcome: Equatable, Sendable {
    /// The visit is recorded; `warning` is set when the binding opened a fallback or did not open
    /// (the localized text from BIND), so the assistant can tell the user.
    case done(warning: String?)
    /// Nothing happened; `message` explains why.
    case failed(String)
}

/// A task picked from tool arguments, or why it could not be.
public enum MCPTaskSelection: Equatable, Sendable {
    case task(UUID)
    case invalid(String)
}

public enum MCPAddOutcome: Equatable, Sendable {
    case added(UUID)
    /// The frontmost window already is this task.
    case alreadyTask(UUID)
    /// Nothing was added; `message` explains why.
    case failed(String)
}

/// A tool as listed by `tools/list`.
public struct MCPToolDefinition: Equatable, Sendable {
    public var name: String
    public var title: String
    public var description: String
    public var inputSchema: JSONValue
    public var readOnly: Bool

    public var json: JSONValue {
        [
            "name": .string(name),
            "title": .string(title),
            "description": .string(description),
            "inputSchema": inputSchema,
            "annotations": [
                "title": .string(title),
                "readOnlyHint": .bool(readOnly),
                "destructiveHint": false,
                "idempotentHint": .bool(readOnly),
                "openWorldHint": false,
            ],
        ]
    }
}

/// Result of `tools/call`: text for the model plus the same data as JSON.
public struct MCPToolResult: Equatable, Sendable {
    public var text: String
    public var structured: JSONValue?
    public var isError: Bool

    public init(text: String, structured: JSONValue? = nil, isError: Bool = false) {
        self.text = text
        self.structured = structured
        self.isError = isError
    }

    public static func error(_ text: String) -> MCPToolResult {
        MCPToolResult(text: text, isError: true)
    }

    public var json: JSONValue {
        var object: [String: JSONValue] = ["content": [["type": "text", "text": .string(text)]]]
        if let structured { object["structuredContent"] = structured }
        if isError { object["isError"] = true }
        return .object(object)
    }
}

/// Tool names, schemas and the dispatch of a call to the backend.
public enum MCPTools {
    public static let listTasks = "list_tasks"
    public static let switchToTask = "switch_to_task"
    public static let addCurrentWindow = "add_current_window"
    public static let markDone = "mark_done"
    public static let markInProgress = "mark_in_progress"
    public static let setNote = "set_note"

    /// Properties of a tool that picks a task: by number (position in the list) or by id.
    static let taskSelector: [String: JSONValue] = [
        "number": ["type": "integer", "minimum": 1,
                   "description": "Task number as shown in the Jugglinator menu and on the transition card (1-based position in the list)."],
        "id": ["type": "string", "description": "Task id (UUID) from list_tasks. Pass either number or id."],
    ]

    public static let catalog: [MCPToolDefinition] = [
        MCPToolDefinition(
            name: listTasks, title: "List Jugglinator tasks",
            description: "List the user's Jugglinator tasks: number, title, note, done mark, what the task is bound to "
                + "(Claude chat, Claude Code session, ChatGPT thread, Chrome tab, Terminal tab or app window), "
                + "minutes since the user last visited it, and which task is current (the frontmost window's task, "
                + "otherwise the last visited one). Call this first to get task numbers and ids.",
            inputSchema: ["type": "object", "properties": [:], "additionalProperties": false],
            readOnly: true),
        MCPToolDefinition(
            name: switchToTask, title: "Switch to a Jugglinator task",
            description: "Bring a task to the front on the user's Mac, like the Control-Tab hotkey landing on it: "
                + "opens the bound chat, session, thread, tab or window, shows the transition card and records the visit. "
                + "Pick the task by number or id from list_tasks.",
            inputSchema: ["type": "object", "properties": .object(taskSelector), "additionalProperties": false],
            readOnly: false),
        MCPToolDefinition(
            name: addCurrentWindow, title: "Add the current window as a task",
            description: "Add the frontmost window (chat, session, thread, tab, Terminal tab or app window) "
                + "to the Jugglinator task list, like the Control-Option-Tab hotkey. If the window already is a task, "
                + "returns that task. The new task becomes current.",
            inputSchema: ["type": "object", "properties": [:], "additionalProperties": false],
            readOnly: false),
        MCPToolDefinition(
            name: markDone, title: "Mark a task done",
            description: "Mark a Jugglinator task as done: the hotkey cycle skips it until it is back in progress. "
                + "Pick the task by number or id.",
            inputSchema: ["type": "object", "properties": .object(taskSelector), "additionalProperties": false],
            readOnly: false),
        MCPToolDefinition(
            name: markInProgress, title: "Mark a task in progress",
            description: "Return a done Jugglinator task to work (clear the done mark). Pick the task by number or id.",
            inputSchema: ["type": "object", "properties": .object(taskSelector), "additionalProperties": false],
            readOnly: false),
        MCPToolDefinition(
            name: setNote, title: "Set a task's note",
            description: "Replace the 'why / next step' note of a Jugglinator task. The note is shown in the menu "
                + "and on the transition card when the user switches to the task. An empty string clears it. "
                + "Pick the task by number or id.",
            inputSchema: [
                "type": "object",
                "properties": .object(taskSelector.merging(
                    ["note": ["type": "string", "description": "The new note text; empty to clear."]],
                    uniquingKeysWith: { _, new in new })),
                "required": ["note"],
                "additionalProperties": false,
            ],
            readOnly: false),
    ]

    public static var names: [String] { catalog.map(\.name) }

    public static func definition(named name: String) -> MCPToolDefinition? {
        catalog.first { $0.name == name }
    }

    /// Runs a tool. An unknown tool and bad arguments are tool errors (`isError`), not protocol errors,
    /// so the assistant sees the explanation and can retry.
    public static func call(_ name: String, arguments: JSONValue?, backend: MCPTaskBackend) -> MCPToolResult {
        let args = arguments?.objectValue ?? [:]
        switch name {
        case listTasks:
            return list(backend.snapshot())

        case switchToTask:
            let snapshot = backend.snapshot()
            switch resolveTask(args, in: snapshot.document) {
            case .invalid(let message): return .error(message)
            case .task(let id):
                switch backend.switchToTask(id: id) {
                case .failed(let message):
                    return .error("Could not switch to task \(describe(id, in: snapshot.document)): \(message)")
                case .done(let warning):
                    let after = backend.snapshot()
                    var text = "Switched to task \(describe(id, in: after.document))."
                    if let warning, !warning.isEmpty { text += " Note: \(warning)" }
                    var structured: [String: JSONValue] = ["task": taskJSON(id, in: after)]
                    if let warning, !warning.isEmpty { structured["warning"] = .string(warning) }
                    return MCPToolResult(text: text, structured: .object(structured))
                }
            }

        case addCurrentWindow:
            switch backend.addCurrentWindow() {
            case .failed(let message):
                return .error("Could not add the frontmost window: \(message)")
            case .alreadyTask(let id):
                let after = backend.snapshot()
                return MCPToolResult(
                    text: "The frontmost window already is task \(describe(id, in: after.document)).",
                    structured: ["task": taskJSON(id, in: after), "added": false])
            case .added(let id):
                let after = backend.snapshot()
                return MCPToolResult(
                    text: "Added the frontmost window as task \(describe(id, in: after.document)).",
                    structured: ["task": taskJSON(id, in: after), "added": true])
            }

        case markDone, markInProgress:
            let done = name == markDone
            let snapshot = backend.snapshot()
            switch resolveTask(args, in: snapshot.document) {
            case .invalid(let message): return .error(message)
            case .task(let id):
                guard backend.setDone(id: id, done) else { return .error("Task not found.") }
                let after = backend.snapshot()
                let state = done ? "done" : "in progress"
                return MCPToolResult(
                    text: "Task \(describe(id, in: after.document)) is now \(state).",
                    structured: ["task": taskJSON(id, in: after)])
            }

        case setNote:
            let snapshot = backend.snapshot()
            guard let note = args["note"]?.stringValue else {
                return .error("Missing argument: note (string).")
            }
            switch resolveTask(args, in: snapshot.document) {
            case .invalid(let message): return .error(message)
            case .task(let id):
                guard backend.setNote(id: id, note) else { return .error("Task not found.") }
                let after = backend.snapshot()
                let shown = after.document.task(withID: id)?.note ?? ""
                return MCPToolResult(
                    text: shown.isEmpty
                        ? "Cleared the note of task \(describe(id, in: after.document))."
                        : "Set the note of task \(describe(id, in: after.document)) to: \(shown)",
                    structured: ["task": taskJSON(id, in: after)])
            }

        default:
            return .error("Unknown tool: \(name). Available tools: \(names.joined(separator: ", ")).")
        }
    }

    // MARK: - Task selection

    /// Picks the task from `number` (1-based, also as a numeric string) or `id` (UUID, any case).
    public static func resolveTask(_ args: [String: JSONValue], in document: TasksDocument) -> MCPTaskSelection {
        if let numberValue = args["number"], !numberValue.isNull {
            guard let number = numberValue.intValue ?? numberValue.stringValue.flatMap({ Int($0.trimmingCharacters(in: .whitespaces)) }) else {
                return .invalid("Argument number must be an integer, got \(numberValue.text()).")
            }
            guard number >= 1, number <= document.tasks.count else {
                return .invalid(document.tasks.isEmpty
                    ? "The task list is empty."
                    : "There is no task \(number): the list has \(document.tasks.count) task\(document.tasks.count == 1 ? "" : "s") (1…\(document.tasks.count)).")
            }
            return .task(document.tasks[number - 1].id)
        }
        if let idValue = args["id"], !idValue.isNull {
            guard let text = idValue.stringValue, let id = UUID(uuidString: text.trimmingCharacters(in: .whitespaces)) else {
                return .invalid("Argument id must be a UUID string, got \(idValue.text()).")
            }
            guard document.task(withID: id) != nil else {
                return .invalid("There is no task with id \(id.uuidString.lowercased()). Call list_tasks for current ids.")
            }
            return .task(id)
        }
        return .invalid("Pass the task as number (1-based) or id (UUID) from list_tasks.")
    }

    // MARK: - Formatting

    static func list(_ snapshot: MCPSnapshot) -> MCPToolResult {
        let document = snapshot.document
        let tasks = document.tasks.map { taskJSON($0.id, in: snapshot) }
        let currentNumber = snapshot.currentTaskID.flatMap { document.number(of: $0) }
        let structured: JSONValue = [
            "tasks": .array(tasks),
            "count": .number(Double(document.tasks.count)),
            "current_number": .int(currentNumber),
        ]
        if document.tasks.isEmpty {
            return MCPToolResult(text: "The Jugglinator task list is empty.", structured: structured)
        }
        var lines: [String] = []
        for (index, task) in document.tasks.enumerated() {
            let number = index + 1
            var marks: [String] = []
            if task.id == snapshot.currentTaskID { marks.append("current") }
            if task.isDone { marks.append("done") }
            var line = "\(number). \(TransitionCardBuilder.title(task.title))"
            if !marks.isEmpty { line += " [\(marks.joined(separator: ", "))]" }
            if let binding = task.binding { line += " · \(bindingKind(binding))" }
            line += " · \(absence(task.lastVisitedAt, now: snapshot.now))"
            let note = TransitionCardBuilder.note(task.note)
            if !note.isEmpty { line += "\n   note: \(note.replacingOccurrences(of: "\n", with: " / "))" }
            lines.append(line)
        }
        let header = "\(document.tasks.count) task\(document.tasks.count == 1 ? "" : "s")"
            + (currentNumber.map { ", current: \($0)" } ?? ", no current task") + ":"
        return MCPToolResult(text: ([header] + lines).joined(separator: "\n"), structured: structured)
    }

    /// One task as JSON: `{"number", "id", "title", "note", "done", "binding", "binding_title", "minutes_since_visit", "is_current"}`.
    public static func taskJSON(_ id: UUID, in snapshot: MCPSnapshot) -> JSONValue {
        guard let task = snapshot.document.task(withID: id), let number = snapshot.document.number(of: id) else { return .null }
        return [
            "number": .number(Double(number)),
            "id": .string(task.id.uuidString.lowercased()),
            "title": .string(task.title),
            "note": .string(task.note),
            "done": .bool(task.isDone),
            "binding": .string(task.binding.map(bindingKind)),
            "binding_title": .string(task.binding?.title),
            "minutes_since_visit": .int(Staleness.minutesSince(task.lastVisitedAt, now: snapshot.now)),
            "is_current": .bool(task.id == snapshot.currentTaskID),
        ]
    }

    /// Binding kind as in tasks.json: `chromeTab`, `claudeChat`, `claudeCodeSession`, `chatGPTThread`, `terminalWindow`, `appWindow`.
    public static func bindingKind(_ binding: TaskBinding) -> String {
        binding.source.rawValue
    }

    static func absence(_ lastVisited: Date?, now: Date) -> String {
        guard let minutes = Staleness.minutesSince(lastVisited, now: now) else { return "never visited" }
        if minutes < 1 { return "visited just now" }
        if minutes < 60 { return "away \(minutes) min" }
        if minutes < 24 * 60 { return "away \(minutes / 60) h \(minutes % 60) min" }
        return "away \(minutes / (24 * 60)) d"
    }

    /// `2 «Title»` for messages.
    static func describe(_ id: UUID, in document: TasksDocument) -> String {
        guard let task = document.task(withID: id), let number = document.number(of: id) else { return "?" }
        return "\(number) «\(TransitionCardBuilder.title(task.title))»"
    }
}
