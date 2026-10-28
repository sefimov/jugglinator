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
//   ChromeController          — AppleScript для Chrome, проверка Automation без запроса;
//   LiveFrontmostContextProvider — контекст переднего окна (NSWorkspace, AX, AppleScript);
//   LiveBindingCapturer       — привязка по контексту (логика в JugglerCore/Bind);
//   LiveBindingActivator      — открытие вкладки, чата, окна; запуск приложения;
//   LivePermissions           — Accessibility, Automation, инструкции;
//   LiveCurrentChatBinder     — «Сделать задачей текущий чат».

@MainActor
enum BindModule {
    static func makeServices() -> BindServices {
        let chrome = ChromeController()
        let provider = LiveFrontmostContextProvider(chrome: chrome)
        let permissions = LivePermissions(chrome: chrome)
        return BindServices(
            contextProvider: provider,
            capturer: LiveBindingCapturer(provider: provider),
            activator: LiveBindingActivator(chrome: chrome, permissions: permissions),
            permissions: permissions)
    }

    static func makeCurrentChatBinder(model: AppModel, services: BindServices) -> CurrentChatBinding {
        guard let provider = services.contextProvider as? LiveFrontmostContextProvider,
              let permissions = services.permissions as? LivePermissions else {
            // Подменённые сервисы (например, в будущих проверках): без диалогов.
            return MinimalCurrentChatBinder(model: model, services: services)
        }
        return LiveCurrentChatBinder(model: model, provider: provider, capturer: services.capturer, permissions: permissions)
    }

    /// `Juggler --probe-frontmost [--delay <сек>] [--app <bundle id>] [--prompt]`:
    /// печатает JSON с контекстом, диагностикой и результатом привязки. Без `--prompt`
    /// системных запросов не показывает. Код выхода 0, если контекст прочитан.
    static func probeFrontmost(arguments: [String]) -> Int32 {
        let options = ProbeOptions.parse(arguments)
        let chrome = ChromeController()
        let provider = LiveFrontmostContextProvider(chrome: chrome)
        if options.delay > 0 {
            // Крутим цикл событий, чтобы NSWorkspace видел смену переднего приложения.
            RunLoop.main.run(until: Date().addingTimeInterval(options.delay))
        }
        if options.allowPrompts, chrome.automationStatus().status == .requiresConsent {
            let code = ChromeController.determinePermission(bundleID: chrome.bundleID, ask: true)
            FileHandle.standardError.write("Automation Chrome: \(AutomationStatus.classify(code: code).rawValue) (\(code))\n".data(using: .utf8)!)
        }
        let context = provider.context(interactive: true, bundleID: options.bundleID)
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

    init(model: AppModel, services: BindServices) {
        self.model = model
        self.services = services
    }

    func bindCurrentChat() {
        let context = services.contextProvider.currentContext()
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
