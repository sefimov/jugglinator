import Foundation

// Хоткей = виртуальный код физической клавиши (kVK_*) + модификаторы.
// Коды не зависят от раскладки, поэтому один и тот же хоткей работает в РУ и EN.
// Здесь только Foundation: значения масок Carbon продублированы константами,
// приложение сверяет их с настоящими в самопроверке.

/// Модификаторы хоткея. Порядок показа — как в macOS: ⌃⌥⇧⌘.
public struct HotkeyModifiers: OptionSet, Hashable, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    public static let control = HotkeyModifiers(rawValue: 1 << 0)
    public static let option = HotkeyModifiers(rawValue: 1 << 1)
    public static let shift = HotkeyModifiers(rawValue: 1 << 2)
    public static let command = HotkeyModifiers(rawValue: 1 << 3)

    public static let all: HotkeyModifiers = [.control, .option, .shift, .command]

    /// Маски Carbon (`Events.h`): cmdKey, shiftKey, optionKey, controlKey.
    public enum CarbonMask {
        public static let command: UInt32 = 0x0100
        public static let shift: UInt32 = 0x0200
        public static let option: UInt32 = 0x0800
        public static let control: UInt32 = 0x1000
    }

    /// Маска модификаторов для `RegisterEventHotKey`.
    public var carbonFlags: UInt32 {
        var flags: UInt32 = 0
        if contains(.command) { flags |= CarbonMask.command }
        if contains(.shift) { flags |= CarbonMask.shift }
        if contains(.option) { flags |= CarbonMask.option }
        if contains(.control) { flags |= CarbonMask.control }
        return flags
    }

    public init(carbonFlags flags: UInt32) {
        var m: HotkeyModifiers = []
        if flags & CarbonMask.command != 0 { m.insert(.command) }
        if flags & CarbonMask.shift != 0 { m.insert(.shift) }
        if flags & CarbonMask.option != 0 { m.insert(.option) }
        if flags & CarbonMask.control != 0 { m.insert(.control) }
        self = m
    }

    /// «⌃⌥⇧⌘» в стандартном порядке.
    public var symbols: String {
        var s = ""
        if contains(.control) { s += "⌃" }
        if contains(.option) { s += "⌥" }
        if contains(.shift) { s += "⇧" }
        if contains(.command) { s += "⌘" }
        return s
    }

    /// Имена для хранения: ["control", "option", "shift", "command"].
    public var names: [String] {
        var n: [String] = []
        if contains(.control) { n.append("control") }
        if contains(.option) { n.append("option") }
        if contains(.shift) { n.append("shift") }
        if contains(.command) { n.append("command") }
        return n
    }

    /// Модификатор по символу или слову (без учёта регистра).
    public static func named(_ token: String) -> HotkeyModifiers? {
        switch token.lowercased() {
        case "⌃", "^", "ctrl", "control", "ctl": return .control
        case "⌥", "alt", "opt", "option": return .option
        case "⇧", "shift": return .shift
        case "⌘", "cmd", "command": return .command
        default: return nil
        }
    }
}

/// Виртуальные коды клавиш (`kVK_*` из Carbon `Events.h`), которые нужны логике.
public enum KeyCode {
    /// ISO: клавиша над Tab, слева от 1 (§ на английской раскладке).
    public static let isoSection: UInt32 = 0x0A
    /// ANSI: клавиша над Tab, слева от 1 (`); на ISO-клавиатуре — у левого Shift.
    public static let ansiGrave: UInt32 = 0x32
    public static let escape: UInt32 = 0x35
    public static let delete: UInt32 = 0x33
    public static let forwardDelete: UInt32 = 0x75

    /// Коды клавиш-модификаторов: сами по себе хоткеем быть не могут.
    public static let modifierKeys: Set<UInt32> = [
        0x37, 0x36, // Command, Right Command
        0x38, 0x3C, // Shift, Right Shift
        0x3A, 0x3D, // Option, Right Option
        0x3B, 0x3E, // Control, Right Control
        0x39,       // Caps Lock
        0x3F,       // Function
    ]

    public static let functionKeys: [UInt32: Int] = [
        0x7A: 1, 0x78: 2, 0x63: 3, 0x76: 4, 0x60: 5, 0x61: 6, 0x62: 7, 0x64: 8,
        0x65: 9, 0x6D: 10, 0x67: 11, 0x6F: 12, 0x69: 13, 0x6B: 14, 0x71: 15,
        0x6A: 16, 0x40: 17, 0x4F: 18, 0x50: 19, 0x5A: 20,
    ]

    /// Имя физической клавиши (по американской раскладке) для показа.
    public static func displayName(_ code: UInt32) -> String {
        if let name = names[code] { return name }
        if let f = functionKeys[code] { return "F\(f)" }
        return String(localized: "Клавиша \(Int(code))")
    }

    /// Код клавиши по имени: символ («§», «A», «1»), слово («space», «f5»)
    /// или явный код («#10», «key10», «0x0A»).
    public static func code(named raw: String) -> UInt32? {
        let token = raw.trimmingCharacters(in: .whitespaces)
        guard !token.isEmpty else { return nil }
        let lower = token.lowercased()
        if let explicit = explicitCode(lower) { return explicit }
        if let code = aliases[lower] { return code }
        if lower.hasPrefix("f"), let n = Int(lower.dropFirst()),
           let code = functionKeys.first(where: { $0.value == n })?.key {
            return code
        }
        if let code = names.first(where: { $0.value.lowercased() == lower })?.key { return code }
        return nil
    }

    private static func explicitCode(_ lower: String) -> UInt32? {
        let digits: Substring
        var radix = 10
        if lower.hasPrefix("#") {
            digits = lower.dropFirst()
        } else if lower.hasPrefix("key"), lower.count > 3 {
            digits = lower.dropFirst(3)
        } else if lower.hasPrefix("0x") {
            digits = lower.dropFirst(2)
            radix = 16
        } else {
            return nil
        }
        guard let value = UInt32(digits, radix: radix), value < 0x80 else { return nil }
        return value
    }

    private static let names: [UInt32: String] = [
        0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F", 0x04: "H", 0x05: "G", 0x06: "Z", 0x07: "X",
        0x08: "C", 0x09: "V", 0x0A: "§", 0x0B: "B", 0x0C: "Q", 0x0D: "W", 0x0E: "E", 0x0F: "R",
        0x10: "Y", 0x11: "T", 0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4", 0x16: "6", 0x17: "5",
        0x18: "=", 0x19: "9", 0x1A: "7", 0x1B: "-", 0x1C: "8", 0x1D: "0", 0x1E: "]", 0x1F: "O",
        0x20: "U", 0x21: "[", 0x22: "I", 0x23: "P", 0x24: "↩", 0x25: "L", 0x26: "J", 0x27: "'",
        0x28: "K", 0x29: ";", 0x2A: "\\", 0x2B: ",", 0x2C: "/", 0x2D: "N", 0x2E: "M", 0x2F: ".",
        0x30: "⇥", 0x31: String(localized: "Пробел"), 0x32: "`", 0x33: "⌫", 0x35: "⎋",
        0x41: "Num .", 0x43: "Num *", 0x45: "Num +", 0x47: "Num Clear", 0x4B: "Num /",
        0x4C: "Num ↩", 0x4E: "Num -", 0x51: "Num =",
        0x52: "Num 0", 0x53: "Num 1", 0x54: "Num 2", 0x55: "Num 3", 0x56: "Num 4",
        0x57: "Num 5", 0x58: "Num 6", 0x59: "Num 7", 0x5B: "Num 8", 0x5C: "Num 9",
        0x5D: "¥", 0x5E: "_", 0x66: "英数", 0x68: "かな",
        0x72: "Help", 0x73: "↖", 0x74: "⇞", 0x75: "⌦", 0x77: "↘", 0x79: "⇟",
        0x7B: "←", 0x7C: "→", 0x7D: "↓", 0x7E: "↑",
    ]

    private static let aliases: [String: UInt32] = [
        "section": 0x0A, "iso_section": 0x0A, "paragraph": 0x0A,
        "grave": 0x32, "backtick": 0x32, "tilde": 0x32, "ё": 0x32,
        "space": 0x31, "пробел": 0x31, "tab": 0x30, "return": 0x24, "enter": 0x24,
        "esc": 0x35, "escape": 0x35, "delete": 0x33, "backspace": 0x33,
        "forwarddelete": 0x75, "del": 0x75,
        "left": 0x7B, "right": 0x7C, "down": 0x7D, "up": 0x7E,
        "home": 0x73, "end": 0x77, "pageup": 0x74, "pagedown": 0x79,
        "minus": 0x1B, "equal": 0x18, "comma": 0x2B, "period": 0x2F, "slash": 0x2C,
        "semicolon": 0x29, "quote": 0x27, "backslash": 0x2A,
        "leftbracket": 0x21, "rightbracket": 0x1E,
    ]
}

/// Глобальный хоткей: физическая клавиша и модификаторы.
public struct Hotkey: Hashable, Sendable {
    public var keyCode: UInt32
    public var modifiers: HotkeyModifiers

    public init(keyCode: UInt32, modifiers: HotkeyModifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(.all)
    }

    /// Для показа: «⌃⇧§».
    public var displayString: String {
        modifiers.symbols + KeyCode.displayName(keyCode)
    }

    /// Для хранения и журналов: «control+shift+#10». Разбирается обратно `Hotkey(parsing:)`.
    public var storageString: String {
        (modifiers.names + ["#\(keyCode)"]).joined(separator: "+")
    }

    /// Разбор строки хоткея. Понимает:
    /// - символы модификаторов перед клавишей: «⌃⇧§», «⌘⌥K»;
    /// - слова через «+»: «ctrl+shift+section», «Control+Option+F5»;
    /// - явный код клавиши: «control+#10», «ctrl+0x0A».
    /// Повтор модификатора допускается, неизвестное слово — `nil`.
    public init?(parsing raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        var modifiers: HotkeyModifiers = []
        var keyToken: String

        if text.contains("+"), text != "+" {
            var parts = text.split(separator: "+", omittingEmptySubsequences: false).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            // «ctrl++» — клавиша «+» не поддерживается (её нет на физической раскладке без Shift).
            guard let last = parts.popLast(), !last.isEmpty else { return nil }
            for part in parts {
                guard !part.isEmpty else { return nil }
                if let m = HotkeyModifiers.named(part) {
                    modifiers.insert(m)
                } else if let symbols = Hotkey.symbolModifiers(part), symbols.rest.isEmpty {
                    modifiers.formUnion(symbols.modifiers)
                } else {
                    return nil
                }
            }
            keyToken = last
        } else {
            keyToken = text
        }

        // Символы модификаторов прямо перед клавишей: «⌃⇧§».
        if let symbols = Hotkey.symbolModifiers(keyToken), !symbols.rest.isEmpty {
            modifiers.formUnion(symbols.modifiers)
            keyToken = symbols.rest
        }

        guard let code = KeyCode.code(named: keyToken) else { return nil }
        self.init(keyCode: code, modifiers: modifiers)
    }

    /// Отделяет ведущие символы ⌃⌥⇧⌘ от остатка строки.
    private static func symbolModifiers(_ s: String) -> (modifiers: HotkeyModifiers, rest: String)? {
        var modifiers: HotkeyModifiers = []
        var rest = Substring(s)
        while let first = rest.first, let m = HotkeyModifiers.named(String(first)), "⌃⌥⇧⌘".contains(first) {
            modifiers.insert(m)
            rest = rest.dropFirst()
        }
        guard !modifiers.isEmpty else { return nil }
        return (modifiers, rest.trimmingCharacters(in: .whitespaces))
    }
}

extension Hotkey: Codable {
    private enum CodingKeys: String, CodingKey { case keyCode, modifiers }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let code = try c.decode(UInt32.self, forKey: .keyCode)
        let names = try c.decodeIfPresent([String].self, forKey: .modifiers) ?? []
        var modifiers: HotkeyModifiers = []
        for name in names {
            guard let m = HotkeyModifiers.named(name) else {
                throw DecodingError.dataCorruptedError(forKey: .modifiers, in: c, debugDescription: "Неизвестный модификатор \(name)")
            }
            modifiers.insert(m)
        }
        self.init(keyCode: code, modifiers: modifiers)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(keyCode, forKey: .keyCode)
        try c.encode(modifiers.names, forKey: .modifiers)
    }
}

/// Почему записанное сочетание не годится в глобальный хоткей.
public enum HotkeyValidationError: Equatable, Sendable {
    /// Нажат только модификатор.
    case modifierOnly
    /// Нет ни ⌃, ни ⌥, ни ⌘: такое сочетание мешало бы обычному набору текста.
    case needsModifier
    /// Код клавиши вне допустимого диапазона.
    case invalidKey
    /// Уже назначено другому действию.
    case conflict(HotkeyAction)

    public var message: String {
        switch self {
        case .modifierOnly: return String(localized: "Нажмите клавишу вместе с модификатором.")
        case .needsModifier: return String(localized: "Добавьте ⌃, ⌥ или ⌘ — иначе сочетание будет мешать набору текста.")
        case .invalidKey: return String(localized: "Эту клавишу нельзя назначить.")
        case .conflict(let action): return String(localized: "Это сочетание уже назначено: «\(action.displayName)».")
        }
    }
}

public enum HotkeyValidator {
    /// Проверка одного сочетания без учёта других действий.
    /// Функциональные клавиши F1–F20 допускаются и без модификаторов.
    public static func validate(_ hotkey: Hotkey) -> HotkeyValidationError? {
        if KeyCode.modifierKeys.contains(hotkey.keyCode) { return .modifierOnly }
        guard hotkey.keyCode < 0x80 else { return .invalidKey }
        if KeyCode.functionKeys[hotkey.keyCode] != nil { return nil }
        if hotkey.modifiers.intersection([.control, .option, .command]).isEmpty { return .needsModifier }
        return nil
    }
}
