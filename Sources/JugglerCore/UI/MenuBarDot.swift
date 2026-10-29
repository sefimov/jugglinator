import Foundation

/// Color of the menu bar dot. Matches the "away N min" colors in the task list.
public enum MenuBarDotColor: String, CaseIterable, Sendable {
    case green, yellow, orange, red

    /// Color by staleness level: <10 min green, <30 yellow, <60 orange, longer red.
    /// "Never visited" does not get here: such a task counts from its creation time.
    public static func color(for level: StalenessLevel) -> MenuBarDotColor {
        switch level {
        case .never, .fresh: return .green
        case .aging: return .yellow
        case .stale: return .orange
        case .forgotten: return .red
        }
    }
}

/// What to draw in the menu bar and what to show in the tooltip.
public struct MenuBarDot: Equatable, Sendable {
    public enum Appearance: Equatable, Sendable {
        /// Gray outline: no tasks or all are done.
        case outline
        /// A filled dot in the color of the most neglected task.
        case filled(MenuBarDotColor)
    }

    public let appearance: Appearance
    /// The task the color was picked by (none if the dot is gray or there are no other tasks).
    public let taskID: UUID?
    public let tooltip: String

    public init(appearance: Appearance, taskID: UUID?, tooltip: String) {
        self.appearance = appearance
        self.taskID = taskID
        self.tooltip = tooltip
    }
}

public enum MenuBarDotPresenter {
    /// Number drawn inside the dot: the task the frontmost window exactly matches (`ExactTaskMatcher`),
    /// `nil` if the window is not in the list or the context is unknown.
    public static func frontWindowNumber(context: FrontmostContext?, document: TasksDocument) -> Int? {
        guard let id = TaskListPresenter.currentTaskID(context: context, document: document) else { return nil }
        return document.number(of: id)
    }

    /// The task not returned to for the longest time: among unfinished ones, except the current one (▸).
    /// The reference time is the last visit, or creation for a never-opened one. On a tie — the first in the list.
    public static func mostNeglected(in document: TasksDocument) -> JugglerTask? {
        var best: JugglerTask?
        var bestDate = Date.distantFuture
        for task in document.tasks where !task.isDone && task.id != document.lastActiveTaskID {
            let date = task.lastVisitedAt ?? task.createdAt
            if best == nil || date < bestDate {
                best = task
                bestDate = date
            }
        }
        return best
    }

    public static func dot(
        for document: TasksDocument, now: Date, thresholds: StalenessThresholds = .standard
    ) -> MenuBarDot {
        if let task = mostNeglected(in: document) {
            let since = task.lastVisitedAt ?? task.createdAt
            let level = Staleness.level(lastVisited: since, now: now, thresholds: thresholds)
            let number = document.number(of: task.id) ?? 0
            let title = task.title.isEmpty ? loc("Без названия") : task.title
            let absence = Staleness.absenceText(lastVisited: since, now: now)
            return MenuBarDot(
                appearance: .filled(MenuBarDotColor.color(for: level)),
                taskID: task.id,
                tooltip: loc("Jugglinator: дольше всех ждёт задача \(number) — \(title), \(absence)"))
        }
        // No other unfinished tasks. If the current one is still in progress, all is calm.
        if let current = document.lastActiveTask, !current.isDone {
            return MenuBarDot(
                appearance: .filled(.green), taskID: nil,
                tooltip: loc("Jugglinator: других задач в работе нет"))
        }
        return MenuBarDot(
            appearance: .outline, taskID: nil,
            tooltip: loc("Jugglinator: нет задач в работе"))
    }
}
