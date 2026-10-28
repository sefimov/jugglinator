import Foundation
import JugglerCore

// Проверки чистой логики UI из Sources/JugglerCore/UI/:
// операции со списком (TaskListOps), строки и тексты меню-бара (TaskListPresenter),
// формы слов, состояния запуска при входе и сохранение списка между запусками.

enum UIChecks: CheckSuite {
    static let name = "UI"

    static func run(_ c: CheckRunner) {
        checkTitles(c)
        checkAdd(c)
        checkEdit(c)
        checkDelete(c)
        checkClearAll(c)
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

    // MARK: - Вспомогательное

    static let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    /// Документ A, B, C, D с фиксированными id.
    static func sample() -> (TasksDocument, [UUID]) {
        let ids = (0..<4).map { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", $0 + 1))! }
        let tasks = zip(ids, ["A", "B", "C", "D"]).map { JugglerTask(id: $0, title: $1, createdAt: t0) }
        return (TasksDocument(tasks: tasks), ids)
    }

    static func titles(_ doc: TasksDocument) -> [String] { doc.tasks.map(\.title) }
}
