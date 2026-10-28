import Foundation

/// Цвет кружка в меню-баре. Совпадает с цветами «не был N мин» в списке задач.
public enum MenuBarDotColor: String, CaseIterable, Sendable {
    case green, yellow, orange, red

    /// Цвет по уровню старения: <10 мин зелёный, <30 жёлтый, <60 оранжевый, дольше красный.
    /// «Ни разу не был» сюда не попадает: такая задача считается от времени создания.
    public static func color(for level: StalenessLevel) -> MenuBarDotColor {
        switch level {
        case .never, .fresh: return .green
        case .aging: return .yellow
        case .stale: return .orange
        case .forgotten: return .red
        }
    }
}

/// Что рисовать в меню-баре и что показывать в подсказке.
public struct MenuBarDot: Equatable, Sendable {
    public enum Appearance: Equatable, Sendable {
        /// Серый контур: задач нет или все сделаны.
        case outline
        /// Закрашенный кружок цвета самой заброшенной задачи.
        case filled(MenuBarDotColor)
    }

    public let appearance: Appearance
    /// Задача, по которой выбран цвет (нет, если кружок серый или остальных задач нет).
    public let taskID: UUID?
    public let tooltip: String

    public init(appearance: Appearance, taskID: UUID?, tooltip: String) {
        self.appearance = appearance
        self.taskID = taskID
        self.tooltip = tooltip
    }
}

public enum MenuBarDotPresenter {
    /// Задача, к которой не возвращались дольше всего: среди несделанных, кроме текущей (▸).
    /// Время отсчёта — последний заход, а для ни разу не открытой — создание. При равенстве — первая в списке.
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
                tooltip: loc("Juggler: дольше всех ждёт задача \(number) — \(title), \(absence)"))
        }
        // Других несделанных задач нет. Если текущая ещё в работе — всё спокойно.
        if let current = document.lastActiveTask, !current.isDone {
            return MenuBarDot(
                appearance: .filled(.green), taskID: nil,
                tooltip: loc("Juggler: других задач в работе нет"))
        }
        return MenuBarDot(
            appearance: .outline, taskID: nil,
            tooltip: loc("Juggler: нет задач в работе"))
    }
}
