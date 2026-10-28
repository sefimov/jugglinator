import AppKit
import Foundation
import JugglerCore

/// AppleScript для Terminal.app: переднее окно и вкладка (id окна, tty), список вкладок, переход.
///
/// Как и у Chrome, скрипт выполняется только при уже выданном разрешении — проверка без запроса
/// (`automationStatus`), поэтому чтение контекста и переключение никогда не показывают системный диалог.
@MainActor
final class TerminalController: AppleScriptController {
    init(bundleID: String = BindApps.terminal) {
        super.init(bundleID: bundleID, logName: "Terminal")
    }

    /// Переднее окно и выбранная вкладка, если разрешение выдано. Статус объясняет, почему окна нет.
    func frontWindow() -> (window: TerminalWindowRef?, status: AutomationStatus, code: Int) {
        let permission = automationStatus()
        guard permission.status == .granted else { return (nil, permission.status, permission.code) }
        let result = run(TerminalScripts.frontWindowSource(bundleID: bundleID))
        guard let output = result.output else { return (nil, result.status, result.errorCode) }
        guard let window = TerminalScripts.parseFrontWindow(output) else { return (nil, .noWindow, -1728) }
        return (window, .granted, 0)
    }

    func tabListing() -> (entries: [TerminalTabEntry], result: ScriptResult) {
        let result = run(TerminalScripts.tabListingSource(bundleID: bundleID))
        return (result.output.map(TerminalScripts.parseTabListing) ?? [], result)
    }

    func focus(_ match: TerminalTabMatcher.Match) -> ScriptResult {
        run(TerminalScripts.focusSource(windowID: match.windowID, tabIndex: match.tabIndex, bundleID: bundleID))
    }

    /// Проверка для самопроверки: скрипты компилируются (без отправки событий Терминалу).
    func compileScripts() -> String? {
        compile([TerminalScripts.frontWindowSource(bundleID: bundleID),
                 TerminalScripts.tabListingSource(bundleID: bundleID),
                 TerminalScripts.focusSource(windowID: 1, tabIndex: 1, bundleID: bundleID),
                 TerminalScripts.focusSource(windowID: 1, tabIndex: nil, bundleID: bundleID)])
    }
}
