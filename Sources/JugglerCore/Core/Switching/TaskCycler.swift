import Foundation

public enum CycleDirection: String, Codable, CaseIterable, Sendable {
    case next
    case previous
}

/// Cyclic task selection in the fixed list order (1→2→3→1),
/// not "most recently used". Tasks marked "done" are skipped.
public enum TaskCycler {
    /// The neighboring task in the cycle.
    ///
    /// - No unfinished tasks at all → `nil`.
    /// - Current is unknown (or not in the list): "next" is the first unfinished one,
    ///   "previous" is the last unfinished one.
    /// - The current one may itself be marked "done": counting still starts from its position.
    /// - If the only unfinished task is the current one, it is returned.
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
