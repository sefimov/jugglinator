import Foundation

// Shared result types for the app's protocols (Sources/Jugglinator/App/ExtensionPoints.swift).
// They live in JugglerCore so they can be used in pure logic
// of UI/SWITCH/BIND and checked from JugglerChecks.

/// Outcome of activating a binding (BIND → SWITCH).
public enum ActivationResult: Equatable, Sendable {
    /// Exactly what was bound was opened (tab, chat, window).
    case activated
    /// A fallback was opened: e.g. the tab URL again, or just the app.
    /// The string is a localized user-facing explanation.
    case fallback(String)
    /// Nothing opened. The string is a localized user-facing explanation.
    case failed(String)

    public var succeeded: Bool {
        if case .failed = self { return false }
        return true
    }
}

/// Outcome of trying to bind the current chat (BIND).
public enum BindingCaptureResult: Equatable, Sendable {
    /// The binding is ready. `suggestedTitle` is the cleaned title for a new task.
    case captured(TaskBinding, suggestedTitle: String)
    /// The chat id cannot be read automatically — the user must be asked for a link
    /// (Claude without Accessibility, ChatGPT always).
    case needsManualLink(BindingSource, suggestedTitle: String)
    /// Cannot bind. The string is a localized user-facing explanation.
    case failed(String)
}

/// Contents of the transition card (SWITCH builds it, the presenter shows it).
public struct TransitionCardContent: Equatable, Sendable {
    public var number: Int
    public var title: String
    public var note: String
    /// "away N min" at the time of the switch (before the visit time is updated).
    public var absenceText: String
    public var staleness: StalenessLevel
    public var source: BindingSource?
    /// A hint, e.g. about the bind hotkey for a task without a binding.
    public var hint: String?

    public init(
        number: Int, title: String, note: String = "", absenceText: String,
        staleness: StalenessLevel, source: BindingSource? = nil, hint: String? = nil
    ) {
        self.number = number
        self.title = title
        self.note = note
        self.absenceText = absenceText
        self.staleness = staleness
        self.source = source
        self.hint = hint
    }
}

/// Actions triggered by global hotkeys.
public enum HotkeyAction: String, Codable, CaseIterable, Sendable {
    case nextTask
    case previousTask
    /// ⌃⌥⇥: add the frontmost window as a task, or remove the task if it already is one (D15).
    /// The case name does not change: it is the key in hotkeys.json.
    case bindCurrentChat
    /// ⌃§: mark the task done or return it to work (D24). The new case is added at the end:
    /// old hotkeys.json files still read, and an action without an entry gets the default.
    case toggleDone

    public var displayName: String {
        switch self {
        case .nextTask: return loc("Следующая задача")
        case .previousTask: return loc("Предыдущая задача")
        case .bindCurrentChat: return TaskToggleTexts.actionTitle
        case .toggleDone: return DoneToggleTexts.actionTitle
        }
    }
}
