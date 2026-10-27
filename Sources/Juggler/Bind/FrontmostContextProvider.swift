import AppKit
import Foundation
import JugglerCore
import os

private let log = Logger(subsystem: JugglerLog.subsystem, category: "bind")

/// Читает контекст переднего окна: приложение (NSWorkspace), заголовок окна (Accessibility),
/// активную вкладку Chrome (AppleScript, только при выданном разрешении), id чата Claude
/// (Accessibility + `AXManualAccessibility`). Системных запросов не показывает.
///
/// Если впереди сам Juggler (меню в меню-баре), берётся последнее активное другое приложение.
@MainActor
final class LiveFrontmostContextProvider: FrontmostContextProviding {
    let chrome: ChromeController
    private(set) var lastDiagnostics = ContextDiagnostics()
    private var rememberedApp: AppIdentity?
    private var observer: NSObjectProtocol?
    private let ownPID = ProcessInfo.processInfo.processIdentifier
    private let ownBundleID = Bundle.main.bundleIdentifier
    /// Приложения, у которых уже включён `AXManualAccessibility` (pid).
    private var manualAccessibilityEnabled = Set<pid_t>()

    init(chrome: ChromeController) {
        self.chrome = chrome
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
    func context(interactive: Bool, bundleID: String? = nil) -> FrontmostContext {
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
            diagnostics.claudeCandidateURLs = read.urls
            diagnostics.claudeChat = ClaudeChatURLExtractor.status(
                candidates: read.urls, treeAvailable: read.foundWebArea, accessibilityTrusted: true)
            if !read.manualAccepted { diagnostics.notes.append("Claude не принял AXManualAccessibility") }

        case .chatGPT:
            diagnostics.notes.append("Id треда ChatGPT автоматически не читается: нужна ссылка codex://threads/<id>")

        case .other:
            break
        }
        lastDiagnostics = diagnostics
        return context
    }

    // MARK: - Внутреннее

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
            if ClaudeChatURLExtractor.conversationID(fromCandidates: last.urls) != nil { break }
            if attempt + 1 < attempts { Thread.sleep(forTimeInterval: 0.15) }
        }
        log.debug("Claude AX: веб-область \(last.foundWebArea), адресов \(last.urls.count)")
        return (last.urls, last.foundWebArea, manualAccepted)
    }
}
