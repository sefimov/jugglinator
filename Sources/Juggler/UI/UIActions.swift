import AppKit
import Foundation
import JugglerCore
import os

let uiLog = Logger(subsystem: JugglerLog.subsystem, category: "ui")

/// Действия меню, которые уводят фокус в другое приложение.
@MainActor
enum UIActions {
    /// Пауза после закрытия панели меню-бара: передним успевает стать окно, где был пользователь.
    static let handOffDelay: TimeInterval = 0.3

    /// Закрыть панель меню-бара, вернуть фокус предыдущему приложению и выполнить действие.
    static func afterClosingMenu(_ dismiss: () -> Void, _ action: @escaping @MainActor () -> Void) {
        dismiss()
        NSApp.deactivate()
        DispatchQueue.main.asyncAfter(deadline: .now() + handOffDelay) {
            MainActor.assumeIsolated { action() }
        }
    }

    /// Перейти к задаче через переключатель (SWITCH): активация привязки, карточка, время захода.
    static func open(taskID: UUID, environment: AppEnvironment, dismiss: () -> Void) {
        afterClosingMenu(dismiss) {
            environment.switcher.activateTask(id: taskID)
        }
    }

    /// «Добавить или удалить текущую задачу» (BIND) — то же, что ⌃⌥§: переднее окно уже задача —
    /// удалить её (с карточкой и возвратом), иначе — «сделать задачей текущий чат».
    static func toggleCurrentTask(environment: AppEnvironment, dismiss: () -> Void) {
        afterClosingMenu(dismiss) {
            environment.perform(.bindCurrentChat)
        }
    }

    /// Открыть окно настроек и вывести его вперёд (приложение без значка в Dock).
    static func activateForSettings() {
        NSApp.activate(ignoringOtherApps: true)
    }
}
