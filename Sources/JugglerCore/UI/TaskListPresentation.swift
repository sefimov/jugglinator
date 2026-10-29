import Foundation

/// A row of the menu bar task list: everything to display is already computed.
public struct TaskRow: Identifiable, Equatable, Sendable {
    public var id: UUID
    /// Task number (1-based position in the list).
    public var number: Int
    public var title: String
    public var note: String
    public var isDone: Bool
    /// Marker for the current (last active) task.
    public var isCurrent: Bool
    public var source: BindingSource?
    /// "away N min".
    public var absenceText: String
    public var staleness: StalenessLevel
    /// Binding hint for the tooltip.
    public var bindingHelp: String

    public init(
        id: UUID, number: Int, title: String, note: String, isDone: Bool, isCurrent: Bool,
        source: BindingSource?, absenceText: String, staleness: StalenessLevel, bindingHelp: String
    ) {
        self.id = id
        self.number = number
        self.title = title
        self.note = note
        self.isDone = isDone
        self.isCurrent = isCurrent
        self.source = source
        self.absenceText = absenceText
        self.staleness = staleness
        self.bindingHelp = bindingHelp
    }
}

/// Texts and list rows for the menu bar, localized via `loc(...)`.
public enum TaskListPresenter {
    /// List row height, pt (with `List` padding): without a note and with a note.
    public static let rowHeight: Double = 24
    public static let rowHeightWithNote: Double = 38
    /// A little padding above/below the list and a height limit (scrolling beyond it).
    public static let listPadding: Double = 4
    public static let maxListHeight: Double = 360

    /// List height from rows: exactly fits the content, no taller than `maxListHeight`.
    public static func listHeight(rows: [TaskRow]) -> Double {
        let total = rows.reduce(listPadding) { $0 + ($1.note.isEmpty ? rowHeight : rowHeightWithNote) }
        return min(total, maxListHeight)
    }

    /// The task marked current (▸) in the menu: the one the frontmost window exactly matches
    /// (`ExactTaskMatcher`). A window that is not a task (or not read yet) — no task is marked,
    /// even if another one was active last.
    public static func currentTaskID(context: FrontmostContext?, document: TasksDocument) -> UUID? {
        guard let context else { return nil }
        return ExactTaskMatcher.match(context: context, document: document)
    }

    /// List rows in document order; `currentTaskID` gets the ▸ mark (see `currentTaskID(context:document:)`).
    public static func rows(
        for document: TasksDocument, now: Date, currentTaskID: UUID?, thresholds: StalenessThresholds = .standard
    ) -> [TaskRow] {
        document.tasks.enumerated().map { index, task in
            TaskRow(
                id: task.id,
                number: index + 1,
                title: task.title.isEmpty ? loc("Без названия") : task.title,
                note: task.note,
                isDone: task.isDone,
                isCurrent: task.id == currentTaskID,
                source: task.binding?.source,
                absenceText: Staleness.absenceText(lastVisited: task.lastVisitedAt, now: now),
                staleness: Staleness.level(lastVisited: task.lastVisitedAt, now: now, thresholds: thresholds),
                bindingHelp: bindingHelp(task.binding))
        }
    }

    /// Binding tooltip: "Chrome: Tab title" or "No binding…".
    public static func bindingHelp(_ binding: TaskBinding?) -> String {
        guard let binding else { return loc("Без привязки: откройте чат и выберите «\(TaskToggleTexts.menuAddTitle)»") }
        let title = binding.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? binding.source.displayName : "\(binding.source.displayName): \(title)"
    }

    /// Summary under the header: "3 tasks, 1 done". Word forms come from the selected language's
    /// `Localizable.stringsdict`; without tables — Russian ones via `RussianPlural`.
    public static func summary(for document: TasksDocument) -> String {
        let total = document.tasks.count
        guard total > 0 else { return loc("Задач пока нет") }
        let done = document.tasks.filter(\.isDone).count
        let head = LocalizedPlural.format("summary.tasks", total)
            ?? "\(total) \(RussianPlural.form(total, one: "задача", few: "задачи", many: "задач"))"
        guard done > 0 else { return head }
        let tail = LocalizedPlural.format("summary.done", done)
            ?? "\(done) \(RussianPlural.form(done, one: "сделана", few: "сделаны", many: "сделано"))"
        return loc("\(head), \(tail)")
    }

    /// Question before deletion.
    public static func deleteConfirmation(title: String) -> String {
        let cleaned = TaskListOps.cleanTitle(title)
        let shown = cleaned.isEmpty ? loc("Без названия") : cleaned
        return loc("Удалить задачу «\(shown)»?")
    }

    /// Question before clearing the list: "Delete all 5 tasks?" (word form via `clearAll.confirm`).
    public static func clearAllConfirmation(count: Int) -> String {
        LocalizedPlural.format("clearAll.confirm", count) ?? {
            switch RussianPlural.form(count, one: "one", few: "few", many: "many") {
            case "one": return "Удалить \(count) задачу?"
            case "few": return "Удалить все \(count) задачи?"
            default: return "Удалить все \(count) задач?"
            }
        }()
    }

    /// Question before deleting done tasks: "Delete 3 done tasks?" (word form via `clearDone.confirm`).
    public static func clearDoneConfirmation(count: Int) -> String {
        LocalizedPlural.format("clearDone.confirm", count) ?? {
            switch RussianPlural.form(count, one: "one", few: "few", many: "many") {
            case "one": return "Удалить \(count) сделанную задачу?"
            case "few": return "Удалить \(count) сделанные задачи?"
            default: return "Удалить \(count) сделанных задач?"
            }
        }()
    }

    /// Explanation under the clear question (used by both "clear all" and "delete done").
    public static var clearAllWarning: String { loc("Задачи, заметки и привязки будут удалены. Это нельзя отменить.") }

    /// Message about restoring `tasks.json` after loading, or `nil` if all is well.
    public static func loadNotice(_ outcome: TaskStore.LoadOutcome?) -> String? {
        switch outcome {
        case .recoveredFromBackup:
            return loc("Файл задач был повреждён или пропал. Список восстановлен из резервной копии.")
        case .resetAfterCorruption:
            return loc("Файл задач был повреждён, резервной копии нет. Испорченный файл сохранён рядом, список начат заново.")
        case .loaded, .missing, nil:
            return nil
        }
    }
}

/// A number with a word in the right form by key from the currently selected language's `Localizable.stringsdict`
/// (plural rules of the table's language), or `nil` if no table has this key.
public enum LocalizedPlural {
    public static func format(_ key: String, _ n: Int, localizer: Localizer = .shared) -> String? {
        localizer.plural(key, n)
    }
}

/// Picks the Russian word form after a number (one/few/many, as for 1, 2, 5).
public enum RussianPlural {
    public static func form(_ n: Int, one: String, few: String, many: String) -> String {
        let n = abs(n)
        let lastTwo = n % 100
        let last = n % 10
        if (11...14).contains(lastTwo) { return many }
        if last == 1 { return one }
        if (2...4).contains(last) { return few }
        return many
    }
}

/// "Launch at login" state (a mirror of `SMAppService.Status`
/// without depending on ServiceManagement, so the texts can be checked).
public enum LoginItemState: String, Equatable, Sendable, CaseIterable {
    case enabled
    case notRegistered
    case requiresApproval
    case notFound

    /// Whether the toggle in settings is on.
    public var isOn: Bool {
        switch self {
        case .enabled, .requiresApproval: return true
        case .notRegistered, .notFound: return false
        }
    }

    /// Explanation under the toggle, or `nil` if there is nothing to explain.
    public var explanation: String? {
        switch self {
        case .enabled: return nil
        case .notRegistered: return nil
        case .requiresApproval:
            return loc("Нужно разрешить запуск в «Системных настройках» → «Основные» → «Объекты входа».")
        case .notFound:
            return loc("Запуск при входе доступен только для собранного приложения Juggler.app.")
        }
    }

    /// Whether the "Open Login Items settings" button is needed.
    public var needsSystemSettings: Bool { self == .requiresApproval }
}
