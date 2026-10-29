import Foundation
import JugglerCore

// Claude Code sessions in the list (task SESSION): their own icon and source label.

extension UIChecks {
    static func checkSessionRows(_ c: CheckRunner) {
        c.group("сессия Claude Code в списке") {
            var (doc, _) = sample()
            doc.tasks[0].binding = .claudeCodeSession(ClaudeCodeSessionRef(sessionID: "local_fae5c400-6c06-4fa7-8cb8-eecc594fc296", title: "Сессии Code"))
            doc.tasks[1].binding = .claudeChat(ClaudeChatRef(conversationID: "0f8fad5b-d9cb-469f-a165-70867728950e", title: "Чат"))
            let rows = TaskListPresenter.rows(for: doc, now: t0, currentTaskID: nil)
            c.expectEqual(rows[0].source, .claudeCodeSession, "источник строки — сессия Claude Code")
            c.expectEqual(rows[0].bindingHelp, "Claude Code: Сессии Code", "справка: «Claude Code: название»")
            c.expectEqual(BindingSource.claudeCodeSession.displayName, "Claude Code", "подпись источника")
            c.expectEqual(BindingSource.claudeCodeSession.symbolName, "terminal", "значок сессии — terminal")
            c.expect(rows[0].source?.symbolName != rows[1].source?.symbolName, "значок сессии отличается от значка чата Claude")
            c.expectEqual(Set(BindingSource.allCases.map(\.symbolName)).count, BindingSource.allCases.count, "у каждого источника свой значок")
        }
    }
}
