import AppKit
import ApplicationServices
import Foundation
import JugglerCore
import os

private let log = Logger(subsystem: JugglerLog.subsystem, category: "bind")

/// Accessibility and Automation (Chrome, Terminal) permissions and user-friendly prompts.
///
/// Nothing is requested on its own: only from user actions
/// (binding, switching to a Chrome tab, a button in the UI). Terminal control
/// is requested only when binding a Terminal window and via the button in settings — not when switching.
@MainActor
final class LivePermissions: PermissionsProviding {
    private let chrome: ChromeController
    let terminal: TerminalController
    private var chromeDeniedShown = false
    private var accessibilityAsked = false
    private var chromeRequestInFlight = false
    private var terminalRequestInFlight = false

    init(chrome: ChromeController, terminal: TerminalController) {
        self.chrome = chrome
        self.terminal = terminal
    }

    var isAccessibilityTrusted: Bool { AX.isTrusted }

    /// Chrome control status without prompting.
    var chromeAutomationStatus: AutomationStatus { chrome.automationStatus().status }

    /// Terminal control status without prompting.
    var terminalAutomationStatus: AutomationStatus { terminal.automationStatus().status }

    /// Explanation and a jump to settings. The `AXIsProcessTrustedWithOptions` system prompt
    /// adds Juggler to the "Accessibility" list.
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

    /// Offer the permission once per launch (in the binding flow). Returns `true`
    /// if the user went to settings.
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

    /// System Automation prompt for Chrome (in the background). On denial — instructions.
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

    /// System Automation prompt for Terminal (in the background). Shows no instructions on denial:
    /// without permission the Terminal window is simply bound as a regular window.
    func requestTerminalAutomation(completion: (@MainActor (AutomationStatus) -> Void)? = nil) {
        guard !terminalRequestInFlight else { return }
        terminalRequestInFlight = true
        terminal.requestAutomation { [weak self] status, code in
            guard let self else { return }
            self.terminalRequestInFlight = false
            log.info("Запрос Automation Терминала: \(status.rawValue, privacy: .public) (\(code))")
            completion?(status)
        }
    }

    static func showTerminalInstructions() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = BindTexts.terminalDeniedTitle
        alert.informativeText = BindTexts.terminalDeniedMessage
        alert.addButton(withTitle: BindTexts.openSettingsButton)
        alert.addButton(withTitle: BindTexts.laterButton)
        if Dialogs.run(alert) == .alertFirstButtonReturn, let url = URL(string: BindTexts.automationSettingsURL) {
            NSWorkspace.shared.open(url)
        }
    }

    /// Denial -1743: show instructions (at most once per launch, unless `force`).
    /// The window is shown asynchronously so as not to block switching.
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

/// Modal windows from a background (accessory) app: activate Juggler first,
/// otherwise the window ends up beneath other windows.
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
