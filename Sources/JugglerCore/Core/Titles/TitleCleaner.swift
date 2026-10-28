import Foundation

/// Очистка заголовков окон и вкладок для названия задачи и сравнения.
///
/// Убирает:
/// - хвосты вида « - Claude», « — ChatGPT», « | Grok» (разделители `-`, `–`, `—`, `|`, `·`
///   с пробелами по обе стороны), в том числе несколько подряд: «Чат - Claude - Google Chrome»;
/// - хвост профиля Chrome: «Заголовок - Google Chrome - Сергей»;
/// - счётчик непрочитанного в начале: «(3) Заголовок»;
/// - лишние пробелы и переводы строк.
///
/// Если от заголовка осталось только имя приложения («Claude»), результат пустой.
public enum TitleCleaner {
    /// Имена приложений и сайтов, которые срезаются с конца заголовка.
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

    /// Название для новой задачи: очищенный заголовок, обрезанный до `maxLength`
    /// символов с «…»; пустой результат заменяется на `fallback`.
    public static func suggestedTaskTitle(from title: String?, fallback: String = loc("Новая задача"), maxLength: Int = 80) -> String {
        let cleaned = clean(title ?? "")
        guard !cleaned.isEmpty else { return fallback }
        guard maxLength > 1, cleaned.count > maxLength else { return cleaned }
        let cut = String(cleaned.prefix(maxLength - 1)).trimmingCharacters(in: .whitespaces)
        return cut + "…"
    }

    // MARK: - Внутреннее

    private static func collapseWhitespace(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
    }

    /// «(3) Заголовок», «(12+) Заголовок».
    private static func stripUnreadCounter(_ text: String) -> String {
        guard text.hasPrefix("("), let close = text.firstIndex(of: ")") else { return text }
        let inner = text[text.index(after: text.startIndex)..<close]
        let digits = inner.hasSuffix("+") ? inner.dropLast() : inner[...]
        guard !digits.isEmpty, digits.allSatisfy(\.isNumber) else { return text }
        let rest = text[text.index(after: close)...].trimmingCharacters(in: .whitespaces)
        return rest.isEmpty ? text : rest
    }

    /// «Заголовок - Google Chrome - Профиль» → «Заголовок».
    private static func stripChromeProfileTail(_ text: String) -> String {
        for marker in [" - Google Chrome - ", " – Google Chrome – ", " — Google Chrome — "] {
            if let range = text.range(of: marker, options: [.backwards, .caseInsensitive]) {
                let head = String(text[..<range.lowerBound])
                if !head.trimmingCharacters(in: .whitespaces).isEmpty { return head }
            }
        }
        return text
    }

    /// Срезает « <разделитель> <name>» с конца; `nil`, если хвоста нет
    /// или после среза ничего не осталось.
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
