import Foundation

/// Заголовки окон Terminal.app.
///
/// Терминал собирает заголовок из частей через « — »: папка, свой заголовок программы
/// (например, «✳ Задача» от Claude Code), активный процесс, пользователь@хост, tty, размер:
/// «sergejefimov — sergejefimov@MacBook-Pro-Sergej — -zsh — 214×24».
/// Размер и процесс меняются на ходу, поэтому для названия задачи и для сравнения
/// убирается шум: размер, имя оболочки, пользователь@хост, tty и значки-индикаторы в начале частей.
public enum TerminalTitle {
    /// Разделитель частей заголовка в Терминале.
    public static let separator = " — "

    /// Оболочки, имя которых — шум (с «-» у login shell, с путём, с ключами: «-zsh», «/bin/bash --login»).
    public static let shells: Set<String> = [
        "zsh", "bash", "sh", "fish", "tcsh", "csh", "ksh", "dash", "nu", "pwsh", "xonsh", "elvish", "login",
    ]

    /// Значимые части заголовка по порядку.
    public static func components(_ title: String) -> [String] {
        title.components(separatedBy: separator)
            .map(stripIndicators)
            .filter { !$0.isEmpty && !isNoise($0) }
    }

    /// Заголовок без шума: значимые части через « — »; пусто, если значимых частей нет.
    public static func clean(_ title: String) -> String {
        components(title).joined(separator: separator)
    }

    /// Название новой задачи из заголовка окна Терминала; без значимых частей — `fallback`.
    public static func taskTitle(from title: String?, fallback: String = defaultTaskTitle) -> String {
        TitleCleaner.suggestedTaskTitle(from: clean(title ?? ""), fallback: fallback)
    }

    public static let defaultTaskTitle = "Терминал"

    /// Тот же заголовок без учёта шума (размера, оболочки…) и регистра. Пустые не совпадают ни с чем.
    /// Это запасное сравнение: когда ни tty, ни id окна не известны.
    public static func same(_ a: String, _ b: String?) -> Bool {
        let x = clean(a), y = clean(b ?? "")
        return !x.isEmpty && x.caseInsensitiveCompare(y) == .orderedSame
    }

    // MARK: - Шум

    static func isNoise(_ part: String) -> Bool {
        isDimensions(part) || isShell(part) || isUserAtHost(part) || isTTY(part)
    }

    /// «214×24», «80x24».
    static func isDimensions(_ part: String) -> Bool {
        let pieces = part.lowercased().split(whereSeparator: { $0 == "×" || $0 == "x" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
        return pieces.count == 2 && pieces.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isASCIIDigit) }
            && part.filter({ $0 == "×" || $0 == "x" || $0 == "X" }).count == 1
    }

    /// «-zsh», «zsh», «/bin/zsh», «bash --login», «login».
    static func isShell(_ part: String) -> Bool {
        let words = part.split(separator: " ").map(String.init)
        guard let first = words.first, words.dropFirst().allSatisfy({ $0.hasPrefix("-") }) else { return false }
        var name = first.hasPrefix("-") ? String(first.dropFirst()) : first
        if let slash = name.lastIndex(of: "/") { name = String(name[name.index(after: slash)...]) }
        return shells.contains(name.lowercased())
    }

    /// «user@host» одним словом.
    static func isUserAtHost(_ part: String) -> Bool {
        guard !part.contains(" ") else { return false }
        let pieces = part.split(separator: "@", omittingEmptySubsequences: false)
        return pieces.count == 2 && pieces.allSatisfy { !$0.isEmpty }
    }

    /// «ttys003», «/dev/ttys003».
    static func isTTY(_ part: String) -> Bool {
        var name = part.lowercased()
        if name.hasPrefix("/dev/") { name.removeFirst(5) }
        guard name.hasPrefix("tty") else { return false }
        var rest = name.dropFirst(3)
        if rest.first == "s" { rest = rest.dropFirst() }
        return !rest.isEmpty && rest.allSatisfy(\.isASCIIDigit)
    }

    /// Значки в начале части: «✳ », «⠂ » (индикатор работы Claude Code), «● ».
    static func stripIndicators(_ part: String) -> String {
        var text = Substring(part.trimmingCharacters(in: .whitespacesAndNewlines))
        while let first = text.first, first.isWhitespace || isIndicator(first) {
            text = text.dropFirst()
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isIndicator(_ c: Character) -> Bool {
        guard let scalar = c.unicodeScalars.first else { return false }
        if (0x2800...0x28FF).contains(scalar.value) { return true }   // шрифт Брайля: спиннеры
        switch scalar.properties.generalCategory {
        case .otherSymbol, .mathSymbol: return !c.isASCII
        default: return false
        }
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
