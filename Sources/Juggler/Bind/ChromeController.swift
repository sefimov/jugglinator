import AppKit
import Foundation
import JugglerCore

// Общая часть (проверка Automation без запроса, выполнение скриптов) — в AppleScriptController.swift.

/// AppleScript для Chrome.
@MainActor
final class ChromeController: AppleScriptController {
    init(bundleID: String = BindApps.chrome) {
        super.init(bundleID: bundleID, logName: "Chrome")
    }

    /// Активная вкладка, если разрешение выдано. Статус объясняет, почему вкладки нет.
    func activeTab() -> (tab: ChromeTabRef?, status: AutomationStatus, code: Int) {
        let permission = automationStatus()
        guard permission.status == .granted else { return (nil, permission.status, permission.code) }
        let result = run(ChromeScripts.activeTabSource(bundleID: bundleID))
        guard let output = result.output else { return (nil, result.status, result.errorCode) }
        guard let tab = ChromeScripts.parseActiveTab(output) else { return (nil, .noWindow, -1728) }
        return (tab, .granted, 0)
    }

    func tabListing() -> (entries: [ChromeTabEntry], result: ScriptResult) {
        let result = run(ChromeScripts.tabListingSource(bundleID: bundleID))
        return (result.output.map(ChromeScripts.parseTabListing) ?? [], result)
    }

    func focus(_ entry: ChromeTabEntry) -> ScriptResult {
        run(ChromeScripts.focusTabSource(windowID: entry.windowID, tabIndex: entry.index, bundleID: bundleID))
    }

    /// Проверка для самопроверки: скрипты компилируются (без отправки событий Chrome).
    func compileScripts() -> String? {
        compile([ChromeScripts.activeTabSource(bundleID: bundleID),
                 ChromeScripts.tabListingSource(bundleID: bundleID),
                 ChromeScripts.focusTabSource(windowID: 1, tabIndex: 1, bundleID: bundleID)])
    }
}
