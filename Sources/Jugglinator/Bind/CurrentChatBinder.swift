import AppKit
import Foundation
import JugglerCore
import os

private let log = Logger(subsystem: JugglerLog.subsystem, category: "bind")

/// Binding from context without dialogs: all the logic is in `BindingCapture` (JugglerCore).
@MainActor
final class LiveBindingCapturer: BindingCapturing {
    private let provider: LiveFrontmostContextProvider

    init(provider: LiveFrontmostContextProvider) {
        self.provider = provider
    }

    func captureBinding(from context: FrontmostContext) -> BindingCaptureResult {
        BindingCapture.capture(
            context: context,
            chromeStatus: provider.lastDiagnostics.chromeAutomation,
            ownBundleID: Bundle.main.bundleIdentifier ?? BindApps.jugglinator,
            chatGPTLookup: provider.lastDiagnostics.chatGPTThread)
    }
}

/// Outcome of ⌃⌥⇥ "add or remove current window" (D15): removal and restore with a card.
/// The decision logic is `TaskToggle` (JugglerCore); here we only apply it to the model and show the card.
@MainActor
enum TaskToggleApplier {
    /// Applies `.restore` and `.remove`; for `.add` returns the context to proceed to binding with.
    static func apply(_ decision: ToggleDecision, model: AppModel, card: TransitionCardPresenting?, hotkey: Hotkey?) -> FrontmostContext? {
        let messages = card as? TransitionMessagePresenting
        switch decision {
        case .restore:
            guard let restored = model.restoreLastRemoved(), let number = model.document.number(of: restored.task.id) else {
                NSSound.beep()
                return nil
            }
            log.info("⌃⌥⇥: задача \(number) возвращена")
            messages?.showMessage(TaskToggleTexts.restoredCard(number: number, title: restored.task.title))
            return nil

        case .remove(let id, let number):
            guard let removed = model.removeTask(id, undoableByToggle: true) else { return nil }
            log.info("⌃⌥⇥: задача \(number) удалена, переднее окно точно совпало с привязкой")
            messages?.showMessage(TaskToggleTexts.removedCard(number: number, title: removed.task.title, hotkey: hotkey),
                                  duration: TaskRemoval.undoWindow)
            return nil

        case .add(let context):
            return context
        }
    }

    /// Card after binding created a new task: the window is now in the list.
    static func showAdded(_ id: UUID, model: AppModel, card: TransitionCardPresenting?) {
        guard let number = model.document.number(of: id), let task = model.document.tasks.first(where: { $0.id == id }) else { return }
        log.info("Окно добавлено как задача \(number)")
        (card as? TransitionMessagePresenting)?.showMessage(TaskToggleTexts.addedCard(number: number, title: task.title))
    }
}

/// "Make the current chat a task"; via `toggleCurrentChat` — also ⌃⌥⇥ "add or remove current window".
///
/// Toggle: within 5 s after a ⌃⌥⇥ removal it restores the task; if the frontmost window exactly
/// matches a task (`ExactTaskMatcher`) — removes it with a card; otherwise — binding, as below.
///
/// 1. Reads the frontmost window context (if Jugglinator is in front — that of the last active app).
/// 2. Builds a binding; for Claude without a read id and for ChatGPT whose thread isn't found by title
///    unambiguously, asks to paste a link (with several threads — with a link to the latest prefilled).
/// 3. If the chat is already bound — makes that task current; if the current task has no binding —
///    offers to bind it; otherwise creates a new task with a cleaned-up title.
@MainActor
final class LiveCurrentChatBinder: CurrentChatBinding {
    private let model: AppModel
    private let provider: LiveFrontmostContextProvider
    private let capturer: BindingCapturing
    private let permissions: LivePermissions
    private let card: TransitionCardPresenting?
    private let toggleHotkey: () -> Hotkey?
    private var isRunning = false

    init(model: AppModel, provider: LiveFrontmostContextProvider, capturer: BindingCapturing, permissions: LivePermissions,
         card: TransitionCardPresenting? = nil, toggleHotkey: @escaping () -> Hotkey? = { nil }) {
        self.model = model
        self.provider = provider
        self.capturer = capturer
        self.permissions = permissions
        self.card = card
        self.toggleHotkey = toggleHotkey
    }

    func bindCurrentChat() {
        guard !isRunning else { return }
        start(context: provider.context(interactive: true))
    }

    func toggleCurrentChat() { toggle(allowRestore: true) }

    func toggleCurrentWindow() { toggle(allowRestore: false) }

    private func toggle(allowRestore: Bool) {
        guard !isRunning else { return }
        let decision = TaskToggle.decide(document: model.document, lastRemoved: model.lastRemoved, now: model.clock(),
                                         allowRestore: allowRestore) {
            provider.context(interactive: true)
        }
        guard let context = TaskToggleApplier.apply(decision, model: model, card: card, hotkey: toggleHotkey()) else { return }
        start(context: context)
    }

    /// Binding from an already read context (diagnostics come from the same read).
    private func start(context: FrontmostContext) {
        let diagnostics = provider.lastDiagnostics
        log.info("Привязка: \(context.bundleID ?? "-", privacy: .public), вкладка \(context.chromeTab != nil), Claude \(diagnostics.claudeChat?.rawValue ?? "-", privacy: .public), ChatGPT \(diagnostics.chatGPTThread?.status.rawValue ?? "-", privacy: .public)")
        isRunning = true
        // Dialogs — outside the hotkey/menu handler.
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.proceed(context: context, diagnostics: diagnostics)
                self.isRunning = false
            }
        }
    }

    // MARK: - Flow

    private var shownDialog = false

    private func proceed(context: FrontmostContext, diagnostics: ContextDiagnostics) {
        shownDialog = false
        defer { if shownDialog { returnFocus(to: context.bundleID) } }

        let kind = BindApps.kind(of: context.bundleID)
        if kind == .chrome, context.chromeTab == nil {
            switch diagnostics.chromeAutomation {
            case .requiresConsent?:
                // System prompt; after consent we bind the Chrome tab again.
                permissions.requestChromeAutomation { [weak self] status in
                    guard let self, status == .granted else { return }
                    let retry = self.provider.context(interactive: true, bundleID: BindApps.chrome)
                    self.proceed(context: retry, diagnostics: self.provider.lastDiagnostics)
                }
                return
            case .denied?:
                shownDialog = true
                LivePermissions.showChromeInstructions()
                return
            default:
                break
            }
        }
        if kind == .terminal, context.terminalWindow == nil, diagnostics.terminalAutomation == .requiresConsent {
            // System prompt for Terminal control; after the answer we bind again:
            // allowed — window and tab (window id, tty), denied — as a regular window, by title.
            permissions.requestTerminalAutomation { [weak self] status in
                guard let self else { return }
                var retry = context
                var retryDiagnostics = diagnostics
                if status == .granted {
                    retry = self.provider.context(interactive: true, bundleID: BindApps.terminal)
                    retryDiagnostics = self.provider.lastDiagnostics
                }
                // Don't ask in a loop: the outcome of the prompt is already known.
                if retryDiagnostics.terminalAutomation == .requiresConsent { retryDiagnostics.terminalAutomation = status }
                self.proceed(context: retry, diagnostics: retryDiagnostics)
            }
            return
        }
        // ChatGPT too: without Accessibility the window title can't be read, and the thread is looked up by it.
        // Terminal without AppleScript is bound by window title — Accessibility is needed too.
        let needsTitle = kind == .claude || kind == .chatGPT || kind == .other || (kind == .terminal && context.terminalWindow == nil)
        if needsTitle, !diagnostics.accessibilityTrusted, context.bundleID != nil {
            shownDialog = true
            if permissions.offerAccessibilityOnce() { return }
        }

        switch capturer.captureBinding(from: context) {
        case .captured(let binding, let title):
            commit(binding, suggestedTitle: title)
        case .needsManualLink(let source, let title):
            guard let binding = askForLink(source: source, context: context, chatGPTLookup: diagnostics.chatGPTThread) else { return }
            commit(binding, suggestedTitle: title)
        case .failed(let message):
            shownDialog = true
            Dialogs.info(BindTexts.bindFailedTitle, message)
        }
    }

    private func commit(_ binding: TaskBinding, suggestedTitle: String) {
        let now = model.clock()
        switch BindPlanner.plan(document: model.document, binding: binding) {
        case .alreadyBound(let id, let number):
            model.markVisited(id)
            shownDialog = true
            Dialogs.info(BindTexts.alreadyBound(number: number))

        case .offerAttach(let id, let number, let taskTitle):
            shownDialog = true
            let alert = NSAlert()
            alert.messageText = BindTexts.offerAttachTitle(number: number, taskTitle: taskTitle)
            alert.informativeText = BindTexts.offerAttachMessage(suggestedTitle: suggestedTitle)
            alert.addButton(withTitle: BindTexts.attachButton(number: number))
            alert.addButton(withTitle: BindTexts.createNewButton)
            alert.addButton(withTitle: BindTexts.cancelButton)
            switch Dialogs.run(alert) {
            case .alertFirstButtonReturn:
                model.update { BindPlanner.attach(binding, to: id, in: &$0, suggestedTitle: suggestedTitle, now: now) }
            case .alertSecondButtonReturn:
                createTask(binding, title: suggestedTitle, now: now)
            default:
                return
            }

        case .createNew:
            createTask(binding, title: suggestedTitle, now: now)
        }
    }

    private func createTask(_ binding: TaskBinding, title: String, now: Date) {
        var id: UUID?
        model.update { id = BindPlanner.createTask(in: &$0, title: title, binding: binding, now: now) }
        if let id { TaskToggleApplier.showAdded(id, model: model, card: card) }
    }

    // MARK: - Link prompt

    /// Dialog with an input field. For ChatGPT with several threads of the same title, a link to
    /// the most recently updated one is prefilled; otherwise — the clipboard link, if it's recognized.
    /// "Bind window only" — the fallback path without a chat id.
    private func askForLink(source: BindingSource, context: FrontmostContext, chatGPTLookup: ChatGPTThreadLookup?) -> TaskBinding? {
        shownDialog = true
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 380, height: 24))
        field.placeholderString = BindTexts.manualLinkPlaceholder
        let prefill = source == .chatGPTThread
            ? BindingCapture.chatGPTPrefillLink(lookup: chatGPTLookup, windowTitle: context.windowTitle) : nil
        if let prefill {
            field.stringValue = prefill
        } else if let clip = NSPasteboard.general.string(forType: .string),
           case .binding = BindingCapture.bindingFromManualLink(clip, expected: source, windowTitle: context.windowTitle) {
            field.stringValue = clip.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let baseMessage = source == .chatGPTThread
            ? BindTexts.chatGPTLinkMessage(lookup: chatGPTLookup?.applies(toWindowTitle: context.windowTitle) == true ? chatGPTLookup : nil,
                                           accessibilityTrusted: AX.isTrusted)
            : BindTexts.manualLinkMessage(source, accessibilityTrusted: AX.isTrusted)
        var message = baseMessage
        while true {
            let alert = NSAlert()
            alert.messageText = BindTexts.manualLinkTitle(source)
            alert.informativeText = message
            alert.accessoryView = field
            alert.addButton(withTitle: BindTexts.bindButton)
            alert.addButton(withTitle: BindTexts.bindWindowOnlyButton)
            alert.addButton(withTitle: BindTexts.cancelButton)
            alert.window.initialFirstResponder = field
            switch Dialogs.run(alert) {
            case .alertFirstButtonReturn:
                switch BindingCapture.bindingFromManualLink(field.stringValue, expected: source, windowTitle: context.windowTitle) {
                case .binding(let binding): return binding
                case .invalid(let error): message = error + "\n\n" + baseMessage
                }
            case .alertSecondButtonReturn:
                guard let bundleID = context.bundleID else { return nil }
                return .appWindow(AppWindowRef(bundleID: bundleID, windowTitle: context.windowTitle ?? "", appName: context.appName ?? ""))
            default:
                return nil
            }
        }
    }

    /// After the dialogs, return focus to the app whose chat was being bound.
    private func returnFocus(to bundleID: String?) {
        guard let bundleID, let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return }
        app.activate(options: [])
    }
}
