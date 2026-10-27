import Foundation

public enum CycleDirection: String, Codable, CaseIterable, Sendable {
    case next
    case previous
}

/// Круговой выбор задачи в фиксированном порядке списка (1→2→3→1),
/// а не «последней использованной». Задачи «сделано» пропускаются.
public enum TaskCycler {
    /// Соседняя по кругу задача.
    ///
    /// - Нет ни одной несделанной задачи → `nil`.
    /// - Текущая неизвестна (или её нет в списке): «следующая» — первая несделанная,
    ///   «предыдущая» — последняя несделанная.
    /// - Текущая может быть сама отмечена «сделано»: отсчёт всё равно идёт от её позиции.
    /// - Если несделанная задача только одна и она текущая — возвращается она же.
    public static func neighbor(of currentID: UUID?, in tasks: [JugglerTask], direction: CycleDirection) -> JugglerTask? {
        guard tasks.contains(where: { !$0.isDone }) else { return nil }
        guard let currentID, let start = tasks.firstIndex(where: { $0.id == currentID }) else {
            switch direction {
            case .next: return tasks.first { !$0.isDone }
            case .previous: return tasks.last { !$0.isDone }
            }
        }
        let count = tasks.count
        let step = direction == .next ? 1 : -1
        for offset in 1...count {
            let index = ((start + step * offset) % count + count) % count
            if !tasks[index].isDone { return tasks[index] }
        }
        return nil
    }
}
