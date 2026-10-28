import AppKit
import Foundation
import JugglerCore
import os

private let log = Logger(subsystem: JugglerLog.subsystem, category: "bind")

/// Привязка по контексту без диалогов: вся логика — в `BindingCapture` (JugglerCore).
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
            ownBundleID: Bundle.main.bundleIdentifier ?? BindApps.juggler,
            chatGPTLookup: provider.lastDiagnostics.chatGPTThread)
    }
}

/// Итог ⌃⌥§ «добавить или удалить текущее окно» (D15): удаление и возврат с карточкой.
/// Логика решения — `TaskToggle` (JugglerCore); здесь только применение к модели и показ карточки.
@MainActor
enum TaskToggleApplier {
    /// Применяет `.restore` и `.remove`; для `.add` возвращает контекст, с которым идти в привязку.
    static func apply(_ decision: ToggleDecision, model: AppModel, card: TransitionCardPresenting?, hotkey: Hotkey?) -> FrontmostContext? {
        let messages = card as? TransitionMessagePresenting
        switch decision {
        case .restore:
            guard let restored = model.restoreLastRemoved(), let number = model.document.number(of: restored.task.id) else {
                NSSound.beep()
                return nil
            }
            log.info("⌃⌥§: задача \(number) возвращена")
            messages?.showMessage(TaskToggleTexts.restoredCard(number: number, title: restored.task.title))
            return nil

        case .remove(let id, let number):
            guard let removed = model.removeTask(id, undoableByToggle: true) else { return nil }
            log.info("⌃⌥§: задача \(number) удалена, переднее окно точно совпало с привязкой")
            messages?.showMessage(TaskToggleTexts.removedCard(number: number, title: removed.task.title, hotkey: hotkey),
                                  duration: TaskRemoval.undoWindow)
            return nil

        case .add(let context):
            return context
        }
    }
}

/// «Сделать задачей текущий чат»; через `toggleCurrentChat` — и ⌃⌥§ «добавить или удалить текущее окно».
///
/// Переключатель: в течение 5 с после удаления ⌃⌥§ возвращает задачу; если переднее окно точно
/// совпадает с задачей (`ExactTaskMatcher`) — удаляет её с карточкой; иначе — привязка, как ниже.
///
/// 1. Читает контекст переднего окна (если впереди Juggler — последнего активного приложения).
/// 2. Строит привязку; для Claude без прочитанного id и для ChatGPT, чей тред не найден по названию
///    однозначно, просит вставить ссылку (при нескольких тредах — с уже вставленной ссылкой на последний).
/// 3. Если чат уже привязан — делает ту задачу текущей; если у текущей задачи нет привязки —
///    предлагает привязать к ней; иначе создаёт новую задачу с очищенным заголовком.
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

    /// Привязка по уже прочитанному контексту (диагностика — от того же чтения).
    private func start(context: FrontmostContext) {
        let diagnostics = provider.lastDiagnostics
        log.info("Привязка: \(context.bundleID ?? "-", privacy: .public), вкладка \(context.chromeTab != nil), Claude \(diagnostics.claudeChat?.rawValue ?? "-", privacy: .public), ChatGPT \(diagnostics.chatGPTThread?.status.rawValue ?? "-", privacy: .public)")
        isRunning = true
        // Диалоги — вне обработчика хоткея/меню.
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.proceed(context: context, diagnostics: diagnostics)
                self.isRunning = false
            }
        }
    }

    // MARK: - Сценарий

    private var shownDialog = false

    private func proceed(context: FrontmostContext, diagnostics: ContextDiagnostics) {
        shownDialog = false
        defer { if shownDialog { returnFocus(to: context.bundleID) } }

        let kind = BindApps.kind(of: context.bundleID)
        if kind == .chrome, context.chromeTab == nil {
            switch diagnostics.chromeAutomation {
            case .requiresConsent?:
                // Системный запрос; после согласия привязываем вкладку Chrome заново.
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
            // Системный запрос управления Терминалом; после ответа привязываем заново:
            // разрешили — окно и вкладку (id окна, tty), нет — как обычное окно, по заголовку.
            permissions.requestTerminalAutomation { [weak self] status in
                guard let self else { return }
                var retry = context
                var retryDiagnostics = diagnostics
                if status == .granted {
                    retry = self.provider.context(interactive: true, bundleID: BindApps.terminal)
                    retryDiagnostics = self.provider.lastDiagnostics
                }
                // Не спрашивать по кругу: итог запроса уже известен.
                if retryDiagnostics.terminalAutomation == .requiresConsent { retryDiagnostics.terminalAutomation = status }
                self.proceed(context: retry, diagnostics: retryDiagnostics)
            }
            return
        }
        // ChatGPT тоже: без Accessibility не прочитать заголовок окна, а по нему ищется тред.
        // Терминал без AppleScript привязывается по заголовку окна — тоже нужен Accessibility.
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
                model.update { BindPlanner.createTask(in: &$0, title: suggestedTitle, binding: binding, now: now) }
            default:
                return
            }

        case .createNew:
            model.update { BindPlanner.createTask(in: &$0, title: suggestedTitle, binding: binding, now: now) }
        }
    }

    // MARK: - Запрос ссылки

    /// Диалог со строкой ввода. Для ChatGPT с несколькими тредами того же названия вставлена ссылка
    /// на последний обновлённый; иначе — ссылка из буфера обмена, если она распознаётся.
    /// «Привязать только окно» — запасной путь без id чата.
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

    /// После диалогов вернуть фокус приложению, чей чат привязывали.
    private func returnFocus(to bundleID: String?) {
        guard let bundleID, let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return }
        app.activate(options: [])
    }
}
