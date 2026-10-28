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

    /// Контекст окна, которое было впереди до открытия меню (если впереди сам Juggler — последнего
    /// активного другого приложения). Системных запросов не показывает: без разрешений вернёт то, что удалось.
    static func readWindowContext(environment: AppEnvironment) -> FrontmostContext {
        environment.bind.contextProvider.currentContext()
    }

    /// «Добавить/Удалить текущее окно» (D16): окно уже задача — удалить её (карточка и возврат, как у ⌃⌥§),
    /// иначе — сделать задачей текущий чат. Окно отмены не учитывается: возврат — отдельный пункт.
    static func toggleCurrentWindow(environment: AppEnvironment, dismiss: () -> Void) {
        afterClosingMenu(dismiss) {
            environment.binder.toggleCurrentWindow()
        }
    }

    /// Открыть окно настроек и вывести его вперёд (приложение без значка в Dock).
    static func activateForSettings() {
        NSApp.activate(ignoringOtherApps: true)
    }
}
