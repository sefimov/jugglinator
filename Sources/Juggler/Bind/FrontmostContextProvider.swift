import AppKit
import Foundation
import JugglerCore
import os

private let log = Logger(subsystem: JugglerLog.subsystem, category: "bind")

/// Читает контекст переднего окна: приложение (NSWorkspace), заголовок окна (Accessibility),
/// активную вкладку Chrome и переднее окно Терминала с tty вкладки (AppleScript, только при выданном
/// разрешении), id чата Claude
/// или сессии Claude Code (Accessibility + `AXManualAccessibility`). Системных запросов не показывает.
///
/// Название сессии Claude Code читается из её метаданных (`claude-code-sessions`, только чтение)
/// лишь в интерактивном режиме — при привязке; при переключении хватает id.
/// Так же только при привязке тред ChatGPT ищется по заголовку окна в `~/.codex/session_index.jsonl`
/// (только чтение; итог — в `lastDiagnostics.chatGPTThread`). При переключении ChatGPT, как и раньше,
/// узнаётся по заголовку окна.
///
/// Если впереди сам Juggler (меню в меню-баре), берётся последнее активное другое приложение.
@MainActor
final class LiveFrontmostContextProvider: FrontmostContextProviding {
    let chrome: ChromeController
    let terminal: TerminalController
    private(set) var lastDiagnostics = ContextDiagnostics()
    private var rememberedApp: AppIdentity?
    private var observer: NSObjectProtocol?
    private let ownPID = ProcessInfo.processInfo.processIdentifier
    private let ownBundleID = Bundle.main.bundleIdentifier
    /// Приложения, у которых уже включён `AXManualAccessibility` (pid).
    private var manualAccessibilityEnabled = Set<pid_t>()
    /// Папка метаданных сессий Claude Code.
    private let claudeCodeSessionsRoot: URL?
    /// Список тредов ChatGPT (`session_index.jsonl`).
    private let chatGPTIndexURL: URL?

    init(chrome: ChromeController,
         terminal: TerminalController,
         claudeCodeSessionsRoot: URL? = ClaudeCodeSessionMetadata.defaultRoot(),
         chatGPTIndexURL: URL? = ChatGPTSessionIndex.defaultURL()) {
        self.chrome = chrome
        self.terminal = terminal
        self.claudeCodeSessionsRoot = claudeCodeSessionsRoot
        self.chatGPTIndexURL = chatGPTIndexURL
        rememberIfExternal(NSWorkspace.shared.frontmostApplication)
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.rememberIfExternal(app) }
        }
    }

    deinit {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }

    func currentContext() -> FrontmostContext {
        context(interactive: false)
    }

    /// `interactive` — сценарий привязки, запущенный пользователем: для Claude даём Electron
    /// чуть больше времени построить дерево веб-содержимого.
    /// `windowTitleOverride` — только для `--probe-frontmost --window-title`: заголовок вместо прочитанного.
    func context(interactive: Bool, bundleID: String? = nil, windowTitleOverride: String? = nil) -> FrontmostContext {
        var diagnostics = ContextDiagnostics(accessibilityTrusted: AX.isTrusted)
        guard let app = targetApp(bundleID: bundleID, diagnostics: &diagnostics) else {
            diagnostics.notes.append("Переднее приложение не определено")
            lastDiagnostics = diagnostics
            return .unknown
        }
        var context = FrontmostContext(bundleID: app.bundleIdentifier, appName: app.localizedName)
        let pid = app.processIdentifier

        let window = diagnostics.accessibilityTrusted ? AX.focusedWindow(pid: pid) : nil
        if let window, let title = AX.title(of: window) {
            context.windowTitle = title
            diagnostics.windowTitleRead = true
        } else if !diagnostics.accessibilityTrusted {
            diagnostics.notes.append("Нет разрешения «Универсальный доступ»: заголовок окна не прочитан")
        }
        if let windowTitleOverride {
            context.windowTitle = windowTitleOverride
            diagnostics.notes.append("Заголовок окна подставлен ключом --window-title")
        }

        switch BindApps.kind(of: app.bundleIdentifier) {
        case .chrome:
            let tab = chrome.activeTab()
            context.chromeTab = tab.tab
            diagnostics.chromeAutomation = tab.status
            diagnostics.chromeErrorCode = tab.code == 0 ? nil : tab.code
            if chrome.lastCheckTimedOut {
                diagnostics.notes.append("Проверка разрешения Chrome не ответила: на экране ждёт системный запрос")
            }
            if context.windowTitle == nil, let title = tab.tab?.title, !title.isEmpty { context.windowTitle = title }

        case .claude:
            guard diagnostics.accessibilityTrusted else {
                diagnostics.claudeChat = .noAccessibility
                break
            }
            let read = readClaudeChat(pid: pid, window: window, interactive: interactive)
            context.claudeConversationID = ClaudeChatURLExtractor.conversationID(fromCandidates: read.urls)
            context.claudeCodeSessionID = ClaudeChatURLExtractor.sessionID(fromCandidates: read.urls)
            if interactive, let sessionID = context.claudeCodeSessionID {
                let info = ClaudeCodeSessionMetadata.info(sessionID: sessionID, root: claudeCodeSessionsRoot)
                if let title = info?.title, !title.isEmpty {
                    context.claudeCodeSessionTitle = title
                } else {
                    diagnostics.notes.append(info == nil
                        ? "Метаданные сессии Claude Code не найдены: название возьмётся из заголовка окна"
                        : "У сессии Claude Code нет названия: оно возьмётся из заголовка окна")
                }
            }
            diagnostics.claudeCandidateURLs = read.urls
            diagnostics.claudeChat = ClaudeChatURLExtractor.status(
                candidates: read.urls, treeAvailable: read.foundWebArea, accessibilityTrusted: true)
            if !read.manualAccepted { diagnostics.notes.append("Claude не принял AXManualAccessibility") }

        case .chatGPT:
            guard interactive else { break }
            let lookup = ChatGPTThreadMatcher.lookup(
                windowTitle: context.windowTitle,
                index: ChatGPTSessionIndex.read(url: chatGPTIndexURL),
                indexPath: chatGPTIndexURL?.path)
            diagnostics.chatGPTThread = lookup
            if let note = Self.note(for: lookup) { diagnostics.notes.append(note) }
            log.debug("ChatGPT: поиск треда \(lookup.status.rawValue, privacy: .public), совпадений \(lookup.matches.count)")

        case .terminal:
            let front = terminal.frontWindow()
            context.terminalWindow = front.window
            diagnostics.terminalAutomation = front.status
            diagnostics.terminalErrorCode = front.code == 0 ? nil : front.code
            if terminal.lastCheckTimedOut {
                diagnostics.notes.append("Проверка разрешения Терминала не ответила: на экране ждёт системный запрос")
            } else if front.status == .denied || front.status == .requiresConsent {
                diagnostics.notes.append("Нет разрешения управлять Терминалом: окно привяжется как обычное, по заголовку")
            }
            if context.windowTitle == nil, let title = front.window?.title, !title.isEmpty { context.windowTitle = title }

        case .other:
            break
        }
        lastDiagnostics = diagnostics
        return context
    }

    // MARK: - Внутреннее

    private static func note(for lookup: ChatGPTThreadLookup) -> String? {
        switch lookup.status {
        case .found: return nil
        case .ambiguous: return "Тредов ChatGPT с таким названием несколько (\(lookup.matches.count)): нужна проверка ссылки"
        case .notFound: return "Тред ChatGPT с таким названием не найден в session_index.jsonl: нужна ссылка codex://threads/<id>"
        case .noWindowTitle: return "Заголовок окна ChatGPT не прочитан: тред не найти по названию"
        case .indexMissing: return "Нет файла session_index.jsonl: тред ChatGPT не найти по названию"
        case .indexTooLarge: return "Файл session_index.jsonl слишком большой: не читается"
        case .indexUnreadable: return "Файл session_index.jsonl не читается"
        }
    }

    private func rememberIfExternal(_ app: NSRunningApplication?) {
        guard let app, let identity = Self.identity(app),
              !FrontmostAppChooser.isOwn(identity, ownBundleID: ownBundleID, ownPID: ownPID) else { return }
        rememberedApp = identity
    }

    private static func identity(_ app: NSRunningApplication?) -> AppIdentity? {
        guard let app else { return nil }
        return AppIdentity(bundleID: app.bundleIdentifier, name: app.localizedName, pid: app.processIdentifier)
    }

    private func targetApp(bundleID: String?, diagnostics: inout ContextDiagnostics) -> NSRunningApplication? {
        if let bundleID {
            return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
        }
        let remembered = rememberedApp.flatMap { NSRunningApplication(processIdentifier: $0.pid) }
        let chosen = FrontmostAppChooser.choose(
            frontmost: Self.identity(NSWorkspace.shared.frontmostApplication),
            remembered: remembered.flatMap(Self.identity),
            ownBundleID: ownBundleID, ownPID: ownPID)
        guard let chosen else { return nil }
        diagnostics.usedRememberedApp = chosen.usedRemembered
        return NSRunningApplication(processIdentifier: chosen.app.pid)
    }

    private func readClaudeChat(pid: pid_t, window: AXUIElement?, interactive: Bool) -> (urls: [String], foundWebArea: Bool, manualAccepted: Bool) {
        var manualAccepted = true
        if !manualAccessibilityEnabled.contains(pid) {
            manualAccepted = AX.enableManualAccessibility(pid: pid)
            manualAccessibilityEnabled.insert(pid)
        }
        // Electron строит дерево после включения флага не сразу: несколько коротких попыток.
        let attempts = interactive ? 6 : 2
        var last: (urls: [String], foundWebArea: Bool) = ([], false)
        for attempt in 0..<attempts {
            guard let window = window ?? AX.focusedWindow(pid: pid) else { break }
            last = AX.webAreaURLs(in: window)
            if ClaudeChatURLExtractor.link(fromCandidates: last.urls) != nil { break }
            if attempt + 1 < attempts { Thread.sleep(forTimeInterval: 0.15) }
        }
        log.debug("Claude AX: веб-область \(last.foundWebArea), адресов \(last.urls.count)")
        return (last.urls, last.foundWebArea, manualAccepted)
    }
}
