import Foundation

/// Physical keyboard type (Carbon `KBGetLayoutType`). It determines
/// the code of the key above Tab, the default "done" key.
public enum KeyboardKind: String, Codable, CaseIterable, Sendable {
    case ansi
    case iso
    case jis

    /// `KBGetLayoutType` values: 'ANSI', 'ISO ', 'JIS ' (four-character codes).
    public static func fromLayoutType(_ value: UInt32) -> KeyboardKind {
        switch value {
        case 0x4953_4F20: return .iso   // 'ISO '
        case 0x4A49_5320: return .jis   // 'JIS '
        default: return .ansi           // 'ANSI' and unknown
        }
    }

    /// The key above Tab, left of 1: on ISO — § (kVK_ISO_Section),
    /// on ANSI — ` (kVK_ANSI_Grave). JIS has no such key; ` is used as the closest.
    public var keyAboveTab: UInt32 {
        self == .iso ? KeyCode.isoSection : KeyCode.ansiGrave
    }
}

/// Hotkey assignments: which combination belongs to which action.
/// Actions without a combination are not registered.
public struct HotkeyAssignments: Equatable, Sendable {
    public private(set) var hotkeys: [HotkeyAction: Hotkey]

    public init(_ hotkeys: [HotkeyAction: Hotkey] = [:]) {
        self.hotkeys = hotkeys
    }

    public subscript(action: HotkeyAction) -> Hotkey? {
        hotkeys[action]
    }

    /// Defaults: ⌃⇥ — next, ⌃⇧⇥ — previous, ⌃⌥⇥ — bind (Tab is the same key on any keyboard);
    /// ⌃ + the key above Tab (§ on ISO, ` on ANSI) — "done".
    public static func defaults(for keyboard: KeyboardKind) -> HotkeyAssignments {
        let tab = KeyCode.tab
        return HotkeyAssignments([
            .nextTask: Hotkey(keyCode: tab, modifiers: [.control]),
            .previousTask: Hotkey(keyCode: tab, modifiers: [.control, .shift]),
            .bindCurrentChat: Hotkey(keyCode: tab, modifiers: [.control, .option]),
            .toggleDone: Hotkey(keyCode: keyboard.keyAboveTab, modifiers: [.control]),
        ])
    }

    /// The action this combination is already assigned to (except `except`).
    public func action(using hotkey: Hotkey, except: HotkeyAction? = nil) -> HotkeyAction? {
        HotkeyAction.allCases.first { $0 != except && hotkeys[$0] == hotkey }
    }

    /// Effective assignments: the user's own combinations on top of the defaults.
    /// A default that matches another action's custom combination is dropped
    /// (the action stays without a hotkey until the user assigns a new one).
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
        // Two identical custom combinations (e.g. the file was edited by hand): the first one stays.
        var seen = Set<Hotkey>()
        for action in HotkeyAction.allCases {
            guard let hotkey = result[action] else { continue }
            if !seen.insert(hotkey).inserted { result[action] = nil }
        }
        return HotkeyAssignments(result)
    }
}

/// Combinations the user assigned. Actions missing here
/// use the default — it is computed at launch from the keyboard type, so
/// switching between ISO ↔ ANSI keyboards does not break default hotkeys.
public struct HotkeyOverrides: Equatable, Sendable {
    public static let currentVersion = 1
    public var hotkeys: [HotkeyAction: Hotkey]

    public init(_ hotkeys: [HotkeyAction: Hotkey] = [:]) {
        self.hotkeys = hotkeys
    }

    /// Assigns a combination to an action with validation. On success returns `nil`
    /// and updates the set; matching the default removes the custom value.
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

    /// Restores the default for an action.
    public mutating func reset(_ action: HotkeyAction) {
        hotkeys[action] = nil
    }
}

extension HotkeyOverrides: Codable {
    private enum CodingKeys: String, CodingKey { case version, hotkeys }

    /// Lenient decoding: unknown actions and broken entries are skipped.
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

/// Storage of custom combinations: `~/Library/Application Support/Jugglinator/hotkeys.json`,
/// next to `tasks.json`. No file or a broken one — defaults are used.
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
        /// The file did not parse — defaults are used; the file is left alone until the next write.
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
