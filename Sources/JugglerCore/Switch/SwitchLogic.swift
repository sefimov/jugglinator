import Foundation

// Чистая логика области SWITCH (только Foundation): выбор задачи при переключении
// и тексты карточки перехода. Приложение (Sources/Juggler/Switch/) лишь вызывает её.

/// Пространство имён области SWITCH.
public enum SwitchLogic {}

/// Выбор задачи при «следующая / предыдущая».
public enum SwitchPlanner {
    /// Текущая задача: по переднему окну, иначе последняя активная.
    public static func currentTaskID(context: FrontmostContext, document: TasksDocument) -> UUID? {
        CurrentTaskResolver.resolve(context: context, tasks: document.tasks, fallbackID: document.lastActiveTaskID)
    }

    /// Соседняя по кругу задача (с пропуском «сделано») или `nil`, если переключаться не на что.
    public static func target(direction: CycleDirection, context: FrontmostContext, document: TasksDocument) -> UUID? {
        let current = currentTaskID(context: context, document: document)
        return TaskCycler.neighbor(of: current, in: document.tasks, direction: direction)?.id
    }
}

/// Сборка содержимого карточки перехода.
public enum TransitionCardBuilder {
    /// Заметка длиннее — обрезается с «…».
    public static let maxNoteLength = 240
    public static let maxTitleLength = 120

    /// Карточка для задачи `id` в момент `now` (до обновления времени захода).
    /// - `bindHotkey`: текущее сочетание «привязать текущий чат» для подсказки (`nil` — не назначено).
    /// - `activation`: итог активации привязки; запасной вариант или ошибка попадают в подсказку.
    public static func content(
        for id: UUID, in document: TasksDocument, now: Date,
        bindHotkey: Hotkey?, activation: ActivationResult? = nil
    ) -> TransitionCardContent? {
        guard let task = document.task(withID: id), let number = document.number(of: id) else { return nil }
        return TransitionCardContent(
            number: number,
            title: title(task.title),
            note: note(task.note),
            absenceText: Staleness.absenceText(lastVisited: task.lastVisitedAt, now: now),
            staleness: Staleness.level(lastVisited: task.lastVisitedAt, now: now),
            source: task.binding?.source,
            hint: hint(hasBinding: task.binding != nil, bindHotkey: bindHotkey, activation: activation))
    }

    public static func title(_ raw: String) -> String {
        let t = collapse(raw)
        return t.isEmpty ? "Без названия" : truncate(t, to: maxTitleLength)
    }

    /// Заметка: обрезаются пробелы по краям и пустые строки, длинная — укорачивается.
    public static func note(_ raw: String) -> String {
        let lines = raw.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return truncate(lines.joined(separator: "\n"), to: maxNoteLength)
    }

    public static func hint(hasBinding: Bool, bindHotkey: Hotkey?, activation: ActivationResult?) -> String? {
        guard hasBinding else { return unboundHint(bindHotkey: bindHotkey) }
        switch activation {
        case .failed(let message)?:
            let m = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return m.isEmpty ? "Не удалось открыть привязку" : "Не удалось открыть: \(m)"
        case .fallback(let message)?:
            let m = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return m.isEmpty ? nil : m
        case .activated?, nil:
            return nil
        }
    }

    /// Подсказка для задачи без привязки.
    public static func unboundHint(bindHotkey: Hotkey?) -> String {
        if let bindHotkey {
            return "Нет привязки: откройте чат и нажмите \(bindHotkey.displayString)"
        }
        return "Нет привязки: откройте чат и выберите в меню «Сделать задачей текущий чат»"
    }

    /// Строка заголовка карточки: «2. Название».
    public static func headline(_ content: TransitionCardContent) -> String {
        "\(content.number). \(content.title)"
    }

    private static func collapse(_ s: String) -> String {
        s.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }

    static func truncate(_ s: String, to limit: Int) -> String {
        guard s.count > limit else { return s }
        let cut = s.prefix(limit - 1).trimmingCharacters(in: .whitespacesAndNewlines)
        return cut + "…"
    }
}

/// Тайминги карточки: появление, показ, плавное исчезновение. Всего 1–1,5 с.
public struct CardTiming: Equatable, Sendable {
    public var fadeIn: TimeInterval
    public var hold: TimeInterval
    public var fadeOut: TimeInterval

    public init(fadeIn: TimeInterval = 0.1, hold: TimeInterval = 0.95, fadeOut: TimeInterval = 0.35) {
        self.fadeIn = fadeIn
        self.hold = hold
        self.fadeOut = fadeOut
    }

    public static let standard = CardTiming()

    public var total: TimeInterval { fadeIn + hold + fadeOut }
}
