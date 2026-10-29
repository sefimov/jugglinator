import Foundation

/// Terminal.app window titles.
///
/// Terminal builds the title from parts joined by " — ": folder, the program's own title
/// (e.g. "✳ Task" from Claude Code), active process, user@host, tty, size:
/// «sergejefimov — sergejefimov@MacBook-Pro-Sergej — -zsh — 214×24».
/// Size and process change on the fly, so for the task name and for comparison
/// noise is removed: size, shell name, user@host, tty and indicator glyphs at the start of parts.
public enum TerminalTitle {
    /// Separator between title parts in Terminal.
    public static let separator = " — "

    /// Shells whose name is noise (with "-" for a login shell, with a path, with flags: "-zsh", "/bin/bash --login").
    public static let shells: Set<String> = [
        "zsh", "bash", "sh", "fish", "tcsh", "csh", "ksh", "dash", "nu", "pwsh", "xonsh", "elvish", "login",
    ]

    /// Meaningful title parts in order.
    public static func components(_ title: String) -> [String] {
        title.components(separatedBy: separator)
            .map(stripIndicators)
            .filter { !$0.isEmpty && !isNoise($0) }
    }

    /// Title without noise: meaningful parts joined by " — "; empty if there are none.
    public static func clean(_ title: String) -> String {
        components(title).joined(separator: separator)
    }

    /// New task name from a Terminal window title; without meaningful parts — `fallback`.
    public static func taskTitle(from title: String?, fallback: String = defaultTaskTitle) -> String {
        TitleCleaner.suggestedTaskTitle(from: clean(title ?? ""), fallback: fallback)
    }

    public static var defaultTaskTitle: String { loc("Терминал") }

    /// Same title ignoring noise (size, shell…) and case. Empty titles match nothing.
    /// This is a fallback comparison: when neither the tty nor the window id is known.
    public static func same(_ a: String, _ b: String?) -> Bool {
        let x = clean(a), y = clean(b ?? "")
        return !x.isEmpty && x.caseInsensitiveCompare(y) == .orderedSame
    }

    // MARK: - Noise

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

    /// "user@host" as a single word.
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

    /// Glyphs at the start of a part: "✳ ", "⠂ " (Claude Code activity indicator), "● ".
    static func stripIndicators(_ part: String) -> String {
        var text = Substring(part.trimmingCharacters(in: .whitespacesAndNewlines))
        while let first = text.first, first.isWhitespace || isIndicator(first) {
            text = text.dropFirst()
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isIndicator(_ c: Character) -> Bool {
        guard let scalar = c.unicodeScalars.first else { return false }
        if (0x2800...0x28FF).contains(scalar.value) { return true }   // Braille patterns: spinners
        switch scalar.properties.generalCategory {
        case .otherSymbol, .mathSymbol: return !c.isASCII
        default: return false
        }
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
