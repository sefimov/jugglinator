import Carbon
import Combine
import Foundation
import JugglerCore

/// Global hotkeys via Carbon `RegisterEventHotKey`.
///
/// Virtual key codes are registered, not characters, so hotkeys work the same
/// in Russian and English layouts. No Accessibility permission is needed.
/// When assignments in `HotkeyPreferences` change, hotkeys re-register themselves.
@MainActor
final class CarbonHotkeyCenter: HotkeyRegistering {
    /// 'JGLR' — signature of the app's hotkeys.
    nonisolated static let appSignature: OSType = 0x4A47_4C52
    /// 'JGLT' — signature for the self-test.
    nonisolated static let testSignature: OSType = 0x4A47_4C54

    let preferences: HotkeyPreferences
    private let signature: OSType

    private var eventHandler: EventHandlerRef?
    private var registered: [HotkeyAction: EventHotKeyRef] = [:]
    private var handler: ((HotkeyAction) -> Void)?
    private var assignmentsSubscription: AnyCancellable?
    private var suspendCount = 0

    init(preferences: HotkeyPreferences, signature: OSType = CarbonHotkeyCenter.appSignature) {
        self.preferences = preferences
        self.signature = signature
    }

    var isStarted: Bool { handler != nil }
    var registeredActions: Set<HotkeyAction> { Set(registered.keys) }
    var hasEventHandler: Bool { eventHandler != nil }

    // MARK: HotkeyRegistering

    func start(handler: @escaping (HotkeyAction) -> Void) {
        self.handler = handler
        installEventHandlerIfNeeded()
        registerAll()
        assignmentsSubscription = preferences.$assignments
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] (new: HotkeyAssignments) in
                // @Published emits the value before it is stored in the property — register that value.
                // Assignments change only on the main thread.
                guard let self else { return }
                MainActor.assumeIsolated { self.applyAssignments(new) }
            }
    }

    func stop() {
        assignmentsSubscription = nil
        unregisterAll()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
        handler = nil
        suspendCount = 0
    }

    private func applyAssignments(_ assignments: HotkeyAssignments) {
        registerAll(assignments)
    }

    // MARK: Pause while a shortcut is being recorded in settings

    /// Unregister hotkeys so the key press being recorded reaches the settings window.
    func suspend() {
        suspendCount += 1
        if suspendCount == 1 { unregisterAll() }
    }

    func resume() {
        guard suspendCount > 0 else { return }
        suspendCount -= 1
        if suspendCount == 0, isStarted { registerAll() }
    }

    // MARK: Registration

    /// Re-registers all assigned hotkeys. Returns errors per action.
    @discardableResult
    func registerAll(_ assignments: HotkeyAssignments? = nil) -> [HotkeyAction: OSStatus] {
        unregisterAll()
        guard suspendCount == 0 else { return [:] }
        let assignments = assignments ?? preferences.assignments
        var errors: [HotkeyAction: OSStatus] = [:]
        for (index, action) in HotkeyAction.allCases.enumerated() {
            guard let hotkey = assignments[action] else { continue }
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: signature, id: UInt32(index + 1))
            let status = RegisterEventHotKey(
                hotkey.keyCode, hotkey.modifiers.carbonFlags, id,
                GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                registered[action] = ref
            } else {
                errors[action] = status
                switchLog.error("Хоткей \(hotkey.storageString, privacy: .public) для \(action.rawValue, privacy: .public) не зарегистрирован: \(status)")
            }
        }
        preferences.registrationErrors = errors
        return errors
    }

    /// Unregisters all hotkeys. Returns `UnregisterEventHotKey` errors, if any.
    @discardableResult
    func unregisterAll() -> [OSStatus] {
        var failures: [OSStatus] = []
        for (_, ref) in registered {
            let status = UnregisterEventHotKey(ref)
            if status != noErr { failures.append(status) }
        }
        registered.removeAll()
        return failures
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetApplicationEventTarget(), carbonHotkeyCallback, 1, &type,
            Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        if status != noErr {
            switchLog.error("InstallEventHandler для хоткеев: \(status)")
        }
    }

    fileprivate func handleHotkey(id: EventHotKeyID) -> OSStatus {
        guard id.signature == signature else { return OSStatus(eventNotHandledErr) }
        let index = Int(id.id) - 1
        guard HotkeyAction.allCases.indices.contains(index) else { return OSStatus(eventNotHandledErr) }
        let action = HotkeyAction.allCases[index]
        // Leave the Carbon callback before performing the action (AppleScript, activation).
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.handler?(action) }
        }
        return noErr
    }
}

/// Carbon C callback: events arrive at the application target on the main thread.
private func carbonHotkeyCallback(
    _ next: EventHandlerCallRef?, _ event: EventRef?, _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var id = EventHotKeyID()
    let status = GetEventParameter(
        event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
        nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
    guard status == noErr else { return status }
    let center = Unmanaged<CarbonHotkeyCenter>.fromOpaque(userData).takeUnretainedValue()
    return MainActor.assumeIsolated { center.handleHotkey(id: id) }
}
