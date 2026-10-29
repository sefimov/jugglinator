import Foundation
import JugglerCore

// Checks for the pure UI logic in Sources/JugglerCore/UI/:
// list operations (TaskListOps), rows and menu bar texts (TaskListPresenter),
// word forms, launch-at-login states and persisting the list between launches.

enum UIChecks: CheckSuite {
    static let name = "UI"

    static func run(_ c: CheckRunner) {
        checkTitles(c)
        checkAdd(c)
        checkEdit(c)
        checkDelete(c)
        checkClearAll(c)
        checkClearDone(c)
        checkDone(c)
        checkMoveOffsets(c)
        checkMoveByAndBefore(c)
        checkRows(c)
        checkTexts(c)
        checkMenuBarDot(c)
        checkLoginItem(c)
        checkPersistence(c)
        checkSessionRows(c)
        checkLanguage(c)
        checkLiveLanguage(c)
    }

    // MARK: - Helpers

    static let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    /// Document A, B, C, D with fixed ids.
    static func sample() -> (TasksDocument, [UUID]) {
        let ids = (0..<4).map { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", $0 + 1))! }
        let tasks = zip(ids, ["A", "B", "C", "D"]).map { JugglerTask(id: $0, title: $1, createdAt: t0) }
        return (TasksDocument(tasks: tasks), ids)
    }

    static func titles(_ doc: TasksDocument) -> [String] { doc.tasks.map(\.title) }
}
