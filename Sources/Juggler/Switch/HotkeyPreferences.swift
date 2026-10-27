import Carbon
import Foundation
import JugglerCore
import os

/// Назначения хоткеев приложения: умолчания по типу клавиатуры + свои сочетания
/// пользователя из `~/Library/Application Support/Juggler/hotkeys.json`.
///
/// Один экземпляр (`SwitchModule.preferences`) разделяют регистратор хоткеев,
/// переключатель (подсказка на карточке) и раздел настроек.
@MainActor
final class HotkeyPreferences: ObservableObject {
    let keyboard: KeyboardKind
    let defaults: HotkeyAssignments

    @Published private(set) var overrides: HotkeyOverrides
    /// Итоговые назначения (что реально регистрируется).
    @Published private(set) var assignments: HotkeyAssignments
    /// Ошибки регистрации по действиям (OSStatus ≠ noErr), заполняет `CarbonHotkeyCenter`.
    @Published var registrationErrors: [HotkeyAction: OSStatus] = [:]
    /// Текст последней ошибки записи файла или `nil`.
    @Published private(set) var lastSaveError: String?

    private let store: HotkeyOverridesStore?

    /// `store == nil` — только в памяти (самопроверка).
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

    /// Назначить сочетание. Возвращает ошибку проверки или `nil` при успехе.
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
            lastSaveError = "Не удалось сохранить хоткеи: \(error.localizedDescription)"
            switchLog.error("Ошибка записи hotkeys.json: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// Тип физической клавиатуры через Carbon `KBGetLayoutType(LMGetKbdType())`.
/// Функции нет в заголовках SDK Command Line Tools, но она экспортируется
/// HIToolbox — берём её через `dlsym`. Не нашлась — считаем клавиатуру ANSI.
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
