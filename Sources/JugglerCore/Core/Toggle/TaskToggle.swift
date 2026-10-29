import Foundation

// ⌃⌥⇥ "add or remove the current window" (D15, D16): pure toggle logic.
//   - ExactTaskMatcher — the frontmost window is a task only on an exact match;
//   - TaskRemoval      — removal that remembers the position, and restoring "as it was";
//   - TaskToggle       — what a keypress does: restore, remove or add;
//   - CurrentWindowMenuAction — menu item title and action for the window that was frontmost;
//   - TaskToggleTexts  — card and menu texts.

/// Exact match of the frontmost window with a task.
///
/// Unlike `CurrentTaskResolver`, there is no fallback "last active" task here
/// and no weak "same app" or "same title" matches (except for ChatGPT,
/// whose thread id cannot be read from the window, and window bindings, which are
/// "bundle id + title" by definition):
/// - Chrome tab — same tab id or same URL (`URLNormalizer`);
/// - Claude chat — same UUID (in Claude desktop or at claude.ai/chat/<uuid> in Chrome);
/// - Claude Code session — same `local_<uuid>`;
/// - ChatGPT thread — same thread id or, in a ChatGPT window, same thread name (cleaned window title);
/// - Terminal window — same tab (tty) or same window (window id) if either side's tty is unknown;
///   by title without size and shell — only when AppleScript is unavailable and the context has neither tty nor id;
/// - app window — same bundle id and same non-empty window title, and only if
///   the frontmost window has no more precise id (tab, chat, session, thread): a window binding is
///   the fallback when the id is unknown.
public enum ExactTaskMatcher {
    /// Strength of an exact match: with several matching tasks, the id wins.
    public enum Strength: Int, Comparable, Sendable {
        case title = 1
        case url = 2
        case id = 3

        public static func < (lhs: Strength, rhs: Strength) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// The task the frontmost window exactly matches, or `nil`.
    /// On equal strength — the last active one (if it is among the matches), otherwise the first in the list.
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
            // The thread name is the ChatGPT window title; "ChatGPT" without a thread cleans to an empty string.
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
                // Terminal without AppleScript: size and shell in the title change — compare without them.
                return TerminalTitle.same(ref.windowTitle, context.windowTitle) ? .title : nil
            }
            guard sameWindowTitle(ref.windowTitle, context.windowTitle) else { return nil }
            return .title
        }
    }

    /// The frontmost window has a tab, chat, session, thread or Terminal window id.
    static func hasSpecificIdentity(_ context: FrontmostContext) -> Bool {
        context.chromeTab != nil
            || !(context.claudeConversationID ?? "").isEmpty
            || !(context.claudeCodeSessionID ?? "").isEmpty
            || !(context.chatGPTThreadID ?? "").isEmpty
            || (context.terminalWindow?.hasIdentity ?? false)
    }

    /// Same non-empty title: verbatim (without surrounding whitespace) or cleaned, case-insensitive.
    /// An unknown (no Accessibility) or empty title matches nothing.
    static func sameWindowTitle(_ bound: String, _ current: String?) -> Bool {
        let a = bound.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = (current ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !a.isEmpty, !b.isEmpty else { return false }
        if a == b { return true }
        let ca = TitleCleaner.clean(a), cb = TitleCleaner.clean(b)
        return !ca.isEmpty && ca.caseInsensitiveCompare(cb) == .orderedSame
    }
}

/// A removed task and everything needed to put it back in its place.
public struct RemovedTask: Equatable, Sendable {
    /// The whole task: id, title, note, "done", binding, visit time.
    public var task: JugglerTask
    /// Position in the list before removal (0-based).
    public var index: Int
    /// Whether it was the last active (current) task.
    public var wasActive: Bool
    public var removedAt: Date
    /// Removed by the ⌃⌥⇥ toggle: pressing it again within `TaskRemoval.undoWindow` restores it.
    /// A task removed from the menu list is restored only by the "Restore removed task" item.
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
    /// How many seconds after removal ⌃⌥⇥ restores the task.
    public static let undoWindow: TimeInterval = 5

    /// Removes the task and returns a record for undo; `nil` if there is no such task.
    @discardableResult
    public static func remove(_ document: inout TasksDocument, id: UUID, now: Date, undoableByToggle: Bool) -> RemovedTask? {
        guard let i = document.index(of: id) else { return nil }
        let removed = RemovedTask(task: document.tasks[i], index: i, wasActive: document.lastActiveTaskID == id,
                                  removedAt: now, undoableByToggle: undoableByToggle)
        TaskListOps.delete(&document, id: id)
        return removed
    }

    /// Restores the task as it was: at its previous position (or at the end if the list got shorter),
    /// with the same id and all fields. It becomes current again if it was current and no other
    /// task has become current since. `false` if a task with this id is already in the list.
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

    /// Whether the toggle's undo window is open: the task was removed by ⌃⌥⇥ less than `undoWindow` seconds ago.
    /// A clock that went backwards closes the window.
    public static func canUndoByToggle(_ removed: RemovedTask?, now: Date, window: TimeInterval = undoWindow) -> Bool {
        guard let removed, removed.undoableByToggle else { return false }
        let elapsed = now.timeIntervalSince(removed.removedAt)
        return elapsed >= 0 && elapsed < window
    }
}

/// What ⌃⌥⇥ "add or remove the current window" does.
public enum ToggleDecision: Equatable, Sendable {
    /// Repeat within the undo window: restore the just-removed task.
    case restore(RemovedTask)
    /// The frontmost window is exactly this task: remove it.
    case remove(taskID: UUID, number: Int)
    /// No match: the usual "make the current chat a task" flow with this context.
    case add(FrontmostContext)
}

public enum TaskToggle {
    /// Undo window first (the context is then not read at all), then exact match, otherwise add.
    /// `allowRestore: false` — the "Add/Remove current window" menu item: restoring has its own
    /// item there, so the undo window is ignored and the action always matches the item title.
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

/// What the "Add/Remove current window" menu item does for the window that was frontmost before the menu opened.
public enum CurrentWindowMenuAction: Equatable, Sendable {
    /// The window is not a task (or the context was not read): add.
    case add
    /// The window exactly matched a task: remove it.
    case remove(taskID: UUID, number: Int)

    public var isRemove: Bool {
        if case .remove = self { return true }
        return false
    }

    /// Menu item title.
    public var title: String {
        switch self {
        case .add: return TaskToggleTexts.menuAddTitle
        case .remove: return TaskToggleTexts.menuRemoveTitle
        }
    }

    /// Exact match (`ExactTaskMatcher`) — remove, otherwise (including without context) — add.
    public static func decide(context: FrontmostContext?, document: TasksDocument) -> CurrentWindowMenuAction {
        guard let context, let id = ExactTaskMatcher.match(context: context, document: document),
              let number = document.number(of: id) else { return .add }
        return .remove(taskID: id, number: number)
    }
}

/// Menu items below the task list, top to bottom (D16).
public enum MenuFooterItem: Equatable, Sendable {
    /// "Add current window" or "Remove current window" (title — `CurrentWindowMenuAction.title`).
    case currentWindow
    case restoreRemoved
    /// "Delete done tasks" — with an inline confirmation first; only when the list has done tasks.
    case clearDone
    /// "Clear all tasks" — with an inline confirmation first (D25).
    case clearAll
    case settings
    case quit

    /// The column below the separator; "Restore removed task" — only if there is something to restore,
    /// "Delete done tasks" — only if the list has done tasks, "Clear all tasks" — only if the list has tasks.
    public static func items(canRestore: Bool, hasTasks: Bool, hasDone: Bool = false) -> [MenuFooterItem] {
        var items: [MenuFooterItem] = [.currentWindow]
        if canRestore { items.append(.restoreRemoved) }
        if hasDone { items.append(.clearDone) }
        if hasTasks { items.append(.clearAll) }
        return items + [.settings, .quit]
    }
}

/// Toggle texts: card and menu.
public enum TaskToggleTexts {
    /// Name of the ⌃⌥⇥ action: hotkey settings, README.
    public static var actionTitle: String { loc("Добавить или удалить текущее окно") }
    /// Menu item: the frontmost window is not a task.
    public static var menuAddTitle: String { loc("Добавить текущее окно") }
    /// Menu item: the frontmost window is already a task.
    public static var menuRemoveTitle: String { loc("Удалить текущее окно") }
    public static var restoreMenuTitle: String { loc("Вернуть удалённую задачу") }
    public static var clearDoneMenuTitle: String { loc("Удалить сделанные задачи") }
    public static var clearAllMenuTitle: String { loc("Очистить все задачи") }
    public static var settingsMenuTitle: String { loc("Настройки…") }
    public static var quitMenuTitle: String { loc("Выйти") }

    /// Card after removal: "Task 2 "Title" removed — ⌃⌥⇥ within 5 s restores it".
    public static func removedCard(number: Int, title: String, hotkey: Hotkey?, window: TimeInterval = TaskRemoval.undoWindow) -> String {
        let head = loc("Задача \(number) «\(TransitionCardBuilder.title(title))» удалена")
        guard let hotkey else { return loc("\(head) — вернуть: «\(restoreMenuTitle)» в меню Juggler") }
        return loc("\(head) — \(hotkey.displayString) в течение \(Int(window.rounded())) с вернёт")
    }

    /// Card after a window was added to the list: "Task 4 "Title" added".
    public static func addedCard(number: Int, title: String) -> String {
        loc("Задача \(number) «\(TransitionCardBuilder.title(title))» добавлена")
    }

    /// Card after restoring: "Task 2 "Title" restored".
    public static func restoredCard(number: Int, title: String) -> String {
        loc("Задача \(number) «\(TransitionCardBuilder.title(title))» возвращена")
    }

    /// Tooltip for the "Restore removed task" item.
    public static func restoreHelp(_ removed: RemovedTask) -> String {
        loc("Вернуть «\(TransitionCardBuilder.title(removed.task.title))» на место \(removed.index + 1)")
    }
}
