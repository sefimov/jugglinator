import Foundation
import JugglerCore
import os

// App extension points. Implementations live in their tasks' folders:
//   Sources/Jugglinator/Bind/   — BIND: frontmost window context, binding, activation, permissions;
//   Sources/Jugglinator/Switch/ — SWITCH: switcher, transition card, hotkeys;
//   Sources/Jugglinator/UI/     — UI: menu bar and settings window scenes.
// The composition root (CompositionRoot.swift) gets implementations only through
// the `BindModule`, `SwitchModule`, `UIModule` factories — their signatures are the contract.
// All interaction happens on the main thread (@MainActor).

// MARK: - BIND

/// Reads the frontmost window context (bundle id, title, Chrome tab, chat id).
/// Must not crash or show system prompts: without permissions it
/// simply returns whatever it managed to find out.
@MainActor
protocol FrontmostContextProviding: AnyObject {
    func currentContext() -> FrontmostContext
}

/// Builds a binding from the frontmost window context (no dialogs).
@MainActor
protocol BindingCapturing: AnyObject {
    func captureBinding(from context: FrontmostContext) -> BindingCaptureResult
}

/// Opens the bound tab, chat or window; launches the app if needed.
@MainActor
protocol BindingActivating: AnyObject {
    func activate(_ binding: TaskBinding) -> ActivationResult
}

/// Accessibility and Automation permissions.
@MainActor
protocol PermissionsProviding: AnyObject {
    /// Whether the app has been granted Accessibility (without prompting).
    var isAccessibilityTrusted: Bool { get }
    /// Show the user a clear Accessibility prompt.
    func requestAccessibility()
}

/// The "Make the current chat a task" flow: capture the binding,
/// ask for a link if needed, create a task or bind to the current task.
@MainActor
protocol CurrentChatBinding: AnyObject {
    func bindCurrentChat()
    /// ⌃⌥⇥ and "Add or remove current window" (D15): within the undo window — restore
    /// the removed task; frontmost window exactly matches a task — remove it with a card;
    /// otherwise — `bindCurrentChat`.
    func toggleCurrentChat()
    /// "Add/Remove current window" menu item (D16): the undo window is ignored (restoring is a separate
    /// item), so the action matches the label: exact match — remove with a card, otherwise — add.
    func toggleCurrentWindow()
}

/// The set of BIND services passed to the rest of the app.
@MainActor
struct BindServices {
    let contextProvider: FrontmostContextProviding
    let capturer: BindingCapturing
    let activator: BindingActivating
    let permissions: PermissionsProviding
}

// MARK: - SWITCH

/// Task switching: cyclic (hotkeys) and direct (click on a task in the list).
@MainActor
protocol TaskSwitching: AnyObject {
    /// Determine the current task from the frontmost window, pick the next one in the cycle,
    /// activate its binding, show the card and update the visit time.
    func switchTask(_ direction: CycleDirection)
    /// Go to a specific task.
    func activateTask(id: UUID)
}

/// ⌃§ "mark done / back to in progress": the frontmost window's task on exact match,
/// otherwise the current one; saves tasks.json, shows a card, doesn't switch windows.
@MainActor
protocol DoneToggling: AnyObject {
    func toggleDone()
}

/// Transition card: a non-activating panel above all desktops.
@MainActor
protocol TransitionCardPresenting: AnyObject {
    func show(_ content: TransitionCardContent)
}

/// Global hotkeys. `start` registers them and calls `handler` on the main thread.
@MainActor
protocol HotkeyRegistering: AnyObject {
    func start(handler: @escaping (HotkeyAction) -> Void)
    func stop()
}

// MARK: - Self-test

/// Result of a single component self-test for `Jugglinator --self-test`.
/// The self-test requests no permissions and shows no windows.
struct SelfTestResult {
    let name: String
    let passed: Bool
    let detail: String

    init(_ name: String, passed: Bool, detail: String = "") {
        self.name = name
        self.passed = passed
        self.detail = detail
    }
}

/// App log: `Logger(subsystem: JugglerLog.subsystem, category: "<area>")`.
enum JugglerLog {
    static let subsystem = "com.sefimov.jugglinator"
    static let app = Logger(subsystem: subsystem, category: "app")
}
