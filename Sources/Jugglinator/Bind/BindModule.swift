import AppKit
import ApplicationServices
import Foundation
import JugglerCore
import os

// The Sources/Jugglinator/Bind/ folder belongs to the BIND task.
// The `BindModule` function signatures are the contract with the composition root (App/CompositionRoot.swift),
// the entry point (App/JugglerApp.swift) and the self-test (App/SelfTest.swift).
//
// Contents:
//   AppleScriptController     — Automation check without prompting and running AppleScript;
//   ChromeController          — AppleScript for Chrome;
//   TerminalController        — AppleScript for Terminal: window, tab tty, switching;
//   LiveFrontmostContextProvider — frontmost window context (NSWorkspace, AX, AppleScript);
//   LiveBindingCapturer       — binding from context (logic in JugglerCore/Bind);
//   LiveBindingActivator      — opening a tab, chat, window; launching an app;
//   LivePermissions           — Accessibility, Automation, instructions;
//   LiveCurrentChatBinder     — "Make the current chat a task" and ⌃⌥⇥ "add or remove current window".

@MainActor
enum BindModule {
    static func makeServices() -> BindServices {
        let chrome = ChromeController()
        let terminal = TerminalController()
        let provider = LiveFrontmostContextProvider(chrome: chrome, terminal: terminal)
        let permissions = LivePermissions(chrome: chrome, terminal: terminal)
        return BindServices(
            contextProvider: provider,
            capturer: LiveBindingCapturer(provider: provider),
            activator: LiveBindingActivator(chrome: chrome, terminal: terminal, permissions: permissions),
            permissions: permissions)
    }

    /// `card` and `toggleHotkey` — for the ⌃⌥⇥ "add or remove current window" cards (removed / restored)
    /// and for the "task added" card after binding creates a new task.
    static func makeCurrentChatBinder(model: AppModel, services: BindServices,
                                      card: TransitionCardPresenting? = nil,
                                      toggleHotkey: @escaping () -> Hotkey? = { nil }) -> CurrentChatBinding {
        guard let provider = services.contextProvider as? LiveFrontmostContextProvider,
              let permissions = services.permissions as? LivePermissions else {
            // Substituted services (e.g., in the self-test): no dialogs.
            return MinimalCurrentChatBinder(model: model, services: services, card: card, toggleHotkey: toggleHotkey)
        }
        return LiveCurrentChatBinder(model: model, provider: provider, capturer: services.capturer, permissions: permissions,
                                     card: card, toggleHotkey: toggleHotkey)
    }

    /// `Jugglinator --probe-frontmost [--delay <sec>] [--app <bundle id>] [--prompt] [--window-title <title>]`:
    /// prints JSON with the context, diagnostics and binding result. Without `--prompt`
    /// shows no system prompts (with `--prompt` — the Chrome or Terminal control prompt, if it's in front).
    /// For Terminal, `context.terminalWindow` holds the window id and tab tty. For ChatGPT, `diagnostics.chatGPTThread` holds the thread lookup
    /// by window title in `session_index.jsonl`; `--window-title` substitutes the title (check without Accessibility).
    /// Exit code 0 if the context was read.
    static func probeFrontmost(arguments: [String]) -> Int32 {
        let options = ProbeOptions.parse(arguments)
        let chrome = ChromeController()
        let terminal = TerminalController()
        let provider = LiveFrontmostContextProvider(chrome: chrome, terminal: terminal)
        if options.delay > 0 {
            // Spin the event loop so that NSWorkspace sees the frontmost app change.
            RunLoop.main.run(until: Date().addingTimeInterval(options.delay))
        }
        if options.allowPrompts, chrome.automationStatus().status == .requiresConsent {
            let code = ChromeController.determinePermission(bundleID: chrome.bundleID, ask: true)
            FileHandle.standardError.write("Automation Chrome: \(AutomationStatus.classify(code: code).rawValue) (\(code))\n".data(using: .utf8)!)
        }
        let probesTerminal = BindApps.same(options.bundleID, BindApps.terminal)
            || (options.bundleID == nil && BindApps.same(NSWorkspace.shared.frontmostApplication?.bundleIdentifier, BindApps.terminal))
        if options.allowPrompts, probesTerminal, terminal.automationStatus().status == .requiresConsent {
            let code = TerminalController.determinePermission(bundleID: terminal.bundleID, ask: true)
            FileHandle.standardError.write("Automation Терминала: \(AutomationStatus.classify(code: code).rawValue) (\(code))\n".data(using: .utf8)!)
        }
        let context = provider.context(interactive: true, bundleID: options.bundleID, windowTitleOverride: options.windowTitle)
        let capture = LiveBindingCapturer(provider: provider).captureBinding(from: context)
        print(ProbeReport(context: context, diagnostics: provider.lastDiagnostics, capture: capture).json())
        return context.bundleID == nil ? 1 : 0
    }

    /// No permission prompts and no windows: only checks that don't disturb the user.
    static func selfTest() -> [SelfTestResult] {
        var results: [SelfTestResult] = []
        let services = makeServices()
        results.append(SelfTestResult(
            "BIND: сервисы собраны",
            passed: services.contextProvider is LiveFrontmostContextProvider && services.activator is LiveBindingActivator))

        let trusted = services.permissions.isAccessibilityTrusted
        results.append(SelfTestResult("BIND: проверка Accessibility без запроса", passed: true,
                                      detail: trusted ? "разрешено" : "не разрешено"))

        let chrome = ChromeController()
        if chrome.appURL == nil {
            results.append(SelfTestResult("BIND: AppleScript для Chrome", passed: true, detail: "Chrome не установлен — пропущено"))
        } else {
            let error = chrome.compileScripts()
            results.append(SelfTestResult("BIND: AppleScript для Chrome компилируется", passed: error == nil, detail: error ?? ""))
        }

        let terminal = TerminalController()
        if terminal.appURL == nil {
            results.append(SelfTestResult("BIND: AppleScript для Терминала", passed: true, detail: "Терминал не установлен — пропущено"))
        } else {
            let error = terminal.compileScripts()
            results.append(SelfTestResult("BIND: AppleScript для Терминала компилируется", passed: error == nil, detail: error ?? ""))
        }
        let front = TerminalScripts.parseFrontWindow("7\u{1F}/dev/ttys003\u{1F}jugglinator — -zsh — 214×24")
        results.append(SelfTestResult("BIND: разбор ответа Терминала",
                                      passed: front?.windowID == 7 && front?.tty == "/dev/ttys003"
                                          && TerminalTitle.taskTitle(from: front?.title) == "jugglinator"))

        let missingSymbols = BindingSource.allCases.filter { NSImage(systemSymbolName: $0.symbolName, accessibilityDescription: nil) == nil }
        results.append(SelfTestResult("BIND: значки источников есть в SF Symbols", passed: missingSymbols.isEmpty,
                                      detail: missingSymbols.isEmpty ? "\(BindingSource.allCases.count) источников"
                                          : missingSymbols.map(\.symbolName).joined(separator: ", ")))

        let parsed = ChromeScripts.parseActiveTab("1\u{1F}2\u{1F}https://claude.ai/chat/x\u{1F}T")
        results.append(SelfTestResult("BIND: разбор ответа Chrome", passed: parsed?.tabID == 2 && parsed?.windowID == 1))

        let handlers = [("claude://", ChatLinkParser.claudeAppURL(conversationID: "00000000-0000-0000-0000-000000000000")),
                        ("claude://…/epitaxy", ChatLinkParser.claudeCodeSessionAppURL(sessionID: "local_00000000-0000-0000-0000-000000000000")),
                        ("codex://", ChatLinkParser.chatGPTAppURL(threadID: "x"))]
            .map { "\($0.0) → \(NSWorkspace.shared.urlForApplication(toOpen: $0.1)?.lastPathComponent ?? "нет приложения")" }
        results.append(SelfTestResult("BIND: обработчики ссылок", passed: true, detail: handlers.joined(separator: ", ")))

        // Read-only: whether the Claude Code session metadata folder exists (its absence is not an error).
        let sessionsRoot = ClaudeCodeSessionMetadata.defaultRoot()
        let sessionsFound = sessionsRoot.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        results.append(SelfTestResult("BIND: метаданные сессий Claude Code", passed: true,
                                      detail: sessionsFound ? "папка найдена" : "папки нет — названия сессий возьмутся из заголовка окна"))

        // Read-only: the ChatGPT thread list (its absence is not an error).
        let indexURL = ChatGPTSessionIndex.defaultURL()
        let indexDetail: String
        switch ChatGPTSessionIndex.read(url: indexURL) {
        case .loaded(let threads, let skipped): indexDetail = "тредов: \(threads.count)" + (skipped > 0 ? ", битых строк: \(skipped)" : "")
        case .missing: indexDetail = "файла нет — тред ChatGPT привяжется по ссылке"
        case .tooLarge: indexDetail = "файл слишком большой — не читается"
        case .unreadable: indexDetail = "файл не читается"
        }
        results.append(SelfTestResult("BIND: список тредов ChatGPT (session_index.jsonl)", passed: true, detail: indexDetail))

        let binder = makeCurrentChatBinder(model: AppModel(store: TaskStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("jugglinator-bind-self-test-\(UUID().uuidString).json"))), services: services)
        results.append(SelfTestResult("BIND: сценарий привязки собран", passed: binder is LiveCurrentChatBinder))
        return results
    }
}

private let log = Logger(subsystem: JugglerLog.subsystem, category: "bind")

/// Fallback flow for substituted services: no dialogs, only what's possible without a link.
@MainActor
private final class MinimalCurrentChatBinder: CurrentChatBinding {
    private let model: AppModel
    private let services: BindServices
    private let card: TransitionCardPresenting?
    private let toggleHotkey: () -> Hotkey?

    init(model: AppModel, services: BindServices, card: TransitionCardPresenting?, toggleHotkey: @escaping () -> Hotkey?) {
        self.model = model
        self.services = services
        self.card = card
        self.toggleHotkey = toggleHotkey
    }

    func bindCurrentChat() {
        bind(context: services.contextProvider.currentContext())
    }

    func toggleCurrentChat() { toggle(allowRestore: true) }

    func toggleCurrentWindow() { toggle(allowRestore: false) }

    private func toggle(allowRestore: Bool) {
        let decision = TaskToggle.decide(document: model.document, lastRemoved: model.lastRemoved, now: model.clock(),
                                         allowRestore: allowRestore) {
            services.contextProvider.currentContext()
        }
        guard let context = TaskToggleApplier.apply(decision, model: model, card: card, hotkey: toggleHotkey()) else { return }
        bind(context: context)
    }

    private func bind(context: FrontmostContext) {
        guard case .captured(let binding, let title) = services.capturer.captureBinding(from: context) else {
            log.info("Привязка без диалогов невозможна")
            NSSound.beep()
            return
        }
        let now = model.clock()
        switch BindPlanner.plan(document: model.document, binding: binding) {
        case .alreadyBound(let id, _): model.markVisited(id)
        case .offerAttach(let id, _, _): model.update { BindPlanner.attach(binding, to: id, in: &$0, suggestedTitle: title, now: now) }
        case .createNew:
            var id: UUID?
            model.update { id = BindPlanner.createTask(in: &$0, title: title, binding: binding, now: now) }
            if let id { TaskToggleApplier.showAdded(id, model: model, card: card) }
        }
    }
}
