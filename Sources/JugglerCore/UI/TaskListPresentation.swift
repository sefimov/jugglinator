import Foundation

/// Строка списка задач в меню-баре: всё, что нужно показать, уже посчитано.
public struct TaskRow: Identifiable, Equatable, Sendable {
    public var id: UUID
    /// Номер задачи (позиция в списке с 1).
    public var number: Int
    public var title: String
    public var note: String
    public var isDone: Bool
    /// Отметка текущей (последней активной) задачи.
    public var isCurrent: Bool
    public var source: BindingSource?
    /// «не был N мин».
    public var absenceText: String
    public var staleness: StalenessLevel
    /// Подсказка про привязку для всплывающей справки.
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

/// Тексты и строки списка для меню-бара. Всё на русском.
public enum TaskListPresenter {
    /// Высота строки списка, pt (с отступами `List`): без заметки и с заметкой.
    public static let rowHeight: Double = 24
    public static let rowHeightWithNote: Double = 38
    /// Небольшой запас сверху/снизу списка и предел высоты (дальше — прокрутка).
    public static let listPadding: Double = 4
    public static let maxListHeight: Double = 360

    /// Высота списка по строкам: ровно по содержимому, не выше `maxListHeight`.
    public static func listHeight(rows: [TaskRow]) -> Double {
        let total = rows.reduce(listPadding) { $0 + ($1.note.isEmpty ? rowHeight : rowHeightWithNote) }
        return min(total, maxListHeight)
    }

    /// Строки списка в порядке документа.
    public static func rows(
        for document: TasksDocument, now: Date, thresholds: StalenessThresholds = .standard
    ) -> [TaskRow] {
        document.tasks.enumerated().map { index, task in
            TaskRow(
                id: task.id,
                number: index + 1,
                title: task.title.isEmpty ? loc("Без названия") : task.title,
                note: task.note,
                isDone: task.isDone,
                isCurrent: task.id == document.lastActiveTaskID,
                source: task.binding?.source,
                absenceText: Staleness.absenceText(lastVisited: task.lastVisitedAt, now: now),
                staleness: Staleness.level(lastVisited: task.lastVisitedAt, now: now, thresholds: thresholds),
                bindingHelp: bindingHelp(task.binding))
        }
    }

    /// Справка о привязке: «Chrome: Заголовок вкладки» или «Без привязки…».
    public static func bindingHelp(_ binding: TaskBinding?) -> String {
        guard let binding else { return loc("Без привязки: откройте чат и выберите «\(TaskToggleTexts.menuAddTitle)»") }
        let title = binding.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? binding.source.displayName : "\(binding.source.displayName): \(title)"
    }

    /// Сводка под заголовком: «3 задачи, 1 сделана». Формы слов — из `Localizable.stringsdict`
    /// выбранного языка; без таблиц — русские по `RussianPlural`.
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

    /// Вопрос перед удалением.
    public static func deleteConfirmation(title: String) -> String {
        let cleaned = TaskListOps.cleanTitle(title)
        let shown = cleaned.isEmpty ? loc("Без названия") : cleaned
        return loc("Удалить задачу «\(shown)»?")
    }

    /// Вопрос перед очисткой списка: «Удалить все 5 задач?» (форма слова — по `clearAll.confirm`).
    public static func clearAllConfirmation(count: Int) -> String {
        LocalizedPlural.format("clearAll.confirm", count) ?? {
            switch RussianPlural.form(count, one: "one", few: "few", many: "many") {
            case "one": return "Удалить \(count) задачу?"
            case "few": return "Удалить все \(count) задачи?"
            default: return "Удалить все \(count) задач?"
            }
        }()
    }

    /// Пояснение под вопросом об очистке.
    public static var clearAllWarning: String { loc("Задачи, заметки и привязки будут удалены. Это нельзя отменить.") }

    /// Сообщение о восстановлении `tasks.json` после загрузки или `nil`, если всё в порядке.
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

/// Число со словом в нужной форме по ключу из `Localizable.stringsdict` выбранного сейчас языка
/// (правила множественного числа — языка таблицы) или `nil`, если таблицы с этим ключом нет.
public enum LocalizedPlural {
    public static func format(_ key: String, _ n: Int, localizer: Localizer = .shared) -> String? {
        localizer.plural(key, n)
    }
}

/// Выбор формы слова после числа: 1 задача, 2 задачи, 5 задач.
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

/// Состояние «запуска при входе в систему» (зеркало `SMAppService.Status`
/// без зависимости от ServiceManagement, чтобы тексты можно было проверить).
public enum LoginItemState: String, Equatable, Sendable, CaseIterable {
    case enabled
    case notRegistered
    case requiresApproval
    case notFound

    /// Включён ли переключатель в настройках.
    public var isOn: Bool {
        switch self {
        case .enabled, .requiresApproval: return true
        case .notRegistered, .notFound: return false
        }
    }

    /// Пояснение под переключателем или `nil`, если пояснять нечего.
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

    /// Нужна ли кнопка «Открыть настройки объектов входа».
    public var needsSystemSettings: Bool { self == .requiresApproval }
}
