import Foundation

// Pure logic of the SWITCH area (Foundation only): picking a task when switching
// and the transition card texts. The app (Sources/Jugglinator/Switch/) only calls it.

/// Namespace of the SWITCH area.
public enum SwitchLogic {}

/// Picking a task for "next / previous".
public enum SwitchPlanner {
    /// Current task: by the frontmost window, otherwise the last active one.
    public static func currentTaskID(context: FrontmostContext, document: TasksDocument) -> UUID? {
        CurrentTaskResolver.resolve(context: context, tasks: document.tasks, fallbackID: document.lastActiveTaskID)
    }

    /// The neighboring task in the cycle (skipping "done"), or `nil` if there is nothing to switch to.
    public static func target(direction: CycleDirection, context: FrontmostContext, document: TasksDocument) -> UUID? {
        let current = currentTaskID(context: context, document: document)
        return TaskCycler.neighbor(of: current, in: document.tasks, direction: direction)?.id
    }

    /// What the frontmost window is for ⌃§: a task, a window to add, or neither.
    ///
    /// The window is a task on an exact match (`ExactTaskMatcher`) or if its binding is already in the list.
    /// Otherwise its binding is captured without dialogs: a window without a title (desktop, no Accessibility)
    /// would be just "the app" and is not added. `capture` is called only when there is no exact match.
    public static func frontWindow(
        context: FrontmostContext, document: TasksDocument,
        capture: (FrontmostContext) -> BindingCaptureResult
    ) -> FrontWindowPlan {
        if let id = ExactTaskMatcher.match(context: context, document: document) { return .task(id) }
        switch capture(context) {
        case .captured(let binding, let title):
            if let task = document.tasks.first(where: { $0.binding.map { BindPlanner.sameTarget($0, binding) } ?? false }) {
                return .task(task.id)
            }
            if case .appWindow(let ref) = binding,
               ref.windowTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .unavailable(message: nil) }
            return .add(binding, title: title)
        case .needsManualLink:
            return .needsLink
        case .failed(let message):
            return .unavailable(message: message)
        }
    }
}

/// What the frontmost window is, for ⌃§ (`SwitchPlanner.frontWindow`).
public enum FrontWindowPlan: Equatable, Sendable {
    /// The window is this task.
    case task(UUID)
    /// The window is not in the list: add it as a new task with this binding and title.
    case add(TaskBinding, title: String)
    /// Not in the list, and the binding needs a link (Claude, ChatGPT): only the flow with dialogs can add it.
    case needsLink
    /// Cannot be added: no window, Jugglinator itself, Chrome without permission, a window without a title.
    /// `message` explains why, when known.
    case unavailable(message: String?)
}

/// Builds the transition card contents.
public enum TransitionCardBuilder {
    /// A longer note is truncated with "…".
    public static let maxNoteLength = 240
    public static let maxTitleLength = 120

    /// Card for task `id` at time `now` (before the visit time is updated).
    /// - `bindHotkey`: the current "add or remove the current window" combination for the hint (`nil` — not assigned).
    /// - `activation`: binding activation outcome; a fallback or an error goes into the hint.
    public static func content(
        for id: UUID, in document: TasksDocument, now: Date,
        bindHotkey: Hotkey?, activation: ActivationResult? = nil
    ) -> TransitionCardContent? {
        guard let task = document.task(withID: id), let number = document.number(of: id) else { return nil }
        return TransitionCardContent(
            number: number,
            title: title(task.title),
            note: note(task.note),
            absenceText: Staleness.absenceText(lastVisited: task.lastVisitedAt, now: now),
            staleness: Staleness.level(lastVisited: task.lastVisitedAt, now: now),
            source: task.binding?.source,
            hint: hint(hasBinding: task.binding != nil, bindHotkey: bindHotkey, activation: activation))
    }

    public static func title(_ raw: String) -> String {
        let t = collapse(raw)
        return t.isEmpty ? loc("Без названия") : truncate(t, to: maxTitleLength)
    }

    /// Note: whitespace at the edges and blank lines are trimmed, a long one is shortened.
    public static func note(_ raw: String) -> String {
        let lines = raw.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return truncate(lines.joined(separator: "\n"), to: maxNoteLength)
    }

    public static func hint(hasBinding: Bool, bindHotkey: Hotkey?, activation: ActivationResult?) -> String? {
        guard hasBinding else { return unboundHint(bindHotkey: bindHotkey) }
        switch activation {
        case .failed(let message)?:
            let m = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return m.isEmpty ? loc("Не удалось открыть привязку") : loc("Не удалось открыть: \(m)")
        case .fallback(let message)?:
            let m = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return m.isEmpty ? nil : m
        case .activated?, nil:
            return nil
        }
    }

    /// Hint for a task without a binding.
    public static func unboundHint(bindHotkey: Hotkey?) -> String {
        if let bindHotkey {
            return loc("Нет привязки: откройте чат и нажмите \(bindHotkey.displayString)")
        }
        return loc("Нет привязки: откройте чат и выберите в меню «\(TaskToggleTexts.menuAddTitle)»")
    }

    /// Card title line: "2. Title".
    public static func headline(_ content: TransitionCardContent) -> String {
        "\(content.number). \(content.title)"
    }

    private static func collapse(_ s: String) -> String {
        s.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }

    static func truncate(_ s: String, to limit: Int) -> String {
        guard s.count > limit else { return s }
        let cut = s.prefix(limit - 1).trimmingCharacters(in: .whitespacesAndNewlines)
        return cut + "…"
    }
}

/// Card timings: fade in, display, smooth fade out. 1–1.5 s in total.
public struct CardTiming: Equatable, Sendable {
    public var fadeIn: TimeInterval
    public var hold: TimeInterval
    public var fadeOut: TimeInterval

    public init(fadeIn: TimeInterval = 0.1, hold: TimeInterval = 0.95, fadeOut: TimeInterval = 0.35) {
        self.fadeIn = fadeIn
        self.hold = hold
        self.fadeOut = fadeOut
    }

    public static let standard = CardTiming()

    public var total: TimeInterval { fadeIn + hold + fadeOut }
}
