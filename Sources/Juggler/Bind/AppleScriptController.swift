import AppKit
import Carbon
import Foundation
import JugglerCore
import os

private let log = Logger(subsystem: JugglerLog.subsystem, category: "bind")

/// AppleScript для приложения (Chrome, Терминал): проверка Automation без запроса и выполнение скриптов.
///
/// Скрипт выполняется только когда разрешение уже выдано: сначала проверяем его через
/// `AEDeterminePermissionToAutomateTarget` без запроса. Так чтение контекста по хоткею
/// никогда не показывает системный диалог и не блокирует главный поток.
@MainActor
class AppleScriptController {
    let bundleID: String
    /// Имя приложения для журнала.
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

    /// Сколько ждать ответа TCC на проверку без запроса.
    static let checkTimeout: TimeInterval = 0.4
    /// Разрешение уже подтверждено в этом запуске: повторно не проверяем
    /// (отзыв всё равно проявится ошибкой -1743 при выполнении скрипта).
    private var grantedConfirmed = false
    /// Проверка, которая ещё не вернулась (висит за системным запросом).
    private var pendingCheck: PermissionCheck?
    /// Последняя проверка не дождалась ответа TCC (висит системный запрос).
    private(set) var lastCheckTimedOut = false

    /// Состояние разрешения Automation без запроса пользователю.
    ///
    /// `AEDeterminePermissionToAutomateTarget` даже с `askUserIfNeeded = false` блокируется,
    /// пока на экране висит системный запрос разрешения для этого же процесса. Поэтому проверка
    /// идёт в фоне с таймаутом: не дождались — считаем, что нужен ответ пользователя.
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

    /// Сбросить подтверждение (после ошибки -1743 при выполнении скрипта).
    func forgetGranted() { grantedConfirmed = false }

    /// Результат фоновой проверки; потокобезопасен.
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

    /// Запросить разрешение (системный диалог). Вызов блокирующий, поэтому идёт в фоне;
    /// `completion` вызывается на главном потоке.
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

    /// Скрипты компилируются (без отправки событий приложению): для самопроверки.
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
