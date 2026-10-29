import AppKit
import Carbon
import Foundation
import JugglerCore
import os

private let log = Logger(subsystem: JugglerLog.subsystem, category: "bind")

/// AppleScript for an app (Chrome, Terminal): Automation check without prompting and running scripts.
///
/// A script runs only when permission is already granted: first we check it via
/// `AEDeterminePermissionToAutomateTarget` without prompting. This way reading context on a hotkey
/// never shows a system dialog and never blocks the main thread.
@MainActor
class AppleScriptController {
    let bundleID: String
    /// App name for the log.
    let logName: String

    init(bundleID: String, logName: String) {
        self.bundleID = bundleID
        self.logName = logName
    }

    var runningApp: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
    }

    var appURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    /// How long to wait for TCC to answer a check without prompting.
    static let checkTimeout: TimeInterval = 0.4
    /// Permission already confirmed in this launch: we don't check again
    /// (revocation still shows up as error -1743 when running a script).
    private var grantedConfirmed = false
    /// A check that hasn't returned yet (stuck behind a system prompt).
    private var pendingCheck: PermissionCheck?
    /// The last check didn't get a TCC answer in time (a system prompt is pending).
    private(set) var lastCheckTimedOut = false

    /// Automation permission state without prompting the user.
    ///
    /// `AEDeterminePermissionToAutomateTarget` blocks even with `askUserIfNeeded = false`
    /// while a system permission prompt for the same process is on screen. So the check
    /// runs in the background with a timeout: if it times out, we assume a user answer is needed.
    func automationStatus() -> (status: AutomationStatus, code: Int) {
        guard runningApp != nil else { return (.notRunning, -600) }
        lastCheckTimedOut = false
        if grantedConfirmed { return (.granted, 0) }
        if let pending = pendingCheck {
            guard let code = pending.result else {
                lastCheckTimedOut = true
                return (.requiresConsent, -1744)
            }
            pendingCheck = nil
            if code != -1744 { return remember(code) }
        }
        let check = PermissionCheck()
        let bundleID = self.bundleID
        DispatchQueue.global(qos: .userInitiated).async {
            check.finish(Self.determinePermission(bundleID: bundleID, ask: false))
        }
        guard let code = check.wait(timeout: Self.checkTimeout) else {
            pendingCheck = check
            lastCheckTimedOut = true
            log.info("Проверка Automation \(self.logName, privacy: .public) не ответила: ждёт системный запрос")
            return (.requiresConsent, -1744)
        }
        return remember(code)
    }

    private func remember(_ code: Int) -> (status: AutomationStatus, code: Int) {
        let status = AutomationStatus.classify(code: code)
        if status == .granted { grantedConfirmed = true }
        return (status, code)
    }

    /// Reset the confirmation (after error -1743 when running a script).
    func forgetGranted() { grantedConfirmed = false }

    /// Result of the background check; thread-safe.
    private final class PermissionCheck: @unchecked Sendable {
        private let lock = NSLock()
        private let done = DispatchSemaphore(value: 0)
        private var code: Int?

        var result: Int? { lock.withLock { code } }

        func finish(_ value: Int) {
            lock.withLock { code = value }
            done.signal()
        }

        func wait(timeout: TimeInterval) -> Int? {
            _ = done.wait(timeout: .now() + timeout)
            return result
        }
    }

    /// Request permission (system dialog). The call is blocking, so it runs in the background;
    /// `completion` is called on the main thread.
    func requestAutomation(completion: @escaping @MainActor (AutomationStatus, Int) -> Void) {
        let bundleID = self.bundleID
        DispatchQueue.global(qos: .userInitiated).async {
            let code = Self.determinePermission(bundleID: bundleID, ask: true)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { completion(AutomationStatus.classify(code: code), code) }
            }
        }
    }

    nonisolated static func determinePermission(bundleID: String, ask: Bool) -> Int {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        guard let desc = target.aeDesc else { return -1 }
        let status = AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, ask)
        return Int(status)
    }

    struct ScriptResult {
        var output: String?
        var errorCode: Int
        var errorMessage: String?
        var status: AutomationStatus { output != nil ? .granted : AutomationStatus.classify(code: errorCode) }
    }

    func run(_ source: String) -> ScriptResult {
        guard let script = NSAppleScript(source: source) else {
            return ScriptResult(output: nil, errorCode: -2700, errorMessage: "Скрипт не создан")
        }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            let code = (error[NSAppleScript.errorNumber] as? Int) ?? -1
            let message = error[NSAppleScript.errorMessage] as? String
            log.error("AppleScript \(self.logName, privacy: .public): \(code) \(message ?? "", privacy: .public)")
            if AutomationStatus.isPermissionDenied(code: code) { forgetGranted() }
            return ScriptResult(output: nil, errorCode: code, errorMessage: message)
        }
        return ScriptResult(output: result.stringValue ?? "", errorCode: 0, errorMessage: nil)
    }

    /// The scripts compile (without sending events to the app): for the self-test.
    func compile(_ sources: [String]) -> String? {
        for source in sources {
            guard let script = NSAppleScript(source: source) else { return "скрипт не создан" }
            var error: NSDictionary?
            if !script.compileAndReturnError(&error) {
                return (error?[NSAppleScript.errorMessage] as? String) ?? "ошибка компиляции"
            }
        }
        return nil
    }
}
