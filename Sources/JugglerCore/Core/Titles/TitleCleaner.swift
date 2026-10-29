import Foundation

/// Cleans window and tab titles for task names and comparison.
///
/// Removes:
/// - suffixes like " - Claude", " — ChatGPT", " | Grok" (separators `-`, `–`, `—`, `|`, `·`
///   with spaces on both sides), including several in a row: "Chat - Claude - Google Chrome";
/// - the Chrome profile suffix: "Title - Google Chrome - Sergey";
/// - an unread counter at the start: "(3) Title";
/// - extra whitespace and newlines.
///
/// If only the app name is left of the title ("Claude"), the result is empty.
public enum TitleCleaner {
    /// App and site names that are stripped from the end of a title.
    public static let knownSuffixes: [String] = [
        "Google Chrome", "Chrome", "Chromium",
        "Claude", "Claude.ai",
        "ChatGPT", "OpenAI",
        "Grok", "Grok Bot", "GrokBot",
        "Safari", "Arc",
    ]

    private static let separators: Set<Character> = ["-", "–", "—", "|", "·", "•"]

    public static func clean(_ title: String) -> String {
        var text = collapseWhitespace(title)
        text = stripUnreadCounter(text)
        text = stripChromeProfileTail(text)

        var changed = true
        while changed {
            changed = false
            for name in knownSuffixes.sorted(by: { $0.count > $1.count }) {
                if let stripped = stripSuffix(name, from: text) {
                    text = stripped
                    changed = true
                }
            }
        }
        if knownSuffixes.contains(where: { $0.caseInsensitiveCompare(text) == .orderedSame }) {
            return ""
        }
        return text
    }

    /// Title for a new task: the cleaned title truncated to `maxLength`
    /// characters with "…"; an empty result is replaced with `fallback`.
    public static func suggestedTaskTitle(from title: String?, fallback: String = loc("Новая задача"), maxLength: Int = 80) -> String {
        let cleaned = clean(title ?? "")
        guard !cleaned.isEmpty else { return fallback }
        guard maxLength > 1, cleaned.count > maxLength else { return cleaned }
        let cut = String(cleaned.prefix(maxLength - 1)).trimmingCharacters(in: .whitespaces)
        return cut + "…"
    }

    // MARK: - Internals

    private static func collapseWhitespace(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
    }

    /// "(3) Title", "(12+) Title".
    private static func stripUnreadCounter(_ text: String) -> String {
        guard text.hasPrefix("("), let close = text.firstIndex(of: ")") else { return text }
        let inner = text[text.index(after: text.startIndex)..<close]
        let digits = inner.hasSuffix("+") ? inner.dropLast() : inner[...]
        guard !digits.isEmpty, digits.allSatisfy(\.isNumber) else { return text }
        let rest = text[text.index(after: close)...].trimmingCharacters(in: .whitespaces)
        return rest.isEmpty ? text : rest
    }

    /// "Title - Google Chrome - Profile" → "Title".
    private static func stripChromeProfileTail(_ text: String) -> String {
        for marker in [" - Google Chrome - ", " – Google Chrome – ", " — Google Chrome — "] {
            if let range = text.range(of: marker, options: [.backwards, .caseInsensitive]) {
                let head = String(text[..<range.lowerBound])
                if !head.trimmingCharacters(in: .whitespaces).isEmpty { return head }
            }
        }
        return text
    }

    /// Strips " <separator> <name>" from the end; `nil` if there is no such suffix
    /// or nothing is left after stripping.
    private static func stripSuffix(_ name: String, from text: String) -> String? {
        guard text.count > name.count + 2,
              text.lowercased().hasSuffix(name.lowercased()) else { return nil }
        var head = text.dropLast(name.count)
        guard head.last == " " else { return nil }
        head = head.dropLast()
        guard let sep = head.last, separators.contains(sep) else { return nil }
        head = head.dropLast()
        guard head.last == " " else { return nil }
        let result = head.trimmingCharacters(in: .whitespaces)
        return result.isEmpty ? nil : result
    }
}
