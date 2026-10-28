import AppKit
import ApplicationServices
import Foundation
import JugglerCore
import os

// Папка Sources/Juggler/Bind/ принадлежит задаче BIND.
// Сигнатуры функций `BindModule` — контракт с корнем композиции (App/CompositionRoot.swift),
// точкой входа (App/JugglerApp.swift) и самопроверкой (App/SelfTest.swift).
//
// Состав:
//   AppleScriptController     — проверка Automation без запроса и выполнение AppleScript;
//   ChromeController          — AppleScript для Chrome;
//   TerminalController        — AppleScript для Терминала: окно, tty вкладки, переход;
//   LiveFrontmostContextProvider — контекст переднего окна (NSWorkspace, AX, AppleScript);
//   LiveBindingCapturer       — привязка по контексту (логика в JugglerCore/Bind);
//   LiveBindingActivator      — открытие вкладки, чата, окна; запуск приложения;
//   LivePermissions           — Accessibility, Automation, инструкции;
//   LiveCurrentChatBinder     — «Сделать задачей текущий чат» и ⌃⌥§ «добавить или удалить текущее окно».

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

    /// `card` и `toggleHotkey` — для карточек ⌃⌥§ «добавить или удалить текущее окно» (удалена / возвращена).
    static func makeCurrentChatBinder(model: AppModel, services: BindServices,
                                      card: TransitionCardPresenting? = nil,
                                      toggleHotkey: @escaping () -> Hotkey? = { nil }) -> CurrentChatBinding {
        guard let provider = services.contextProvider as? LiveFrontmostContextProvider,
              let permissions = services.permissions as? LivePermissions else {
            // Подменённые сервисы (например, в самопроверке): без диалогов.
            return MinimalCurrentChatBinder(model: model, services: services, card: card, toggleHotkey: toggleHotkey)
        }
        return LiveCurrentChatBinder(model: model, provider: provider, capturer: services.capturer, permissions: permissions,
                                     card: card, toggleHotkey: toggleHotkey)
    }

    /// `Juggler --probe-frontmost [--delay <сек>] [--app <bundle id>] [--prompt] [--window-title <заголовок>]`:
    /// печатает JSON с контекстом, диагностикой и результатом привязки. Без `--prompt`
    /// системных запросов не показывает (с `--prompt` — запрос управления Chrome или Терминалом, если впереди он).
    /// Для Терминала в `context.terminalWindow` — id окна и tty вкладки. Для ChatGPT в `diagnostics.chatGPTThread` — поиск треда
    /// по заголовку окна в `session_index.jsonl`; `--window-title` подставляет заголовок (проверка без Accessibility).
    /// Код выхода 0, если контекст прочитан.
    static func probeFrontmost(arguments: [String]) -> Int32 {
        let options = ProbeOptions.parse(arguments)
        let chrome = ChromeController()
        let terminal = TerminalController()
        let provider = LiveFrontmostContextProvider(chrome: chrome, terminal: terminal)
        if options.delay > 0 {
            // Крутим цикл событий, чтобы NSWorkspace видел смену переднего приложения.
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

    /// Без запросов разрешений и без окон: проверяется только то, что не трогает пользователя.
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
        let front = TerminalScripts.parseFrontWindow("7\u{1F}/dev/ttys003\u{1F}juggler — -zsh — 214×24")
        results.append(SelfTestResult("BIND: разбор ответа Терминала",
                                      passed: front?.windowID == 7 && front?.tty == "/dev/ttys003"
                                          && TerminalTitle.taskTitle(from: front?.title) == "juggler"))

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

        // Только чтение: есть ли папка метаданных сессий Claude Code (её отсутствие — не ошибка).
        let sessionsRoot = ClaudeCodeSessionMetadata.defaultRoot()
        let sessionsFound = sessionsRoot.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        results.append(SelfTestResult("BIND: метаданные сессий Claude Code", passed: true,
                                      detail: sessionsFound ? "папка найдена" : "папки нет — названия сессий возьмутся из заголовка окна"))

        // Только чтение: список тредов ChatGPT (его отсутствие — не ошибка).
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
            .appendingPathComponent("juggler-bind-self-test-\(UUID().uuidString).json"))), services: services)
        results.append(SelfTestResult("BIND: сценарий привязки собран", passed: binder is LiveCurrentChatBinder))
        return results
    }
}

private let log = Logger(subsystem: JugglerLog.subsystem, category: "bind")

/// Запасной сценарий для подменённых сервисов: без диалогов, только то, что можно без ссылки.
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
        case .createNew: model.update { BindPlanner.createTask(in: &$0, title: title, binding: binding, now: now) }
        }
    }
}
