import Carbon
import Foundation
import JugglerCore
import os

/// The app's hotkey assignments: defaults by keyboard type + the user's custom shortcuts
/// from `~/Library/Application Support/Juggler/hotkeys.json`.
///
/// A single instance (`SwitchModule.preferences`) is shared by the hotkey registrar,
/// the switcher (hint on the card) and the settings section.
@MainActor
final class HotkeyPreferences: ObservableObject {
    let keyboard: KeyboardKind
    let defaults: HotkeyAssignments

    @Published private(set) var overrides: HotkeyOverrides
    /// Effective assignments (what actually gets registered).
    @Published private(set) var assignments: HotkeyAssignments
    /// Registration errors per action (OSStatus ≠ noErr), filled in by `CarbonHotkeyCenter`.
    @Published var registrationErrors: [HotkeyAction: OSStatus] = [:]
    /// Text of the last file write error, or `nil`.
    @Published private(set) var lastSaveError: String?

    private let store: HotkeyOverridesStore?

    /// `store == nil` — in memory only (self-test).
    init(store: HotkeyOverridesStore?, keyboard: KeyboardKind = KeyboardDetector.current()) {
        self.store = store
        self.keyboard = keyboard
        self.defaults = HotkeyAssignments.defaults(for: keyboard)
        var loaded = HotkeyOverrides()
        if let store {
            let result = store.load()
            loaded = result.overrides
            if case .corrupt(let reason) = result.outcome {
                switchLog.error("hotkeys.json не разобран, взяты умолчания: \(reason, privacy: .public)")
            }
        }
        self.overrides = loaded
        self.assignments = HotkeyAssignments.resolve(overrides: loaded, defaults: defaults)
    }

    func isCustom(_ action: HotkeyAction) -> Bool {
        overrides.hotkeys[action] != nil
    }

    /// Assign a shortcut. Returns a validation error, or `nil` on success.
    @discardableResult
    func assign(_ hotkey: Hotkey, to action: HotkeyAction) -> HotkeyValidationError? {
        var copy = overrides
        if let error = copy.assign(hotkey, to: action, defaults: defaults) { return error }
        apply(copy)
        return nil
    }

    func reset(_ action: HotkeyAction) {
        var copy = overrides
        copy.reset(action)
        apply(copy)
    }

    func resetAll() {
        apply(HotkeyOverrides())
    }

    private func apply(_ new: HotkeyOverrides) {
        guard new != overrides else { return }
        overrides = new
        assignments = HotkeyAssignments.resolve(overrides: new, defaults: defaults)
        guard let store else { return }
        do {
            try store.save(new)
            lastSaveError = nil
        } catch {
            lastSaveError = loc("Не удалось сохранить хоткеи: \(error.localizedDescription)")
            switchLog.error("Ошибка записи hotkeys.json: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// Physical keyboard type via Carbon `KBGetLayoutType(LMGetKbdType())`.
/// The function is missing from the Command Line Tools SDK headers, but HIToolbox
/// exports it — we get it via `dlsym`. If not found, assume an ANSI keyboard.
enum KeyboardDetector {
    private typealias LayoutTypeFunction = @convention(c) (Int16) -> UInt32

    static func layoutType() -> UInt32? {
        guard let handle = dlopen(nil, RTLD_NOW), let symbol = dlsym(handle, "KBGetLayoutType") else { return nil }
        let function = unsafeBitCast(symbol, to: LayoutTypeFunction.self)
        return function(Int16(LMGetKbdType()))
    }

    static func current() -> KeyboardKind {
        layoutType().map(KeyboardKind.fromLayoutType) ?? .ansi
    }
}

let switchLog = Logger(subsystem: JugglerLog.subsystem, category: "switch")
