import Foundation

// Общие типы-результаты для протоколов приложения (Sources/Juggler/App/ExtensionPoints.swift).
// Лежат в JugglerCore, чтобы их можно было использовать в чистой логике
// UI/SWITCH/BIND и проверять из JugglerChecks.

/// Итог активации привязки (BIND → SWITCH).
public enum ActivationResult: Equatable, Sendable {
    /// Открыто именно то, что привязано (вкладка, чат, окно).
    case activated
    /// Открыт запасной вариант: например, адрес вкладки заново или просто приложение.
    /// Строка — пояснение для пользователя на русском.
    case fallback(String)
    /// Ничего не открылось. Строка — пояснение для пользователя на русском.
    case failed(String)

    public var succeeded: Bool {
        if case .failed = self { return false }
        return true
    }
}

/// Итог попытки привязать текущий чат (BIND).
public enum BindingCaptureResult: Equatable, Sendable {
    /// Привязка готова. `suggestedTitle` — очищенный заголовок для новой задачи.
    case captured(TaskBinding, suggestedTitle: String)
    /// Id чата автоматически не прочитать — нужно попросить ссылку у пользователя
    /// (Claude без Accessibility, ChatGPT всегда).
    case needsManualLink(BindingSource, suggestedTitle: String)
    /// Привязать нельзя. Строка — пояснение для пользователя на русском.
    case failed(String)
}

/// Содержимое карточки перехода (SWITCH строит, презентер показывает).
public struct TransitionCardContent: Equatable, Sendable {
    public var number: Int
    public var title: String
    public var note: String
    /// «не был N мин» на момент перехода (до обновления времени захода).
    public var absenceText: String
    public var staleness: StalenessLevel
    public var source: BindingSource?
    /// Подсказка, например про хоткей привязки у задачи без привязки.
    public var hint: String?

    public init(
        number: Int, title: String, note: String = "", absenceText: String,
        staleness: StalenessLevel, source: BindingSource? = nil, hint: String? = nil
    ) {
        self.number = number
        self.title = title
        self.note = note
        self.absenceText = absenceText
        self.staleness = staleness
        self.source = source
        self.hint = hint
    }
}

/// Действия, которые запускаются глобальными хоткеями.
public enum HotkeyAction: String, Codable, CaseIterable, Sendable {
    case nextTask
    case previousTask
    /// ⌃⌥§: добавить переднее окно задачей или удалить задачу, если оно уже задача (D15).
    /// Имя случая не меняется: это ключ в hotkeys.json.
    case bindCurrentChat

    public var displayName: String {
        switch self {
        case .nextTask: return String(localized: "Следующая задача")
        case .previousTask: return String(localized: "Предыдущая задача")
        case .bindCurrentChat: return TaskToggleTexts.actionTitle
        }
    }
}
