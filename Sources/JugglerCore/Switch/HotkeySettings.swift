import Foundation

/// Физический тип клавиатуры (Carbon `KBGetLayoutType`). От него зависит,
/// какой код у клавиши над Tab.
public enum KeyboardKind: String, Codable, CaseIterable, Sendable {
    case ansi
    case iso
    case jis

    /// Значения `KBGetLayoutType`: 'ANSI', 'ISO ', 'JIS ' (четырёхсимвольные коды).
    public static func fromLayoutType(_ value: UInt32) -> KeyboardKind {
        switch value {
        case 0x4953_4F20: return .iso   // 'ISO '
        case 0x4A49_5320: return .jis   // 'JIS '
        default: return .ansi           // 'ANSI' и неизвестные
        }
    }

    /// Клавиша над Tab, слева от 1: на ISO — § (kVK_ISO_Section),
    /// на ANSI — ` (kVK_ANSI_Grave). На JIS такой клавиши нет, берём ` как ближайшую.
    public var keyAboveTab: UInt32 {
        self == .iso ? KeyCode.isoSection : KeyCode.ansiGrave
    }
}

/// Назначения хоткеев: какое сочетание у какого действия.
/// Действия без сочетания не регистрируются.
public struct HotkeyAssignments: Equatable, Sendable {
    public private(set) var hotkeys: [HotkeyAction: Hotkey]

    public init(_ hotkeys: [HotkeyAction: Hotkey] = [:]) {
        self.hotkeys = hotkeys
    }

    public subscript(action: HotkeyAction) -> Hotkey? {
        hotkeys[action]
    }

    /// По умолчанию (D9): ⌃ + клавиша над Tab — следующая, ⌃⇧ — предыдущая, ⌃⌥ — привязать; ⌃⌥D — «сделано» (D24, физическая клавиша D на любой клавиатуре).
    public static func defaults(for keyboard: KeyboardKind) -> HotkeyAssignments {
        let key = keyboard.keyAboveTab
        return HotkeyAssignments([
            .nextTask: Hotkey(keyCode: key, modifiers: [.control]),
            .previousTask: Hotkey(keyCode: key, modifiers: [.control, .shift]),
            .bindCurrentChat: Hotkey(keyCode: key, modifiers: [.control, .option]),
            .toggleDone: Hotkey(keyCode: KeyCode.ansiD, modifiers: [.control, .option]),
        ])
    }

    /// Действие, которому уже назначено это сочетание (кроме `except`).
    public func action(using hotkey: Hotkey, except: HotkeyAction? = nil) -> HotkeyAction? {
        HotkeyAction.allCases.first { $0 != except && hotkeys[$0] == hotkey }
    }

    /// Итоговые назначения: свои сочетания пользователя поверх умолчаний.
    /// Умолчание, совпавшее со своим сочетанием другого действия, снимается
    /// (действие остаётся без хоткея, пока пользователь не назначит новый).
    public static func resolve(overrides: HotkeyOverrides, defaults: HotkeyAssignments) -> HotkeyAssignments {
        var result: [HotkeyAction: Hotkey] = [:]
        let custom = Set(overrides.hotkeys.values)
        for action in HotkeyAction.allCases {
            if let own = overrides.hotkeys[action] {
                result[action] = own
            } else if let fallback = defaults.hotkeys[action], !custom.contains(fallback) {
                result[action] = fallback
            }
        }
        // Два своих одинаковых сочетания (например, файл правили руками): остаётся первое.
        var seen = Set<Hotkey>()
        for action in HotkeyAction.allCases {
            guard let hotkey = result[action] else { continue }
            if !seen.insert(hotkey).inserted { result[action] = nil }
        }
        return HotkeyAssignments(result)
    }
}

/// Сочетания, которые пользователь назначил сам. Действия, которых здесь нет,
/// берут умолчание — оно вычисляется при запуске по типу клавиатуры, поэтому
/// смена клавиатуры ISO ↔ ANSI не ломает хоткеи по умолчанию.
public struct HotkeyOverrides: Equatable, Sendable {
    public static let currentVersion = 1
    public var hotkeys: [HotkeyAction: Hotkey]

    public init(_ hotkeys: [HotkeyAction: Hotkey] = [:]) {
        self.hotkeys = hotkeys
    }

    /// Назначить сочетание действию с проверками. При успехе возвращает `nil`
    /// и меняет набор; совпадение с умолчанием убирает своё значение.
    public mutating func assign(
        _ hotkey: Hotkey, to action: HotkeyAction, defaults: HotkeyAssignments
    ) -> HotkeyValidationError? {
        if let error = HotkeyValidator.validate(hotkey) { return error }
        let effective = HotkeyAssignments.resolve(overrides: self, defaults: defaults)
        if let other = effective.action(using: hotkey, except: action) { return .conflict(other) }
        if defaults[action] == hotkey {
            hotkeys[action] = nil
        } else {
            hotkeys[action] = hotkey
        }
        return nil
    }

    /// Вернуть умолчание для действия.
    public mutating func reset(_ action: HotkeyAction) {
        hotkeys[action] = nil
    }
}

extension HotkeyOverrides: Codable {
    private enum CodingKeys: String, CodingKey { case version, hotkeys }

    /// Терпимое чтение: неизвестные действия и битые записи пропускаются.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try c.decodeIfPresent([String: LossyHotkey].self, forKey: .hotkeys) ?? [:]
        var result: [HotkeyAction: Hotkey] = [:]
        for (name, entry) in raw {
            guard let action = HotkeyAction(rawValue: name), let hotkey = entry.value else { continue }
            result[action] = hotkey
        }
        hotkeys = result
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(HotkeyOverrides.currentVersion, forKey: .version)
        var raw: [String: Hotkey] = [:]
        for (action, hotkey) in hotkeys { raw[action.rawValue] = hotkey }
        try c.encode(raw, forKey: .hotkeys)
    }
}

private struct LossyHotkey: Decodable {
    let value: Hotkey?
    init(from decoder: Decoder) throws { value = try? Hotkey(from: decoder) }
}

/// Хранение своих сочетаний: `~/Library/Application Support/Juggler/hotkeys.json`,
/// рядом с `tasks.json`. Нет файла или он битый — используются умолчания.
public final class HotkeyOverridesStore {
    public let fileURL: URL
    private let fileManager: FileManager

    public static var defaultFileURL: URL {
        TaskStore.defaultFileURL.deletingLastPathComponent().appendingPathComponent("hotkeys.json")
    }

    public init(fileURL: URL = HotkeyOverridesStore.defaultFileURL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    public enum LoadOutcome: Equatable, Sendable {
        case loaded
        case missing
        /// Файл не разобрался — взяты умолчания, файл не трогаем до следующей записи.
        case corrupt(String)
    }

    public func load() -> (overrides: HotkeyOverrides, outcome: LoadOutcome) {
        guard let data = try? Data(contentsOf: fileURL) else { return (HotkeyOverrides(), .missing) }
        do {
            return (try JSONDecoder().decode(HotkeyOverrides.self, from: data), .loaded)
        } catch {
            return (HotkeyOverrides(), .corrupt(String(describing: error)))
        }
    }

    public func save(_ overrides: HotkeyOverrides) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(overrides)
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }
}
