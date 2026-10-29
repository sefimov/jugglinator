import AppKit
import Foundation
import JugglerCore

/// AppleScript for Terminal.app: front window and tab (window id, tty), tab list, switching.
///
/// As with Chrome, a script runs only when permission is already granted — a check without prompting
/// (`automationStatus`), so reading context and switching never show a system dialog.
@MainActor
final class TerminalController: AppleScriptController {
    init(bundleID: String = BindApps.terminal) {
        super.init(bundleID: bundleID, logName: "Terminal")
    }

    /// The front window and selected tab, if permission is granted. The status explains why there's no window.
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

    /// Check for the self-test: the scripts compile (without sending events to Terminal).
    func compileScripts() -> String? {
        compile([TerminalScripts.frontWindowSource(bundleID: bundleID),
                 TerminalScripts.tabListingSource(bundleID: bundleID),
                 TerminalScripts.focusSource(windowID: 1, tabIndex: 1, bundleID: bundleID),
                 TerminalScripts.focusSource(windowID: 1, tabIndex: nil, bundleID: bundleID)])
    }
}
