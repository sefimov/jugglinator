import AppKit
import ApplicationServices
import Foundation
import JugglerCore
import os

private let log = Logger(subsystem: JugglerLog.subsystem, category: "bind")

/// Разрешения Accessibility и Automation (Chrome) и понятные пользователю запросы.
///
/// Ничего не запрашивается само по себе: только из действий пользователя
/// (привязка, переключение на вкладку Chrome, кнопка в интерфейсе).
@MainActor
final class LivePermissions: PermissionsProviding {
    private let chrome: ChromeController
    private var chromeDeniedShown = false
    private var accessibilityAsked = false
    private var chromeRequestInFlight = false

    init(chrome: ChromeController) {
        self.chrome = chrome
    }

    var isAccessibilityTrusted: Bool { AX.isTrusted }

    /// Статус управления Chrome без запроса.
    var chromeAutomationStatus: AutomationStatus { chrome.automationStatus().status }

    /// Объяснение и переход в настройки. Системный запрос `AXIsProcessTrustedWithOptions`
    /// добавляет Juggler в список «Универсальный доступ».
    func requestAccessibility() {
        guard !AX.isTrusted else { return }
        let alert = NSAlert()
        alert.messageText = BindTexts.accessibilityTitle
        alert.informativeText = BindTexts.accessibilityMessage
        alert.addButton(withTitle: BindTexts.openSettingsButton)
        alert.addButton(withTitle: BindTexts.laterButton)
        guard Dialogs.run(alert) == .alertFirstButtonReturn else { return }
        openAccessibilitySettings()
    }

    /// Предложить разрешение один раз за запуск (в сценарии привязки). Возвращает `true`,
    /// если пользователь пошёл в настройки.
    func offerAccessibilityOnce() -> Bool {
        guard !AX.isTrusted, !accessibilityAsked else { return false }
        accessibilityAsked = true
        let alert = NSAlert()
        alert.messageText = BindTexts.accessibilityTitle
        alert.informativeText = BindTexts.accessibilityMessage
        alert.addButton(withTitle: BindTexts.openSettingsButton)
        alert.addButton(withTitle: BindTexts.continueWithoutButton)
        guard Dialogs.run(alert) == .alertFirstButtonReturn else { return false }
        openAccessibilitySettings()
        return true
    }

    func openAccessibilitySettings() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: BindTexts.accessibilitySettingsURL) { NSWorkspace.shared.open(url) }
    }

    /// Системный запрос Automation для Chrome (в фоне). При отказе — инструкция.
    func requestChromeAutomation(completion: (@MainActor (AutomationStatus) -> Void)? = nil) {
        guard !chromeRequestInFlight else { return }
        chromeRequestInFlight = true
        chrome.requestAutomation { [weak self] status, code in
            guard let self else { return }
            self.chromeRequestInFlight = false
            log.info("Запрос Automation Chrome: \(status.rawValue, privacy: .public) (\(code))")
            if status == .denied { self.reportChromeDenied(force: true) }
            completion?(status)
        }
    }

    /// Отказ -1743: показать инструкцию (не чаще раза за запуск, если не `force`).
    /// Окно показывается асинхронно, чтобы не блокировать переключение.
    func reportChromeDenied(force: Bool = false) {
        guard force || !chromeDeniedShown else { return }
        chromeDeniedShown = true
        DispatchQueue.main.async {
            MainActor.assumeIsolated { Self.showChromeInstructions() }
        }
    }

    static func showChromeInstructions() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = BindTexts.chromeDeniedTitle
        alert.informativeText = BindTexts.chromeDeniedMessage
        alert.addButton(withTitle: BindTexts.openSettingsButton)
        alert.addButton(withTitle: BindTexts.laterButton)
        if Dialogs.run(alert) == .alertFirstButtonReturn, let url = URL(string: BindTexts.automationSettingsURL) {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Модальные окна из фонового (accessory) приложения: сначала активируем Juggler,
/// иначе окно окажется под чужими окнами.
@MainActor
enum Dialogs {
    static func run(_ alert: NSAlert) -> NSApplication.ModalResponse {
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal()
    }

    static func info(_ title: String, _ message: String = "") {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        _ = run(alert)
    }
}
