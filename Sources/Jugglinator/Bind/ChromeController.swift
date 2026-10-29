import AppKit
import Foundation
import JugglerCore

// The shared part (Automation check without prompting, running scripts) is in AppleScriptController.swift.

/// AppleScript for Chrome.
@MainActor
final class ChromeController: AppleScriptController {
    init(bundleID: String = BindApps.chrome) {
        super.init(bundleID: bundleID, logName: "Chrome")
    }

    /// The active tab, if permission is granted. The status explains why there's no tab.
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

    /// Check for the self-test: the scripts compile (without sending events to Chrome).
    func compileScripts() -> String? {
        compile([ChromeScripts.activeTabSource(bundleID: bundleID),
                 ChromeScripts.tabListingSource(bundleID: bundleID),
                 ChromeScripts.focusTabSource(windowID: 1, tabIndex: 1, bundleID: bundleID)])
    }
}
