import Foundation

// ⌃⌥§ «добавить или удалить текущее окно» (D15, D16): чистая логика переключателя.
//   - ExactTaskMatcher — переднее окно — это задача, только при точном совпадении;
//   - TaskRemoval      — удаление с запоминанием места и возврат «как было»;
//   - TaskToggle       — что делать по нажатию: вернуть, удалить или добавить;
//   - CurrentWindowMenuAction — подпись и действие пункта меню по окну, что было впереди;
//   - TaskToggleTexts  — тексты карточки и меню.

/// Точное совпадение переднего окна с задачей.
///
/// В отличие от `CurrentTaskResolver`, здесь нет запасной «последней активной» задачи
/// и нет слабых совпадений «то же приложение» или «тот же заголовок» (кроме ChatGPT,
/// у которого id треда из окна не читается, и привязки к окну, которая сама и есть
/// «bundle id + заголовок»):
/// - вкладка Chrome — тот же id вкладки или тот же адрес (`URLNormalizer`);
/// - чат Claude — тот же UUID (в Claude desktop или на claude.ai/chat/<uuid> в Chrome);
/// - сессия Claude Code — тот же `local_<uuid>`;
/// - тред ChatGPT — тот же id треда или, в окне ChatGPT, то же название треда (очищенный заголовок окна);
/// - окно Терминала — та же вкладка (tty) или то же окно (id окна), если tty одной из сторон не известен;
///   по заголовку без размера и оболочки — только когда AppleScript недоступен и в контексте нет ни tty, ни id;
/// - окно приложения — тот же bundle id и тот же непустой заголовок окна, и только если
///   в переднем окне нет более точного id (вкладки, чата, сессии, треда): привязка к окну —
///   запасной путь, когда id неизвестен.
public enum ExactTaskMatcher {
    /// Сила точного совпадения: при нескольких подходящих задачах побеждает id.
    public enum Strength: Int, Comparable, Sendable {
        case title = 1
        case url = 2
        case id = 3

        public static func < (lhs: Strength, rhs: Strength) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// Задача, которой точно соответствует переднее окно, или `nil`.
    /// При равной силе — последняя активная (если она среди подходящих), иначе первая по списку.
    public static func match(context: FrontmostContext, document: TasksDocument) -> UUID? {
        var best: Strength?
        var candidates: [UUID] = []
        for task in document.tasks {
            guard let binding = task.binding, let s = strength(binding, against: context) else { continue }
            if best.map({ s > $0 }) ?? true {
                best = s
                candidates = [task.id]
            } else if s == best {
                candidates.append(task.id)
            }
        }
        if let active = document.lastActiveTaskID, candidates.contains(active) { return active }
        return candidates.first
    }

    public static func strength(_ binding: TaskBinding, against context: FrontmostContext) -> Strength? {
        switch binding {
        case .chromeTab(let ref):
            guard let tab = context.chromeTab else { return nil }
            if let a = ref.tabID, let b = tab.tabID, a == b { return .id }
            if !ref.url.isEmpty, !tab.url.isEmpty, URLNormalizer.normalize(ref.url) == URLNormalizer.normalize(tab.url) { return .url }
            return nil

        case .claudeChat(let ref):
            let id = ref.conversationID.lowercased()
            guard !id.isEmpty else { return nil }
            if let current = context.claudeConversationID?.lowercased(), current == id { return .id }
            if let url = context.chromeTab?.url, case .claude(let webID)? = ChatLinkParser.parse(url), webID.lowercased() == id {
                return .id
            }
            return nil

        case .claudeCodeSession(let ref):
            let id = ref.sessionID.lowercased()
            guard !id.isEmpty, let current = context.claudeCodeSessionID?.lowercased(), current == id else { return nil }
            return .id

        case .chatGPTThread(let ref):
            if !ref.threadID.isEmpty, let current = context.chatGPTThreadID, current == ref.threadID { return .id }
            guard KnownBundleIDs.isChatGPT(context.bundleID) else { return nil }
            // Название треда — заголовок окна ChatGPT; «ChatGPT» без треда очищается в пустую строку.
            let bound = TitleCleaner.clean(ref.title)
            let current = TitleCleaner.clean(context.windowTitle ?? "")
            guard !bound.isEmpty, bound.caseInsensitiveCompare(current) == .orderedSame else { return nil }
            return .title

        case .terminalWindow(let ref):
            switch TerminalWindowMatch.evaluate(ref, context: context) {
            case .tab?: return .id
            case .window?: return .url
            case .title?: return .title
            case nil: return nil
            }

        case .appWindow(let ref):
            guard KnownBundleIDs.same(context.bundleID, ref.bundleID), !hasSpecificIdentity(context) else { return nil }
            if KnownBundleIDs.same(ref.bundleID, KnownBundleIDs.terminal) {
                // Терминал без AppleScript: размер и оболочка в заголовке меняются — сравнение без них.
                return TerminalTitle.same(ref.windowTitle, context.windowTitle) ? .title : nil
            }
            guard sameWindowTitle(ref.windowTitle, context.windowTitle) else { return nil }
            return .title
        }
    }

    /// В переднем окне есть id вкладки, чата, сессии, треда или окна Терминала.
    static func hasSpecificIdentity(_ context: FrontmostContext) -> Bool {
        context.chromeTab != nil
            || !(context.claudeConversationID ?? "").isEmpty
            || !(context.claudeCodeSessionID ?? "").isEmpty
            || !(context.chatGPTThreadID ?? "").isEmpty
            || (context.terminalWindow?.hasIdentity ?? false)
    }

    /// Тот же непустой заголовок: дословно (без краевых пробелов) или очищенный без учёта регистра.
    /// Неизвестный (без Accessibility) или пустой заголовок не совпадает ни с чем.
    static func sameWindowTitle(_ bound: String, _ current: String?) -> Bool {
        let a = bound.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = (current ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !a.isEmpty, !b.isEmpty else { return false }
        if a == b { return true }
        let ca = TitleCleaner.clean(a), cb = TitleCleaner.clean(b)
        return !ca.isEmpty && ca.caseInsensitiveCompare(cb) == .orderedSame
    }
}

/// Удалённая задача и всё, что нужно, чтобы вернуть её на прежнее место.
public struct RemovedTask: Equatable, Sendable {
    /// Задача целиком: id, название, заметка, «сделано», привязка, время захода.
    public var task: JugglerTask
    /// Позиция в списке до удаления (с 0).
    public var index: Int
    /// Была ли она последней активной (текущей).
    public var wasActive: Bool
    public var removedAt: Date
    /// Удалена переключателем ⌃⌥§: повторное нажатие в течение `TaskRemoval.undoWindow` вернёт её.
    /// Удалённую из списка меню возвращает только пункт «Вернуть удалённую задачу».
    public var undoableByToggle: Bool

    public init(task: JugglerTask, index: Int, wasActive: Bool, removedAt: Date, undoableByToggle: Bool) {
        self.task = task
        self.index = index
        self.wasActive = wasActive
        self.removedAt = removedAt
        self.undoableByToggle = undoableByToggle
    }
}

public enum TaskRemoval {
    /// Сколько секунд после удаления ⌃⌥§ возвращает задачу.
    public static let undoWindow: TimeInterval = 5

    /// Удаляет задачу и возвращает запись для отмены; `nil`, если задачи нет.
    @discardableResult
    public static func remove(_ document: inout TasksDocument, id: UUID, now: Date, undoableByToggle: Bool) -> RemovedTask? {
        guard let i = document.index(of: id) else { return nil }
        let removed = RemovedTask(task: document.tasks[i], index: i, wasActive: document.lastActiveTaskID == id,
                                  removedAt: now, undoableByToggle: undoableByToggle)
        TaskListOps.delete(&document, id: id)
        return removed
    }

    /// Возвращает задачу как была: на прежнюю позицию (или в конец, если список стал короче),
    /// с тем же id и всеми полями. Текущей она снова становится, если была ею и с тех пор
    /// текущей не стала другая. `false`, если задача с этим id уже есть в списке.
    @discardableResult
    public static func restore(_ removed: RemovedTask, into document: inout TasksDocument) -> Bool {
        guard document.index(of: removed.task.id) == nil else { return false }
        let index = min(max(removed.index, 0), document.tasks.count)
        document.tasks.insert(removed.task, at: index)
        if removed.wasActive, document.lastActiveTaskID == nil {
            document.lastActiveTaskID = removed.task.id
        }
        return true
    }

    /// Открыто ли окно отмены переключателем: задача удалена ⌃⌥§ меньше `undoWindow` секунд назад.
    /// Часы, ушедшие назад, окно закрывают.
    public static func canUndoByToggle(_ removed: RemovedTask?, now: Date, window: TimeInterval = undoWindow) -> Bool {
        guard let removed, removed.undoableByToggle else { return false }
        let elapsed = now.timeIntervalSince(removed.removedAt)
        return elapsed >= 0 && elapsed < window
    }
}

/// Что делает ⌃⌥§ «добавить или удалить текущее окно».
public enum ToggleDecision: Equatable, Sendable {
    /// Повтор в окне отмены: вернуть только что удалённую задачу.
    case restore(RemovedTask)
    /// Переднее окно — точно эта задача: удалить её.
    case remove(taskID: UUID, number: Int)
    /// Совпадения нет: прежний сценарий «сделать задачей текущий чат» с этим контекстом.
    case add(FrontmostContext)
}

public enum TaskToggle {
    /// Сначала окно отмены (контекст тогда не читается вовсе), затем точное совпадение, иначе — добавить.
    /// `allowRestore: false` — пункт меню «Добавить/Удалить текущее окно»: возврат у него отдельный
    /// пункт, поэтому окно отмены не учитывается, и действие всегда совпадает с подписью пункта.
    public static func decide(
        document: TasksDocument, lastRemoved: RemovedTask?, now: Date, allowRestore: Bool = true,
        context: () -> FrontmostContext
    ) -> ToggleDecision {
        if allowRestore, let removed = lastRemoved, TaskRemoval.canUndoByToggle(removed, now: now),
           document.index(of: removed.task.id) == nil {
            return .restore(removed)
        }
        let context = context()
        if let id = ExactTaskMatcher.match(context: context, document: document), let number = document.number(of: id) {
            return .remove(taskID: id, number: number)
        }
        return .add(context)
    }
}

/// Что делает пункт меню «Добавить/Удалить текущее окно» для окна, которое было впереди до открытия меню.
public enum CurrentWindowMenuAction: Equatable, Sendable {
    /// Окно не задача (или контекст не прочитан): добавить.
    case add
    /// Окно точно совпало с задачей: удалить её.
    case remove(taskID: UUID, number: Int)

    public var isRemove: Bool {
        if case .remove = self { return true }
        return false
    }

    /// Подпись пункта меню.
    public var title: String {
        switch self {
        case .add: return TaskToggleTexts.menuAddTitle
        case .remove: return TaskToggleTexts.menuRemoveTitle
        }
    }

    /// Точное совпадение (`ExactTaskMatcher`) — удалить, иначе (в том числе без контекста) — добавить.
    public static func decide(context: FrontmostContext?, document: TasksDocument) -> CurrentWindowMenuAction {
        guard let context, let id = ExactTaskMatcher.match(context: context, document: document),
              let number = document.number(of: id) else { return .add }
        return .remove(taskID: id, number: number)
    }
}

/// Пункты меню под списком задач, сверху вниз (D16).
public enum MenuFooterItem: Equatable, Sendable {
    /// «Добавить текущее окно» или «Удалить текущее окно» (подпись — `CurrentWindowMenuAction.title`).
    case currentWindow
    case restoreRemoved
    /// «Очистить все задачи» — сначала встроенное подтверждение (D25).
    case clearAll
    case settings
    case quit

    /// Столбик под разделителем; «Вернуть удалённую задачу» — только если есть что вернуть,
    /// «Очистить все задачи» — только если в списке есть задачи.
    public static func items(canRestore: Bool, hasTasks: Bool) -> [MenuFooterItem] {
        var items: [MenuFooterItem] = [.currentWindow]
        if canRestore { items.append(.restoreRemoved) }
        if hasTasks { items.append(.clearAll) }
        return items + [.settings, .quit]
    }
}

/// Тексты переключателя: карточка и меню.
public enum TaskToggleTexts {
    /// Название действия ⌃⌥§: настройки хоткеев, README.
    public static let actionTitle = String(localized: "Добавить или удалить текущее окно")
    /// Пункт меню: переднее окно не задача.
    public static let menuAddTitle = String(localized: "Добавить текущее окно")
    /// Пункт меню: переднее окно уже задача.
    public static let menuRemoveTitle = String(localized: "Удалить текущее окно")
    public static let restoreMenuTitle = String(localized: "Вернуть удалённую задачу")
    public static let clearAllMenuTitle = String(localized: "Очистить все задачи")
    public static let settingsMenuTitle = String(localized: "Настройки…")
    public static let quitMenuTitle = String(localized: "Выйти")

    /// Карточка после удаления: «Задача 2 «Название» удалена — ⌃⌥§ в течение 5 с вернёт».
    public static func removedCard(number: Int, title: String, hotkey: Hotkey?, window: TimeInterval = TaskRemoval.undoWindow) -> String {
        let head = String(localized: "Задача \(number) «\(TransitionCardBuilder.title(title))» удалена")
        guard let hotkey else { return String(localized: "\(head) — вернуть: «\(restoreMenuTitle)» в меню Juggler") }
        return String(localized: "\(head) — \(hotkey.displayString) в течение \(Int(window.rounded())) с вернёт")
    }

    /// Карточка после возврата: «Задача 2 «Название» возвращена».
    public static func restoredCard(number: Int, title: String) -> String {
        String(localized: "Задача \(number) «\(TransitionCardBuilder.title(title))» возвращена")
    }

    /// Подсказка к пункту «Вернуть удалённую задачу».
    public static func restoreHelp(_ removed: RemovedTask) -> String {
        String(localized: "Вернуть «\(TransitionCardBuilder.title(removed.task.title))» на место \(removed.index + 1)")
    }
}
