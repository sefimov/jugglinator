import AppKit
import Foundation
import JugglerCore
import os

private let log = Logger(subsystem: JugglerLog.subsystem, category: "bind")

/// Открывает привязанную вкладку, чат или окно. Незапущенное приложение запускается.
@MainActor
final class LiveBindingActivator: BindingActivating {
    private let chrome: ChromeController
    private let terminal: TerminalController
    private let permissions: LivePermissions

    init(chrome: ChromeController, terminal: TerminalController, permissions: LivePermissions) {
        self.chrome = chrome
        self.terminal = terminal
        self.permissions = permissions
    }

    func activate(_ binding: TaskBinding) -> ActivationResult {
        let result: ActivationResult
        switch binding {
        case .chromeTab(let ref): result = activateChrome(ref)
        case .claudeChat(let ref): result = openAppURL(ref.appURL, name: "Claude", webFallback: ChatLinkParser.claudeWebURL(conversationID: ref.conversationID))
        // Локальная сессия Claude Code живёт только в Claude desktop: в браузере её не открыть.
        case .claudeCodeSession(let ref): result = openAppURL(ref.appURL, name: "Claude", webFallback: nil)
        case .chatGPTThread(let ref): result = openAppURL(ref.appURL, name: "ChatGPT", webFallback: nil)
        case .terminalWindow(let ref): result = activateTerminal(ref)
        case .appWindow(let ref): result = activateWindow(ref)
        }
        log.info("Активация \(binding.source.rawValue, privacy: .public): \(String(describing: result), privacy: .public)")
        return result
    }

    // MARK: - Chrome

    private func activateChrome(_ ref: ChromeTabRef) -> ActivationResult {
        guard chrome.runningApp != nil else {
            // Chrome закрыт: открываем адрес — Chrome запустится сам.
            if let url = ChromeTabMatcher.reopenURL(for: ref), open(url, inAppWithBundleID: chrome.bundleID) {
                return .fallback(BindTexts.appLaunched)
            }
            return launch(bundleID: chrome.bundleID, name: "Google Chrome") ? .fallback(BindTexts.appLaunched)
                : .failed(BindTexts.appNotInstalled("Google Chrome"))
        }

        let permission = chrome.automationStatus()
        switch permission.status {
        case .granted:
            break
        case .denied:
            permissions.reportChromeDenied()
            return reopenChrome(ref, message: BindTexts.chromeReopenedNoAccess)
        case .requiresConsent:
            // Спрашиваем в фоне (системный диалог), а пока открываем адрес.
            permissions.requestChromeAutomation()
            return reopenChrome(ref, message: BindTexts.chromeReopenedNoAccess)
        default:
            return reopenChrome(ref, message: BindTexts.chromeReopened)
        }

        let listing = chrome.tabListing()
        if listing.result.output == nil, AutomationStatus.isPermissionDenied(code: listing.result.errorCode) {
            permissions.reportChromeDenied()
            return reopenChrome(ref, message: BindTexts.chromeReopenedNoAccess)
        }
        if let match = ChromeTabMatcher.find(ref, in: listing.entries) {
            let focus = chrome.focus(match.entry)
            if focus.output != nil {
                return match.kind == .byID ? .activated : .fallback("Вкладка найдена по адресу.")
            }
            if AutomationStatus.isPermissionDenied(code: focus.errorCode) { permissions.reportChromeDenied() }
        }
        return reopenChrome(ref, message: BindTexts.chromeReopened)
    }

    private func reopenChrome(_ ref: ChromeTabRef, message: String) -> ActivationResult {
        if let url = ChromeTabMatcher.reopenURL(for: ref), open(url, inAppWithBundleID: chrome.bundleID) {
            return .fallback(message)
        }
        return launch(bundleID: chrome.bundleID, name: "Google Chrome") ? .fallback(BindTexts.chromeActivatedOnly)
            : .failed(BindTexts.appNotInstalled("Google Chrome"))
    }

    // MARK: - Терминал

    /// Вкладка по tty, затем окно по id, затем окно по заголовку без шума; иначе — просто Терминал.
    /// Разрешение только проверяется (без запроса): переключение никогда не показывает системный диалог.
    private func activateTerminal(_ ref: TerminalWindowRef) -> ActivationResult {
        guard let app = terminal.runningApp else {
            return launch(bundleID: terminal.bundleID, name: "Терминал") ? .fallback(BindTexts.terminalLaunched)
                : .failed(BindTexts.appNotInstalled("Терминал"))
        }
        guard terminal.automationStatus().status == .granted else {
            return activateTerminalWithoutAccess(ref, app: app)
        }
        let listing = terminal.tabListing()
        guard listing.result.output != nil else {
            log.info("Терминал: список вкладок не прочитан (\(listing.result.errorCode))")
            return activateTerminalWithoutAccess(ref, app: app)
        }
        if let match = TerminalTabMatcher.find(ref, in: listing.entries) {
            if terminal.focus(match).output != nil {
                switch match.kind {
                case .byTTY: return .activated
                case .byWindowID: return ref.tty.isEmpty ? .activated : .fallback(BindTexts.terminalTabClosed)
                case .byTitle: return .fallback(BindTexts.terminalFoundByTitle)
                }
            }
        }
        bringToFront(app, bundleID: terminal.bundleID)
        return .fallback(BindTexts.terminalWindowClosed)
    }

    /// Без AppleScript: окно по заголовку через Accessibility (вкладку так не выбрать) и Терминал вперёд.
    private func activateTerminalWithoutAccess(_ ref: TerminalWindowRef, app: NSRunningApplication) -> ActivationResult {
        var raised = false
        if AX.isTrusted, !ref.title.trimmingCharacters(in: .whitespaces).isEmpty {
            let pid = app.processIdentifier
            let windows = AX.windows(pid: pid)
            let titles = windows.map { AX.title(of: $0) ?? "" }
            if let index = WindowTitleMatcher.bestIndex(of: ref.title, in: titles, bundleID: terminal.bundleID) {
                raised = AX.raise(windows[index], pid: pid)
            }
        }
        bringToFront(app, bundleID: terminal.bundleID)
        return .fallback(raised ? BindTexts.terminalNoAccessByTitle : BindTexts.terminalNoAccess)
    }

    // MARK: - Claude, ChatGPT

    private func openAppURL(_ url: URL, name: String, webFallback: URL?) -> ActivationResult {
        if NSWorkspace.shared.urlForApplication(toOpen: url) != nil {
            NSWorkspace.shared.open(url)
            return .activated
        }
        if let webFallback {
            NSWorkspace.shared.open(webFallback)
            return .fallback("Приложение \(name) не найдено — чат открыт в браузере.")
        }
        return .failed(BindTexts.urlNotHandled(name))
    }

    // MARK: - Окно

    private func activateWindow(_ ref: AppWindowRef) -> ActivationResult {
        let name = ref.appName.isEmpty ? ref.bundleID : ref.appName
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: ref.bundleID).first else {
            return launch(bundleID: ref.bundleID, name: name) ? .fallback(BindTexts.appLaunched)
                : .failed(BindTexts.appNotInstalled(name))
        }
        let pid = app.processIdentifier
        let wantsWindow = !ref.windowTitle.trimmingCharacters(in: .whitespaces).isEmpty
        var raised = false
        if wantsWindow, AX.isTrusted {
            let windows = AX.windows(pid: pid)
            let titles = windows.map { AX.title(of: $0) ?? "" }
            if let index = WindowTitleMatcher.bestIndex(of: ref.windowTitle, in: titles, bundleID: ref.bundleID) {
                raised = AX.raise(windows[index], pid: pid)
            }
        }
        bringToFront(app, bundleID: ref.bundleID)
        if !wantsWindow || raised { return .activated }
        return .fallback(AX.isTrusted ? BindTexts.windowNotFound : BindTexts.windowNoAccessibility)
    }

    // MARK: - Общее

    /// Активация уже запущенного приложения. С macOS 14 `activate()` из фонового приложения
    /// может не сработать, поэтому дополнительно просим LaunchServices (как `open -a`).
    private func bringToFront(_ app: NSRunningApplication, bundleID: String) {
        app.unhide()
        app.activate(options: [.activateAllWindows])
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
                if let error { log.error("Не удалось активировать \(bundleID, privacy: .public): \(error.localizedDescription, privacy: .public)") }
            }
        }
    }

    private func launch(bundleID: String, name: String) -> Bool {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            if let error { log.error("Не удалось запустить \(name, privacy: .public): \(error.localizedDescription, privacy: .public)") }
        }
        return true
    }

    private func open(_ url: URL, inAppWithBundleID bundleID: String) -> Bool {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: configuration) { _, error in
            if let error { log.error("Не удалось открыть адрес: \(error.localizedDescription, privacy: .public)") }
        }
        return true
    }
}
